import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/booking.dart';

void main() {
  group('Booking', () {
    group('fromJson', () {
      test('parses a complete booking row', () {
        final json = {
          'id': 'b1',
          'client_id': 'c1',
          'provider_id': 'p1',
          'service_ids': ['s1', 's2'],
          'scheduled_at': '2025-08-15T10:00:00Z',
          'status': 'confirmed',
          'total_price_fcfa': 10000,
          'notes': 'Trim and fade',
          'created_at': '2025-08-10T08:00:00Z',
          'verification_pin': '1234',
          'arrival_lat': 4.0511,
          'arrival_lng': 9.7679,
          'arrived_at': '2025-08-15T09:55:00Z',
          'started_at': '2025-08-15T10:00:00Z',
          'completed_at': null,
        };

        final booking = Booking.fromJson(json);

        expect(booking.id, 'b1');
        expect(booking.clientId, 'c1');
        expect(booking.providerId, 'p1');
        expect(booking.serviceIds, ['s1', 's2']);
        expect(booking.scheduledAt, DateTime.utc(2025, 8, 15, 10));
        expect(booking.status, BookingStatus.confirmed);
        expect(booking.totalPriceFcfa, 10000);
        expect(booking.notes, 'Trim and fade');
        expect(booking.verificationPin, '1234');
        expect(booking.arrivalLat, closeTo(4.0511, 0.0001));
        expect(booking.arrivalLng, closeTo(9.7679, 0.0001));
        expect(booking.arrivedAt, isNotNull);
        expect(booking.startedAt, isNotNull);
        expect(booking.completedAt, isNull);
      });

      test('handles null and missing fields gracefully', () {
        final json = {
          'id': 'b2',
          'client_id': 'c2',
          'provider_id': 'p2',
          'service_ids': null,
          'scheduled_at': null,
          'status': null,
          'total_price_fcfa': null,
        };

        final booking = Booking.fromJson(json);

        expect(booking.id, 'b2');
        expect(booking.serviceIds, isEmpty);
        expect(booking.status, BookingStatus.pending);
        expect(booking.totalPriceFcfa, 0);
        expect(booking.notes, isNull);
        expect(booking.createdAt, isNull);
      });

      test('parses numeric total_price_fcfa from num type', () {
        final json = {
          'id': 'b3',
          'client_id': 'c3',
          'provider_id': 'p3',
          'service_ids': [],
          'scheduled_at': '2025-01-01T00:00:00Z',
          'status': 'pending',
          'total_price_fcfa': 5500.0, // double from JSON
        };

        final booking = Booking.fromJson(json);
        expect(booking.totalPriceFcfa, 5500);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final booking = Booking(
          id: 'b1',
          clientId: 'c1',
          providerId: 'p1',
          serviceIds: ['s1'],
          scheduledAt: DateTime.utc(2025, 8, 15, 10),
          status: BookingStatus.confirmed,
          totalPriceFcfa: 8000,
        );

        final json = booking.toJson();

        expect(json['id'], 'b1');
        expect(json['client_id'], 'c1');
        expect(json['provider_id'], 'p1');
        expect(json['service_ids'], ['s1']);
        expect(json['status'], 'confirmed');
        expect(json['total_price_fcfa'], 8000);
      });

      test('serializes in_progress as in_progress in JSON', () {
        final booking = Booking(
          id: 'b2',
          clientId: 'c2',
          providerId: 'p2',
          serviceIds: [],
          scheduledAt: DateTime.utc(2025, 1, 1),
          status: BookingStatus.inProgress,
        );

        final json = booking.toJson();
        expect(json['status'], 'in_progress');
      });

      test('includes optional fields only when non-null', () {
        final booking = Booking(
          id: 'b3',
          clientId: 'c3',
          providerId: 'p3',
          serviceIds: [],
          scheduledAt: DateTime.utc(2025, 1, 1),
          status: BookingStatus.pending,
        );

        final json = booking.toJson();
        expect(json.containsKey('verification_pin'), isFalse);
        expect(json.containsKey('arrived_at'), isFalse);
        expect(json.containsKey('completed_at'), isFalse);
      });
    });

    group('isUpcoming / isPast', () {
      test('pending is upcoming', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.pending,
        );
        expect(b.isUpcoming, isTrue);
        expect(b.isPast, isFalse);
      });

      test('confirmed is upcoming', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.confirmed,
        );
        expect(b.isUpcoming, isTrue);
      });

      test('arrived is upcoming', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.arrived,
        );
        expect(b.isUpcoming, isTrue);
      });

      test('inProgress is upcoming', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.inProgress,
        );
        expect(b.isUpcoming, isTrue);
      });

      test('completed is past', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.completed,
        );
        expect(b.isPast, isTrue);
        expect(b.isUpcoming, isFalse);
      });

      test('cancelled is past', () {
        final b = Booking(
          id: 'x',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: DateTime.now(),
          status: BookingStatus.cancelled,
        );
        expect(b.isPast, isTrue);
      });
    });

    group('BookingStatus.parse', () {
      test('parses all known statuses', () {
        expect(BookingStatus.parse('pending'), BookingStatus.pending);
        expect(BookingStatus.parse('confirmed'), BookingStatus.confirmed);
        expect(BookingStatus.parse('arrived'), BookingStatus.arrived);
        expect(BookingStatus.parse('in_progress'), BookingStatus.inProgress);
        expect(BookingStatus.parse('completed'), BookingStatus.completed);
        expect(BookingStatus.parse('cancelled'), BookingStatus.cancelled);
        expect(BookingStatus.parse('canceled'), BookingStatus.cancelled);
        expect(BookingStatus.parse('rejected'), BookingStatus.rejected);
      });

      test('falls back to pending for unknown status', () {
        expect(BookingStatus.parse('unknown'), BookingStatus.pending);
        expect(BookingStatus.parse(null), BookingStatus.pending);
      });
    });

    group('BookingStatus.dbValue', () {
      test('in_progress maps to in_progress', () {
        expect(BookingStatus.inProgress.dbValue, 'in_progress');
      });

      test('other statuses use their name', () {
        expect(BookingStatus.pending.dbValue, 'pending');
        expect(BookingStatus.confirmed.dbValue, 'confirmed');
        expect(BookingStatus.completed.dbValue, 'completed');
        expect(BookingStatus.cancelled.dbValue, 'cancelled');
      });
    });

    group('BookingStatus.statusLabel', () {
      test('provides bilingual labels', () {
        expect(BookingStatus.pending.statusLabel, contains('Pending'));
        expect(BookingStatus.confirmed.statusLabel, contains('Confirmed'));
        expect(BookingStatus.arrived.statusLabel, contains('Arrived'));
        expect(BookingStatus.inProgress.statusLabel, contains('In Progress'));
        expect(BookingStatus.completed.statusLabel, contains('Completed'));
        expect(BookingStatus.cancelled.statusLabel, contains('Cancelled'));
      });
    });
  });
}
