import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/profile.dart';
import '../../models/provider.dart';
import '../../models/service.dart';
import '../../controllers/service_tracker_controller.dart';
import '../../services/analytics_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/booking_tracker_card.dart';
import '../../widgets/counter_proposal_sheet.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badge.dart';
import '../client/chat_screen.dart';

/// Live provider operational dashboard.
///
/// Streams incoming requests with [SupabaseService.watchBookingsForProvider],
/// computes live metrics (today's clients + revenue from confirmed/completed
/// bookings) and lets the provider Accept (-> confirmed) or Cancel/Reschedule
/// (-> cancelled) each request.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// A booking enriched with its client's profile and service details.
class _EnrichedBooking {
  const _EnrichedBooking({
    required this.booking,
    required this.client,
    required this.services,
  });

  final Booking booking;
  final Profile? client;
  final List<Service> services;
}

class _DashboardScreenState extends State<DashboardScreen> {
  final supabase = SupabaseService.instance;
  final _tracker = ServiceTrackerController.instance;

  Future<Provider?>? _providerFuture;
  Stream<List<_EnrichedBooking>>? _stream;
  String? _providerId;
  bool _isAvailable = true;

  /// How many active services the shop currently lists. 0 → the shop is
  /// hidden from clients, so the setup banner is shown.
  Future<int>? _serviceCountFuture;

  @override
  void initState() {
    super.initState();
    _providerFuture = _resolveProvider();
  }

  /// Re-resolve the service count (used after adding a service or when the
  /// widget is re-keyed by the shell after the onboarding wizard).
  void _reloadServiceCount(String providerId) {
    setState(() {
      _serviceCountFuture = supabase.fetchServicesForProvider(providerId)
          .then((services) => services.length);
    });
  }

  @override
  void dispose() {
    _tracker.unsubscribeFromBookings();
    super.dispose();
  }

  Future<Provider?> _resolveProvider() async {
    final user = supabase.currentUser;
    if (user == null) return null;
    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return provider;
    setState(() {
      _providerId = provider?.id;
      _isAvailable = provider?.isAvailable ?? true;
      _stream =
          provider == null ? Stream.value(const []) : _buildStream(provider.id);
      _serviceCountFuture = provider == null
          ? Future.value(0)
          : supabase
              .fetchServicesForProvider(provider.id)
              .then((services) => services.length);
    });
    // Subscribe to realtime booking changes for this provider.
    if (provider != null) {
      _tracker.subscribeToProviderBookings(provider.id);
    }
    return provider;
  }

  Stream<List<_EnrichedBooking>> _buildStream(String providerId) {
    return supabase.watchBookingsForProvider(providerId).asyncMap(
      (bookings) async {
        final sorted = [...bookings]..sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

        final clientIds = sorted.map((b) => b.clientId).toSet().toList();
        final serviceIds = sorted.expand((b) => b.serviceIds).toSet().toList();

        final clients = await supabase.fetchProfilesByIds(clientIds);
        final services = await supabase.fetchServicesByIds(serviceIds);
        final clientsById = {for (final c in clients) c.id: c};
        final servicesById = {for (final s in services) s.id: s};

        return sorted
            .map(
              (b) => _EnrichedBooking(
                booking: b,
                client: clientsById[b.clientId],
                services: b.serviceIds
                    .map((id) => servicesById[id])
                    .whereType<Service>()
                    .toList(),
              ),
            )
            .toList();
      },
    );
  }

