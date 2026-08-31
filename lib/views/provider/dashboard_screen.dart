import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/profile.dart';
import '../../models/provider.dart';
import '../../models/service.dart';
import '../../controllers/service_tracker_controller.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/booking_tracker_card.dart';
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

  @override
  void initState() {
    super.initState();
    _providerFuture = _resolveProvider();
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
        final sorted = [...bookings]
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

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
        SnackBar(content: Text('Could not update availability: $e'), backgroundColor: const Color(0xFFB3261E)),
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                provider == null
                                    ? 'Checking profile…'
                                    : '${provider.category} · ${provider.city}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _OnlinePill(isAvailable: _isAvailable, onToggle: _toggleAvailability),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Upcoming Bookings / Réservations',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildStreamView()),
        ],
      ),
    );
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
    required this.onMessage,
    required this.onRefresh,
  });

  final List<_EnrichedBooking> rows;
  final ValueChanged<Booking> onAccept;
  final ValueChanged<Booking> onCancel;
  final ValueChanged<Booking> onReject;
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
        .where((r) => r.booking.isUpcoming || r.booking.status == BookingStatus.completed)
        .fold<int>(0, (sum, r) => sum + r.booking.totalPriceFcfa);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            _MetricCard(
              label: "Today's Clients / Clients Aujourd'hui",
              value: '${upcoming.length}',
              sub: upcoming.isEmpty ? 'No bookings today' : 'Bookings today',
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Total Revenue / Revenu',
              value: formatFcfa(revenue),
              sub: 'Confirmed + completed',
              coral: true,
            ),
          ],
        ),
        const SizedBox(height: 18),
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
    this.coral = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool coral;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: coral ? const Color(0xFFF4665C) : null,
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
    required this.onMessage,
  });

  final _EnrichedBooking row;
  final VoidCallback onAccept;
  final VoidCallback onCancel;
  final VoidCallback onReject;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final booking = row.booking;
    final client = row.client;
    final diff = booking.scheduledAt.difference(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFF4665C), width: 1.4),
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
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
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
                fontSize: 13,
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Accept / Accepter'),
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6E6A76),
                      side: const BorderSide(color: Color(0x33000000)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
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
          color: isAvailable ? const Color(0x143FBF7F) : const Color(0x14FF9F45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isAvailable ? const Color(0x333FBF7F) : const Color(0x33FF9F45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isAvailable ? const Color(0xFF3FBF7F) : const Color(0xFFFF9F45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              isAvailable ? 'Online / Disponible' : 'Offline / Hors ligne',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isAvailable ? const Color(0xFF2E9E66) : const Color(0xFFCC8030),
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
                hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
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
