import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../models/provider.dart';
import '../../models/service.dart';
import '../../services/analytics_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Provider detail + booking flow.
///
/// Loads the real provider row (bio, location, working hours) and the live
/// service menu from `public.services`. The client multi-selects services
/// (live FCFA total), then "Book Now" opens a date & time slot picker modal.
/// Confirming inserts a `public.bookings` row and, on success, pops back and
/// fires [onCreated] so the shell can open the live Bookings tab.
class ProviderDetailScreen extends StatefulWidget {
  const ProviderDetailScreen({
    super.key,
    required this.providerId,
    this.onBookingCreated,
  });

  final String providerId;
  final VoidCallback? onBookingCreated;

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen>
    with SingleTickerProviderStateMixin {
  final supabase = SupabaseService.instance;
  final _notes = TextEditingController();

  late Future<Provider?> _providerFuture;
  late Future<List<Service>> _servicesFuture;
  late final TabController _tabController;

  List<Service> _loaded = const [];
  final Set<String> _selectedIds = {};
  DateTime? _scheduledAt;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _providerFuture = supabase.fetchProviderById(widget.providerId).then((p) {
      // Record profile view for analytics (fire-and-forget).
      if (p != null) {
        SupabaseService.instance.recordProfileView(p.id);
      }
      return p;
    });
    _servicesFuture =
        supabase.fetchServicesForProvider(widget.providerId).then((services) {
      _loaded = services;
      return services;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<Service> get _selectedServices =>
      _loaded.where((s) => _selectedIds.contains(s.id)).toList();

  int get _totalFcfa =>
      _selectedServices.fold(0, (sum, s) => sum + s.price);

  void _toggleService(Service service) {
    setState(() {
      if (!_selectedIds.add(service.id)) {
        _selectedIds.remove(service.id);
      }
    });
  }

  Future<void> _openSlotPicker() async {
    // Resolve the provider so we can pass working hours to the slot picker.
    final provider = await _providerFuture;
    if (!mounted) return;
    final selection = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF7F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SlotPickerSheet(
        initial: _scheduledAt,
        workingHours: provider?.workingHours ?? const {},
      ),
    );
    if (selection != null && mounted) {
      setState(() => _scheduledAt = selection);
    }
  }

  Future<void> _confirm() async {
    final user = supabase.currentUser;
    if (user == null || _scheduledAt == null || _selectedIds.isEmpty) return;

    setState(() => _submitting = true);
    try {
      // Pre-flight check: ensure the provider isn't already booked at this time.
      final available = await supabase.checkProviderSlotAvailable(
        providerId: widget.providerId,
        scheduledAt: _scheduledAt!,
      );
      if (!available && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This time slot is no longer available. Please pick another.'),
            backgroundColor: Color(0xFFB3261E),
            duration: Duration(seconds: 4),
          ),
        );
        setState(() => _submitting = false);
        return;
      }

      final booking = await supabase.createBooking(
        clientId: user.id,
        providerId: widget.providerId,
        serviceIds: _selectedIds.toList(),
        scheduledAt: _scheduledAt!,
        totalPriceFcfa: _totalFcfa,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      AnalyticsService.instance.logBookingCreated(
        providerId: widget.providerId,
        serviceCount: _selectedIds.length,
        totalPriceFcfa: _totalFcfa,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle,
              color: Color(0xFF3FBF7F), size: 44),
          title: const Text('Booking requested!'),
          content: Text(
            'Your ${formatBookingDateTime(booking.scheduledAt)} appointment '
            'is pending confirmation.\n\n'
            'Total: ${formatFcfa(booking.totalPriceFcfa)}',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('View My Bookings'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close the detail screen
      widget.onBookingCreated?.call(); // switch shell to the Bookings tab
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // P0001 = raised exception from a PL/pgSQL function (e.g. provider busy guard).
      final message = e.code == 'P0001'
          ? 'This provider just entered a session. Please try again later.'
          : 'Could not create booking: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFB3261E),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create booking: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Provider?>(
        future: _providerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: ListSkeleton(count: 3),
            );
          }
          final provider = snapshot.data;
          if (provider == null) {
            return const ErrorRetry(
              message: 'This provider could not be found.',
              onRetry: _nothing,
            );
          }
          return _buildDetail(provider);
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  static void _nothing() {}

  Future<void> _showReportDialog(Provider provider) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag_outlined, color: Color(0xFFE5484D), size: 36),
        title: const Text('Report / Block'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Block ${provider.businessName} so they no longer appear in your search results.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            const _ReportReasonChip(label: 'Inappropriate content', value: 'inappropriate'),
            const SizedBox(height: 8),
            const _ReportReasonChip(label: 'Spam or fake profile', value: 'spam'),
            const SizedBox(height: 8),
            const _ReportReasonChip(label: 'Other', value: 'other'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await SupabaseService.instance.blockProvider(
        providerId: provider.id,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${provider.businessName} blocked.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => SupabaseService.instance.unblockProvider(provider.id),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(); // go back to home
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not block provider: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  /// Mockup layout: soft-focus hero header, Overview / Reviews tabs, then the
  /// profile card (avatar, name, verified badge), bio, tag row and portfolio.
  Widget _buildDetail(Provider provider) {
    return Column(
      children: [
        _HeroHeader(
          provider: provider,
          onReport: () => _showReportDialog(provider),
        ),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFF4665C),
            unselectedLabelColor: Colors.grey.shade600,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            indicatorColor: const Color(0xFFF4665C),
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Reviews'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverview(provider),
              _buildReviews(provider),
            ],
          ),
        ),
      ],
    );
  }

  /// Overview tab: the profile card (avatar, name, verified badge), bio, tag
  /// row, portfolio and working hours always render from the provider row;
  /// only the bookable services section reacts to the (separately loaded)
  /// service list, so a services outage never hides the profile.
  Widget _buildOverview(Provider provider) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        _buildProfileHeader(provider),
        if (provider.bio != null && provider.bio!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            provider.bio!,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buildTagRow(provider),
        const SizedBox(height: 24),
        _sectionTitle('Portfolio'),
        const SizedBox(height: 10),
        _buildPortfolio(provider),
        const SizedBox(height: 24),
        _sectionTitle('Working Hours / Horaires'),
        const SizedBox(height: 8),
        _infoCard(
          icon: Icons.schedule_outlined,
          text: provider.workingHoursLabel ?? 'Hours not set yet',
        ),
        const SizedBox(height: 20),
        _buildServicesSection(provider),
        const SizedBox(height: 20),
        _sectionTitle('Date & Time / Date et heure'),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x14000000)),
          ),
          child: ListTile(
            leading:
                const Icon(Icons.event_outlined, color: Color(0xFFF4665C)),
            title: Text(
              _scheduledAt == null
                  ? 'Pick a date and time / Choisir une date et heure'
                  : formatBookingDateTime(_scheduledAt!),
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    _scheduledAt == null ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSlotPicker,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Notes for the stylist (optional)…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  /// Services section: loading skeleton, inline retry, or the live menu.
  Widget _buildServicesSection(Provider provider) {
    return FutureBuilder<List<Service>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: ListSkeleton(count: 2),
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('Services / Prestations'),
              const SizedBox(height: 8),
              ErrorRetry(
                message: 'Could not load services.\n${snapshot.error}',
                onRetry: () => setState(() {
                  _servicesFuture =
                      supabase.fetchServicesForProvider(provider.id);
                }),
              ),
            ],
          );
        }
        final services = snapshot.data ?? const <Service>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              services.isEmpty
                  ? 'Services / Prestations'
                  : 'Select Services / Choisir des services',
            ),
            const SizedBox(height: 4),
            Text(
              'Tap services to add them to your booking.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            if (services.isEmpty)
              const EmptyState(
                icon: Icons.content_cut_outlined,
                title: 'No services published yet',
                subtitle: 'This provider has not added any services.',
              )
            else
              for (final service in services)
                _ServiceTile(
                  service: service,
                  selected: _selectedIds.contains(service.id),
                  onTap: () => _toggleService(service),
                ),
          ],
        );
      },
    );
  }

  /// Reviews tab: rating summary + live review list from the reviews table.
  Widget _buildReviews(Provider provider) {
    final filledStars = provider.rating.round().clamp(0, 5);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase.fetchReviewsForProvider(provider.id, limit: 30),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            // ─── Rating summary header ─────────────────────────────────
            Row(
              children: [
                Text(
                  provider.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Icon(
                            i < filledStars
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 18,
                            color: i < filledStars
                                ? const Color(0xFFFFB93F)
                                : Colors.grey.shade300,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${provider.reviewCount} review${provider.reviewCount == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ─── Review list ───────────────────────────────────────────
            if (reviews.isEmpty)
              const EmptyState(
                icon: Icons.rate_review_outlined,
                title: 'No reviews yet',
                subtitle:
                    'Reviews will appear here once clients rate this provider.',
              )
            else
              for (final review in reviews)
                _ReviewCard(review: review),
          ],
        );
      },
    );
  }

  /// Avatar, business name + category, and the green verified badge.
  Widget _buildProfileHeader(Provider provider) {
    return Row(
      children: [
        _Avatar(provider: provider, size: 60),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.businessName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                provider.category,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (!provider.isAvailable)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x14FF9F45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_outlined, size: 14, color: Color(0xFFFF9F45)),
                SizedBox(width: 4),
                Text(
                  'Busy',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF9F45),
                  ),
                ),
              ],
            ),
          ),
        if (provider.isVerified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x143FBF7F),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, size: 14, color: Color(0xFF3FBF7F)),
                SizedBox(width: 4),
                Text(
                  'Verified',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3FBF7F),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Pill tags: category, city, rating and review count.
  Widget _buildTagRow(Provider provider) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TagPill(
          icon: Icons.content_cut_outlined,
          label: provider.category,
        ),
        _TagPill(icon: Icons.location_on_outlined, label: provider.city),
        _TagPill(
          icon: Icons.star_rounded,
          label: '${provider.rating.toStringAsFixed(1)} ★',
          accent: true,
        ),
        _TagPill(
          icon: Icons.chat_bubble_outline,
          label:
              '${provider.reviewCount} review${provider.reviewCount == 1 ? '' : 's'}',
        ),
      ],
    );
  }

  /// Portfolio photo grid. When the provider has uploaded work-sample
  /// images they render in a responsive grid; otherwise a branded
  /// placeholder is shown.
  Widget _buildPortfolio(Provider provider) {
    final images = provider.portfolioImages;
    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined,
                size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No work samples uploaded yet',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _openImageViewer(images, index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey.shade400),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Full-screen image viewer (swipeable).
  void _openImageViewer(List<String> images, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          imageUrls: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  Widget _infoCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFF4665C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasSelection = _selectedIds.isNotEmpty;
    final hasTime = _scheduledAt != null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: FutureBuilder<Provider?>(
          future: _providerFuture,
          builder: (context, snapshot) {
            final provider = snapshot.data;
            final isBusy = provider != null && !provider.isAvailable;

            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total / Total',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        hasSelection ? formatFcfa(_totalFcfa) : '—',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF4665C),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isBusy)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: const Text(
                        'Provider Busy\nEn session',
                        textAlign: TextAlign.center,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.grey.shade300,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: hasSelection && hasTime && !_submitting
                        ? _confirm
                        : hasSelection
                            ? _openSlotPicker
                            : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF4665C),
                      disabledBackgroundColor: const Color(0x22F4665C),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Book Now / Réserver'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Modal date & time slot picker: a 7-day strip plus hourly slots
/// filtered by the provider's working hours. When hours are set for a day,
/// only slots within the open window are shown. When hours are not set,
/// the provider is closed that day and no slots are offered.
class _SlotPickerSheet extends StatefulWidget {
  const _SlotPickerSheet({this.initial, this.workingHours = const {}});

  final DateTime? initial;

  /// Provider's weekly schedule keyed by day abbreviation ("Mon"…"Sun").
  /// Values are "HH:MM-HH:MM" windows or null when closed.
  final Map<String, String?> workingHours;

  @override
  State<_SlotPickerSheet> createState() => _SlotPickerSheetState();
}

class _SlotPickerSheetState extends State<_SlotPickerSheet> {
  final _days = List.generate(7, (i) {
    final d = DateTime.now();
    return DateTime(d.year, d.month, d.day).add(Duration(days: i));
  });

  late DateTime _selectedDay = widget.initial == null
      ? _days.first
      : _days.firstWhere(
          (d) =>
              d.year == widget.initial!.year &&
              d.month == widget.initial!.month &&
              d.day == widget.initial!.day,
          orElse: () => _days.first,
        );

  late TimeOfDay? _selectedTime = widget.initial == null
      ? null
      : TimeOfDay.fromDateTime(widget.initial!);

  /// Day abbreviation for the currently selected day ("Mon"…"Sun").
  String get _selectedDayAbbr {
    const abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return abbr[_selectedDay.weekday - 1];
  }

  /// Whether the provider is open on the selected day.
  bool get _isOpen {
    if (widget.workingHours.isEmpty) return true; // no hours set → show all
    return widget.workingHours.containsKey(_selectedDayAbbr);
  }

  /// Parse the working hours window for the selected day.
  /// Returns (openHour, closeHour) or null if not set.
  (int, int)? _parseHours() {
    final window = widget.workingHours[_selectedDayAbbr];
    if (window == null || window.isEmpty) return null;
    final parts = window.split('-');
    if (parts.length != 2) return null;
    final open = int.tryParse(parts[0].split(':')[0]);
    final close = int.tryParse(parts[1].split(':')[0]);
    if (open == null || close == null) return null;
    return (open, close);
  }

  List<DateTime> get _slots {
    final now = DateTime.now();
    final hours = _parseHours();
    final startHour = hours?.$1 ?? 9;
    final endHour = hours?.$2 ?? 19;
    return [
      for (var h = startHour; h <= endHour; h++)
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, h),
    ].where((s) => !s.isBefore(now)).toList();
  }

  void _confirm() {
    final time = _selectedTime;
    if (time == null) return;
    Navigator.of(context).pop(
      DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day,
          time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x22000000),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Pick a date & time / Choisissez une date et heure',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final day = _days[i];
                  final active = _isSameDay(day, _selectedDay);
                  final dayAbbr = _weekday(day);
                  final isClosed = widget.workingHours.isNotEmpty &&
                      !widget.workingHours.containsKey(dayAbbr);
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedDay = day;
                      _selectedTime = null;
                    }),
                    child: Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: active
                            ? const Color(0xFFF4665C)
                            : Colors.white,
                        border: Border.all(
                          color: active
                              ? const Color(0xFFF4665C)
                              : isClosed
                                  ? const Color(0x33E5484D)
                                  : const Color(0x18000000),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayAbbr,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.white
                                  : isClosed
                                      ? const Color(0xFFE5484D)
                                      : Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.white
                                  : isClosed
                                      ? const Color(0xFFE5484D)
                                      : const Color(0xFF2A2730),
                            ),
                          ),
                          if (isClosed && !active)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE5484D),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            if (!_isOpen)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_outlined, size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'Provider closed on ${_weekday(_selectedDay)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      Text(
                        'Choisissez un autre jour.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else if (_slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No more available slots today.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final slot in _slots)
                    _TimeChip(
                      time: slot,
                      selected:
                          _selectedTime?.hour == slot.hour &&
                          _selectedTime?.minute == slot.minute,
                      onTap: () => setState(() => _selectedTime = TimeOfDay(
                            hour: slot.hour,
                            minute: slot.minute,
                          )),
                    ),
                ],
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _selectedTime == null ? null : _confirm,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFFF4665C),
                disabledBackgroundColor: const Color(0x22F4665C),
              ),
              child: const Text('Confirm / Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekday(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.time,
    required this.selected,
    required this.onTap,
  });

  final DateTime time;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? const Color(0xFFF4665C) : Colors.white,
          border: Border.all(
            color: selected ? const Color(0xFFF4665C) : const Color(0x18000000),
          ),
        ),
        child: Text(
          formatTime(time),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF2A2730),
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final Service service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? const Color(0xFFF4665C) : const Color(0x14000000),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (service.description != null &&
                        service.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        service.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${service.durationLabel} · ${service.priceLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? const Color(0xFFF4665C) : Colors.white,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFF4665C)
                        : const Color(0x44000000),
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.provider, this.size = 50});

  final Provider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = provider.avatarUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
        ),
      ),
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(),
            )
          : _initials(),
    );
  }

  Widget _initials() => Center(
        child: Text(
          provider.businessName.isEmpty
              ? '?'
              : provider.businessName.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Soft-focus hero header from the mockup: the cover photo blurred and faded
/// into the white page, a back button, and the gradient "Provider Profile"
/// title.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.provider, this.onReport});

  final Provider provider;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    // Banner background: cover → first portfolio → gradient fallback.
    final coverUrl = provider.coverUrl;
    final bannerImage = coverUrl != null && coverUrl.isNotEmpty
        ? coverUrl
        : (provider.portfolioImages.isNotEmpty
            ? provider.portfolioImages.first
            : null);
    return SizedBox(
      height: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bannerImage != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Image.network(
                bannerImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
            )
          else
            _fallback(),
          // Fade the photo into the white page (mockup's soft-focus look).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white],
                stops: [0.45, 1],
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: _CircleIconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                Icons.arrow_back,
                size: 20,
                color: Color(0xFF2A2730),
              ),
            ),
          ),
          if (onReport != null)
            Positioned(
              top: 14,
              right: 14,
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'report') onReport!();
                },
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert, size: 18, color: Color(0xFF2A2730)),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 18, color: Color(0xFFE5484D)),
                        SizedBox(width: 10),
                        Text('Report / Block'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 20,
            bottom: 16,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF9E86E6), Color(0xFFF4665C)],
              ).createShader(bounds),
              child: const Text(
                'Provider Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white, // replaced by the gradient shader
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}

