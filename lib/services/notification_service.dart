import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';

/// Central notification service for StyleLink.
///
/// Initialises local push notifications and attaches Supabase Realtime
/// listeners to the current user's bookings. When a booking's status changes,
/// a heads-up notification is displayed with the appropriate title and body.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  FirebaseMessaging? _fcm;
  FirebaseMessaging get fcm {
    _fcm ??= FirebaseMessaging.instance;
    return _fcm!;
  }

  // ── Channel IDs ──────────────────────────────────────────────────────────

  static const _clientChannel = 'stylelink_booking_updates';
  static const _providerChannel = 'stylelink_provider_alerts';

  // ── Subscriptions ────────────────────────────────────────────────────────

  StreamSubscription<List<Map<String, dynamic>>>? _clientSub;
  StreamSubscription<List<Map<String, dynamic>>>? _providerSub;

  /// Previous status for each booking ID (to detect transitions).
  final Map<String, BookingStatus> _previousStatuses = {};

  // ═════════════════════════════════════════════════════════════════════════
  // Initialization
  // ═════════════════════════════════════════════════════════════════════════

  /// Call once from `main()` after Supabase is initialized.
  Future<void> init() async {
    if (_initialized) return;

    // ── Android settings ───────────────────────────────────────────────
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // ── iOS / macOS settings ───────────────────────────────────────────
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // ── Web settings (no-op but required by the API) ──────────────────
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(initSettings);
    } catch (e) {
      debugPrint('Local notifications init skipped: $e');
    }

    // ── Firebase Cloud Messaging setup (web-safe)
    try {
      if (!kIsWeb) {
        await fcm.requestPermission(alert: true, badge: true, sound: true);
      }
      FirebaseMessaging.onMessage.listen(_onFcmForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onFcmMessageOpenedApp);
      final initialMessage = await fcm.getInitialMessage();
      if (initialMessage != null) _onFcmMessageOpenedApp(initialMessage);
      _saveFcmToken();
      fcm.onTokenRefresh.listen(_saveFcmTokenToServer);
    } catch (e) {
      debugPrint('FCM init skipped: $e');
    }

    // ── Create high-priority channels ──────────────────────────────────
    try {
      await _createChannels();
    } catch (e) {
      debugPrint('Notification channels skipped: $e');
    }

    _initialized = true;
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _clientChannel,
        'Booking Updates',
        description: 'Alerts when your booking status changes',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _providerChannel,
        'Provider Alerts',
        description: 'New bookings, cancellations, and reviews',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Permission prompt
  // ═════════════════════════════════════════════════════════════════════════

  /// Request notification permission — show a soft prompt during onboarding.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    // Web and Linux — permission is typically granted by default.
    return true;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Show a local notification
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> showNotification({
    required String channel,
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      channel,
      channel == _clientChannel ? 'Booking Updates' : 'Provider Alerts',
      channelDescription: channel == _clientChannel
          ? 'Alerts when your booking status changes'
          : 'New bookings, cancellations, and reviews',
      importance: Importance.high,
      priority: Priority.high,
      ticker: title,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Firebase Cloud Messaging

  Future<void> _saveFcmToken() async {
    try {
      final token = await fcm.getToken();
      if (token != null) await _saveFcmTokenToServer(token);
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }
  }

  Future<void> _saveFcmTokenToServer(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client.from('profiles').update({'fcm_token': token}).eq('id', userId);
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  void _onFcmForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    showNotification(
      channel: _clientChannel,
      title: notification.title ?? 'StyleLink',
      body: notification.body ?? '',
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    );
  }

  void _onFcmMessageOpenedApp(RemoteMessage message) {
    debugPrint('FCM notification opened app');
  }

  // Realtime listeners
  // ═════════════════════════════════════════════════════════════════════════

  /// Start listening to booking changes for the current user.
  /// Call this after authentication succeeds.
  void startListening() {
    stopListening(); // prevent duplicates

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final db = Supabase.instance.client;

    // ── Client bookings ───────────────────────────────────────────────
    _clientSub = db
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('client_id', userId)
        .order('created_at', ascending: false)
        .listen(_onClientBookingsUpdate);

    // ── Provider bookings ─────────────────────────────────────────────
    // bookings.provider_id references providers(id), not auth.users(id),
    // so we must resolve the provider row ID before subscribing.
    _resolveProviderAndSubscribe(userId, db);
  }

  /// Look up the provider row for the given auth user, then subscribe to
  /// bookings filtered by that provider ID.
  Future<void> _resolveProviderAndSubscribe(
    String userId,
    SupabaseClient db,
  ) async {
    try {
      final rows = await db
          .from('providers')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) return; // not a provider
      final providerId = rows.first['id'] as String;
      _providerSub = db
          .from('bookings')
          .stream(primaryKey: ['id'])
          .eq('provider_id', providerId)
          .order('created_at', ascending: false)
          .listen(_onProviderBookingsUpdate);
    } catch (e) {
      debugPrint('Failed to resolve provider ID for notifications: $e');
    }
  }

  /// Stop all active listeners.
  void stopListening() {
    _clientSub?.cancel();
    _providerSub?.cancel();
    _clientSub = null;
    _providerSub = null;
  }

  // ── Client booking transitions ──────────────────────────────────────────

  void _onClientBookingsUpdate(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final bookingId = row['id']?.toString() ?? '';
      final statusStr = row['status']?.toString() ?? '';
      final currentStatus = BookingStatus.parse(statusStr);

      if (bookingId.isEmpty) continue;

      final previous = _previousStatuses[bookingId];

      // First time we see this booking — store its status, don't notify.
      if (previous == null) {
        _previousStatuses[bookingId] = currentStatus;
        continue;
      }

      // No change.
      if (previous == currentStatus) continue;

      // Status changed — update stored value and notify.
      _previousStatuses[bookingId] = currentStatus;
      _notifyClientTransition(currentStatus, bookingId);
    }
  }

  void _notifyClientTransition(BookingStatus status, String bookingId) {
    String? title;
    String? body;

    switch (status) {
      case BookingStatus.confirmed:
        title = 'Booking Confirmed! / Réservation confirmée !';
        body = 'Your stylist has accepted the request.';
      case BookingStatus.arrived:
        title = 'Stylist Arrived! / Le prestataire est arrivé !';
        body = 'Your stylist has logged their GPS arrival.';
      case BookingStatus.inProgress:
        title = 'Session Started / Séance commencée';
        body = 'Your PIN was verified. Enjoy your service!';
      case BookingStatus.completed:
        title = 'Service Complete! / Service terminé !';
        body = 'Tap to rate your experience.';
      case BookingStatus.cancelled:
        title = 'Booking Cancelled / Réservation annulée';
        body = 'Your appointment has been cancelled.';
      default:
        return; // Don't notify for pending / rejected.
    }

    showNotification(
      channel: _clientChannel,
      title: title,
      body: body,
      id: bookingId.hashCode,
    );
  }

  // ── Provider booking transitions ────────────────────────────────────────

  void _onProviderBookingsUpdate(List<Map<String, dynamic>> rows) {
    // Detect new bookings (not previously tracked) and status changes.
    for (final row in rows) {
      final bookingId = row['id']?.toString() ?? '';
      final statusStr = row['status']?.toString() ?? '';
      final currentStatus = BookingStatus.parse(statusStr);

      if (bookingId.isEmpty) continue;

      final previous = _previousStatuses[bookingId];

      // New booking — first time seeing it.
      if (previous == null) {
        _previousStatuses[bookingId] = currentStatus;
        if (currentStatus == BookingStatus.pending) {
          _notifyProviderNewBooking(bookingId);
        }
        continue;
      }

      if (previous == currentStatus) continue;

      _previousStatuses[bookingId] = currentStatus;
      _notifyProviderTransition(currentStatus, bookingId);
    }
  }

  void _notifyProviderNewBooking(String bookingId) {
    showNotification(
      channel: _providerChannel,
      title: 'New Request / Nouvelle demande !',
      body: 'A client booked a service with you.',
      id: bookingId.hashCode,
    );
  }

  void _notifyProviderTransition(BookingStatus status, String bookingId) {
    String? title;
    String? body;

    switch (status) {
      case BookingStatus.cancelled:
        title = 'Booking Cancelled / Réservation annulée';
        body = 'A client cancelled their appointment.';
      case BookingStatus.completed:
        title = 'Service Complete! / Service terminé !';
        body = 'The session has been marked as completed.';
      default:
        return; // Don't notify providers for other transitions.
    }

    showNotification(
      channel: _providerChannel,
      title: title,
      body: body,
      id: bookingId.hashCode,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Helper: trigger a review notification (called from submitReview)
  // ═════════════════════════════════════════════════════════════════════════

  /// Show a "New Review" notification on the provider's device.
  void notifyNewReview(String providerId) {
    showNotification(
      channel: _providerChannel,
      title: 'New Review! / Nouvel avis !',
      body: 'A client left a star rating and comment on your profile.',
      id: 'review-$providerId-${DateTime.now().millisecondsSinceEpoch}'.hashCode,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Cleanup
  // ═════════════════════════════════════════════════════════════════════════

  void dispose() {
    stopListening();
    _previousStatuses.clear();
  }
}
