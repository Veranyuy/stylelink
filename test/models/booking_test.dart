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

    group('reschedule proposal fields', () {
      final originalSlot = DateTime.utc(2025, 9, 20, 10);
      final proposedSlot = DateTime.utc(2025, 9, 21, 14);

      Booking pendingProposal(
              {BookingStatus status = BookingStatus.confirmed}) =>
          Booking(
            id: 'b10',
            clientId: 'c1',
            providerId: 'p1',
            serviceIds: ['s1'],
            scheduledAt: originalSlot,
            status: status,
            proposedScheduledAt: proposedSlot,
            rescheduleStatus: RescheduleStatus.pending,
          );

      test('parses proposed_scheduled_at and reschedule_status', () {
        final b = Booking.fromJson({
          'id': 'b11',
          'client_id': 'c1',
          'provider_id': 'p1',
          'service_ids': ['s1'],
          'scheduled_at': '2025-09-20T10:00:00Z',
          'status': 'confirmed',
          'proposed_scheduled_at': '2025-09-21T14:00:00Z',
          'reschedule_status': 'pending',
        });

        expect(b.proposedScheduledAt, DateTime.utc(2025, 9, 21, 14));
        expect(b.rescheduleStatus, RescheduleStatus.pending);
        expect(b.hasPendingReschedule, isTrue);
      });

      test('null proposal fields mean no reschedule', () {
        final b = Booking.fromJson({
          'id': 'b12',
          'client_id': 'c1',
          'provider_id': 'p1',
          'service_ids': [],
          'scheduled_at': '2025-09-20T10:00:00Z',
          'status': 'confirmed',
        });

        expect(b.proposedScheduledAt, isNull);
        expect(b.rescheduleStatus, isNull);
        expect(b.hasPendingReschedule, isFalse);
      });

      test('parses declined alias and unknown as null', () {
        expect(RescheduleStatus.parse('declined'), RescheduleStatus.rejected);
        expect(RescheduleStatus.parse('rejected'), RescheduleStatus.rejected);
        expect(RescheduleStatus.parse('pending'), RescheduleStatus.pending);
        expect(RescheduleStatus.parse('accepted'), RescheduleStatus.accepted);
        expect(RescheduleStatus.parse('weird'), isNull);
        expect(RescheduleStatus.parse(null), isNull);
        expect(RescheduleStatus.parse(''), isNull);
      });

      test('toJson round-trips the proposal', () {
        final json = pendingProposal().toJson();
        expect(json['proposed_scheduled_at'], '2025-09-21T14:00:00.000Z');
        expect(json['reschedule_status'], 'pending');
      });

      test('hasPendingReschedule requires slot AND pending status', () {
        final noSlot = Booking(
          id: 'b13',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: originalSlot,
          rescheduleStatus: RescheduleStatus.pending,
        );
        expect(noSlot.hasPendingReschedule, isFalse);

        final resolved = Booking(
          id: 'b14',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: proposedSlot,
          rescheduleStatus: RescheduleStatus.accepted,
        );
        expect(resolved.hasPendingReschedule, isFalse);
      });
    });

    group('resolveRescheduleResponse (respondToReschedule logic)', () {
      final originalSlot = DateTime.utc(2025, 9, 20, 10);
      final proposedSlot = DateTime.utc(2025, 9, 21, 14);

      Booking bookingWithProposal({
        BookingStatus status = BookingStatus.confirmed,
        RescheduleStatus reschedule = RescheduleStatus.pending,
        DateTime? respondedAt,
      }) =>
          Booking(
            id: 'b20',
            clientId: 'c1',
            providerId: 'p1',
            serviceIds: ['s1'],
            scheduledAt: originalSlot,
            status: status,
            proposedScheduledAt:
                reschedule == RescheduleStatus.pending ? proposedSlot : null,
            rescheduleStatus: reschedule,
            respondedAt: respondedAt,
          );

      test('SUCCESS accept: moves slot, confirms, clears proposal', () {
        final decision = resolveRescheduleResponse(
          booking: bookingWithProposal(),
          accept: true,
        );

        expect(decision.status, BookingStatus.confirmed);
        expect(decision.resolvedSlot, proposedSlot);
        expect(decision.updates['scheduled_at'], '2025-09-21T14:00:00.000Z');
        expect(decision.updates['status'], 'confirmed');
        expect(decision.updates['reschedule_status'], 'accepted');
        expect(decision.updates['proposed_scheduled_at'], isNull);
        expect(decision.updates['responded_at'], isNotNull);
      });

      test('SUCCESS decline: keeps original slot and status', () {
        final decision = resolveRescheduleResponse(
          booking: bookingWithProposal(),
          accept: false,
        );

        expect(decision.status, BookingStatus.confirmed); // original status
        expect(decision.resolvedSlot, originalSlot); // original slot
        expect(decision.updates['scheduled_at'], '2025-09-20T10:00:00.000Z');
        expect(decision.updates['status'], 'confirmed');
        expect(decision.updates['reschedule_status'], 'rejected');
        expect(decision.updates['proposed_scheduled_at'], isNull);
      });

      test('decline on a pending booking keeps it pending', () {
        final decision = resolveRescheduleResponse(
          booking: bookingWithProposal(status: BookingStatus.pending),
          accept: false,
        );

        expect(decision.status, BookingStatus.pending);
        expect(decision.updates['status'], 'pending');
        expect(decision.resolvedSlot, originalSlot);
      });

      test('decline stamps responded_at (or now when never set)', () {
        final stamped = DateTime.utc(2025, 9, 19, 9);
        final d1 = resolveRescheduleResponse(
          booking: bookingWithProposal(respondedAt: stamped),
          accept: false,
        );
        expect(d1.updates['responded_at'], '2025-09-19T09:00:00.000Z');

        final d2 = resolveRescheduleResponse(
          booking: bookingWithProposal(respondedAt: null),
          accept: false,
        );
        expect(d2.updates['responded_at'], isNotNull);
      });

      test('EDGE: throws when there is no pending proposal', () {
        final noProposal = Booking(
          id: 'b21',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: originalSlot,
          status: BookingStatus.confirmed,
        );
        expect(
          () => resolveRescheduleResponse(booking: noProposal, accept: true),
          throwsStateError,
        );
      });

      test('EDGE: throws when proposal already resolved', () {
        final resolved = Booking(
          id: 'b22',
          clientId: 'c',
          providerId: 'p',
          serviceIds: [],
          scheduledAt: originalSlot,
          status: BookingStatus.confirmed,
          rescheduleStatus: RescheduleStatus.accepted,
        );
        expect(
          () => resolveRescheduleResponse(booking: resolved, accept: true),
          throwsStateError,
        );
      });

      test('EDGE: throws for terminal booking states', () {
        for (final terminal in [
          BookingStatus.completed,
          BookingStatus.cancelled,
          BookingStatus.rejected,
        ]) {
          final done = Booking(
            id: 'b23',
            clientId: 'c',
            providerId: 'p',
            serviceIds: [],
            scheduledAt: originalSlot,
            status: terminal,
            proposedScheduledAt: proposedSlot,
            rescheduleStatus: RescheduleStatus.pending,
          );
          expect(
            () => resolveRescheduleResponse(booking: done, accept: true),
            throwsStateError,
            reason: '$terminal must not be reschedule-respondable',
          );
        }
      });

      test('EDGE: accept on a pending booking still confirms', () {
        final decision = resolveRescheduleResponse(
          booking: bookingWithProposal(status: BookingStatus.pending),
          accept: true,
        );
        expect(decision.status, BookingStatus.confirmed);
        expect(decision.resolvedSlot, proposedSlot);
      });
    });
  });
}
