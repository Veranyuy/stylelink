import 'package:flutter/material.dart';

/// Opens a date picker followed by a time picker and returns the combined
/// [DateTime] (local), or null when cancelled.
///
/// Used by the provider "Counter" action to propose a different slot for a
/// booking (new request or reschedule request).
Future<DateTime?> showCounterProposalSheet(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final base = initial ?? now;

  final date = await showDatePicker(
    context: context,
    initialDate: base.isBefore(now) ? now : base,
    firstDate: now,
    lastDate: now.add(const Duration(days: 120)),
    helpText: 'Counter proposal date / Date de contre-proposition',
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
    helpText: 'Counter proposal time / Heure de contre-proposition',
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
