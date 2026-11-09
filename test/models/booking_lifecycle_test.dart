import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/booking.dart';

/// The server enforces these transitions in
/// supabase/migrations/20261109000000_launch_readiness.sql. These tests keep
/// the client's visibility rules aligned with that contract.
void main() {
  test('clients can cancel only before a session starts', () {
    expect(BookingLifecycle.clientCanCancel(BookingStatus.pending), isTrue);
    expect(BookingLifecycle.clientCanCancel(BookingStatus.confirmed), isTrue);
    expect(BookingLifecycle.clientCanCancel(BookingStatus.arrived), isFalse);
    expect(BookingLifecycle.clientCanCancel(BookingStatus.inProgress), isFalse);
    expect(BookingLifecycle.clientCanCancel(BookingStatus.completed), isFalse);
  });

  test('clients can reschedule only pending or confirmed bookings', () {
    expect(BookingLifecycle.clientCanReschedule(BookingStatus.pending), isTrue);
    expect(
        BookingLifecycle.clientCanReschedule(BookingStatus.confirmed), isTrue);
    expect(
        BookingLifecycle.clientCanReschedule(BookingStatus.arrived), isFalse);
  });

  test('providers cannot skip arrival or PIN verification', () {
    expect(BookingLifecycle.providerCanMarkArrived(BookingStatus.confirmed),
        isTrue);
    expect(BookingLifecycle.providerCanMarkArrived(BookingStatus.pending),
        isFalse);
    expect(
        BookingLifecycle.providerCanVerifyPin(BookingStatus.arrived), isTrue);
    expect(BookingLifecycle.providerCanVerifyPin(BookingStatus.confirmed),
        isFalse);
    expect(
        BookingLifecycle.providerCanComplete(BookingStatus.inProgress), isTrue);
    expect(
        BookingLifecycle.providerCanComplete(BookingStatus.confirmed), isFalse);
  });

  test('provider may respond only to pending requests', () {
    expect(BookingLifecycle.providerCanRespond(BookingStatus.pending), isTrue);
    expect(
        BookingLifecycle.providerCanRespond(BookingStatus.confirmed), isFalse);
    expect(
        BookingLifecycle.providerCanRespond(BookingStatus.cancelled), isFalse);
  });
}
