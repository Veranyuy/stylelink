import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../models/booking.dart';
import '../../../models/provider.dart';
import '../../../services/supabase_service.dart';
import '../../../widgets/custom_avatar.dart';
import '../../../widgets/review_modal.dart';

/// Realtime tracker card shown at the top of the Client Home screen when
/// the client has an active booking (confirmed → arrived → in_progress).
///
/// Subscribes to Supabase Realtime changes on `public.bookings` for the
/// client's most recent active booking, so stage transitions pushed by
/// the provider update the UI instantly.
///
/// ## Stage-specific UI
///
/// | Status       | What the client sees                                      |
/// |-------------|------------------------------------------------------------|
/// | confirmed   | "Provider is En Route" banner, provider details, Call/Msg  |
/// | arrived     | Flashing "Provider Has Arrived!" banner, prominent PIN     |
/// | in_progress | Session timer (from started_at), "Service Underway"        |
/// | completed   | Completion toast + prompt to rate (handled by parent)      |
class ActiveBookingTrackerCard extends StatefulWidget {
  const ActiveBookingTrackerCard({super.key});

  @override
  State<ActiveBookingTrackerCard> createState() =>
      _ActiveBookingTrackerCardState();
}

class _ActiveBookingTrackerCardState extends State<ActiveBookingTrackerCard> {
  final supabase = SupabaseService.instance;

  Stream<List<Booking>>? _bookingStream;
  Timer? _timer;

  /// The latest active booking from the stream.
  Booking? _activeBooking;

  /// Set of booking ids we have already shown the review modal for,
  /// so we don't re-trigger on the same completed booking.
  final Set<String> _reviewedBookingIds = {};

  /// The id of the last booking we saw in the active list.
  /// When it disappears, we check the full stream for a completed transition.
  String? _lastActiveBookingId;

  /// Enriched provider data for the active booking.
  Provider? _provider;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initStream() {
    final userId = supabase.currentUser?.id;
    if (userId == null) return;

    _bookingStream = supabase.watchBookingsForClient(userId);
  }

  /// Resolve provider metadata for the active booking.
  Future<void> _resolveProvider(String providerId) async {
    final provider = await supabase.fetchProviderById(providerId);
    if (mounted) setState(() => _provider = provider);
  }

  /// Start a 1-second timer for the live session clock.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bookingStream == null) return const SizedBox.shrink();

    return StreamBuilder<List<Booking>>(
      stream: _bookingStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final bookings = snapshot.data!;
        // Find the most recent active booking (confirmed/arrived/in_progress).
        final active = bookings
            .where((b) =>
                b.status == BookingStatus.confirmed ||
                b.status == BookingStatus.arrived ||
                b.status == BookingStatus.inProgress)
            .toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

        // Detect completion: if a previously-active booking has left the
        // active list and now has status 'completed', trigger the review.
        if (_lastActiveBookingId != null) {
          final stillActive = active.any((b) => b.id == _lastActiveBookingId);
          if (!stillActive) {
            final completed = bookings.firstWhere(
              (b) => b.id == _lastActiveBookingId &&
                  b.status == BookingStatus.completed,
              orElse: () => Booking(
                id: '', clientId: '', providerId: '',
                serviceIds: const [], scheduledAt: DateTime(0),
              ),
            );
            if (completed.id.isNotEmpty &&
                !_reviewedBookingIds.contains(completed.id)) {
              _triggerReview(completed);
            }
          }
        }

        if (active.isEmpty) {
          _lastActiveBookingId = null;
          return const SizedBox.shrink();
        }

        final booking = active.first;
        _lastActiveBookingId = booking.id;

        // Track state changes.
        if (_activeBooking?.id != booking.id) {
          _activeBooking = booking;
          _provider = null; // reset
          _resolveProvider(booking.providerId);
        }



        // Ensure timer is running for in_progress.
        if (booking.status == BookingStatus.inProgress && _timer == null) {
          _startTimer();
        } else if (booking.status != BookingStatus.inProgress) {
          _timer?.cancel();
        }

        return _buildCard(booking);
      },
    );
  }

  Widget _buildCard(Booking booking) {        return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: switch (booking.status) {
        BookingStatus.confirmed => _buildConfirmed(booking),
        BookingStatus.arrived => _buildArrived(booking),
        BookingStatus.inProgress => _buildInProgress(booking),
        BookingStatus.completed => _buildCompleted(booking),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ─── Confirmed: Provider is En Route ──────────────────────────────────────

  Widget _buildConfirmed(Booking booking) {
    return _CardShell(
      key: const ValueKey('confirmed'),
      borderColor: const Color(0x443FBF7F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x143FBF7F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.directions_car_filled,
                    size: 18, color: Color(0xFF2E9E66)),
                SizedBox(width: 8),
                Text(
                  'Provider is En Route',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E9E66),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Provider details.
          _ProviderRow(provider: _provider, providerId: booking.providerId),
          const SizedBox(height: 14),
          // Verification PIN badge.
          _PinBadge(pin: booking.verificationPin),
          const SizedBox(height: 14),
          // Call / Message buttons.
          _ActionButtons(
            provider: _provider,
            providerId: booking.providerId,
            clientId: booking.clientId,
          ),
        ],
      ),
    );
  }

  // ─── Arrived: Provider Has Arrived! ───────────────────────────────────────

  Widget _buildArrived(Booking booking) {
    return _CardShell(
      key: const ValueKey('arrived'),
      borderColor: const Color(0xFFF4665C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flashing arrival banner.
          _ArrivalBanner(),
          const SizedBox(height: 14),
          // Provider details.
          _ProviderRow(provider: _provider, providerId: booking.providerId),
          const SizedBox(height: 14),
          // Highlighted PIN badge.
          _PinBadge(
            pin: booking.verificationPin,
            highlight: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Share this code with your provider to start the session.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 14),
          // Call / Message buttons.
          _ActionButtons(
            provider: _provider,
            providerId: booking.providerId,
            clientId: booking.clientId,
          ),
        ],
      ),
    );
  }

  // ─── In Progress: Session Active ──────────────────────────────────────────

  Widget _buildInProgress(Booking booking) {
    final startedAt = booking.startedAt;
    final elapsed = startedAt != null
        ? DateTime.now().difference(startedAt)
        : Duration.zero;

    return _CardShell(
      key: const ValueKey('in_progress'),
      borderColor: const Color(0x66F4665C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active session banner.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x14F4665C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Pulsing dot.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  builder: (_, v, __) => Opacity(
                    opacity: v,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF4665C),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Service Underway',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF4665C),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Session timer.
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x22F4665C)),
              ),
              child: Column(
                children: [
                  Text(
                    _formatDuration(elapsed),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A2730),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Session Duration',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Provider details (compact).
          _ProviderRow(provider: _provider, providerId: booking.providerId),
        ],
      ),
    );
  }

  // ─── Completed: Session Finished ─────────────────────────────────────────

  Widget _buildCompleted(Booking booking) {
    return _CardShell(
      key: const ValueKey('completed'),
      borderColor: const Color(0xFF3FBF7F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x143FBF7F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 20, color: Color(0xFF3FBF7F)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Session Completed / Session Terminée',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3FBF7F),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ProviderRow(provider: _provider, providerId: booking.providerId),
          if (booking.totalPriceFcfa > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Total Paid / Montant:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Text(
                  '${booking.totalPriceFcfa.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} FCFA',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3FBF7F),
                  ),
                ),
              ],
            ),
          ],
          if (_reviewedBookingIds.contains(booking.id)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x0A3FBF7F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB93F)),
                  SizedBox(width: 6),
                  Text(
                    'Reviewed / Avis donné',
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
    );
  }

  // ─── Review trigger ────────────────────────────────────────────────────────

  void _triggerReview(Booking booking) {
    // Mark as handled immediately to prevent duplicate triggers.
    _reviewedBookingIds.add(booking.id);

    // Delay slightly so the completed UI renders first.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      ReviewModal.show(
        context,
        bookingId: booking.id,
        providerId: booking.providerId,
        providerName: _provider?.businessName ?? 'your stylist',
        onReviewSubmitted: () {
          if (mounted) setState(() {});
        },
      );
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// Card shell
// =============================================================================

