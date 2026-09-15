/// Strongly-typed model for the `public.bookings` table.
///
/// A booking links one client to one provider's schedule. `serviceIds` holds
/// the ids of the chosen `services` rows (uuid[]); `scheduledAt` is the exact
/// appointment timestamp in UTC. Status transitions are driven by the
/// provider side ("pending" -> "confirmed" | "cancelled") and by completion.
class Booking {
  final String id;
  final String clientId; // references profiles(id)
  final String providerId; // references providers(id)
  final List<String> serviceIds; // references services(id)
  final DateTime scheduledAt;
  final BookingStatus status;
  final int totalPriceFcfa; // FCFA
  final String? notes;
  final DateTime? createdAt;

  /// When the provider first responded (accepted/rejected/cancelled).
  final DateTime? respondedAt;

  /// The slot the client proposed in a reschedule request (null = none).
  ///
  /// While a reschedule is pending, [scheduledAt] keeps the ORIGINAL
  /// appointment; only when the provider accepts does the booking move to
  /// this slot.
  final DateTime? proposedScheduledAt;

  /// Lifecycle of the client's reschedule request (null = not a reschedule).
  final RescheduleStatus? rescheduleStatus;

  /// True when the provider still has to accept/decline a reschedule.
  bool get hasPendingReschedule =>
      rescheduleStatus == RescheduleStatus.pending &&
      proposedScheduledAt != null;

