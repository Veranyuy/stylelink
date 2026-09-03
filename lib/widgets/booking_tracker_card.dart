import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../controllers/service_tracker_controller.dart';
import '../models/booking.dart';

/// A self-contained card that drives the provider-side booking lifecycle.
///
/// Accepts a raw booking map (as returned by Supabase `select()`) and renders
/// the appropriate action buttons for the current status:
///
/// - **confirmed** → "Open GPS Navigation" + "Mark as Arrived"
/// - **arrived**   → "Start Work" (opens PIN verification dialog)
/// - **in_progress** → "Finish Session & Collect Cash/Mobile Money"
/// - **completed** → green completion badge
///
/// After every successful stage advance, [onStatusUpdated] is called so the
/// parent can refresh its data.
class BookingTrackerCard extends StatefulWidget {
  const BookingTrackerCard({
    super.key,
    required this.booking,
    required this.onStatusUpdated,
  });

  /// Raw booking row from Supabase (must contain `id`, `status`, and
  /// optionally `client_id`, `provider_id`, `total_price_fcfa`, `notes`).
  final Map<String, dynamic> booking;

  /// Called after a successful stage transition so the parent can reload.
  final VoidCallback onStatusUpdated;

  @override
  State<BookingTrackerCard> createState() => _BookingTrackerCardState();
}

class _BookingTrackerCardState extends State<BookingTrackerCard> {
  final _tracker = ServiceTrackerController.instance;
  bool _loading = false;
  Timer? _ticker;