  Future<void> _openChat(_EnrichedBooking row) async {
    final providerId = _providerId;
    if (providerId == null) return;
    try {
      final provider = await supabase.fetchProviderById(providerId);
      if (provider == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            provider: provider,
            clientId: row.booking.clientId,
            counterpartName: row.client?.fullName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open chat: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Future<void> _setStatus(Booking booking, BookingStatus status) async {
    try {
      await supabase.updateBookingStatus(booking.id, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update booking: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  /// Provider counters a booking (new request or reschedule proposal) with
  /// their own slot: opens the date/time picker and writes the proposal.
  Future<void> _counterBooking(Booking booking) async {
    final proposed = await showCounterProposalSheet(
      context,
      initial: booking.proposedScheduledAt ?? booking.scheduledAt,
    );
    if (proposed == null || !mounted) return;

    try {
      await supabase.counterBooking(
        bookingId: booking.id,
        proposedAt: proposed,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Counter proposal sent / Contre-proposition envoyée — '
            '${formatBookingDateTime(proposed)}',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send counter proposal: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  /// Rebuild the realtime stream so enriched data (clients, services)
  /// and metric cards refresh after a tracker stage change.
  Future<void> _toggleAvailability() async {
    final newAvailable = !_isAvailable;
    setState(() => _isAvailable = newAvailable);
    try {
      await supabase.toggleAvailability(newAvailable);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAvailable = !newAvailable);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not update availability: $e'),
            backgroundColor: const Color(0xFFB3261E)),
      );
    }
  }

  void _refresh() {
    final id = _providerId;
    if (id == null) return;
    setState(() {
      _stream = _buildStream(id);
    });
  }

  Future<void> _rejectBooking(Booking booking) async {
    // Look up the client name for the dialog.
    String? clientName;
    try {
      final profiles = await supabase.fetchProfilesByIds([booking.clientId]);
      clientName = profiles.isNotEmpty ? profiles.first.fullName : null;
    } catch (_) {
      // Ignore — dialog still works without a name.
    }
    if (!mounted) return;

    final result = await showDialog<RejectResult>(
      context: context,
      builder: (context) => _RejectDialog(clientName: clientName),
    );
    if (result == null || !mounted) return;

    try {
      await supabase.updateBookingStatus(booking.id, BookingStatus.rejected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.reason.isNotEmpty
                  ? 'Booking rejected: ${result.reason}'
                  : 'Booking rejected / Réservation refusée',
            ),
            backgroundColor: const Color(0xFFE5484D),
          ),
        );
        _refresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reject booking: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: FutureBuilder<Provider?>(
              future: _providerFuture,
              builder: (context, snapshot) {
                final provider = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Avatar(provider: provider),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider?.businessName ?? 'Loading…',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: Color(0xFF2A2730),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                provider == null
                                    ? 'Checking profile…'
                                    : '${provider.category} · ${provider.city}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF8B8694),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _OnlinePill(
                            isAvailable: _isAvailable,
                            onToggle: _toggleAvailability),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFF4665C), Color(0xFF9E86E6)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          'Upcoming Bookings / Réservations',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: Color(0xFF2A2730),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          // Hidden-shop banner: providers with 0 services cannot be booked
          // and don't appear in client search results.
          _buildSetupBanner(),
          Expanded(child: _buildStreamView()),
        ],
      ),
    );
  }

  /// Prominent top banner shown when the provider has 0 active services:
  /// "Your shop is hidden!" with a direct + Add Service action.
  Widget _buildSetupBanner() {
    final providerId = _providerId;
    final countFuture = _serviceCountFuture;
    if (providerId == null || countFuture == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<int>(
      future: countFuture,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        // Only render the banner once the count resolved to 0 — any active
        // service (or a still-loading count) keeps it hidden.
        if (!done || (snapshot.data ?? 0) > 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFA5252), Color(0xFFF4665C)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFA5252).withValues(alpha: .30),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.visibility_off_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Your shop is hidden! Add at least 1 service to start '
                    'accepting bookings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _showAddServiceSheet(providerId),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFFA5252),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Service'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bottom-sheet Add Service form opened from the banner. Returns the
  /// created service (or null). The sheet prompts until the input is valid.
  Future<void> _showAddServiceSheet(String providerId) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddServiceSheet(
        nameCtrl: nameCtrl,
        priceCtrl: priceCtrl,
        durationCtrl: durationCtrl,
      ),
    );
    if (created != true || !mounted) return;

    try {
      final service = await supabase.createService(
        providerId: providerId,
        name: nameCtrl.text.trim(),
        price: int.parse(priceCtrl.text.trim()),
        durationMinutes: int.parse(durationCtrl.text.trim()),
      );
      AnalyticsService.instance.logServiceCreated(
        providerId: providerId,
        serviceName: service.name,
        price: service.price,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service added — your shop is now live! 🎉'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      _reloadServiceCount(providerId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add service: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Widget _buildStreamView() {
    final stream = _stream;
    if (stream == null) {
      return FutureBuilder<Provider?>(
        future: _providerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: ListSkeleton(count: 3),
            );
          }
          if (snapshot.data == null) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No provider profile yet',
              subtitle: 'Providers need a row in public.providers linked to '
                  'their account to see bookings.',
            );
          }
          return const SizedBox.shrink();
        },
      );
    }
    return StreamBuilder<List<_EnrichedBooking>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: ListSkeleton(count: 3),
          );
        }
        if (snapshot.hasError) {
          return ErrorRetry(
            message: 'Could not load your schedule. ${snapshot.error}',
            onRetry: () => setState(() {
              final id = _providerId;
              _stream = id == null ? Stream.value(const []) : _buildStream(id);
            }),
          );
        }
        final rows = snapshot.data ?? const <_EnrichedBooking>[];
        return _DashboardBody(
          rows: rows,
          onAccept: (b) => _setStatus(b, BookingStatus.confirmed),
          onCancel: (b) => _setStatus(b, BookingStatus.cancelled),
          onReject: (b) => _rejectBooking(b),
          onCounter: (b) => _counterBooking(b),
          onMessage: _openChat,
          onRefresh: _refresh,
        );
      },
    );
  }
}

