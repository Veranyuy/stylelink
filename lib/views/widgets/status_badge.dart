import 'package:flutter/material.dart';

import '../../models/booking.dart';

/// Colored status pill used on booking cards and the provider dashboard.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final BookingStatus status;

  Color get _color => switch (status) {
        BookingStatus.pending => const Color(0xFFFF9F45), // orange — awaiting
        BookingStatus.confirmed => const Color(0xFF3FBF7F), // green
        BookingStatus.arrived => const Color(0xFF9E86E6), // lavender
        BookingStatus.inProgress => const Color(0xFFF4665C), // coral
        BookingStatus.completed => const Color(0xFF4A90E2), // blue
        BookingStatus.cancelled => const Color(0xFFE5484D), // red
        BookingStatus.rejected => const Color(0xFFE5484D), // red
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withValues(alpha: .45)),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .02,
            ),
          ),
        ],
      ),
    );
  }
}
