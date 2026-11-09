import 'package:supabase_flutter/supabase_flutter.dart';

/// Invokes a Supabase Edge Function and returns its response.
typedef AccountDeleteInvoker = Future<FunctionResponse> Function(
  String functionName,
);

/// Signs the now-deleted user out of the local Supabase session.
typedef SignOutCallback = Future<void> Function();

/// Thrown when the server did not confirm that the account was deleted.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deletes the signed-in account through the trusted `delete-account` Edge
/// Function.
///
/// The browser never receives the Supabase service-role key. The function
/// verifies the caller's access token, removes the user's stored images, and
/// deletes the auth user (database rows cascade). Sign-out happens only after
/// the server confirms `deleted: true`, so a failed deletion leaves the
/// session intact and the error visible to the user.
class AccountDeletionService {
  const AccountDeletionService({
    required this.invoke,
    required this.signOut,
  });

  final AccountDeleteInvoker invoke;
  final SignOutCallback signOut;

  Future<void> deleteAccount() async {
    final response = await invoke('delete-account');
    final data = response.data;

    final confirmed =
        response.status == 200 && data is Map && data['deleted'] == true;

    if (!confirmed) {
      final serverMessage =
          data is Map ? (data['error'] ?? data['message'])?.toString() : null;
      throw AccountDeletionException(
        serverMessage == null || serverMessage.isEmpty
            ? 'The server did not confirm account deletion (HTTP '
                '${response.status}). Your account has not been deleted.'
            : 'Account deletion failed: $serverMessage',
      );
    }

    await signOut();
  }
}
