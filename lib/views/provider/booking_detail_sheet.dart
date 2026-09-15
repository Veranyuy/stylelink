import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/status_badge.dart';

/// Bottom sheet showing a booking's full details with status-aware actions.
///
/// - Pending booking → Accept Booking (→ confirmed) / Decline (→ rejected)
/// - Pending reschedule request → Accept New Time (move slot + confirm) /
///   Decline New Time (keep original slot, mark rejected)
/// - Confirmed booking → Mark as Completed (→ completed) / Cancel
///
/// After any successful write the Future resolves and the caller should
/// refresh its data ([onActionTaken] callback).
Future<void> showBookingDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> booking,
  required String clientName,
  required String serviceName,
  required VoidCallback onActionTaken,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BookingDetailSheet(
      booking: booking,
      clientName: clientName,
      serviceName: serviceName,
      onActionTaken: onActionTaken,
    ),
  );
}

class _BookingDetailSheet extends StatefulWidget {
  const _BookingDetailSheet({
    required this.booking,
    required this.clientName,
    required this.serviceName,
    required this.onActionTaken,
  });

  final Map<String, dynamic> booking;
  final String clientName;
  final String serviceName;
  final VoidCallback onActionTaken;

  @override
  State<_BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends State<_BookingDetailSheet> {
  bool _busy = false;
  String? _error;

  BookingStatus get _status =>
      BookingStatus.parse(widget.booking['status']?.toString());
  DateTime? get _proposedAt => DateTime.tryParse(
      widget.booking['proposed_scheduled_at']?.toString() ?? '');
  RescheduleStatus? get _rescheduleStatus =>
      RescheduleStatus.parse(widget.booking['reschedule_status']?.toString());
  bool get _hasPendingReschedule =>
      _rescheduleStatus == RescheduleStatus.pending && _proposedAt != null;

  DateTime get _slot {
    final raw = widget.booking['scheduled_at']?.toString();
    return DateTime.tryParse(raw ?? '') ?? DateTime.now();
  }

  int get _totalFcfa {
    final v = widget.booking['total_price_fcfa'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get _notes => widget.booking['notes']?.toString() ?? '';

  String? get _bookingId => widget.booking['id']?.toString();

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      widget.onActionTaken();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Action failed: $e';
      });
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _acceptBooking() => _runAction(() async {
        await SupabaseService.instance
            .updateBookingStatus(_bookingId!, BookingStatus.confirmed);
      });

  Future<void> _declineBooking() => _runAction(() async {
        await SupabaseService.instance
            .updateBookingStatus(_bookingId!, BookingStatus.rejected);
      });

  Future<void> _acceptNewTime() => _runAction(() async {
        await SupabaseService.instance.respondToReschedule(_bookingId!, true);
      });

  Future<void> _declineNewTime() => _runAction(() async {
        await SupabaseService.instance.respondToReschedule(_bookingId!, false);
      });

  Future<void> _markCompleted() => _runAction(() async {
        await SupabaseService.instance
            .updateBookingStatus(_bookingId!, BookingStatus.completed);
      });

  Future<void> _cancelBooking() => _runAction(() async {
        await SupabaseService.instance
            .updateBookingStatus(_bookingId!, BookingStatus.cancelled);
      });

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header: client + status
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.clientName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      StatusBadge(status: _status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Details grid
                  _detailRow(
                      Icons.content_cut_rounded, 'Service', widget.serviceName),
                  _detailRow(Icons.calendar_month_rounded, 'Date & Time',
                      formatBookingDateTime(_slot)),
                  _detailRow(Icons.payments_rounded, 'Total',
                      _totalFcfa > 0 ? formatFcfa(_totalFcfa) : '—'),
                  if (_notes.isNotEmpty)
                    _detailRow(Icons.notes_rounded, 'Notes', _notes),
                  // Reschedule banner
                  if (_hasPendingReschedule) ...[
                    const SizedBox(height: 14),
                    _rescheduleBanner(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFB3261E)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  // Status-aware actions
                  ..._buildActions(),
                ],
              ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFFF4665C)),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rescheduleBanner() {
    final proposed = _proposedAt!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFB93F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x55FFB93F)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.update_rounded, size: 19, color: Color(0xFFB57A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reschedule request / Demande de report',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A5A00),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Proposed / Proposé : ${formatDate(proposed)} · ${formatTime(proposed)}\n'
                  'Current / Actuel : ${formatDate(_slot)} · ${formatTime(_slot)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A2730),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    // A pending reschedule request takes priority over the status actions:
    // deciding the proposed move comes first.
    if (_hasPendingReschedule) {
      return [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _acceptNewTime,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Accept New Time'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _declineNewTime,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6E6A76),
                  side: const BorderSide(color: Color(0x33000000)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Decline New Time'),
              ),
            ),
          ],
        ),
      ];
    }
    switch (_status) {
      case BookingStatus.pending:
        return [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _acceptBooking,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept Booking'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _declineBooking,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE5484D),
                    side: const BorderSide(color: Color(0x33E5484D)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ];
      case BookingStatus.confirmed:
        return [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _markCompleted,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark as Completed'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelBooking,
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
        ];
      case BookingStatus.arrived:
      case BookingStatus.inProgress:
        return [
          Text(
            'Manage the live session from the Bookings tab tracker.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ];
      case BookingStatus.completed:
        return [
          Text(
            '✅ Completed / Terminé',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700),
          ),
        ];
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
        return [
          Text(
            _status.statusLabel,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ];
    }
  }
}