  /// Service-tracker fields (may be null for legacy bookings).
  final String? verificationPin;
  final double? arrivalLat;
  final double? arrivalLng;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const Booking({
    required this.id,
    required this.clientId,
    required this.providerId,
    required this.serviceIds,
    required this.scheduledAt,
    this.status = BookingStatus.pending,
    this.totalPriceFcfa = 0,
    this.notes,
    this.createdAt,
    this.respondedAt,
    this.proposedScheduledAt,
    this.rescheduleStatus,
    this.verificationPin,
    this.arrivalLat,
    this.arrivalLng,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      providerId: json['provider_id'] as String,
      serviceIds: (json['service_ids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      scheduledAt: DateTime.tryParse(json['scheduled_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: BookingStatus.parse(json['status']),
      totalPriceFcfa: _asInt(json['total_price_fcfa']),
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      respondedAt: DateTime.tryParse(json['responded_at']?.toString() ?? ''),
      proposedScheduledAt:
          DateTime.tryParse(json['proposed_scheduled_at']?.toString() ?? ''),
      rescheduleStatus: RescheduleStatus.parse(json['reschedule_status']),
      verificationPin: json['verification_pin']?.toString(),
      arrivalLat: _asDouble(json['arrival_lat']),
      arrivalLng: _asDouble(json['arrival_lng']),
      arrivedAt: DateTime.tryParse(json['arrived_at']?.toString() ?? ''),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'provider_id': providerId,
        'service_ids': serviceIds,
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'status': status.dbValue,
        'total_price_fcfa': totalPriceFcfa,
        'notes': notes,
        if (verificationPin != null) 'verification_pin': verificationPin,
        if (respondedAt != null) 'responded_at': respondedAt!.toIso8601String(),
        if (proposedScheduledAt != null)
          'proposed_scheduled_at':
              proposedScheduledAt!.toUtc().toIso8601String(),
        if (rescheduleStatus != null)
          'reschedule_status': rescheduleStatus!.dbValue,
        if (arrivedAt != null) 'arrived_at': arrivedAt!.toIso8601String(),
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };
  bool get isUpcoming =>
      status == BookingStatus.pending ||
      status == BookingStatus.confirmed ||
      status == BookingStatus.arrived ||
      status == BookingStatus.inProgress;

  bool get isPast =>
      status == BookingStatus.completed || status == BookingStatus.cancelled;

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }
}

/// Lifecycle of a client's reschedule request on a booking.
enum RescheduleStatus {
  /// The client proposed a new time; the provider has not responded yet.
  pending,

  /// The provider accepted: the booking now lives at the proposed slot.
  accepted,

  /// The provider declined: the booking keeps its original slot and status.
  rejected;

  /// Name as stored in the database (snake_case).
  String get dbValue => name;

  /// Localized-ish label for chips and banners.
  String get label => switch (this) {
        RescheduleStatus.pending => 'Reschedule request / Demande de report',
        RescheduleStatus.accepted => 'Reschedule accepted / Report accepté',
        RescheduleStatus.rejected => 'Reschedule declined / Report refusé',
      };

  static RescheduleStatus? parse(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'pending':
        return RescheduleStatus.pending;
      case 'accepted':
        return RescheduleStatus.accepted;
      case 'rejected':
      case 'declined':
        return RescheduleStatus.rejected;
      case '':
      case null:
        return null;
      default:
        return null;
    }
  }
}

/// Pure decision table for [SupabaseService.respondToReschedule].
///
/// Maps a pending reschedule request to the exact fields the provider's
/// response should write, or throws when the request cannot be resolved.
/// Kept side-effect-free so it can be unit-tested without a database.
({Map<String, dynamic> updates, DateTime resolvedSlot, BookingStatus status})
    resolveRescheduleResponse({
  required Booking booking,
  required bool accept,
}) {
  if (booking.rescheduleStatus != RescheduleStatus.pending ||
      booking.proposedScheduledAt == null) {
    throw StateError('This booking has no pending reschedule request.');
  }
  if (booking.status != BookingStatus.confirmed &&
      booking.status != BookingStatus.pending) {
    throw StateError(
      'Only pending or confirmed bookings can be reschedule-responded.',
    );
  }

  if (accept) {
    return (
      updates: {
        'scheduled_at': booking.proposedScheduledAt!.toUtc().toIso8601String(),
        'status': BookingStatus.confirmed.dbValue,
        'reschedule_status': RescheduleStatus.accepted.dbValue,
        'proposed_scheduled_at': null,
        'responded_at': DateTime.now().toUtc().toIso8601String()
      },
      resolvedSlot: booking.proposedScheduledAt!,
      status: BookingStatus.confirmed,
    );
  }

  return (
    updates: {
      // Original scheduled_at is untouched — only clear the proposal.
      'reschedule_status': RescheduleStatus.rejected.dbValue,
      'proposed_scheduled_at': null,
      'responded_at':
          (booking.respondedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'status': booking.status.dbValue,
      'scheduled_at': booking.scheduledAt.toUtc().toIso8601String(),
    },
    resolvedSlot: booking.scheduledAt, // original slot preserved
    status: booking.status, // original status preserved
  );
}

enum BookingStatus {
  pending,
  confirmed,
  arrived,
  inProgress,
  completed,
  cancelled,
  rejected;

  /// Localized status label for chips and lists.
  String get statusLabel => switch (this) {
        BookingStatus.pending => 'Pending / En attente',
        BookingStatus.confirmed => 'Confirmed / Confirmé',
        BookingStatus.arrived => 'Arrived / Arrivé',
        BookingStatus.inProgress => 'In Progress / En cours',
        BookingStatus.completed => 'Completed / Terminé',
        BookingStatus.cancelled => 'Cancelled / Annulé',
        BookingStatus.rejected => 'Rejected / Refusé',
      };

  /// The status name as stored in the database (snake_case).
  String get dbValue => switch (this) {
        BookingStatus.inProgress => 'in_progress',
        _ => name,
      };

  static BookingStatus parse(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'arrived':
        return BookingStatus.arrived;
      case 'in_progress':
        return BookingStatus.inProgress;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
      case 'canceled':
        return BookingStatus.cancelled;
      case 'rejected':
        return BookingStatus.rejected;
      case 'pending':
      case null:
        return BookingStatus.pending;
      default:
        return BookingStatus.pending;
    }
  }
}
