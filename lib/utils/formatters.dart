import 'package:intl/intl.dart';

/// "8 000 FCFA" — thin-space grouped, matching the app's copy style.
String formatFcfa(int amount) =>
    '${NumberFormat.decimalPattern('fr').format(amount)} FCFA';

/// "Tue, Aug 18 · 10:30 AM" — used across booking cards.
String formatBookingDateTime(DateTime dt) {
  final local = dt.toLocal();
  final date = DateFormat('EEE, MMM d').format(local);
  final time = DateFormat('h:mm a').format(local);
  return '$date · $time';
}

/// "10:30 AM" — used on provider dashboard time pills.
String formatTime(DateTime dt) => DateFormat('h:mm a').format(dt.toLocal());

/// "Tue, Aug 18" — used for date-only chips.
String formatDate(DateTime dt) => DateFormat('EEE, MMM d').format(dt.toLocal());

/// "Aug 18" — compact date used in conversation lists.
String formatShortDate(DateTime dt) => DateFormat('MMM d').format(dt.toLocal());
