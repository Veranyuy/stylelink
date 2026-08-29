import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

/// Utility for wrapping Supabase / network calls with user-friendly error
/// messages and optional retry logic.
class NetworkAware {
  NetworkAware._();

  /// Execute [operation] with automatic retry on transient network errors.
  ///
  /// Returns the result on success, or throws a [NetworkError] with a
  /// user-friendly message on failure.
  static Future<T> run<T>(
    Future<T> Function() operation, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 2),
    String? context,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        final isTransient = _isTransientError(e);

        if (isTransient && attempt <= maxRetries) {
          debugPrint(
            'NetworkAware: retry $attempt/$maxRetries'
            '${context != null ? ' for $context' : ''}: $e',
          );
          await Future.delayed(retryDelay * attempt);
          continue;
        }

        throw NetworkError(
          message: _friendlyMessage(e),
          originalError: e,
          isTransient: isTransient,
        );
      }
    }
  }

  /// Check if the error is likely transient (timeout, connection refused, etc.)
  static bool _isTransientError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('failed host lookup') ||
        msg.contains('eof') ||
        msg.contains('http status 5') || // 5xx server errors
        msg.contains('http status 429'); // rate limited
  }

  /// Convert a raw error into a user-friendly message.
  static String _friendlyMessage(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('timeout')) {
      return 'Connection timed out. Please check your internet and try again.\n'
          'La connexion a expiré. Vérifiez votre connexion internet.';
    }
    if (msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('failed host lookup')) {
      return 'No internet connection. Please check your network settings.\n'
          'Aucune connexion internet. Vérifiez vos paramètres réseau.';
    }
    if (msg.contains('http status 429')) {
      return 'Too many requests. Please wait a moment and try again.\n'
          'Trop de requêtes. Veuillez patienter et réessayer.';
    }
    if (msg.contains('http status 5')) {
      return 'Server error. Please try again later.\n'
          'Erreur serveur. Veuillez réessayer plus tard.';
    }

    // Return the original error for known/local errors.
    return error.toString();
  }
}

/// A typed error with a user-friendly message and retry metadata.
class NetworkError implements Exception {
  const NetworkError({
    required this.message,
    this.originalError,
    this.isTransient = false,
  });

  final String message;
  final Object? originalError;
  final bool isTransient;

  @override
  String toString() => message;
}