/// Scrollable dashboard body: metrics row + appointment list.
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.rows,
    required this.onAccept,
    required this.onCancel,
    required this.onReject,
    required this.onCounter,
    required this.onMessage,
    required this.onRefresh,
  });

  final List<_EnrichedBooking> rows;
  final ValueChanged<Booking> onAccept;
  final ValueChanged<Booking> onCancel;
  final ValueChanged<Booking> onReject;
  final ValueChanged<Booking> onCounter;
  final ValueChanged<_EnrichedBooking> onMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final upcoming = rows
        .where((r) => r.booking.isUpcoming)
        .where((r) => r.booking.scheduledAt.isBefore(tomorrow))
        .toList();

    // Revenue: sum of confirmed, arrived, in-progress, and completed bookings.
    final revenue = rows
        .where((r) =>
            r.booking.isUpcoming || r.booking.status == BookingStatus.completed)
        .fold<int>(0, (sum, r) => sum + r.booking.totalPriceFcfa);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetricCard(
              label: "Today's Clients",
              value: '${upcoming.length}',
              sub: upcoming.isEmpty ? 'No bookings today' : 'Bookings today',
              icon: Icons.people_outline_rounded,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Total Revenue',
              value: formatFcfa(revenue),
              sub: 'Confirmed + completed',
              coral: true,
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: 'No bookings yet',
            subtitle: 'New requests appear here in real time.\n'
                'Les nouvelles demandes apparaissent ici.',
          )
        else
          for (final row in rows) ...[
            // Pending bookings: accept / cancel actions.
            if (row.booking.status == BookingStatus.pending)
              _PendingBookingCard(
                row: row,
                onAccept: () => onAccept(row.booking),
                onCancel: () => onCancel(row.booking),
                onReject: () => onReject(row.booking),
                onCounter: () => onCounter(row.booking),
                onMessage: () => onMessage(row),
              ),
            // Confirmed / arrived / in-progress / completed: tracker card.
            if (row.booking.status != BookingStatus.pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BookingTrackerCard(
                  booking: row.booking.toJson(),
                  onStatusUpdated: onRefresh,
                ),
              ),
          ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    this.coral = false,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final bool coral;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = coral ? const Color(0xFFF4665C) : const Color(0xFF2A2730);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF242030) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: coral
                ? const Color(0x22F4665C)
                : (isDark ? Colors.white10 : const Color(0x0F000000)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: coral
                        ? const Color(0x14F4665C)
                        : (isDark ? Colors.white10 : const Color(0xFFF2EFF6)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: coral
                        ? const Color(0xFFF4665C)
                        : const Color(0xFF6E6A76),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 14,
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .04,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card for **pending** bookings — Accept / Cancel actions.
class _PendingBookingCard extends StatelessWidget {
  const _PendingBookingCard({
    required this.row,
    required this.onAccept,
    required this.onCancel,
    required this.onReject,
    required this.onCounter,
    required this.onMessage,
  });

  final _EnrichedBooking row;
  final VoidCallback onAccept;
  final VoidCallback onCancel;
  final VoidCallback onReject;
  final VoidCallback onCounter;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final booking = row.booking;
    final client = row.client;
    final diff = booking.scheduledAt.difference(DateTime.now());

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242030) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x44F4665C), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF4665C).withValues(alpha: .10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x14F4665C),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    formatTime(booking.scheduledAt),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF4665C),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diff.isNegative
                        ? 'Started ${formatDate(booking.scheduledAt)}'
                        : diff.inMinutes < 60
                            ? 'In ${diff.inMinutes} mins'
                            : 'In ${diff.inHours} hrs',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                StatusBadge(status: booking.status),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onMessage,
                  tooltip: 'Message client',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 19, color: Color(0xFFF4665C)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              client?.fullName ?? 'Client',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: Color(0xFF2A2730),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              row.services.isEmpty
                  ? 'Services'
                  : row.services.map((s) => s.name).join(' + '),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              formatFcfa(booking.totalPriceFcfa),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF4665C),
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF4665C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Accept / Accepter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCounter,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9E6A00),
                      side: const BorderSide(color: Color(0x55FFB93F)),
                      backgroundColor: const Color(0x0DFFB93F),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Counter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE5484D),
                      side: const BorderSide(color: Color(0x33E5484D)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Reject / Refuser'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6E6A76),
                side: const BorderSide(color: Color(0x33000000)),
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: .04)
                    : Colors.grey.shade50,
                minimumSize: const Size.fromHeight(38),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text('Cancel booking'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.isAvailable, required this.onToggle});

  final bool isAvailable;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              isAvailable ? const Color(0x143FBF7F) : const Color(0x14FF9F45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                isAvailable ? const Color(0x333FBF7F) : const Color(0x33FF9F45),
          ),
          boxShadow: [
            if (isAvailable)
              BoxShadow(
                color: const Color(0xFF3FBF7F).withValues(alpha: .18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isAvailable
                    ? const Color(0xFF3FBF7F)
                    : const Color(0xFFFF9F45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              isAvailable ? 'Online / Disponible' : 'Offline / Hors ligne',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isAvailable
                    ? const Color(0xFF2E9E66)
                    : const Color(0xFFCC8030),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.provider});

  final Provider? provider;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = provider?.avatarUrl;
    return Container(
      width: 46,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9E86E6).withValues(alpha: .35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
          (provider?.businessName.isNotEmpty ?? false)
              ? provider!.businessName.substring(0, 1).toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// =============================================================================
// Add Service sheet (opened from the "shop is hidden" banner)
// =============================================================================

/// Modal bottom sheet with the Add Service form: Name, Duration, Price.
/// Pops `true` when the inputs are valid; the dashboard then writes the
/// service to the DB and reloads its banner state.
class _AddServiceSheet extends StatefulWidget {
  const _AddServiceSheet({
    required this.nameCtrl,
    required this.priceCtrl,
    required this.durationCtrl,
  });

  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController durationCtrl;

  @override
  State<_AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends State<_AddServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  static const _templates = [
    ('Haircut / Coupe', '2000', '30'),
    ('Braids / Tresses', '5000', '120'),
    ('Washing / Lavage', '1000', '30'),
    ('Beard Trim / Barbe', '1000', '15'),
  ];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    // Give the sheet time to close smoothly before the DB write completes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAF7F3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Add Service / Ajouter une prestation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2A2730),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (name, price, duration) in _templates)
                        ActionChip(
                          onPressed: () => setState(() {
                            widget.nameCtrl.text = name;
                            widget.priceCtrl.text = price;
                            widget.durationCtrl.text = duration;
                          }),
                          label: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          backgroundColor: const Color(0x14F4665C),
                          side: const BorderSide(color: Color(0x33F4665C)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: widget.nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _sheetInput('Service Name / Nom',
                        Icons.content_cut_outlined),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: widget.priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              _sheetInput('Price (FCFA)', Icons.payments_outlined),
                          validator: (v) {
                            final p = int.tryParse(v?.trim() ?? '');
                            return (p == null || p <= 0)
                                ? 'Enter a price > 0'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: widget.durationCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _sheetInput(
                              'Duration (mins)', Icons.timer_outlined),
                          validator: (v) {
                            final d = int.tryParse(v?.trim() ?? '');
                            return (d == null || d <= 0)
                                ? 'Enter minutes > 0'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF4665C),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0x22F4665C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline, size: 20),
                      label: const Text('Save Service'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _sheetInput(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x14000000)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x14000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF4665C), width: 1.6),
      ),
    );
  }
}

// =============================================================================
// Reject dialog with optional reason
// =============================================================================

class RejectResult {
  const RejectResult({this.reason = ''});
  final String reason;
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({this.clientName});
  final String? clientName;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reasonCtrl = TextEditingController();
  String? _selectedReason;

  static const _reasons = [
    'Schedule conflict / Conflit d\'agenda',
    'Fully booked / Complet',
    'Service unavailable / Service indisponible',
    'Too far / Trop éloigné',
    'Other / Autre',
  ];

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selectedReason == 'Other / Autre'
        ? _reasonCtrl.text.trim()
        : (_selectedReason ?? '');
    Navigator.of(context).pop(RejectResult(reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.cancel_outlined, color: Color(0xFFE5484D), size: 24),
          SizedBox(width: 10),
          Text('Reject Booking'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.clientName != null
                ? 'Reject booking from ${widget.clientName}?'
                : 'Reject this booking request?',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF6E6A76)),
          ),
          const SizedBox(height: 14),
          Text(
            'Reason (optional) / Raison (optionnel)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _reasons.map((r) {
              final selected = _selectedReason == r;
              return ChoiceChip(
                label: Text(
                  r,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF6E6A76),
                  ),
                ),
                selected: selected,
                selectedColor: const Color(0xFFE5484D),
                backgroundColor: Colors.grey.shade100,
                onSelected: (_) => setState(() => _selectedReason = r),
              );
            }).toList(),
          ),
          if (_selectedReason == 'Other / Autre') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Type a reason… / Tapez une raison…',
                hintStyle:
                    TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE5484D),
          ),
          child: const Text('Reject / Refuser'),
        ),
      ],
    );
  }
}
