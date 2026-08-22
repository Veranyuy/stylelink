import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../services/supabase_service.dart';
import '../../widgets/booking_tracker_card.dart';

/// Provider calendar/schedule view with a month grid.
/// Days with bookings show a coral dot indicator.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final supabase = SupabaseService.instance;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;
  List<Booking> _allBookings = [];
  String? _providerId;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _resolveProvider();
  }

  Future<void> _resolveProvider() async {
    final user = supabase.currentUser;
    if (user == null) return;
    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return;
    setState(() => _providerId = provider?.id);
    _loadBookings();
  }

  void _loadBookings() {
    final pid = _providerId;
    if (pid == null) return;
    supabase.watchBookingsForProvider(pid).listen((bookings) {
      if (mounted) setState(() => _allBookings = bookings);
    });
  }

  List<Booking> get _selectedDayBookings {
    if (_selectedDay == null) return [];
    final day = _selectedDay!;
    return _allBookings.where((b) {
      final s = b.scheduledAt.toLocal();
      return s.year == day.year && s.month == day.month && s.day == day.day;
    }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Set<int> get _daysWithBookings {
    final set = <int>{};
    for (final b in _allBookings) {
      final s = b.scheduledAt.toLocal();
      if (s.year == _focusedMonth.year && s.month == _focusedMonth.month) set.add(s.day);
    }
    return set;
  }

  void _prev() => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
  void _next() => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));

  @override
  Widget build(BuildContext context) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final title = '${months[_focusedMonth.month - 1]} ${_focusedMonth.year}';
    return SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Schedule / Agenda', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(children: [
          IconButton(onPressed: _prev, icon: const Icon(Icons.chevron_left, size: 24)),
          Expanded(child: Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          IconButton(onPressed: _next, icon: const Icon(Icons.chevron_right, size: 24)),
        ]),
        const SizedBox(height: 10),
        _buildCalendarGrid(),
        const SizedBox(height: 16),
      ],)),
      Expanded(child: _buildDayBookings()),
    ],));
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday - 1;
    final days = _daysWithBookings;
    final today = DateTime.now();
    final weekdays = ['Mo','Tu','We','Th','Fr','Sa','Su'];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000))),
      child: Column(children: [
        Row(children: weekdays.map((d) => Expanded(child: Center(child: Text(d,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
        )).toList()),
        const SizedBox(height: 6),
        for (var week = 0; week < 6; week++)
          Row(children: List.generate(7, (col) {
            final dayNum = week * 7 + col - startWeekday + 1;
            if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox(height: 42));
            final isSel = _selectedDay != null && _selectedDay!.year == _focusedMonth.year
              && _selectedDay!.month == _focusedMonth.month && _selectedDay!.day == dayNum;
            final isToday = today.year == _focusedMonth.year && today.month == _focusedMonth.month && today.day == dayNum;
            final hasDot = days.contains(dayNum);
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _selectedDay = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum)),
              child: Container(height: 40, margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: isSel ? const Color(0xFFF4665C) : isToday ? const Color(0x14F4665C) : null,
                  borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(dayNum.toString(), style: TextStyle(fontSize: 14,
                    fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w500,
                    color: isSel ? Colors.white : null)),
                  if (hasDot) Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(color: isSel ? Colors.white : const Color(0xFFF4665C), shape: BoxShape.circle)),
                ]),
              ),),
            );
          })),
      ],));
  }

  Widget _buildDayBookings() {
    final bookings = _selectedDayBookings;
    if (_selectedDay == null) return const Center(child: Text('Select a day'));
    if (bookings.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.event_available_outlined, size: 40, color: Colors.grey.shade400),
      const SizedBox(height: 8),
      Text('No bookings on this day', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
    ]));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: bookings.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: BookingTrackerCard(booking: bookings[i].toJson(), onStatusUpdated: () => setState(() {})),
      ),);
  }
}
