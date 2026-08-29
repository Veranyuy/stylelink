import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/provider.dart';
import '../../models/service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/review_modal.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badge.dart';
import 'chat_screen.dart';

/// Live bookings tracker.
///
/// Listens to the client's booking stream via Supabase Realtime and renders
/// cards enriched with provider and service details from the database.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

/// A booking row enriched with its provider and service details.
class _BookingRow {
  const _BookingRow({
    required this.booking,
    required this.provider,
    required this.services,
    this.isReviewed = false,
  });

  final Booking booking;
  final Provider? provider;
  final List<Service> services;
  final bool isReviewed;
}

class _BookingsScreenState extends State<BookingsScreen> {
  final supabase = SupabaseService.instance;

  /// 'upcoming' | 'past'
  String _tab = 'upcoming';
  late Stream<List<_BookingRow>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
  }

  Stream<List<_BookingRow>> _buildStream() {
    final userId = supabase.currentUser?.id;
    if (userId == null) {
      return Stream.value(const []);
    }
    return supabase.watchBookingsForClient(userId).asyncMap((bookings) async {
      // Apply the active tab filter before enriching.
      final filtered = bookings
          .where((b) => _tab == 'upcoming' ? b.isUpcoming : b.isPast)
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      final providerIds = filtered.map((b) => b.providerId).toSet().toList();
      final serviceIds = filtered.expand((b) => b.serviceIds).toSet().toList();

      final providers = await supabase.fetchProvidersByIds(providerIds);
      final services = await supabase.fetchServicesByIds(serviceIds);
      final providersById = {for (final p in providers) p.id: p};
      final servicesById = {for (final s in services) s.id: s};

      // Check review status for completed bookings.
      final completedIds = filtered
          .where((b) => b.status == BookingStatus.completed)
          .map((b) => b.id)
          .toList();
      final reviewStatus = <String, bool>{};
      for (final id in completedIds) {
        reviewStatus[id] = await supabase.isBookingReviewed(id);
      }

      return filtered
          .map(
            (b) => _BookingRow(
              booking: b,
              provider: providersById[b.providerId],
              services: b.serviceIds
                  .map((id) => servicesById[id])
                  .whereType<Service>()
                  .toList(),
              isReviewed: reviewStatus[b.id] ?? false,
            ),
          )
          .toList();
    });
  }

  void _switchTab(String tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _stream = _buildStream();
    });
  }

  void _retry() {
    setState(() => _stream = _buildStream());
  }

  Future<void> _rateBooking(_BookingRow row) async {
    final provider = row.provider;
    if (provider == null) return;
    final submitted = await ReviewModal.show(
      context,
      bookingId: row.booking.id,
      providerId: row.booking.providerId,
      providerName: provider.businessName,
      onReviewSubmitted: _retry,
    );
    if (submitted) _retry();
  }

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.event_busy, color: Color(0xFFE5484D), size: 36),
        title: const Text('Cancel this booking?'),
        content: const Text(
          'This will cancel your appointment and cannot be undone.\n'
          'Voulez-vous annuler ce rendez-vous ?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep / Garder'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await supabase.cancelBooking(booking.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled / Réservation annulée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel booking: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Future<void> _openChat(Provider? provider) async {
    final userId = supabase.currentUser?.id;
    if (provider == null || userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(provider: provider, clientId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Appointments / Mes Rendez-vous',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _tabPill('Upcoming · À venir', 'upcoming'),
                    const SizedBox(width: 9),
                    _tabPill('Past / History', 'past'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildStreamView()),
        ],
      ),
    );
  }

  Widget _tabPill(String label, String value) {
    final active = _tab == value;
    return GestureDetector(
      onTap: () => _switchTab(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? const Color(0xFFF4665C) : Colors.white,
          border: Border.all(
            color: active ? const Color(0xFFF4665C) : const Color(0x22000000),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF6E6A76),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamView() {
    return StreamBuilder<List<_BookingRow>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: ListSkeleton(count: 3),
          );
        }
        if (snapshot.hasError) {
          return ErrorRetry(
            message: 'Could not load your bookings.\n${snapshot.error}',
            onRetry: _retry,
          );
        }
        final rows = snapshot.data ?? const <_BookingRow>[];
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.calendar_today_outlined,
            title: _tab == 'upcoming'
                ? 'No upcoming appointments found'
                : 'No past appointments yet',
            subtitle: _tab == 'upcoming'
                ? 'Book a stylist and it will appear here.\n'
                    'Aucun rendez-vous à venir.'
                : 'Completed and cancelled bookings will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: rows.length,
          itemBuilder: (context, i) => _BookingCard(
            row: rows[i],
            onCancel: () => _cancelBooking(rows[i].booking),
            onMessage: () => _openChat(rows[i].provider),
            onRate: rows[i].booking.status == BookingStatus.completed && !rows[i].isReviewed
                ? () => _rateBooking(rows[i])
                : null,
          ),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.row,
    required this.onCancel,
    required this.onMessage,
    this.onRate,
  });

  final _BookingRow row;
  final VoidCallback onCancel;
  final VoidCallback onMessage;
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final booking = row.booking;
    final provider = row.provider;
    final location = provider == null
        ? '—'
        : [
            if (provider.quarter != null && provider.quarter!.isNotEmpty)
              provider.quarter!,
            provider.city,
          ].join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x14000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProviderAvatar(provider: provider),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider?.businessName ?? 'Unknown provider',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider?.category ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 13),
            _detailRow(
              Icons.calendar_today_outlined,
              formatBookingDateTime(booking.scheduledAt),
            ),
            const SizedBox(height: 7),
            _detailRow(Icons.place_outlined, location),
            const SizedBox(height: 12),
            Row(
              children: [                  Expanded(
                    child: Text(
                      row.services.isEmpty
                          ? '${row.booking.serviceIds.length} service${row.booking.serviceIds.length == 1 ? '' : 's'}'
                          : row.services.map((s) => s.name).join(' + '),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Text(
                  formatFcfa(booking.totalPriceFcfa),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF4665C),
                  ),
                ),
              ],
            ),
            if (booking.isUpcoming) ...[
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onMessage,
                      icon: const Icon(Icons.chat_bubble_outline, size: 17),
                      label: const Text('Message Provider'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6E6A76),
                        side: const BorderSide(color: Color(0x33000000)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.event_busy, size: 17),
                      label: const Text('Cancel Booking'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5484D),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: onMessage,
                      icon: const Icon(Icons.chat_bubble_outline, size: 17),
                      label: const Text('Message Provider'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6E6A76),
                        side: const BorderSide(color: Color(0x33000000)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                    if (onRate != null && !row.isReviewed) ...[
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: onRate,
                        icon: const Icon(Icons.star_outline, size: 17),
                        label: const Text('Rate'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB93F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                    if (row.isReviewed) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x143FBF7F),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 14, color: Color(0xFF3FBF7F)),
                            SizedBox(width: 4),
                            Text('Reviewed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3FBF7F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({required this.provider});

  final Provider? provider;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = provider?.avatarUrl;
    return Container(
      width: 46,
      height: 46,
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
