import 'package:intl/intl.dart';

/// Strongly-typed model for the `public.services` table.
///
/// A provider's bookable menu item. Prices are stored as whole FCFA
/// (CFA franc has no fractional unit), matching the UI copy across StyleLink
/// (e.g. "Gentleman's Cut — 5 000 FCFA · 30 mins").
class Service {
  final String id;
  final String providerId; // references providers(id)
  final String name;
  final String? description;
  final int price; // FCFA
  final int durationMinutes;
  final bool isActive;
  final DateTime? createdAt;

  const Service({
    required this.id,
    required this.providerId,
    required this.name,
    this.description,
    required this.price,
    this.durationMinutes = 30,
    this.isActive = true,
    this.createdAt,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      // Deployed databases may still carry a legacy `title` column (see
      // supabase/fix_services_title_column.sql) — fall back to it when a
      // row comes back with `name` missing.
      name: (json['name'] ?? json['title']) as String,
      description: json['description'] as String?,
      price: _asInt(json['price']),
      durationMinutes: _asInt(json['duration_minutes']),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'provider_id': providerId,
        'name': name,
        'description': description,
        'price': price,
        'duration_minutes': durationMinutes,
        'is_active': isActive,
      };

  /// "5 000 FCFA" — formatted with thin spaces, matching the app's copy.
  String get priceLabel =>
      '${NumberFormat.decimalPattern('fr').format(price)} FCFA';

  /// "30 mins" / "1 hr 30" style duration label.
  String get durationLabel {
    if (durationMinutes < 60) return '$durationMinutes mins';
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    return m == 0 ? '$h hr' : '$h hr $m';
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
