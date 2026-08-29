import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

/// Thin wrapper around Firebase Analytics that provides typed event-logging
/// helpers for StyleLink's key user flows.
///
/// On web, analytics is a no-op unless Firebase is properly configured.
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseAnalytics get _fb =>
      _analytics ??= FirebaseAnalytics.instance;

  // ═════════════════════════════════════════════════════════════════════════
  // Auth events
  // ═════════════════════════════════════════════════════════════════════════

  void logSignUp({required String method}) => _safeLog(() =>
      _fb.logSignUp(signUpMethod: method));

  void logLogin({required String method}) => _safeLog(() =>
      _fb.logLogin(loginMethod: method));

  void logSignOut() => _safeLog(() => _fb.logEvent(name: 'sign_out'));

  // ═════════════════════════════════════════════════════════════════════════
  // Discovery / Search
  // ═════════════════════════════════════════════════════════════════════════

  void logSearch({String? query, String? category, String? city}) =>
      _safeLog(() => _fb.logEvent(
            name: 'search',
            parameters: {
              if (query != null) 'query': query,
              if (category != null) 'category': category,
              if (city != null) 'city': city,
            },
          ));

  void logProviderViewed({required String providerId, String? category}) =>
      _safeLog(() => _fb.logEvent(
            name: 'provider_viewed',
            parameters: {
              'provider_id': providerId,
              if (category != null) 'category': category,
            },
          ));

  void logFavoriteToggled({
    required String providerId,
    required bool isFavorited,
  }) =>
      _safeLog(() => _fb.logEvent(
            name: 'favorite_toggled',
            parameters: {
              'provider_id': providerId,
              'is_favorited': isFavorited,
            },
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // Booking events
  // ═════════════════════════════════════════════════════════════════════════

  void logBookingCreated({
    required String providerId,
    required int serviceCount,
    required int totalPriceFcfa,
  }) =>
      _safeLog(() => _fb.logEvent(
            name: 'booking_created',
            parameters: {
              'provider_id': providerId,
              'service_count': serviceCount,
              'total_price_fcfa': totalPriceFcfa,
            },
          ));

  void logBookingStatusChanged({
    required String bookingId,
    required String newStatus,
  }) =>
      _safeLog(() => _fb.logEvent(
            name: 'booking_status_changed',
            parameters: {
              'booking_id': bookingId,
              'new_status': newStatus,
            },
          ));

  void logBookingCancelled({required String bookingId}) =>
      _safeLog(() => _fb.logEvent(
            name: 'booking_cancelled',
            parameters: {'booking_id': bookingId},
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // Provider events
  // ═════════════════════════════════════════════════════════════════════════

  void logBecomeProvider({required String category, required String city}) =>
      _safeLog(() => _fb.logEvent(
            name: 'become_provider',
            parameters: {'category': category, 'city': city},
          ));

  void logServiceCreated({
    required String providerId,
    required String serviceName,
    required int price,
  }) =>
      _safeLog(() => _fb.logEvent(
            name: 'service_created',
            parameters: {
              'provider_id': providerId,
              'service_name': serviceName,
              'price': price,
            },
          ));

  void logAvailabilityToggled({required bool isAvailable}) =>
      _safeLog(() => _fb.logEvent(
            name: 'availability_toggled',
            parameters: {'is_available': isAvailable},
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // Messaging
  // ═════════════════════════════════════════════════════════════════════════

  void logMessageSent({required String providerId}) =>
      _safeLog(() => _fb.logEvent(
            name: 'message_sent',
            parameters: {'provider_id': providerId},
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // Reviews
  // ═════════════════════════════════════════════════════════════════════════

  void logReviewSubmitted({
    required String providerId,
    required int rating,
  }) =>
      _safeLog(() => _fb.logEvent(
            name: 'review_submitted',
            parameters: {
              'provider_id': providerId,
              'rating': rating,
            },
          ));

  // ═════════════════════════════════════════════════════════════════════════
  // User properties
  // ═════════════════════════════════════════════════════════════════════════

  void setUserRole(String role) => _safeLog(() =>
      _fb.setUserProperty(name: 'user_role', value: role));

  void setUserCity(String? city) => _safeLog(() =>
      _fb.setUserProperty(name: 'city', value: city));

  // ═════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═════════════════════════════════════════════════════════════════════════

  void _safeLog(void Function() log) {
    try {
      log();
    } catch (e) {
      debugPrint('Analytics log failed: $e');
    }
  }
}
