import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/services/account_deletion_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('signs out only after the server confirms deletion', () async {
    var signedOut = false;

    final service = AccountDeletionService(
      invoke: (_) async => FunctionResponse(
        status: 200,
        data: {'deleted': true},
      ),
      signOut: () async {
        signedOut = true;
      },
    );

    await service.deleteAccount();

    expect(signedOut, isTrue);
  });

  test('keeps the session and surfaces the error when deletion fails',
      () async {
    var signedOut = false;

    final service = AccountDeletionService(
      invoke: (_) async => FunctionResponse(
        status: 500,
        data: {'error': 'storage cleanup failed'},
      ),
      signOut: () async {
        signedOut = true;
      },
    );

    await expectLater(
      service.deleteAccount(),
      throwsA(isA<AccountDeletionException>().having(
        (e) => e.message,
        'message',
        contains('storage cleanup failed'),
      )),
    );
    expect(signedOut, isFalse);
  });

  test('does not treat a 200 response without deleted:true as success',
      () async {
    var signedOut = false;

    final service = AccountDeletionService(
      invoke: (_) async => FunctionResponse(status: 200, data: {'ok': true}),
      signOut: () async {
        signedOut = true;
      },
    );

    await expectLater(
      service.deleteAccount(),
      throwsA(isA<AccountDeletionException>()),
    );
    expect(signedOut, isFalse);
  });
}
