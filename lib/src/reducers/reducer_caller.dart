import 'dart:async';
import 'dart:typed_data';

import 'package:spacetimedb_dart_sdk/src/codec/bsatn_encoder.dart';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/messages/client_messages.dart';
import 'package:spacetimedb_dart_sdk/src/reducers/transaction_result.dart';

/// Tracks a pending reducer request
class _PendingRequest {
  final Completer<TransactionResult> completer;
  final Timer timeout;
  final String reducerName;

  _PendingRequest({
    required this.completer,
    required this.timeout,
    required this.reducerName,
  });

  void dispose() {
    timeout.cancel();
  }
}

class ReducerCaller {
  final SpacetimeDbConnection _connection;
  int _nextRequestId = 1;

  /// Map of pending requests by requestId
  final Map<int, _PendingRequest> _pendingRequests = {};

  /// Default timeout for reducer calls (10 seconds)
  Duration defaultTimeout = const Duration(seconds: 10);

  ReducerCaller(this._connection);

  /// Call a reducer with BSATN-encoded arguments
  ///
  /// Returns a [TransactionResult] containing the execution status, timing, and energy usage.
  ///
  /// Example:
  /// ```dart
  /// final encoder = BsatnEncoder();
  /// encoder.writeString("My Note");
  /// encoder.writeString("Note content here");
  /// final result = await reducer.call("create_note", encoder.toBytes());
  /// if (result.isSuccess) {
  ///   print('Note created! Energy: ${result.energyConsumed}');
  /// } else {
  ///   print('Failed: ${result.errorMessage}');
  /// }
  /// ```
  Future<TransactionResult> call(
    String reducerName,
    Uint8List args, {
    Duration? timeout,
  }) async {
    final requestId = _nextRequestId++;
    final completer = Completer<TransactionResult>();
    final effectiveTimeout = timeout ?? defaultTimeout;

    // Create timeout timer
    final timer = Timer(effectiveTimeout, () {
      _timeoutRequest(requestId, reducerName, effectiveTimeout);
    });

    // Track pending request
    _pendingRequests[requestId] = _PendingRequest(
      completer: completer,
      timeout: timer,
      reducerName: reducerName,
    );

    // Send message
    final message = CallReducerMessage(
      reducerName: reducerName,
      args: args,
      requestId: requestId,
    );
    _connection.send(message.encode());

    return completer.future;
  }

  /// Helper to call reducer with a callback to encode arguments
  ///
  /// Example:
  /// ```dart
  /// final result = await reducer.callWith("create_note", (encoder) {
  ///   encoder.writeString("My Note");
  ///   encoder.writeString("Note content here");
  /// });
  /// ```
  Future<TransactionResult> callWith(
    String reducerName,
    void Function(BsatnEncoder encoder) encodeArgs, {
    Duration? timeout,
  }) async {
    final encoder = BsatnEncoder();
    encodeArgs(encoder);
    return call(reducerName, encoder.toBytes(), timeout: timeout);
  }

  /// Called by SubscriptionManager when TransactionUpdate arrives
  void completeRequest(int requestId, TransactionResult result) {
    // RACE CONDITION SAFETY: remove() is atomic and happens first.
    // If timeout fires simultaneously, only ONE wins the remove() race.
    // The loser gets null and returns early - no double-completion possible.
    final pending = _pendingRequests.remove(requestId);
    if (pending == null) {
      // Not our request (server-initiated reducer or already completed/timed out)
      return;
    }

    pending.dispose(); // Cancel timeout timer

    if (result.isSuccess) {
      pending.completer.complete(result);
    } else {
      pending.completer.completeError(
        ReducerException(
          reducerName: pending.reducerName,
          message: result.errorMessage ?? 'Unknown error',
          result: result,
        ),
      );
    }
  }

  /// Handle timeout for a pending request
  void _timeoutRequest(int requestId, String reducerName, Duration timeout) {
    // RACE CONDITION SAFETY: If completeRequest() already removed this ID,
    // we get null here and return early without double-completing.
    final pending = _pendingRequests.remove(requestId);
    if (pending != null) {
      pending.completer.completeError(
        TimeoutException(
          'Reducer "$reducerName" timed out after ${timeout.inSeconds}s',
          timeout,
        ),
      );
    }
  }

  /// Fail all pending requests (called when connection is lost)
  void failAllPendingRequests(String reason) {
    for (var pending in _pendingRequests.values) {
      pending.dispose();
      pending.completer.completeError(
        ConnectionException(
          'Connection lost during reducer call: $reason',
        ),
      );
    }
    _pendingRequests.clear();
  }

  /// Clean up all pending requests
  void dispose() {
    for (var pending in _pendingRequests.values) {
      pending.dispose();
    }
    _pendingRequests.clear();
  }
}

/// Exception thrown when a reducer fails
class ReducerException implements Exception {
  final String reducerName;
  final String message;
  final TransactionResult result;

  ReducerException({
    required this.reducerName,
    required this.message,
    required this.result,
  });

  @override
  String toString() => 'ReducerException($reducerName): $message';
}

/// Exception thrown when connection is lost during reducer call
class ConnectionException implements Exception {
  final String message;

  ConnectionException(this.message);

  @override
  String toString() => 'ConnectionException: $message';
}
