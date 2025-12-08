import 'package:fixnum/fixnum.dart';

import '../messages/server_messages.dart';
import '../messages/update_status.dart';

/// Result of a reducer call, containing execution status and metadata.
///
/// This is returned when awaiting a reducer call:
/// ```dart
/// final result = await client.reducers.createNote(title: 'Hello', content: 'World');
/// if (result.isSuccess) {
///   print('Reducer completed successfully');
/// }
/// ```
class TransactionResult {
  /// The status of the transaction (Committed, Failed, or OutOfEnergy)
  final UpdateStatus status;

  /// Timestamp when the reducer started
  final DateTime timestamp;

  /// Energy consumed by this reducer execution
  ///
  /// `null` means unavailable (e.g., TransactionUpdateLight).
  /// `0` means the reducer was free (no energy charged).
  final int? energyConsumed;

  /// Total execution duration
  ///
  /// `null` means unavailable (e.g., TransactionUpdateLight).
  final Duration? executionDuration;

  /// The reducer name (null for TransactionUpdateLight)
  final String? reducerName;

  /// The reducer ID (null for TransactionUpdateLight)
  final int? reducerId;

  /// Whether this was a lightweight update (no reducer metadata)
  final bool isLightUpdate;

  TransactionResult({
    required this.status,
    required this.timestamp,
    this.energyConsumed,
    this.executionDuration,
    this.reducerName,
    this.reducerId,
    this.isLightUpdate = false,
  });

  /// Create result from a full TransactionUpdate message
  factory TransactionResult.fromTransactionUpdate(
      TransactionUpdateMessage message) {
    return TransactionResult(
      status: message.status,
      timestamp: DateTime.fromMicrosecondsSinceEpoch(
        (message.timestamp ~/ Int64(1000)).toInt(),
      ),
      energyConsumed: message.energyQuantaUsed,
      executionDuration: Duration(microseconds: message.totalHostExecutionDuration.toInt()),
      reducerName: message.reducerCall.reducerName,
      reducerId: message.reducerCall.reducerId,
      isLightUpdate: false,
    );
  }

  /// Create result from a lightweight TransactionUpdateLight message
  factory TransactionResult.fromTransactionUpdateLight(
      TransactionUpdateLightMessage message) {
    return TransactionResult(
      status: Committed(), // Light updates always mean success
      timestamp: DateTime.now(), // Approximate - server doesn't provide timestamp
      energyConsumed: null, // Not available in light updates
      executionDuration: null, // Not available in light updates
      reducerName: null,
      reducerId: null,
      isLightUpdate: true,
    );
  }

  /// Whether the transaction was committed successfully
  bool get isSuccess => status is Committed;

  /// Whether the transaction failed
  bool get isFailed => status is Failed;

  /// Whether the transaction ran out of energy
  bool get isOutOfEnergy => status is OutOfEnergy;

  /// Get error message if failed, otherwise null
  String? get errorMessage {
    final s = status;
    if (s is Failed) {
      return s.message;
    }
    if (s is OutOfEnergy) {
      return 'Out of energy: ${s.budgetInfo}';
    }
    return null;
  }

  @override
  String toString() {
    final energyStr = energyConsumed != null ? '$energyConsumed' : 'unknown';
    final durationStr = executionDuration != null ? '${executionDuration!.inMilliseconds}ms' : 'unknown';
    return 'TransactionResult('
        'status: ${status.runtimeType}, '
        'reducer: $reducerName, '
        'duration: $durationStr, '
        'energy: $energyStr, '
        'isLight: $isLightUpdate'
        ')';
  }
}
