import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/controllers/service_tracker_controller.dart';

void main() {
  group('ServiceTrackerController', () {
    group('distanceKm', () {
      test('returns 0 for same coordinates', () {
        final distance = ServiceTrackerController.distanceKm(
          4.0511,
          9.7679,
          4.0511,
          9.7679,
        );
        expect(distance, closeTo(0, 0.001));
      });

      test('calculates distance between Douala and Yaoundé correctly', () {
        // Douala: 4.0511°N, 9.7679°E
        // Yaoundé: 3.8480°N, 11.4980°E
        // Approximate distance: ~193 km
        final distance = ServiceTrackerController.distanceKm(
          4.0511,
          9.7679,
          3.8480,
          11.4980,
        );
        expect(distance, greaterThan(180));
        expect(distance, lessThan(210));
      });

      test('calculates small distance accurately', () {
        // Two points ~1km apart
        final distance = ServiceTrackerController.distanceKm(
          4.0511,
          9.7679,
          4.0520,
          9.7680,
        );
        expect(distance, greaterThan(0.01));
        expect(distance, lessThan(1));
      });

      test('handles negative coordinates', () {
        final distance = ServiceTrackerController.distanceKm(
          -4.0511,
          -9.7679,
          -4.0520,
          -9.7680,
        );
        expect(distance, greaterThan(0));
      });
    });
  });
}