  String get _bookingId => widget.booking['id']?.toString() ?? '';
  BookingStatus get _status => BookingStatus.parse(widget.booking['status']);
  int get _totalFcfa {
    final v = widget.booking['total_price_fcfa'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Parsed started_at timestamp for the live session timer.
  DateTime? get _startedAt {
    final raw = widget.booking['started_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Manage the 1-second ticker based on status changes.
  void _manageTicker() {
    if (_status == BookingStatus.inProgress && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (_status != BookingStatus.inProgress && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _markArrived() async {
    setState(() => _loading = true);

    double? lat;
    double? lng;

    // Attempt to get GPS position — on web or unsupported browsers this
    // may throw MissingPluginException, PermissionDeniedException, or a
    // plain [Exception].  We catch everything and fall back to null coords
    // so the status transition can still complete.
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          // Permission denied — proceed without GPS.
          _showLocationFallback();
        }
      }

      // Only attempt to read position if permission was granted.
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        lat = position.latitude;
        lng = position.longitude;
      }
    } catch (_) {
      // Geolocator unavailable (web, MissingPluginException, etc.).
      // MissingPluginException extends Error, not Exception, so we catch
      // everything here to ensure the advance phase still runs.
      _showLocationFallback();
    }

    try {
      await _tracker.advanceBookingStage(
        bookingId: _bookingId,
        currentStatus: _status,
        arrivalLat: lat,
        arrivalLng: lng,
      );

      if (mounted) widget.onStatusUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not mark arrival: $e'),
            backgroundColor: const Color(0xFFB3261E),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showLocationFallback() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Location unavailable; proceeding without GPS tagging',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showPinDialog() async {
    final pinController = TextEditingController();
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.pin_outlined, color: Color(0xFFF4665C)),
            SizedBox(width: 10),
            Text('Verification PIN'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask the client for their 4-digit verification code.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6E6A76)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                hintStyle: TextStyle(
                  fontSize: 24,
                  color: Colors.grey.shade300,
                  letterSpacing: 12,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Color(0xFFF4665C), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF4665C),
            ),
            child: const Text('Verify & Start'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      pinController.dispose();
      return;
    }

    final pin = pinController.text;
    pinController.dispose();

    // Attempt PIN verification and stage advance.
    setState(() => _loading = true);
    try {
      await _tracker.advanceBookingStage(
        bookingId: _bookingId,
        currentStatus: _status,
        pin: pin,
      );
      if (mounted) widget.onStatusUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: const Color(0xFFB3261E),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndComplete() async {
    // Show a confirmation dialog before marking the session as done.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF3FBF7F)),
            SizedBox(width: 10),
            Text('Complete Service?'),
          ],
        ),
        content: const Text(
          'Mark this service as completed and collect payment.\n'
          'Ce service sera marqué comme terminé.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF6E6A76)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3FBF7F),
            ),
            child: const Text('Complete Service'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _tracker.completeBooking(_bookingId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Service completed! Collect payment from client.'),
            backgroundColor: Color(0xFF2E9E66),
            duration: Duration(seconds: 3),
          ),
        );
        widget.onStatusUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not complete session: $e'),
            backgroundColor: const Color(0xFFB3261E),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _manageTicker();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _statusBorderColor,
          width: _status == BookingStatus.pending ? 1 : 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: status badge + total.
            Row(
              children: [
                _StatusChip(status: _status),
                const Spacer(),
                if (_totalFcfa > 0)
                  Text(
                    '$_totalFcfa FCFA',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF4665C),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Dynamic action area based on status.
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else
              _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    switch (_status) {
      case BookingStatus.confirmed:
        return _buildConfirmedActions();
      case BookingStatus.arrived:
        return _buildArrivedActions();
      case BookingStatus.inProgress:
        return _buildInProgressActions();
      case BookingStatus.completed:
        return _buildCompletedBadge();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── confirmed ─────────────────────────────────────────────────────────────

  Widget _buildConfirmedActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openNavigation,
            icon: const Icon(Icons.directions_car_outlined, size: 18),
            label: const Text('Open GPS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6E6A76),
              side: const BorderSide(color: Color(0x33000000)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PulsingButton(
            child: FilledButton.icon(
              onPressed: _markArrived,
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Mark Arrived'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openNavigation() async {
    // Try to extract lat/lng from the booking's provider location.
    // For now, use the provider's city as a fallback.
    try {
      // If we have arrival coordinates, navigate there.
      final lat = widget.booking['arrival_lat'];
      final lng = widget.booking['arrival_lng'];
      if (lat != null && lng != null) {
        await _tracker.openNavigation(
          (lat as num).toDouble(),
          (lng as num).toDouble(),
        );
      } else {
        // Fallback: open Google Maps search.
        final uri = Uri.https('www.google.com', '/maps', {
          'api': '1',
          'query': widget.booking['provider_city']?.toString() ?? '',
          'travelmode': 'driving',
        });
        await launcher.launchUrl(uri,
            mode: launcher.LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open navigation: $e'),
            backgroundColor: const Color(0xFFB3261E),
          ),
        );
      }
    }
  }

  // ── arrived ───────────────────────────────────────────────────────────────

  Widget _buildArrivedActions() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _showPinDialog,
        icon: const Icon(Icons.play_circle_outline, size: 20),
        label: const Text('Start Work'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3FBF7F),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── in_progress ───────────────────────────────────────────────────────────

  Widget _buildInProgressActions() {
    final elapsed = _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : Duration.zero;

    return Column(
      children: [
        // Pulsing "in progress" indicator.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4665C),
                  shape: BoxShape.circle,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  builder: (_, v, __) => Opacity(
                    opacity: v,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Service in progress…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF4665C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Live session timer.
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                    fontSize: 26,
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
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _confirmAndComplete,
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('Complete & Collect Payment'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3FBF7F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
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

  // ── completed ─────────────────────────────────────────────────────────────

  Widget _buildCompletedBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x143FBF7F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Color(0xFF3FBF7F), size: 22),
          SizedBox(width: 8),
          Text(
            'Session Completed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E9E66),
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusBorderColor => switch (_status) {
        BookingStatus.confirmed => const Color(0x443FBF7F),
        BookingStatus.arrived => const Color(0x44F4665C),
        BookingStatus.inProgress => const Color(0x66F4665C),
        BookingStatus.completed => const Color(0x443FBF7F),
        _ => const Color(0x14000000),
      };
}

// =============================================================================
// Status chip
// =============================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.statusLabel,
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color get _color => switch (status) {
        BookingStatus.pending => const Color(0xFFFF9F45),
        BookingStatus.confirmed => const Color(0xFF3FBF7F),
        BookingStatus.arrived => const Color(0xFF9E86E6),
        BookingStatus.inProgress => const Color(0xFFF4665C),
        BookingStatus.completed => const Color(0xFF4A90E2),
        BookingStatus.cancelled => const Color(0xFFE5484D),
        BookingStatus.rejected => const Color(0xFFE5484D),
      };
}

// =============================================================================
// Pulsing wrapper — draws a soft glow behind the child that breathes in/out.
// =============================================================================

class _PulsingButton extends StatefulWidget {
  const _PulsingButton({required this.child});
  final Widget child;

  @override
  State<_PulsingButton> createState() => _PulsingButtonState();
}

class _PulsingButtonState extends State<_PulsingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);
  late final Animation<double> _glow =
      Tween(begin: 0.0, end: 12.0).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );
  late final Animation<double> _scale =
      Tween(begin: 1.0, end: 1.035).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF4665C).withValues(alpha: 0.35),
                blurRadius: _glow.value,
                spreadRadius: _glow.value * 0.3,
              ),
            ],
          ),
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
