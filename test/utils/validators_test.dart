import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/utils/validators.dart';

void main() {
  group('sign-in / sign-up validation', () {
    test('rejects empty, malformed and domain-less emails', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a@@b.com'), isNotNull);
    });

    test('accepts a normal email', () {
      expect(Validators.email('client@stylelink.app'), isNull);
    });

    test('enforces the six-character password minimum', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('requires a full name only when signing up', () {
      expect(Validators.required('   ', message: 'Name required'), isNotNull);
      expect(Validators.required('Awa N.'), isNull);
    });

    test('normalises Cameroon phone numbers', () {
      expect(
          Validators.normalizeCameroonPhone('6 77 12 34 56'), '+237677123456');
      expect(Validators.normalizeCameroonPhone('+237 677 12 34 56'),
          '+237677123456');
      expect(Validators.normalizeCameroonPhone('123'), isNull);
    });
  });

  group('provider onboarding validation', () {
    test('step 1 requires name, category and city', () {
      expect(
        Validators.canContinueShopDetails(
          businessName: 'Glow Studio',
          category: 'Braiding / Tresses',
          city: 'Douala',
        ),
        isTrue,
      );
      expect(
        Validators.canContinueShopDetails(
          businessName: '  ',
          category: 'Braiding / Tresses',
          city: 'Douala',
        ),
        isFalse,
      );
      expect(
        Validators.canContinueShopDetails(
          businessName: 'Glow Studio',
          category: null,
          city: 'Douala',
        ),
        isFalse,
      );
    });

    test('service drafts need a name, positive price and duration', () {
      expect(
        Validators.serviceDraftError(
          name: 'Braids',
          priceText: '5000',
          durationText: '120',
        ),
        isNull,
      );
      expect(
        Validators.serviceDraftError(
          name: '',
          priceText: '5000',
          durationText: '120',
        ),
        isNotNull,
      );
      expect(
        Validators.serviceDraftError(
          name: 'Braids',
          priceText: '0',
          durationText: '120',
        ),
        isNotNull,
      );
      expect(
        Validators.serviceDraftError(
          name: 'Braids',
          priceText: '5000',
          durationText: '0',
        ),
        isNotNull,
      );
    });

    test('cannot finish setup with no services (shop would be hidden)', () {
      expect(Validators.finishSetupError(serviceCount: 0), isNotNull);
      expect(Validators.finishSetupError(serviceCount: 1), isNull);
    });
  });
}
