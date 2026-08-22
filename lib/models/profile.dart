/// Strongly-typed model for the `public.profiles` table.
///
/// Every authenticated user has exactly one profile row, created by the
/// `handle_new_user()` trigger in `supabase/schema.sql`. The `role` column
/// drives role-based checks (client vs provider) across the app.
class Profile {
  final String id; // references auth.users(id)
  final String? fullName;
  final String? email;
  final String? phoneNumber;
  final UserRole role;
  final String? avatarUrl;
  final String languagePreference;
  final String? city;
  final DateTime? createdAt;

  const Profile({
    required this.id,
    this.fullName,
    this.email,
    this.phoneNumber,
    this.role = UserRole.client,
    this.avatarUrl,
    this.languagePreference = 'en',
    this.city,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      role: UserRole.parse(json['role']),
      avatarUrl: json['avatar_url'] as String?,
      languagePreference: json['language_preference'] as String? ?? 'en',
      city: json['city'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'role': role.name,
        'avatar_url': avatarUrl,
        'language_preference': languagePreference,
        'city': city,
      };

  Profile copyWith({
    String? fullName,
    String? phoneNumber,
    String? avatarUrl,
    String languagePreference = 'en',
    String? city,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      languagePreference: languagePreference,
      city: city ?? this.city,
      createdAt: createdAt,
    );
  }

  bool get isProvider => role == UserRole.provider;
  bool get isClient => role == UserRole.client;

  /// Initials for avatar fallbacks, e.g. "Carl Ayuni" -> "CA".
  String get initials {
    final parts = (fullName ?? '?').trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
  }
}

/// The two user types StyleLink serves.
enum UserRole {
  client,
  provider;

  static UserRole parse(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'provider':
        return UserRole.provider;
      case 'client':
      case null:
        return UserRole.client;
      default:
        return UserRole.client;
    }
  }

  /// Localized label, e.g. for role chips in the UI.
  String get label => switch (this) {
        UserRole.client => 'Client',
        UserRole.provider => 'Provider',
      };
}
