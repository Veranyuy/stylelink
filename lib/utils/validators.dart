/// Pure validation helpers shared by the auth screen, the provider onboarding
/// wizard, and unit tests.
///
/// Keeping these rules outside widgets makes the launch-critical flows
/// testable without initialising Supabase, Firebase, or platform plugins.
class Validators {
  const Validators._();

  /// A generic non-empty requirement.
  static String? required(String? value, {String message = 'Required'}) {
    return value == null || value.trim().isEmpty ? message : null;
  }

  /// Minimal email shape check used by sign-in, sign-up and password reset.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your email.';
    final at = v.indexOf('@');
    if (at <= 0 || at != v.lastIndexOf('@') || at == v.length - 1) {
      return 'Please enter a valid email.';
    }
    final domain = v.substring(at + 1);
    if (!domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.')) {
      return 'Please enter a valid email.';
    }
    return null;
  }

  /// Supabase's default minimum password length.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password.';
    if (value.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  /// Normalise a Cameroon phone number to E.164, or null when it is not a
  /// plausible 9-digit local number / 237-prefixed number.
  static String? normalizeCameroonPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 9) return '+237$digits';
    if (digits.length == 12 && digits.startsWith('237')) return '+$digits';
    return null;
  }

  /// Step 1 of provider onboarding: a named shop with category and city.
  static bool canContinueShopDetails({
    required String businessName,
    required String? category,
    required String? city,
  }) {
    return businessName.trim().isNotEmpty &&
        category != null &&
        category.trim().isNotEmpty &&
        city != null &&
        city.trim().isNotEmpty;
  }

  /// Step 2 of provider onboarding: a named service with a positive price and
  /// duration. Returns a user-facing error, or null when the draft is valid.
  static String? serviceDraftError({
    required String name,
    required String priceText,
    required String durationText,
  }) {
    final price = int.tryParse(priceText.trim());
    final duration = int.tryParse(durationText.trim());
    if (name.trim().isEmpty || price == null || price <= 0) {
      return 'Enter a service name and a price above 0 FCFA.';
    }
    if (duration == null || duration <= 0) {
      return 'Enter a duration in minutes (e.g. 30).';
    }
    return null;
  }

  /// A completed shop must list at least one bookable service; otherwise the
  /// database hides it from clients.
  static String? finishSetupError({required int serviceCount}) {
    return serviceCount == 0
        ? 'Add at least one service so clients can find and book your shop.'
        : null;
  }
}
