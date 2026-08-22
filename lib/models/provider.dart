/// Strongly-typed model for the `public.providers` table.
///
/// Each row belongs to a `profiles` row whose role is `provider`. `rating` is
/// maintained by the app (e.g. recomputed from bookings/reviews); `priceFrom`
/// is the cheapest active service price in FCFA, cached for list screens.
class Provider {
  final String id;
  final String userId; // references profiles(id)
  final String businessName;
  final String category; // e.g. "Barbing / Coiffure"
  final String city; // Douala | Yaoundé | Limbe | Bafoussam | Kribi
  final String? quarter; // e.g. "Bonapriso"
  final String? bio;
  final double rating; // 0..5
  final int reviewCount;
  final ServiceType serviceType; // studio / home
  final int priceFrom; // FCFA
  final String? coverUrl;
  final String? avatarUrl;
  final bool isVerified;
  final bool isAvailable;

  /// Up to 7 portfolio work-sample image URLs.
  final List<String> portfolioImages;

  /// Weekly schedule keyed by day ("Mon"…"Sun"): a "09:00-19:00" window,
  /// or null when the provider is closed that day. Stored as jsonb.
  final Map<String, String?> workingHours;
  final DateTime? createdAt;

  const Provider({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.category,
    required this.city,
    this.quarter,
    this.bio,
    this.rating = 0,
    this.reviewCount = 0,
    this.serviceType = ServiceType.studio,
    this.priceFrom = 0,
    this.coverUrl,
    this.avatarUrl,
    this.isVerified = false,
    this.isAvailable = true,
    this.portfolioImages = const [],
    this.workingHours = const {},
    this.createdAt,
  });

  factory Provider.fromJson(Map<String, dynamic> json) {
    // Resolve avatar_url: prefer top-level, fall back to joined profiles row.
    String? avatarUrl = json['avatar_url'] as String?;
    if (avatarUrl == null && json['profiles'] is Map) {
      avatarUrl = (json['profiles'] as Map)['avatar_url'] as String?;
    }

    return Provider(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      businessName: json['business_name'] as String,
      category: json['category'] as String? ?? '',
      city: json['city'] as String? ?? '',
      quarter: json['quarter'] as String?,
      bio: json['bio'] as String?,
      rating: _asDouble(json['rating']),
      reviewCount: _asInt(json['review_count']),
      serviceType: ServiceType.parse(json['service_type']),
      priceFrom: _asInt(json['price_from']),
      coverUrl: json['cover_url'] as String?,
      avatarUrl: avatarUrl,
      isVerified: json['is_verified'] as bool? ?? false,
      isAvailable: json['is_available'] as bool? ?? true,
      portfolioImages: _parseStringList(json['portfolio_images']),
      workingHours: _parseWorkingHours(json['working_hours']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'business_name': businessName,
        'category': category,
        'city': city,
        'quarter': quarter,
        'bio': bio,
        'rating': rating,
        'review_count': reviewCount,
        'service_type': serviceType.name,
        'price_from': priceFrom,
        'cover_url': coverUrl,
        'avatar_url': avatarUrl,
        'is_verified': isVerified,
        'is_available': isAvailable,
        'portfolio_images': portfolioImages,
        'working_hours': workingHours,
      };

  /// Copy with editable business fields (used by the provider management
  /// form before an upsert).
  Provider copyWith({
    String? businessName,
    String? category,
    String? city,
    String? quarter,
    String? bio,
    ServiceType? serviceType,
    String? coverUrl,
    String? avatarUrl,
    bool? isAvailable,
    List<String>? portfolioImages,
    Map<String, String?>? workingHours,
  }) {
    return Provider(
      id: id,
      userId: userId,
      businessName: businessName ?? this.businessName,
      category: category ?? this.category,
      city: city ?? this.city,
      quarter: quarter ?? this.quarter,
      bio: bio ?? this.bio,
      rating: rating,
      reviewCount: reviewCount,
      serviceType: serviceType ?? this.serviceType,
      priceFrom: priceFrom,
      coverUrl: coverUrl ?? this.coverUrl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified,
      isAvailable: isAvailable ?? this.isAvailable,
      portfolioImages: portfolioImages ?? this.portfolioImages,
      workingHours: workingHours ?? this.workingHours,
      createdAt: createdAt,
    );
  }

  /// "Mon–Sat · 9:00 AM – 7:00 PM" style summary of the weekly schedule,
  /// or null when no hours are set.
  String? get workingHoursLabel {
    if (workingHours.isEmpty) return null;
    const order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // Group consecutive days sharing the same window.
    final groups = <List<String>>[];
    String? prevWindow;
    for (final day in order) {
      final window = workingHours[day];
      if (window == null) {
        prevWindow = null;
        continue;
      }
      if (groups.isEmpty || prevWindow != window) {
        groups.add([day]);
      } else {
        groups.last.add(day);
      }
      prevWindow = window;
    }
    if (groups.isEmpty) return null;
    return groups.map((g) {
      final days = g.length == 1 ? g.first : '${g.first}–${g.last}';
      final window = workingHours[g.first]!;
      final parts = window.split('-');
      final start = _to12h(parts.isNotEmpty ? parts[0] : '');
      final end = _to12h(parts.length > 1 ? parts[1] : '');
      return '$days $start–$end';
    }).join(' · ');
  }

  /// Whether this provider operates from a studio, at the client's home,
  /// or both (serialized as "both").
  bool get offersHomeService =>
      serviceType == ServiceType.home || serviceType == ServiceType.both;

  /// "Starting from X FCFA" label used across cards and lists.
  String get priceLabel => 'Starting from $priceFrom FCFA';

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  static Map<String, String?> _parseWorkingHours(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v?.toString()));
    }
    return const {};
  }

  static String _to12h(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = parts[1];
    if (h == null) return hhmm;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return m == '00' ? '$hour12 $suffix' : '$hour12:$m $suffix';
  }
}

/// Where the provider delivers services.
enum ServiceType {
  studio,
  home,
  both;

  static ServiceType parse(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'home':
        return ServiceType.home;
      case 'both':
        return ServiceType.both;
      case 'studio':
      case null:
        return ServiceType.studio;
      default:
        return ServiceType.studio;
    }
  }
}
