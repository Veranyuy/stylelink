import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/service.dart';

void main() {
  group('Service', () {
    group('fromJson', () {
      test('parses a complete service row', () {
        final json = {
          'id': 's1',
          'provider_id': 'p1',
          'name': "Gentleman's Cut",
          'description': 'Classic haircut with hot towel',
          'price': 5000,
          'duration_minutes': 30,
          'is_active': true,
          'created_at': '2025-01-01T00:00:00Z',
        };

        final service = Service.fromJson(json);

        expect(service.id, 's1');
        expect(service.providerId, 'p1');
        expect(service.name, "Gentleman's Cut");
        expect(service.description, 'Classic haircut with hot towel');
        expect(service.price, 5000);
        expect(service.durationMinutes, 30);
        expect(service.isActive, isTrue);
      });

      test('falls back to title column when name is missing', () {
        final json = {
          'id': 's2',
          'provider_id': 'p1',
          'title': 'Legacy Service',
          'price': 3000,
          'duration_minutes': 15,
        };

        final service = Service.fromJson(json);
        expect(service.name, 'Legacy Service');
      });

      test('handles null fields gracefully', () {
        final json = {
          'id': 's3',
          'provider_id': 'p1',
          'name': 'Basic',
          'price': null,
          'duration_minutes': null,
          'is_active': null,
        };

        final service = Service.fromJson(json);
        expect(service.price, 0);
        expect(service.durationMinutes, 0);
        expect(service.isActive, isTrue); // default
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Service',
          price: 5000,
          durationMinutes: 30,
          isActive: true,
        );

        final json = service.toJson();
        expect(json['name'], 'Service');
        expect(json['price'], 5000);
        expect(json['duration_minutes'], 30);
        expect(json['is_active'], isTrue);
        expect(json.containsKey('id'), isFalse); // id not sent on update
      });
    });

    group('priceLabel', () {
      test('formats FCFA with thousands separator', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Test',
          price: 15000,
          durationMinutes: 30,
        );
        expect(service.priceLabel, contains('15'));
        expect(service.priceLabel, contains('FCFA'));
      });

      test('formats small amounts', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Test',
          price: 500,
          durationMinutes: 15,
        );
        expect(service.priceLabel, contains('500'));
        expect(service.priceLabel, contains('FCFA'));
      });
    });

    group('durationLabel', () {
      test('formats minutes only', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Test',
          price: 5000,
          durationMinutes: 30,
        );
        expect(service.durationLabel, '30 mins');
      });

      test('formats hours only', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Test',
          price: 5000,
          durationMinutes: 60,
        );
        expect(service.durationLabel, '1 hr');
      });

      test('formats hours and minutes', () {
        final service = Service(
          id: 's1',
          providerId: 'p1',
          name: 'Test',
          price: 5000,
          durationMinutes: 90,
        );
        expect(service.durationLabel, '1 hr 30');
      });
    });
  });
}
