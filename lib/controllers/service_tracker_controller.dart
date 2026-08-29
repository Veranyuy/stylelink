import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/booking.dart';

/// Controls the real-time service tracking lifecycle: navigation,
/// arrival detection, verification PIN validation, and stage transitions.
///
/// ## Booking state machine
///
/// ```
/// confirmed  ──(provider taps "I've Arrived")──▶  arrived
/// arrived    ──(PIN verified)──────────────────▶  in_progress
/// in_progress ──(provider taps "Complete")─────▶  completed
/// ```
///
/// Each transition writes a timestamp column to `public.bookings`:
/// - `arrived_at`   — when the provider marks arrival
/// - `started_at`   — when the verification PIN is accepted
/// - `completed_at` — when the service is marked complete
///
/// Arrival also records the provider's GPS coordinates into
/// `arrival_lat` / `arrival_lng` so the client can track progress.
class ServiceTrackerController extends ChangeNotifier {
  ServiceTrackerController._();
  static final ServiceTrackerController instance =
      ServiceTrackerController._();

  SupabaseClient get _db => Supabase.instance.client;

  // -------------------------------------------------------------------------
  // Realtime subscription
  // -------------------------------------------------------------------------

  RealtimeChannel? _channel;

  /// Subscribe to realtime changes on bookings for a specific provider.
  /// When a booking status changes, [notifyListeners] is called so any
  /// listening widgets rebuild.
  void subscribeToProviderBookings(String providerId) {
    _channel?.unsubscribe();
    _channel = _db
        .channel('provider-bookings-$providerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: providerId,
          ),
          callback: (_) => notifyListeners(),
        )
        .subscribe();
  }

  /// Stop listening for realtime booking changes.
  void unsubscribeFromBookings() {
    _channel?.unsubscribe();
    _channel = null;
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  /// Launch Google Maps (native app on mobile, web on desktop) centred on
  /// the given coordinates.
  Future<void> openNavigation(double lat, double lng) async {
    // Google Maps URL works everywhere — on mobile it opens the native app,
    // on web it opens maps.google.com.
    final uri = Uri.https('www.google.com', '/maps', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': 'driving',
    });
    if (!await launcher.launchUrl(uri,
        mode: launcher.LaunchMode.externalApplication)) {
      // Fallback: try the maps:// scheme (iOS/Android native).
      final fallback = Uri(scheme: 'geo', host: '', queryParameters: {
        'q': '$lat,$lng',
      });
      await launcher.launchUrl(fallback,
          mode: launcher.LaunchMode.externalApplication);
    }
  }

  // -------------------------------------------------------------------------
  // Arrival coordinates
  // -------------------------------------------------------------------------

  /// Compute the great-circle distance (Haversine) between two points in
  /// kilometres. Used by the client side to verify the provider is nearby.
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371; // Earth radius in km
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * asin(sqrt(a));
  }

  static double _toRad(double deg) => deg * pi / 180;

  // -------------------------------------------------------------------------
  // State machine
  // -------------------------------------------------------------------------

  /// Advance a booking to the next stage.
  ///
  /// | Current    | Next          | Requirements                          |
  /// |------------|---------------|---------------------------------------|
  /// | confirmed  | arrived       | [arrivalLat], [arrivalLng] required   |
  /// | arrived    | in_progress   | [pin] must match booking verification |
  /// | in_progress| completed     | (none)                                |
  ///
  /// Throws [StateError] if the current status is not in the table above,
  /// or if the verification PIN is incorrect.
  ///
  /// Returns the updated [Booking] on success.
  Future<Booking> advanceBookingStage({
    required String bookingId,
    required BookingStatus currentStatus,
    String? pin,
    double? arrivalLat,
    double? arrivalLng,
  }) async {
    switch (currentStatus) {
      // ── confirmed → arrived ──────────────────────────────────────────
      case BookingStatus.confirmed:
        final update = <String, dynamic>{
          'status': BookingStatus.arrived.dbValue,
          'arrived_at': DateTime.now().toUtc().toIso8601String(),
        };
        // Only attach GPS coords if available (graceful web fallback).
        if (arrivalLat != null) update['arrival_lat'] = arrivalLat;
        if (arrivalLng != null) update['arrival_lng'] = arrivalLng;
        await _db.from('bookings').update(update).eq('id', bookingId);
        notifyListeners();
        break;

      // ── arrived → in_progress (PIN verification) ─────────────────────
      case BookingStatus.arrived:
        await _verifyPin(bookingId, pin);
        await _db.from('bookings').update({
          'status': BookingStatus.inProgress.dbValue,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', bookingId);
        notifyListeners();
        break;

      // ── in_progress → completed ──────────────────────────────────────
      case BookingStatus.inProgress:
        await _db.from('bookings').update({
          'status': BookingStatus.completed.dbValue,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', bookingId);
        notifyListeners();
        break;

      // ── invalid transition ───────────────────────────────────────────
      default:
        throw StateError(
            'Cannot advance booking from status "${currentStatus.name}".');
    }

    // Fetch and return the updated booking.
    final row = await _db
        .from('bookings')
        .select()
        .eq('id', bookingId)
        .single();
    return Booking.fromJson(row);
  }

  /// Convenience wrapper for the in_progress → completed transition.
  ///
  /// Sets `completed_at` and returns the updated [Booking].
  Future<Booking> completeBooking(String bookingId) async {
    try {
      await _db.from('bookings').update({
        'status': BookingStatus.completed.dbValue,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bookingId);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('total_amount') || msg.contains('42703')) {
        throw Exception(
          'Database trigger error: a rogue trigger on the bookings table '
          'references a non-existent "total_amount" column. '
          'Run NUCLEAR_fix_total_amount.sql in the Supabase SQL Editor to fix this.',
        );
      }
      rethrow;
    }
    notifyListeners();

    final row = await _db
        .from('bookings')
        .select()
        .eq('id', bookingId)
        .single();
    return Booking.fromJson(row);
  }

  /// Validate the 6-digit verification PIN.
  ///
  /// The PIN is generated when the booking is confirmed and stored as
  /// `verification_pin` on the bookings row. Only the client sees it;
  /// the provider must ask for it on arrival.
  Future<void> _verifyPin(String bookingId, String? pin) async {
    if (pin == null || pin.trim().isEmpty) {
      throw StateError('Verification PIN is required.');
    }

    final row = await _db
        .from('bookings')
        .select('verification_pin')
        .eq('id', bookingId)
        .single();

    final stored = row['verification_pin']?.toString().trim();
    if (stored == null || stored.isEmpty) {
      // No PIN set — allow advancement (legacy bookings).
      return;
    }

    if (pin.trim() != stored) {
      throw StateError(
          'Incorrect verification PIN. Please ask the client for the code.');
    }
  }
}
