import 'package:flutter/foundation.dart' show kIsWeb;

/// Generates and parses deep links for StyleLink.
///
/// URL scheme: `https://stylelink.app/provider/{providerId}`
///
/// On web the links open in-browser. On native they can be handled via
/// `app_links` or `uni_links` (not added yet — the share-to-clipboard
/// path works everywhere).
class DeepLinkService {
  DeepLinkService._();
  static final instance = DeepLinkService._();

  /// Base URL for shareable links.
  static const _baseUrl = 'https://stylelink.app';

  /// Generate a shareable URL for a provider profile.
  String providerUrl(String providerId) => '$_baseUrl/provider/$providerId';

  /// Generate shareable URL for a booking.
  String bookingUrl(String bookingId) => '$_baseUrl/booking/$bookingId';

  /// Build the clipboard/share text for a provider.
  String providerShareText({
    required String businessName,
    required String category,
    required String providerId,
    String? city,
  }) {
    final location = city != null && city.isNotEmpty ? ' in $city' : '';
    return 'Check out $businessName ($category$location) on StyleLink!\n'
        '${providerUrl(providerId)}';
  }

  /// Parse a deep link URL and extract the route + ID.
  /// Returns `(route, id)` or `null` if not a valid StyleLink link.
  (String route, String id)? parse(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // Handle both custom scheme and HTTPS links.
    final path = uri.path;
    if (path.startsWith('/provider/')) {
      final id = path.substring('/provider/'.length);
      if (id.isNotEmpty) return ('provider', id);
    }
    if (path.startsWith('/booking/')) {
      final id = path.substring('/booking/'.length);
      if (id.isNotEmpty) return ('booking', id);
    }
    return null;
  }
}
