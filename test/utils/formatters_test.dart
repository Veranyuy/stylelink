import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/utils/formatters.dart';

void main() {
  group('formatFcfa', () {
    test('formats zero', () {
      expect(formatFcfa(0), contains('0'));
      expect(formatFcfa(0), contains('FCFA'));
    });

    test('formats small amounts', () {
      expect(formatFcfa(500), contains('500'));
    });

    test('formats large amounts with separator', () {
      final result = formatFcfa(15000);
      expect(result, contains('15'));
      expect(result, contains('000'));
    });

    test('formats 50000', () {
      final result = formatFcfa(50000);
      expect(result, contains('50'));
      expect(result, contains('000'));
    });
  });

  group('formatBookingDateTime', () {
    test('formats a date correctly', () {
      final dt = DateTime(2025, 8, 15, 14, 30);
      final result = formatBookingDateTime(dt);
      // Should contain the date and time
      expect(result, anyOf(contains('10:30 AM'), contains('2:30 PM')));
      expect(result, contains('Aug'));
    });

    test('formats midnight', () {
      final dt = DateTime(2025, 1, 1, 0, 0);
      final result = formatBookingDateTime(dt);
      expect(result, isNotEmpty);
    });
  });

  group('formatTime', () {
    test('formats morning time', () {
      final dt = DateTime(2025, 8, 15, 9, 0);
      final result = formatTime(dt);
      expect(result, contains('9'));
      expect(result, contains('AM'));
    });

    test('formats afternoon time', () {
      final dt = DateTime(2025, 8, 15, 14, 30);
      final result = formatTime(dt);
      expect(result, contains('2:30'));
      expect(result, contains('PM'));
    });

    test('formats noon', () {
      final dt = DateTime(2025, 8, 15, 12, 0);
      final result = formatTime(dt);
      expect(result, contains('12'));
      expect(result, contains('PM'));
    });
  });

  group('formatDate', () {
    test('formats a date', () {
      final dt = DateTime(2025, 8, 15);
      final result = formatDate(dt);
      expect(result, contains('Aug'));
      expect(result, contains('15'));
    });
  });

  group('formatShortDate', () {
    test('formats compact date', () {
      final dt = DateTime(2025, 8, 15);
      final result = formatShortDate(dt);
      expect(result, contains('Aug'));
      expect(result, contains('15'));
    });
  });
}