/// Small white circular icon button (back arrow on the hero header).
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Light grey pill used for the profile tag row (category, city, rating,
/// review count).
class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    this.icon,
    this.accent = false,
  });

  final String label;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: accent ? const Color(0xFFFFB93F) : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Review card
// =============================================================================

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  /// Raw row from `public.reviews` joined with profiles.
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString();
    final createdAt = review['created_at']?.toString();
    // Extract joined profile data.
    final profile = review['profiles'];
    final String clientName = (profile != null && profile['full_name'] != null && profile['full_name'].toString().isNotEmpty)
        ? profile['full_name'].toString()
        : '';
    final String? avatarUrl = profile != null ? profile['avatar_url']?.toString() : null;
    final clientId = review['client_id']?.toString();

    // Parse the timestamp for display.
    String? dateLabel;
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateLabel = '${dt.day.toString().padLeft(2, '0')} '
            '${_monthShort(dt.month)} ${dt.year}';
      }
    }

    // Display name: prefer real name from profiles, fallback to anonymous.
    final displayName = clientName.isNotEmpty
        ? clientName
        : (clientId != null && clientId.length >= 6
            ? 'Client ${clientId.substring(0, 6).toUpperCase()}'
            : 'Anonymous');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x10000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header: avatar + name + date ──────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF9E86E6),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (dateLabel != null)
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Star rating ──────────────────────────────────────────────
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 17,
                  color: i < rating
                      ? const Color(0xFFFFB93F)
                      : Colors.grey.shade300,
                ),
              const SizedBox(width: 6),
              Text(
                '$rating/5',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),

          // ─── Comment ──────────────────────────────────────────────────
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _monthShort(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}

// =============================================================================
// Full-screen image viewer (swipeable)
// =============================================================================

class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_current + 1} / ${widget.imageUrls.length}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.imageUrls[index],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 48),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReportReasonChip extends StatelessWidget {
  const _ReportReasonChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(value),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          side: const BorderSide(color: Color(0x33000000)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }
}
