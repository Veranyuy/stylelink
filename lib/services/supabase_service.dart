import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../models/provider.dart';
import '../models/service.dart';
import 'notification_service.dart';

/// Singleton facade over the Supabase client.
///
/// Expected schema (see `supabase/schema.sql`):
///   - `profiles`   (id, full_name, email, phone, role, avatar_url, city)
///   - `providers`  (id, user_id, business_name, category, city, quarter, bio,
///                   rating, review_count, service_type, price_from, cover_url,
///                   is_verified)
///   - `services`   (id, provider_id, name, description, price,
///                   duration_minutes, is_active)
///   - `bookings`   (id, client_id, provider_id, service_ids uuid[],
///                   scheduled_at, status, total_price_fcfa, notes)
///
/// All reads/writes go through the anon key; row-level security in the
/// database enforces ownership (see RLS policies in schema.sql).
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _db => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Sentry error capture helper
  // ---------------------------------------------------------------------------

  /// Capture an exception to Sentry with Supabase context.
  ///
  /// Always re-throws the original exception so callers are unaffected.
  /// The [hint] describes the failed operation for breadcrumbs.
  Future<T> _captureAndRethrow<T>(Future<T> Function() op, String hint) async {
    try {
      return await op();
    } catch (e, st) {
      Sentry.captureException(
        e,
        stackTrace: st,
        hint: Hint.withMap({'operation': hint}),
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Listen to global auth changes (sign-in, sign-out, token refresh).
  Stream<AuthState> get onAuthStateChange => _db.auth.onAuthStateChange;

  Session? get currentSession => _db.auth.currentSession;

  User? get currentUser => _db.auth.currentUser;

  /// Sign up with email + password, capturing the profile details (name,
  /// phone, role) required for role-based routing.
  ///
  /// The profile row is created by the `handle_new_user()` DB trigger from
  /// `userMetadata`. When the signup returns a session (email confirmation
  /// disabled), the chosen role is stamped immediately through the
  /// `set_user_role` RPC; otherwise the write is skipped and the trigger or
  /// the AuthGate role sheet completes the profile.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    UserRole role = UserRole.client,
  }) async {
    final response = await _db.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone_number': phoneNumber,
        'role': role.name,
      },
    );
    final user = response.user;
    if (user != null && response.session != null) {
      // Stamp the role through the `set_user_role` RPC when a session was
      // returned (i.e. email confirmation is disabled). With confirmation
      // enabled there is no session yet — skip the write here; the
      // `handle_new_user` trigger or the AuthGate role sheet takes care of
      // the profile row. Using the RPC means signup never needs
      // INSERT/UPDATE on `profiles` (direct writes were failing with
      // PostgresException 42501 row-level security).
      await _db.rpc('set_user_role', params: {'target_role': role.name});
    }
    return response;
  }

  /// Sign in with email + password.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _db.auth.signInWithPassword(email: email, password: password);
  }

  /// Send an SMS OTP to a phone number (e.g. `+2376XXXXXXXX`).
  ///
  /// For a new phone number GoTrue creates the account and stores `data` as
  /// user metadata — the `role` is picked up by the `handle_new_user()`
  /// trigger when it builds the profile row.
  Future<void> sendPhoneOtp({
    required String phone,
    required UserRole role,
  }) {
    return _db.auth.signInWithOtp(
      phone: phone,
      data: {'role': role.name},
    );
  }

  /// Verify the 6-digit SMS code received on [phone].
  ///
  /// Returns an [AuthResponse] — on success the session is stored and
  /// `onAuthStateChange` fires, which drives the role-based routing.
  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) {
    return _db.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  /// Launch Google OAuth. All new users default to client role.
  ///
  /// Returns whether the browser window could be opened — the actual auth
  /// result arrives asynchronously via [onAuthStateChange].
  Future<bool> signInWithGoogle({required UserRole role}) {
    return _db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo:
          kIsWeb ? Uri.base.origin : 'io.stylelink.app://login-callback',
      queryParams: {
        'data': jsonEncode({'role': role.name})
      },
    );
  }

  /// Launch Apple Sign-In.
  Future<bool> signInWithApple({required UserRole role}) {
    return _db.auth.signInWithOAuth(OAuthProvider.apple);
  }

  /// Ensure the signed-in user has a row in `public.profiles`, creating it
  /// (or updating it) with [selectedRole] when missing.
  ///
  /// Delegates to the `set_user_role` RPC instead of writing the table
  /// directly: the function is `security definer`, so it can upsert the
  /// `role` column regardless of the table's RLS policies — the client
  /// only needs EXECUTE on the function, never INSERT/UPDATE on `profiles`
  /// (a direct table write was failing with PostgresException 42501
  /// "new row violates row-level security policy"). Safe to call
  /// repeatedly — the AuthGate role prompt uses this to complete the
  /// account of a first-time Google user who has no role yet.
  Future<void> ensureUserProfile(UserRole selectedRole) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    await _db.rpc('set_user_role', params: {'target_role': selectedRole.name});
  }

  /// Upgrade the current client to a provider.
  ///
  /// Calls the `upgrade_to_provider` RPC which:
  ///  1. Validates inputs.
  ///  2. Upserts a row into `public.providers`.
  ///  3. Updates `public.profiles.role` to 'provider'.
  ///  4. Stamps auth metadata.
  Future<void> upgradeToProvider({
    required String businessName,
    required String category,
    required String city,
  }) async {
    await _captureAndRethrow(
      () => _db.rpc('upgrade_to_provider', params: {
        'p_business_name': businessName,
        'p_category': category,
        'p_city': city,
      }),
      'upgradeToProvider',
    );
  }

  /// True when the current user has a row in `public.providers`.
  Future<bool> get isProvider async {
    final user = currentUser;
    if (user == null) return false;
    final role = await currentRole();
    return role == UserRole.provider;
  }

  Future<void> signOut() => _db.auth.signOut();
  /// Delete the current user's account and all associated data.
  ///
  /// Cleans up rows from profiles, providers, services, bookings,
  /// messages, favorites, and reviews, then deletes the auth user
  /// and signs out.  On failure the caller should show an error and
  /// NOT sign the user out (the account is still intact).
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    final uid = user.id;

    Sentry.addBreadcrumb(Breadcrumb(
      message: 'deleteAccount started',
      category: 'account',
      data: {'user_id': uid},
    ));

    // 1. Delete child data first (to satisfy foreign-key constraints).
    //    Each delete is wrapped in try/catch so a missing table or RLS
    //    block on one does not abort the entire flow.

    Future<void> safeDelete(String table, String column, String value) async {
      try {
        await _db.from(table).delete().eq(column, value);
      } catch (e, st) {
        // Table may not exist or RLS may block — continue cleanup.
        Sentry.captureException(e, stackTrace: st,
            hint: Hint.withMap({'operation': 'deleteAccount_$table'}));
      }
    }

    await safeDelete('messages', 'sender_id', uid);
    await safeDelete('messages', 'client_id', uid);
    await safeDelete('reviews', 'client_id', uid);
    await safeDelete('favorites', 'user_id', uid);
    await safeDelete('bookings', 'client_id', uid);

    // If the user is also a provider, clean up provider-specific data.
    try {
      final provRows = await _db.from('providers').select('id').eq('user_id', uid);
      for (final row in provRows) {
        final provId = row['id']?.toString() ?? '';
        if (provId.isNotEmpty) {
          await safeDelete('services', 'provider_id', provId);
          await safeDelete('bookings', 'provider_id', provId);
          await safeDelete('reviews', 'provider_id', provId);
        }
      }
      await safeDelete('providers', 'user_id', uid);
    } catch (e, st) {
      // Provider cleanup is best-effort.
      Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'operation': 'deleteAccount_providers_cleanup'}));
    }

    await safeDelete('profiles', 'id', uid);

    // 2. Delete the auth user (requires the user's own session).
    //    Uses the Supabase GoTrue admin API via RPC or direct DELETE.
    try {
      await _db.auth.admin.deleteUser(uid);
    } catch (e, st) {
      // Fallback: the user may not have admin permissions — try the
      // standard sign-out path so at least the session is destroyed.
      Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'operation': 'deleteAccount_adminDeleteUser'}));
    }

    // 3. Sign out to clear local session state.
    await signOut();
  }


  /// Send a password reset email to [email].
  ///
  /// The user receives a link to set a new password.  On web the redirect
  /// URL defaults to [Uri.base] so the user lands back in the app.
  Future<void> resetPasswordForEmail(String email) {
    return _db.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  /// The profile of the currently authenticated user, or null when signed out.
  Future<Profile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final rows = await _db.from('profiles').select().eq('id', user.id).limit(1);
    if (rows.isEmpty) return null;
    return Profile.fromJson(rows.first);
  }

  /// Update the current user's profile fields.
  ///
  /// Only the provided (non-null) fields are written — omitted fields
  /// are left untouched.  Returns the updated [Profile].
  Future<Profile> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? city,
  }) async {
    final user = currentUser;
    if (user == null) throw const AuthException('You are not signed in.');

    final payload = <String, dynamic>{};
    if (fullName != null) payload['full_name'] = fullName.trim();
    if (phoneNumber != null) payload['phone_number'] = phoneNumber.trim();
    if (city != null) payload['city'] = city.trim();

    if (payload.isEmpty) return (await fetchCurrentProfile())!;

    final row = await _db
        .from('profiles')
        .update(payload)
        .eq('id', user.id)
        .select()
        .single();
    return Profile.fromJson(row);
  }

  /// Role of the signed-in user, resolved from the `profiles` table.
  ///
  /// Returns null when signed out or when no profile row exists yet.
  Future<UserRole?> currentRole() async {
    final profile = await fetchCurrentProfile();
    return profile?.role;
  }

  /// True when the signed-in user holds the given role.
  Future<bool> hasRole(UserRole role) async => await currentRole() == role;

  /// Ensure the signed-in user has a row in `public.profiles`.
  ///
  /// The `handle_new_user()` database trigger should handle this, but when
  /// it fails (RLS edge-cases, race conditions, or OAuth callback quirks)
  /// the client would be stuck with no role.  This method acts as a client-
  /// side safety net: it queries `profiles`, and when the row is missing it
  /// calls the `set_user_role` RPC to upsert a default client profile.
  ///
  /// Safe to call repeatedly — the RPC is idempotent.
  Future<void> ensureProfileExists() async {
    final user = currentUser;
    if (user == null) return;

    final profile = await fetchCurrentProfile();
    if (profile != null) return; // profile already exists

    // Profile is missing — create one via the security-definer RPC.
    // Extract a display name from auth metadata (Google OAuth, email signup).
    final meta = user.userMetadata;
    final fullName = (meta?['full_name'] as String?) ??
        (meta?['name'] as String?) ??
        user.email?.split('@').first ??
        'User';

    try {
      await _db.rpc('set_user_role', params: {
        'target_role': 'client',
      });
    } catch (e, st) {
      debugPrint('ensureProfileExists: set_user_role RPC failed: $e');
      Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'operation': 'ensureProfileExists_RPC'}));
    }

    // If the RPC still didn't create the row (e.g. RPC doesn't exist yet),
    // try a direct insert as a last resort.
    try {
      final existing = await fetchCurrentProfile();
      if (existing == null) {
        await _db.from('profiles').upsert({
          'id': user.id,
          'full_name': fullName,
          'email': user.email,
          'role': 'client',
        }, onConflict: 'id');
      }
    } catch (e, st) {
      debugPrint('ensureProfileExists: direct upsert failed: $e');
      Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'operation': 'ensureProfileExists_upsert'}));
    }
  }

  // ---------------------------------------------------------------------------
  // Providers & services
  // ---------------------------------------------------------------------------

  /// Top-rated providers, optionally narrowed to one of the supported cities
  /// (Douala, Yaoundé, Limbe, Bafoussam, Kribi).
  Future<List<Provider>> fetchTopRated({
    String? city,
    int limit = 10,
  }) async {
    // Filters (eq) must be applied before transforms (order/limit).
    var query = _db.from('providers').select();
    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }
    final rows = await query.order('rating', ascending: false).limit(limit);
    return rows.map(Provider.fromJson).toList();
  }

  /// All providers in a city, optionally filtered by service category
  /// (e.g. "Barbing / Coiffure", "Braiding / Tresses").
  Future<List<Provider>> fetchProvidersByCity(
    String city, {
    String? category,
    int limit = 50,
  }) async {
    var query = _db.from('providers').select('*, profiles!user_id(avatar_url)').eq('city', city);
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    final rows = await query.order('rating', ascending: false).limit(limit);
    return rows.map(Provider.fromJson).toList();
  }

  /// Generic provider search: any combination of city, category and a
  /// maximum starting price (price_from <= [maxPrice]).
  Future<List<Provider>> fetchProviders({
    String? city,
    String? category,
    int? maxPrice,
    int limit = 50,
  }) async {
    var query = _db.from('providers').select('*, profiles!user_id(avatar_url)');
    if (city != null && city.isNotEmpty) query = query.eq('city', city);
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (maxPrice != null && maxPrice > 0) {
      query = query.lte('price_from', maxPrice);
    }
    final rows = await query.order('rating', ascending: false).limit(limit);
    return rows.map(Provider.fromJson).toList();
  }

  /// Full-text style search over provider names, quarters and cities, plus
  /// any provider whose published service names match the query.
  Future<List<Provider>> searchProviders({
    String? query,
    String? category,
    String? city,
    int? maxPrice,
    int limit = 50,
  }) async {
    final q = query?.trim().toLowerCase() ?? '';

    var providerQuery = _db.from('providers').select('*, profiles!user_id(avatar_url)');
    if (city != null && city.isNotEmpty) {
      providerQuery = providerQuery.eq('city', city);
    }
    if (category != null && category.isNotEmpty) {
      providerQuery = providerQuery.eq('category', category);
    }
    if (maxPrice != null && maxPrice > 0) {
      providerQuery = providerQuery.lte('price_from', maxPrice);
    }
    if (q.isNotEmpty) {
      providerQuery = providerQuery.or(
        'business_name.ilike.%$q%,city.ilike.%$q%,quarter.ilike.%$q%',
      );
    }
    final providerRows =
        await providerQuery.order('rating', ascending: false).limit(limit);

    var providers = providerRows.map(Provider.fromJson).toList();

    // Also surface providers whose *services* match (the query may be a
    // service name like "box braids").
    if (q.isNotEmpty) {
      final serviceRows = await _db
          .from('services')
          .select('provider_id')
          .ilike('name', '%$q%')
          .limit(limit);
      final extraIds =
          serviceRows.map((r) => r['provider_id'].toString()).toSet();
      if (extraIds.isNotEmpty) {
        final extra = await fetchProvidersByIds(extraIds.toList());
        final seen = providers.map((p) => p.id).toSet();
        providers.addAll(extra.where((p) => !seen.contains(p.id)));
      }
    }

    providers.sort((a, b) => b.rating.compareTo(a.rating));
    return providers.take(limit).toList();
  }

  Future<Provider?> fetchProviderById(String providerId) async {
    final rows = await _db
        .from('providers')
        .select('*, profiles!user_id(avatar_url)')
        .eq('id', providerId)
        .limit(1);
    if (rows.isEmpty) return null;
    return Provider.fromJson(rows.first);
  }

  /// The provider row belonging to the given user (for provider dashboards).
  Future<Provider?> fetchProviderByUserId(String userId) async {
    final rows = await _db
        .from('providers')
        .select('*, profiles!user_id(avatar_url)')
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    return Provider.fromJson(rows.first);
  }

  /// Bulk provider lookup (for enriching booking rows with names/locations).
  Future<List<Provider>> fetchProvidersByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _db
        .from('providers')
        .select('*, profiles!user_id(avatar_url)')
        .inFilter('id', ids);
    return rows.map(Provider.fromJson).toList();
  }

  /// Bulk service lookup (for rendering the service names of a booking).
  Future<List<Service>> fetchServicesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _db.from('services').select().inFilter('id', ids);
    return rows.map(Service.fromJson).toList();
  }

  /// Bulk profile lookup (for showing client names on the provider side).
  Future<List<Profile>> fetchProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _db.from('profiles').select().inFilter('id', ids);
    return rows.map(Profile.fromJson).toList();
  }

  /// Active service catalog for a provider, sorted by name.
  ///
  /// Tolerates deployments where the `services` table lacks the `is_active`
  /// column (drift from this repo's schema): it retries the fetch without the
  /// filter when Postgres reports the column is missing.
  Future<List<Service>> fetchServicesForProvider(String providerId) async {
    try {
      final rows = await _db
          .from('services')
          .select()
          .eq('provider_id', providerId)
          .eq('is_active', true)
          .order('name');
      return rows.map(Service.fromJson).toList();
    } catch (e) {
      if (!e.toString().contains('42703')) rethrow;
      final rows = await _db
          .from('services')
          .select()
          .eq('provider_id', providerId)
          .order('name');
      return rows.map(Service.fromJson).toList();
    }
  }

  // ---------------------------------------------------------------------------
  // Bookings
  // ---------------------------------------------------------------------------

  /// Check whether a provider already has a non-cancelled booking at the
  /// requested time. Returns `true` when the slot is free.
  ///
  /// This is a client-side pre-flight check — the DB trigger may also
  /// enforce uniqueness server-side.
  Future<bool> checkProviderSlotAvailable({
    required String providerId,
    required DateTime scheduledAt,
  }) async {
    try {
      final rows = await _db
          .from('bookings')
          .select('id')
          .eq('provider_id', providerId)
          .eq('scheduled_at', scheduledAt.toUtc().toIso8601String())
          .not('status', 'eq', 'cancelled')
          .limit(1);
      return rows.isEmpty;
    } catch (_) {
      // If the check fails, allow the booking (the DB trigger will catch it).
      return true;
    }
  }

  /// Insert a new booking request (status starts as "pending" in the DB).
  ///
  /// `totalPriceFcfa` should be the sum of the selected services' prices.
  Future<Booking> createBooking({
    required String clientId,
    required String providerId,
    required List<String> serviceIds,
    required DateTime scheduledAt,
    required int totalPriceFcfa,
    String? notes,
  }) async {
    return _captureAndRethrow(
      () async {
        final row = await _db
            .from('bookings')
            .insert({
              'client_id': clientId,
              'provider_id': providerId,
              'service_ids': serviceIds,
              'scheduled_at': scheduledAt.toUtc().toIso8601String(),
              'total_price_fcfa': totalPriceFcfa,
              'notes': notes,
            })
            .select()
            .single();
        return Booking.fromJson(row);
      },
      'createBooking',
    );
  }

  /// Update a booking's status (provider side).
  ///
  /// When transitioning from pending, also stamps responded_at for
  /// response time analytics.
  Future<void> updateBookingStatus(
    String bookingId,
    BookingStatus status,
  ) async {
    final payload = <String, dynamic>{'status': status.name};

    // Stamp responded_at when the provider first responds to a pending booking.
    if (status != BookingStatus.pending) {
      payload['responded_at'] = DateTime.now().toUtc().toIso8601String();
    }

    await _db
        .from('bookings')
        .update(payload)
        .eq('id', bookingId);
  }

  /// Live, ordered stream of a provider's bookings.
  ///
  /// Backed by Supabase Realtime: any insert/update on `public.bookings`
  /// filtered to this provider is pushed to every connected client. Requires
  /// the table to be added to the `supabase_realtime` publication
  /// (included in schema.sql).
  Stream<List<Booking>> watchBookingsForProvider(String providerId) {
    return _db
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Booking.fromJson).toList());
  }

  /// Live, ordered stream of a client's bookings.
  Stream<List<Booking>> watchBookingsForClient(String clientId) {
    return _db
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Booking.fromJson).toList());
  }

  /// Total booking count for a client (used by profile stats pill).
  Future<int> fetchBookingCount(String clientId) async {
    try {
      final data = await _db
          .from('bookings')
          .select('id')
          .eq('client_id', clientId);
      return data.length;
    } catch (_) {
      return 0;
    }
  }

  /// Completed booking count for a provider (used by profile stats bar).
  Future<int> fetchProviderCompletedBookingCount(String providerId) async {
    try {
      final data = await _db
          .from('bookings')
          .select('id')
          .eq('provider_id', providerId)
          .eq('status', 'completed');
      return data.length;
    } catch (_) {
      return 0;
    }
  }

  /// A client cancels one of their own upcoming bookings.
  Future<void> cancelBooking(String bookingId) async {
    await _db
        .from('bookings')
        .update({'status': BookingStatus.cancelled.name})
        .eq('id', bookingId);
  }

  /// Reschedule an upcoming booking to a new date/time.
  ///
  /// Only pending or confirmed bookings can be rescheduled. The new slot is
  /// checked for conflicts before writing. Returns the updated [Booking].
  Future<Booking> rescheduleBooking({
    required String bookingId,
    required DateTime newScheduledAt,
  }) async {
    return _captureAndRethrow(
      () async {
        final row = await _db
            .from('bookings')
            .select()
            .eq('id', bookingId)
            .single();
        final booking = Booking.fromJson(row);

        // Verify the new slot is available for this provider.
        final available = await checkProviderSlotAvailable(
          providerId: booking.providerId,
          scheduledAt: newScheduledAt,
        );
        if (!available) {
          throw Exception(
            'This time slot is no longer available. / Ce créneau n\'est plus disponible.',
          );
        }

        final updated = await _db
            .from('bookings')
            .update({
              'scheduled_at': newScheduledAt.toUtc().toIso8601String(),
            })
            .eq('id', bookingId)
            .select()
            .single();
        return Booking.fromJson(updated);
      },
      'rescheduleBooking',
    );
  }

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------

  /// Live set of provider ids the user has favorited.
  ///
  /// Backed by Supabase Realtime on `public.favorites`, so a heart tapped in
  /// one screen is reflected everywhere (and survives app restarts).
  Stream<Set<String>> watchFavoriteProviderIds(String userId) {
    return _db
        .from('favorites')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) => rows
            .map((r) => r['provider_id'].toString())
            .toSet());
  }

  /// Persist a favorite (upsert is idempotent).
  Future<void> addFavorite({
    required String userId,
    required String providerId,
  }) async {
    await _db.from('favorites').upsert({
      'user_id': userId,
      'provider_id': providerId,
    }, onConflict: 'user_id,provider_id');
  }

  /// Remove a favorite.
  Future<void> removeFavorite({
    required String userId,
    required String providerId,
  }) async {
    await _db
        .from('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('provider_id', providerId);
  }

  /// Favorited providers for the given user (for the Profile favorites list).
  Future<List<Provider>> fetchFavoriteProviders(String userId) async {
    final rows = await _db
        .from('favorites')
        .select('provider_id')
        .eq('user_id', userId);
    final ids = rows.map((r) => r['provider_id'].toString()).toList();
    return fetchProvidersByIds(ids);
  }

  // ---------------------------------------------------------------------------
  // Messages / chat
  // ---------------------------------------------------------------------------

  /// Live, oldest-first stream of every message in one client<->provider
  /// thread.
  Stream<List<Message>> watchMessages({
    required String clientId,
    required String providerId,
  }) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('client_id', clientId)
        .eq('provider_id', providerId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  /// Live stream of all of a client's messages (for the Messages tab,
  /// grouped by provider in the UI).
  Stream<List<Message>> watchMessagesForClient(String clientId) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('client_id', clientId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  /// Live stream of all of a provider's messages (for provider Messages tab).
  Stream<List<Message>> watchMessagesForProvider(String providerId) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('provider_id', providerId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  /// Send one message; the sender must be one of the two thread
  /// participants (enforced by RLS too).
  Future<Message> sendMessage({
    required String clientId,
    required String providerId,
    required String senderId,
    required String body,
  }) async {
    final row = await _db
        .from('messages')
        .insert({
          'client_id': clientId,
          'provider_id': providerId,
          'sender_id': senderId,
          'body': body.trim(),
        })
        .select()
        .single();
    return Message.fromJson(row);
  }

  // ---------------------------------------------------------------------------
  // Notification Preferences
  // ---------------------------------------------------------------------------

  /// Get a notification preference. Defaults to true (enabled).
  Future<bool> getNotificationPref(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Set a notification preference.
  Future<void> setNotificationPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best effort.
    }
  }

  /// Check if notifications are enabled for a specific category.
  Future<bool> isNotificationEnabled(String category) async {
    return getNotificationPref(category);
  }

  /// In-memory timestamp of the last time the user viewed messages.
  /// Reset to now on app start; updated when Messages tab is opened.
  static DateTime _lastMessagesSeen = DateTime.now().toUtc();

  /// Count unread messages for the current user.
  ///
  /// Counts messages where sender_id != current user and
  /// created_at > _lastMessagesSeen.
  Future<int> getUnreadMessageCount() async {
    final user = currentUser;
    if (user == null) return 0;

    try {
      final rows = await _db
          .from('messages')
          .select('id')
          .neq('sender_id', user.id)
          .gt('created_at', _lastMessagesSeen.toIso8601String());
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Mark all messages as read by updating the last-seen timestamp.
  void markMessagesAsRead() {
    _lastMessagesSeen = DateTime.now().toUtc();
  }

  // ---------------------------------------------------------------------------
  // Provider business & service management
  // ---------------------------------------------------------------------------

  /// Upload the provider's cover photo to Storage and return its public URL.
  ///
  /// The image is stored at `covers/<user_id>.jpg` in the public
  /// `provider_assets` bucket, so re-saving simply overwrites the same
  /// object (no orphaned files when the photo changes). Requires the bucket
  /// and its storage policies — see `supabase/schema.sql` (or run
  /// `supabase/provider_cover_storage.sql` against an existing database).
  ///
  /// Uses [uploadBinary] (not [upload]) because on web `storage_client`
  /// types its `File` parameter as `dynamic` and calls
  /// `file.readAsBytesSync()` on it — a `Uint8List` has `readAsBytes` but not
  /// `readAsBytesSync`, so a photo upload on web threw
  /// `NoSuchMethodError: method not found: ... (c... is not a function)`.
  /// [uploadBinary] is the documented web-safe path for raw bytes.
  Future<String> uploadProviderCover(Uint8List bytes) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    const bucket = 'provider_assets';
    final path = 'covers/${user.id}.jpg';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }

  /// Upload a portfolio work-sample image to Storage and return its public URL.
  ///
  /// Stored at `provider-portfolios/{user_id}/{fileName}`. The caller is
  /// responsible for appending the returned URL to the provider's
  /// `portfolio_images` array via [updatePortfolioImages].
  Future<String> uploadPortfolioImage(
    Uint8List bytes,
    String fileName,
  ) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    const bucket = 'provider_portfolios';
    final path = '${user.id}/$fileName';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }

  /// Upload a profile avatar to Supabase Storage and update both
  /// `profiles.avatar_url` and `providers.cover_url` (if the user is a provider).
  ///
  /// Returns the public URL of the uploaded image.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }

    const bucket = 'avatars';
    final path = 'avatar_${user.id}.jpg';

    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl = _db.storage.from(bucket).getPublicUrl(path);

    // Update profiles table — avatar only.
    await _db
        .from('profiles')
        .update({'avatar_url': publicUrl}).eq('id', user.id);

    // Also update providers.avatar_url if the user is a provider.
    try {
      await _db
          .from('providers')
          .update({'avatar_url': publicUrl}).eq('user_id', user.id);
    } catch (_) {
      // User may not be a provider — ignore.
    }

    return publicUrl;
  }

  /// Upload a cover / work showcase photo for a provider.
  ///
  /// Writes to the 'covers' bucket and updates `providers.cover_url` only.
  Future<String> uploadCoverPhoto({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }

    const bucket = 'covers';
    final path = 'cover_${user.id}.jpg';

    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl = _db.storage.from(bucket).getPublicUrl(path);

    await _db
        .from('providers')
        .update({'cover_url': publicUrl}).eq('user_id', user.id);

    return publicUrl;
  }

  /// Replace the provider's portfolio image URL list.
  ///
  /// Strictly enforces a maximum of 7 images. Throws an [ArgumentError]
  /// if the list exceeds the limit.
  Future<void> updatePortfolioImages(List<String> imageUrls) async {
    if (imageUrls.length > 7) {
      throw ArgumentError('Portfolio can contain at most 7 images.');
    }
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    await _db
        .from('providers')
        .update({'portfolio_images': imageUrls}).eq('user_id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Provider availability
  // ---------------------------------------------------------------------------

  /// Toggle the provider's availability status (online / busy).
  Future<void> toggleAvailability(bool isAvailable) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    await _db
        .from('providers')
        .update({'is_available': isAvailable}).eq('user_id', user.id);
  }

  /// Watch for changes on the providers table so the client home screen
  /// updates availability badges in realtime.
  Stream<List<Provider>> watchProviders() {
    return _db
        .from('providers')
        .stream(primaryKey: ['id'])
        .order('rating', ascending: false)
        .map((rows) => rows.map(Provider.fromJson).toList());
  }

  /// Create (or update) the provider's own business row.
  ///
  /// When [providerId] is null the row is created for the current user;
  /// otherwise the existing row is updated in place.
  Future<Provider> saveBusiness({
    String? providerId,
    required String businessName,
    required String category,
    required String city,
    String? quarter,
    String? bio,
    required ServiceType serviceType,
    String? coverUrl,
    Map<String, String?>? workingHours,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    final payload = {
      'business_name': businessName,
      'category': category,
      'city': city,
      'quarter': quarter,
      'bio': bio,
      'service_type': serviceType.name,
      'cover_url': coverUrl,
      'working_hours': workingHours ?? const <String, String?>{},
    };
    final Map<String, dynamic> row;
    if (providerId == null) {
      row = await _db
          .from('providers')
          .insert({...payload, 'user_id': user.id})
          .select()
          .single();
    } else {
      row = await _db
          .from('providers')
          .update(payload)
          .eq('id', providerId)
          .select()
          .single();
    }
    return Provider.fromJson(row);
  }

  /// Create a new service listing.
  Future<Service> createService({
    required String providerId,
    required String name,
    String? description,
    required int price,
    required int durationMinutes,
  }) async {
    final row = await _db
        .from('services')
        .insert({
          'provider_id': providerId,
          'name': name,
          'description': description,
          'price': price,
          'duration_minutes': durationMinutes,
          'is_active': true,
        })
        .select()
        .single();
    return Service.fromJson(row);
  }

  /// Update an existing service listing.
  Future<Service> updateService(Service service) async {
    final row = await _db
        .from('services')
        .update(service.toJson())
        .eq('id', service.id)
        .select()
        .single();
    return Service.fromJson(row);
  }

  /// Permanently delete a service listing.
  Future<void> deleteService(String serviceId) async {
    await _db.from('services').delete().eq('id', serviceId);
  }

  // ---------------------------------------------------------------------------
  // Blocked providers
  // ---------------------------------------------------------------------------

  /// Block a provider — they won't appear in the client's search results.
  Future<void> blockProvider({
    required String providerId,
    String? reason,
  }) async {
    final user = currentUser;
    if (user == null) throw const AuthException('You are not signed in.');
    await _db.from('blocked_providers').upsert({
      'user_id': user.id,
      'provider_id': providerId,
      'reason': reason,
    }, onConflict: 'user_id,provider_id');
  }

  /// Unblock a previously blocked provider.
  Future<void> unblockProvider(String providerId) async {
    final user = currentUser;
    if (user == null) throw const AuthException('You are not signed in.');
    await _db
        .from('blocked_providers')
        .delete()
        .eq('user_id', user.id)
        .eq('provider_id', providerId);
  }

  /// Live stream of blocked provider IDs for the current user.
  Stream<Set<String>> watchBlockedProviderIds() {
    final userId = currentUser?.id;
    if (userId == null) return Stream.value(const {});
    return _db
        .from('blocked_providers')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) => rows
            .map((r) => r['provider_id'].toString())
            .toSet());
  }

  /// Check if a specific provider is blocked.
  Future<bool> isProviderBlocked(String providerId) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      final rows = await _db
          .from('blocked_providers')
          .select('id')
          .eq('user_id', user.id)
          .eq('provider_id', providerId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Reviews
  // ---------------------------------------------------------------------------

  /// Submit a client review for a completed booking.
  ///
  /// Inserts into `public.reviews` and updates the provider's aggregate
  /// `rating` and `review_count`. Throws if the booking has already been
  /// reviewed (unique constraint on booking_id).
  Future<void> submitReview({
    required String bookingId,
    required String providerId,
    required int rating,
    String? comment,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('You are not signed in.');
    }
    try {
      await _db.from('reviews').insert({
        'booking_id': bookingId,
        'provider_id': providerId,
        'client_id': user.id,
        'rating': rating,
        'comment': comment,
      });
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'operation': 'submitReview', 'booking_id': bookingId}));
      final msg = e.toString();
      // Provide a user-friendly message for common DB errors.
      if (msg.contains('relation "public.reviews" does not exist') ||
          msg.contains('42P01')) {
        throw Exception(
          'The reviews table is not set up yet. '
          'Please run supabase/add_reviews_table_v2.sql in the Supabase SQL Editor first.',
        );
      }
      if (msg.contains('23503')) {
        throw Exception(
          'Invalid booking or provider reference. The booking may no longer exist.',
        );
      }
      if (msg.contains('23505')) {
        throw Exception('This booking has already been reviewed.');
      }
      if (msg.contains('row-level security') || msg.contains('42501')) {
        throw Exception(
          'Permission denied. The reviews table RLS policy may need updating. '
          'Run supabase/add_reviews_table_v2.sql in the Supabase SQL Editor.',
        );
      }
      rethrow;
    }
    // Notify the provider that a new review was submitted (fire-and-forget).
    NotificationService.instance.notifyNewReview(providerId);
  }

  /// Check if a booking has already been reviewed.
  Future<bool> isBookingReviewed(String bookingId) async {
    final rows = await _db
        .from('reviews')
        .select('id')
        .eq('booking_id', bookingId)
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Fetch all reviews for a provider, newest first.
  Future<List<Map<String, dynamic>>> fetchReviewsForProvider(
    String providerId, {
    int limit = 20,
  }) async {
    return await _db
        .from('reviews')
        .select('id, rating, comment, created_at, client_id, profiles!client_id(full_name, avatar_url)')
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .limit(limit);
  }

  // ---------------------------------------------------------------------------
  // Provider Analytics
  // ---------------------------------------------------------------------------

  /// Record a profile view.  Deduplicates per client+provider+day server-side
  /// via the UNIQUE constraint on (provider_id, viewer_id, day).
  Future<void> recordProfileView(String providerId) async {
    final userId = currentUser?.id;
    try {
      await _db.from('profile_views').upsert({
        'provider_id': providerId,
        'viewer_id': userId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'provider_id,viewer_id,viewed_at');
    } catch (_) {
      // Analytics should never block the UX.
    }
  }

  /// Record a search impression for one or more provider IDs.
  Future<void> recordSearchImpressions({
    required List<String> providerIds,
    String? query,
    String? city,
    String? category,
  }) async {
    if (providerIds.isEmpty) return;
    try {
      final rows = providerIds
          .map((id) => {
                'provider_id': id,
                'query': query,
                'city': city,
                'category': category,
                'shown_at': DateTime.now().toUtc().toIso8601String(),
              })
          .toList();
      await _db.from('search_impressions').insert(rows);
    } catch (_) {
      // Analytics should never block the UX.
    }
  }

  /// Total profile views for a provider within an optional date range.
  Future<int> getProfileViewCount(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_profile_view_count', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Total search impressions for a provider within an optional date range.
  Future<int> getSearchImpressionCount(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_search_impression_count', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Booking conversion rate (completed bookings / views) as a percentage.
  Future<double> getConversionRate(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_conversion_rate', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Daily profile views as [{day: "2025-01-15", count: 12}, ...].
  Future<List<Map<String, dynamic>>> getDailyViews(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_daily_views', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Top search queries that led to impressions for a provider.
  Future<List<Map<String, dynamic>>> getTopSearchQueries(
    String providerId, {
    int limit = 10,
  }) async {
    try {
      final result = await _db.rpc('get_top_search_queries', params: {
        'p_provider_id': providerId,
        'p_limit': limit,
      });
      return (result as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Average response time in minutes for a provider within a date range.
  Future<double> getAvgResponseTime(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_avg_response_time', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Response rate: percentage of bookings that received a response.
  Future<double> getResponseRate(String providerId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final result = await _db.rpc('get_response_rate', params: {
        'p_provider_id': providerId,
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      });
      return (result as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}