class _CardShell extends StatelessWidget {
  const _CardShell({
    super.key,
    required this.borderColor,
    required this.child,
  });

  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: .08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// =============================================================================
// Verification PIN badge
// =============================================================================

class _PinBadge extends StatelessWidget {
  const _PinBadge({this.pin, this.highlight = false});

  final String? pin;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (pin == null || pin!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x14F4665C) : const Color(0x0AF4665C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? const Color(0xFFF4665C)
              : const Color(0x33F4665C),
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: highlight
                    ? const Color(0xFFF4665C)
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Verification PIN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlight
                      ? const Color(0xFFF4665C)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pin!,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
              color: highlight
                  ? const Color(0xFFF4665C)
                  : const Color(0xFF2A2730),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share this code with your provider upon arrival to start the session.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Arrival banner (flashing)
// =============================================================================

class _ArrivalBanner extends StatefulWidget {
  @override
  State<_ArrivalBanner> createState() => _ArrivalBannerState();
}

class _ArrivalBannerState extends State<_ArrivalBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);
  late final Animation<double> _anim =
      Tween(begin: 0.4, end: 1.0).animate(_ctrl);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF4665C), width: 1.5),
        ),
        child: const Row(
          children: [
            Icon(Icons.notifications_active,
                size: 20, color: Color(0xFFF4665C)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provider Has Arrived!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF4665C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Prepare for your service.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB3261E)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Provider row (avatar + name + category)
// =============================================================================

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider, required this.providerId});

  final Provider? provider;
  final String providerId;

  @override
  Widget build(BuildContext context) {
    final name = provider?.businessName ?? 'Your provider';
    final category = provider?.category ?? '';

    return Row(
      children: [
        CustomAvatar(
          avatarUrl: provider?.avatarUrl,
          displayName: name,
          radius: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (category.isNotEmpty)
                Text(
                  category,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Call / Message action buttons
// =============================================================================

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.provider,
    required this.providerId,
    required this.clientId,
  });

  final Provider? provider;
  final String providerId;
  final String clientId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _callProvider,
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E9E66),
              side: const BorderSide(color: Color(0x443FBF7F)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openChat(context),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF4665C),
              side: const BorderSide(color: Color(0x33F4665C)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _callProvider() async {
    // No phone number on the provider model — open the dialer with a
    // placeholder or use the chat as the primary contact method.
    final uri = Uri(scheme: 'tel', path: '');
    await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
  }

  void _openChat(BuildContext context) {
    // Navigate to the chat screen — the parent shell handles routing.
    // For now, show a placeholder.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening chat…')),
    );
  }
}
