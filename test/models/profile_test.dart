import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/profile.dart';

void main() {
  group('Profile', () {
    group('fromJson', () {
      test('parses a complete profile row', () {
        final json = {
          'id': 'u1',
          'full_name': 'Jean Mbarga',
          'email': 'jean@example.com',
          'phone_number': '+237612345678',
          'role': 'provider',
          'avatar_url': 'https://example.com/avatar.jpg',
          'language_preference': 'fr',
          'city': 'Douala',
          'created_at': '2025-01-01T00:00:00Z',
        };

        final profile = Profile.fromJson(json);

        expect(profile.id, 'u1');
        expect(profile.fullName, 'Jean Mbarga');
        expect(profile.email, 'jean@example.com');
        expect(profile.phoneNumber, '+237612345678');
        expect(profile.role, UserRole.provider);
        expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
        expect(profile.languagePreference, 'fr');
        expect(profile.city, 'Douala');
        expect(profile.createdAt, isNotNull);
      });

      test('handles missing optional fields', () {
        final json = {
          'id': 'u2',
        };

        final profile = Profile.fromJson(json);

        expect(profile.id, 'u2');
        expect(profile.fullName, isNull);
        expect(profile.email, isNull);
        expect(profile.phoneNumber, isNull);
        expect(profile.role, UserRole.client); // default
        expect(profile.avatarUrl, isNull);
        expect(profile.languagePreference, 'en'); // default
        expect(profile.city, isNull);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final profile = Profile(
          id: 'u1',
          fullName: 'Test User',
          email: 'test@example.com',
          role: UserRole.client,
        );

        final json = profile.toJson();
        expect(json['id'], 'u1');
        expect(json['full_name'], 'Test User');
        expect(json['email'], 'test@example.com');
        expect(json['role'], 'client');
      });
    });

    group('copyWith', () {
      test('copies with new values', () {
        final original = Profile(
          id: 'u1',
          fullName: 'Old Name',
          email: 'test@example.com',
          role: UserRole.client,
          avatarUrl: 'old.jpg',
          city: 'Douala',
        );

        final updated = original.copyWith(
          fullName: 'New Name',
          city: 'Yaoundé',
        );

        expect(updated.id, 'u1');
        expect(updated.fullName, 'New Name');
        expect(updated.email, 'test@example.com');
        expect(updated.avatarUrl, 'old.jpg');
        expect(updated.city, 'Yaoundé');
      });
    });

    group('UserRole', () {
      test('parses all roles', () {
        expect(UserRole.parse('client'), UserRole.client);
        expect(UserRole.parse('provider'), UserRole.provider);
        expect(UserRole.parse(null), UserRole.client);
        expect(UserRole.parse('unknown'), UserRole.client);
      });

      test('labels are correct', () {
        expect(UserRole.client.label, 'Client');
        expect(UserRole.provider.label, 'Provider');
      });
    });

    group('isProvider / isClient', () {
      test('provider role', () {
        final p = Profile(id: 'u1', role: UserRole.provider);
        expect(p.isProvider, isTrue);
        expect(p.isClient, isFalse);
      });

      test('client role', () {
        final p = Profile(id: 'u1', role: UserRole.client);
        expect(p.isProvider, isFalse);
        expect(p.isClient, isTrue);
      });
    });

    group('initials', () {
      test('returns two-letter initials from full name', () {
        final p = Profile(id: 'u1', fullName: 'Jean Mbarga');
        expect(p.initials, 'JM');
      });

      test('returns single letter for single name', () {
        final p = Profile(id: 'u1', fullName: 'Jean');
        expect(p.initials, 'J');
      });

      test('returns ? for null name', () {
        final p = Profile(id: 'u1');
        expect(p.initials, '?');
      });

      test('returns ? for empty name', () {
        final p = Profile(id: 'u1', fullName: '');
        expect(p.initials, '?');
      });
    });
  });
}
