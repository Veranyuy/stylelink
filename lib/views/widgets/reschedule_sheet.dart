import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';

/// Bottom sheet that lets a client reschedule an upcoming booking.
///
/// Shows a horizontal 7-day day picker and hourly time slots filtered by the
/// provider's `working_hours`. Returns the new [DateTime] when confirmed,
/// or null if cancelled.
class RescheduleSheet extends StatefulWidget {
  const RescheduleSheet({
    super.key,
    required this.booking,
    required this.provider,
  });

  final Booking booking;
  final Provider? provider;

  static Future<DateTime?> show(
    BuildContext context, {
    required Booking booking,
    required Provider? provider,
  }) {
    return showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => RescheduleSheet(booking: booking, provider: provider),
    );
  }

  @override
  State<RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<RescheduleSheet> {
  bool _saving = false;

  // ── Schedule generation (mirrors _SlotPickerSheet) ────────────────────
  final _days = List.generate(14, (i) {
    final d = DateTime.now();
    return DateTime(d.year, d.month, d.day).add(Duration(days: i));
  });

  late DateTime _selectedDay;
  TimeOfDay? _selectedTime;

  Map<String, String?> get _workingHours =>
      widget.provider?.workingHours ?? const {};

  @override
  void initState() {
    super.initState();
    // Default to the booking's current day if within the 14-day window.
    final current = widget.booking.scheduledAt;
    final sameDay = _days.where(
      (d) =>
          d.year == current.year &&
          d.month == current.month &&
          d.day == current.day,
    );
    _selectedDay = sameDay.isNotEmpty ? sameDay.first : _days.first;
    _selectedTime = TimeOfDay.fromDateTime(current);
  }

  String get _selectedDayAbbr {
    const abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return abbr[_selectedDay.weekday - 1];
  }

  bool get _isOpen {
    if (_workingHours.isEmpty) return true;
    return _workingHours.containsKey(_selectedDayAbbr);
  }

  (int, int)? _parseHours() {
    final window = _workingHours[_selectedDayAbbr];
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
        DateTime(
            _selectedDay.year, _selectedDay.month, _selectedDay.day, h),
    ].where((s) => !s.isBefore(now)).toList();
  }

  static String _weekday(DateTime d) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[d.weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Confirm ──────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    final time = _selectedTime;
    if (time == null) return;

    final newDt = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      time.hour,
      time.minute,
    );

    setState(() => _saving = true);
    try {
      await SupabaseService.instance.rescheduleBooking(
        bookingId: widget.booking.id,
        newScheduledAt: newDt,
      );
      if (mounted) Navigator.of(context).pop(newDt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reschedule: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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

            // Title
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 20, color: Color(0xFFF4665C)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Reschedule / Reprogrammer',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Current: ${formatBookingDateTime(widget.booking.scheduledAt)}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 14),

            // ── Day chips ──────────────────────────────────────
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final day = _days[i];
                  final active = _isSameDay(day, _selectedDay);
                  final dayAbbr = _weekday(day).substring(0, 3);
                  final isClosed = _workingHours.isNotEmpty &&
                      !_workingHours.containsKey(dayAbbr);
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

            // ── Closed state ───────────────────────────────────
            if (!_isOpen)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 28, color: Colors.grey.shade400),
                      const SizedBox(height: 6),
                      Text(
                        'Provider closed on ${_weekday(_selectedDay)}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // ── Time slots ──────────────────────────────────
              Text(
                'Available slots / Créneaux disponibles',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 10),
              if (_slots.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No more slots today',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _slots.map((slot) {
                    final isSelected = _selectedTime != null &&
                        slot.hour == _selectedTime!.hour &&
                        slot.minute == _selectedTime!.minute;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedTime = TimeOfDay(
                            hour: slot.hour, minute: slot.minute);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected
                              ? const Color(0xFFF4665C)
                              : const Color(0x08F4665C),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFF4665C)
                                : const Color(0x18000000),
                          ),
                        ),
                        child: Text(
                          formatTime(slot),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF2A2730),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],

            const SizedBox(height: 18),

            // ── Confirm button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _saving || _selectedTime == null || !_isOpen
                        ? null
                        : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF4665C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirm New Time / Confirmer',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
