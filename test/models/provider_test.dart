import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/provider.dart';

void main() {
  group('Provider', () {
    group('fromJson', () {
      test('parses a complete provider row', () {
        final json = {
          'id': 'p1',
          'user_id': 'u1',
          'business_name': 'Studio Akwa',
          'category': 'Barbing / Coiffure',
          'city': 'Douala',
          'quarter': 'Bonapriso',
          'bio': 'Best barbers in town',
          'rating': 4.5,
          'review_count': 23,
          'service_type': 'both',
          'price_from': 5000,
          'cover_url': 'https://example.com/cover.jpg',
          'avatar_url': 'https://example.com/avatar.jpg',
          'is_verified': true,
          'is_available': false,
          'portfolio_images': ['https://img1.jpg', 'https://img2.jpg'],
          'working_hours': {
            'Mon': '09:00-18:00',
            'Tue': '09:00-18:00',
            'Wed': null,
            'Thu': '10:00-16:00',
            'Fri': '09:00-19:00',
            'Sat': '09:00-14:00',
            'Sun': null,
          },
          'created_at': '2025-01-01T00:00:00Z',
        };

        final provider = Provider.fromJson(json);

        expect(provider.id, 'p1');
        expect(provider.userId, 'u1');
        expect(provider.businessName, 'Studio Akwa');
        expect(provider.category, 'Barbing / Coiffure');
        expect(provider.city, 'Douala');
        expect(provider.quarter, 'Bonapriso');
        expect(provider.bio, 'Best barbers in town');
        expect(provider.rating, closeTo(4.5, 0.01));
        expect(provider.reviewCount, 23);
        expect(provider.serviceType, ServiceType.both);
        expect(provider.priceFrom, 5000);
        expect(provider.coverUrl, 'https://example.com/cover.jpg');
        expect(provider.avatarUrl, 'https://example.com/avatar.jpg');
        expect(provider.isVerified, isTrue);
        expect(provider.isAvailable, isFalse);
        expect(provider.portfolioImages, hasLength(2));
        expect(provider.workingHours['Mon'], '09:00-18:00');
        expect(provider.workingHours['Wed'], isNull);
      });

      test('resolves avatar_url from joined profiles', () {
        final json = {
          'id': 'p2',
          'user_id': 'u2',
          'business_name': 'Hair Art',
          'category': 'Braiding / Tresses',
          'city': 'Yaoundé',
          'profiles': {
            'avatar_url': 'https://example.com/profile_avatar.jpg',
          },
        };

        final provider = Provider.fromJson(json);
        expect(provider.avatarUrl, 'https://example.com/profile_avatar.jpg');
      });

      test('handles missing fields gracefully', () {
        final json = {
          'id': 'p3',
          'user_id': 'u3',
          'business_name': 'Minimal',
          'category': '',
          'city': '',
        };

        final provider = Provider.fromJson(json);
        expect(provider.quarter, isNull);
        expect(provider.bio, isNull);
        expect(provider.rating, 0);
        expect(provider.reviewCount, 0);
        expect(provider.priceFrom, 0);
        expect(provider.isVerified, isFalse);
        expect(provider.isAvailable, isTrue);
        expect(provider.portfolioImages, isEmpty);
        expect(provider.workingHours, isEmpty);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final provider = Provider(
          id: 'p1',
          userId: 'u1',
          businessName: 'Studio',
          category: 'Barbing',
          city: 'Douala',
          rating: 4.0,
          reviewCount: 10,
          priceFrom: 3000,
        );

        final json = provider.toJson();
        expect(json['id'], 'p1');
        expect(json['business_name'], 'Studio');
        expect(json['category'], 'Barbing');
        expect(json['rating'], 4.0);
        expect(json['review_count'], 10);
      });
    });

    group('workingHoursLabel', () {
      test('returns null when no hours are set', () {
        final provider = Provider(
          id: 'p1',
          userId: 'u1',
          businessName: 'Test',
          category: 'Barbing',
          city: 'Douala',
        );
        expect(provider.workingHoursLabel, isNull);
      });

      test('groups consecutive days with same hours', () {
        final provider = Provider(
          id: 'p1',
          userId: 'u1',
          businessName: 'Test',
          category: 'Barbing',
          city: 'Douala',
          workingHours: {
            'Mon': '09:00-18:00',
            'Tue': '09:00-18:00',
            'Wed': '09:00-18:00',
            'Thu': '09:00-18:00',
            'Fri': '09:00-18:00',
            'Sat': '10:00-14:00',
            'Sun': null,
          },
        );

        final label = provider.workingHoursLabel;
        expect(label, isNotNull);
        expect(label, contains('Mon'));
        expect(label, contains('Fri'));
        expect(label, contains('Sat'));
      });
    });

    group('ServiceType', () {
      test('parses all types', () {
        expect(ServiceType.parse('studio'), ServiceType.studio);
        expect(ServiceType.parse('home'), ServiceType.home);
        expect(ServiceType.parse('both'), ServiceType.both);
        expect(ServiceType.parse(null), ServiceType.studio);
        expect(ServiceType.parse('unknown'), ServiceType.studio);
      });
    });

    group('offersHomeService', () {
      test('home service type returns true', () {
        final p = Provider(
          id: 'p',
          userId: 'u',
          businessName: 'Test',
          category: 'Barbing',
          city: 'Douala',
          serviceType: ServiceType.home,
        );
        expect(p.offersHomeService, isTrue);
      });

      test('both service type returns true', () {
        final p = Provider(
          id: 'p',
          userId: 'u',
          businessName: 'Test',
          category: 'Barbing',
          city: 'Douala',
          serviceType: ServiceType.both,
        );
        expect(p.offersHomeService, isTrue);
      });

      test('studio service type returns false', () {
        final p = Provider(
          id: 'p',
          userId: 'u',
          businessName: 'Test',
          category: 'Barbing',
          city: 'Douala',
          serviceType: ServiceType.studio,
        );
        expect(p.offersHomeService, isFalse);
      });
    });

    group('copyWith', () {
      test('copies with new values', () {
        final original = Provider(
          id: 'p1',
          userId: 'u1',
          businessName: 'Old Name',
          category: 'Barbing',
          city: 'Douala',
          rating: 4.5,
        );

        final updated = original.copyWith(
          businessName: 'New Name',
          city: 'Yaoundé',
        );

        expect(updated.id, 'p1');
        expect(updated.userId, 'u1');
        expect(updated.businessName, 'New Name');
        expect(updated.city, 'Yaoundé');
        expect(updated.rating, 4.5); // unchanged
      });
    });
  });
}
