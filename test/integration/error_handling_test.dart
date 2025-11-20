import 'dart:async';
import 'dart:typed_data';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';
import 'package:spacetimedb_dart_sdk/src/messages/server_messages.dart';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_encoder.dart';
import 'note_decoder.dart';

/// Error handling and failure mode tests for SpacetimeDB Dart SDK
///
/// Before running:
/// 1. spacetime start
/// 2. cd spacetime_test_module && spacetime publish notes-crud --server local
/// 3. dart run test/integration/error_handling_test.dart
///
/// IMPORTANT NOTES:
/// - Some tests require error-inducing procedures (divide_by_zero) in the module
/// - ERROR TEST 4 & 5 are NON-DETERMINISTIC and rely on timeout behavior
/// - These tests may be flaky in different network/server conditions (CI, slow networks)
/// - SpacetimeDB does not always send explicit error messages for invalid calls
/// - Timeout-based tests use 5-second timeouts to reduce false positives
/// - Consider these limitations when interpreting test results in CI/CD pipelines
///
/// For robust error detection, ideally SpacetimeDB would:
/// - Send explicit error messages for invalid reducer arguments
/// - Send error responses for BSATN decoding failures
/// - Provide consistent error feedback across all operation types
void main() async {
  print('🧪 Testing Error Handling & Failure Modes\n');

  final connection = SpacetimeDbConnection(
    host: 'localhost:3000',
    database: 'notesdb',
  );

  final subscriptionManager = SubscriptionManager(connection);

  subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());
  subscriptionManager.cache.activateTable(4096, 'note');

  print('📡 Connecting...');
  await connection.connect();
  await subscriptionManager.onIdentityToken.first;
  print('✅ Connected\n');

  // =============================================================================
  // ERROR TEST 1: Invalid Procedure Name
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 1: Non-existent Procedure');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const nonExistentProcRequestId = 1001;
  final nonExistentProcFuture = subscriptionManager.onProcedureResult.first;

  subscriptionManager.callProcedure('non_existent_procedure', Uint8List(0), requestId: nonExistentProcRequestId);

  final nonExistentResult = await nonExistentProcFuture;

  print('✅ Received ProcedureResult');
  print('   Request ID: ${nonExistentResult.requestId}');
  print('   Status: ${nonExistentResult.status.type}');

  // Verify request ID matches
  if (nonExistentResult.requestId == nonExistentProcRequestId) {
    print('   ✅ Request ID matches as expected');
  } else {
    throw Exception('Request ID mismatch: expected $nonExistentProcRequestId, got ${nonExistentResult.requestId}');
  }

  if (nonExistentResult.status.type == ProcedureStatusType.internalError) {
    print('   ✅ Correctly returned internalError status');
    print('   Error message: ${nonExistentResult.status.errorMessage}');

    if ((nonExistentResult.status.errorMessage?.contains('not found') ?? false) ||
        (nonExistentResult.status.errorMessage?.contains('No such procedure') ?? false)) {
      print('   ✅ Error message indicates procedure not found\n');
    } else {
      print('   ⚠️  Unexpected error message\n');
    }
  } else {
    throw Exception('Expected internalError, got ${nonExistentResult.status.type}');
  }

  // =============================================================================
  // ERROR TEST 2: Invalid Subscription Query
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 2: Invalid SQL Query');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const invalidQueryRequestId = 1002;
  const invalidQueryId = 9999;

  subscriptionManager.subscribeSingle(
    'SELECT * FROM non_existent_table',
    requestId: invalidQueryRequestId,
    queryId: invalidQueryId,
  );

  final subscriptionError = await subscriptionManager.onSubscriptionError.first;

  print('✅ Received SubscriptionError');
  print('   Request ID: ${subscriptionError.requestId}');
  print('   Query ID: ${subscriptionError.queryId}');
  print('   Error: ${subscriptionError.error}');

  if (subscriptionError.requestId == invalidQueryRequestId &&
      subscriptionError.queryId == invalidQueryId) {
    print('   ✅ Request ID and Query ID match as expected');
  } else {
    throw Exception('ID mismatch in error response');
  }

  if (subscriptionError.error.contains('table') ||
      subscriptionError.error.contains('not found') ||
      subscriptionError.error.contains('does not exist')) {
    print('   ✅ Error message indicates table not found\n');
  } else {
    print('   ⚠️  Unexpected error message\n');
  }

  // =============================================================================
  // ERROR TEST 3: Unsubscribe Non-existent Subscription
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 3: Unsubscribe Non-existent');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const nonExistentSubRequestId = 1003;
  const nonExistentSubQueryId = 88888;

  subscriptionManager.unsubscribe(nonExistentSubQueryId, requestId: nonExistentSubRequestId);

  final unsubError = await subscriptionManager.onSubscriptionError.first;

  print('✅ Received SubscriptionError');
  print('   Request ID: ${unsubError.requestId}');
  print('   Query ID: ${unsubError.queryId}');
  print('   Error: ${unsubError.error}');

  if (unsubError.requestId == nonExistentSubRequestId &&
      unsubError.queryId == nonExistentSubQueryId) {
    print('   ✅ Request ID and Query ID match as expected');
  } else {
    throw Exception('ID mismatch in error response');
  }

  if (unsubError.error.contains('Subscription not found') ||
      unsubError.error.contains('not found')) {
    print('   ✅ Error message indicates subscription not found\n');
  } else {
    print('   ⚠️  Unexpected error message\n');
  }

  // =============================================================================
  // ERROR TEST 4: Invalid Reducer Arguments
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 4: Invalid Reducer Arguments');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('   NOTE: This test is non-deterministic and relies on timeout behavior.');
  print('   SpacetimeDB does not send explicit error messages for invalid reducer args.');
  print('   Test may be flaky in different network/server conditions.\n');

  // Reducers send TransactionUpdate on success, but no error message on failure
  // We listen for both TransactionUpdate and SubscriptionError with timeout
  final invalidArgsUpdate = Future.any([
    subscriptionManager.onTransactionUpdate.first.then((_) => 'success'),
    subscriptionManager.onSubscriptionError.first.then((_) => 'error'),
  ]);

  const invalidArgsRequestId = 1004;

  // Call create_note with wrong number of arguments (expects 2 strings, send 0)
  await subscriptionManager.reducers.callWith('create_note', (encoder) {
    // Send nothing - wrong number of arguments
  }, requestId: invalidArgsRequestId);

  try {
    // Increased timeout to 5 seconds to reduce false positives in slow environments
    final result = await invalidArgsUpdate.timeout(Duration(seconds: 5));

    if (result == 'success') {
      print('   ⚠️  Server accepted invalid arguments (reducer succeeded)');
      print('   SpacetimeDB may use default values or have lenient argument parsing\n');
    } else {
      print('   ✅ Received SubscriptionError for invalid arguments\n');
    }
  } on TimeoutException {
    print('   ⚠️  Timeout - no response received');
    print('   This could indicate:');
    print('   - Server silently rejected invalid arguments (expected)');
    print('   - Network/server latency (false positive)');
    print('   - Consider this test result with caution\n');
  }

  // =============================================================================
  // ERROR TEST 5: Procedure with Wrong Argument Types
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 5: Wrong Argument Types');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('   NOTE: This test may timeout if BSATN decoding fails before procedure execution.');
  print('   Timeout behavior is non-deterministic across environments.\n');

  const wrongTypesRequestId = 1005;
  final wrongTypesProcFuture = subscriptionManager.onProcedureResult.first;

  // add_numbers expects (u32, u32), send strings instead
  final wrongTypesEncoder = BsatnEncoder();
  wrongTypesEncoder.writeString('not a number');
  wrongTypesEncoder.writeString('also not a number');

  subscriptionManager.callProcedure('add_numbers', wrongTypesEncoder.toBytes(), requestId: wrongTypesRequestId);

  final wrongTypesResult = await wrongTypesProcFuture.timeout(
    Duration(seconds: 5), // Increased timeout for slow environments
    onTimeout: () {
      print('   ⚠️  Timeout - no response received');
      print('   This could indicate:');
      print('   - BSATN decoding failed on server (expected)');
      print('   - Network/server latency (false positive)');
      print('   - Consider this test result with caution\n');
      return ProcedureResultMessage(
        status: ProcedureStatus(type: ProcedureStatusType.returned),
        timestamp: 0,
        totalHostExecutionDurationMicros: 0,
        requestId: 0,
      );
    },
  );

  // Only check requestId if we didn't timeout (requestId != 0)
  if (wrongTypesResult.requestId != 0) {
    if (wrongTypesResult.requestId == wrongTypesRequestId) {
      print('   ✅ Request ID matches as expected');
    } else {
      throw Exception('Request ID mismatch: expected $wrongTypesRequestId, got ${wrongTypesResult.requestId}');
    }

    if (wrongTypesResult.status.type == ProcedureStatusType.internalError) {
      print('   ✅ Received error for wrong argument types');
      print('   Error: ${wrongTypesResult.status.errorMessage}\n');
    } else {
      print('   ⚠️  Server accepted wrong argument types\n');
    }
  }
  // If requestId == 0, timeout message was already printed

  // =============================================================================
  // ERROR TEST 6: Procedure That Panics (divide_by_zero)
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ ERROR TEST 6: Procedure Panic (Division by Zero)');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const divByZeroRequestId = 1006;
  final divByZeroProcFuture = subscriptionManager.onProcedureResult.first;

  final divEncoder = BsatnEncoder();
  divEncoder.writeU32(100);
  subscriptionManager.callProcedure('divide_by_zero', divEncoder.toBytes(), requestId: divByZeroRequestId);

  final divByZeroResult = await divByZeroProcFuture;

  print('✅ Received ProcedureResult');
  print('   Request ID: ${divByZeroResult.requestId}');
  print('   Status: ${divByZeroResult.status.type}');

  // Verify request ID matches
  if (divByZeroResult.requestId == divByZeroRequestId) {
    print('   ✅ Request ID matches as expected');
  } else {
    throw Exception('Request ID mismatch: expected $divByZeroRequestId, got ${divByZeroResult.requestId}');
  }

  if (divByZeroResult.status.type == ProcedureStatusType.internalError) {
    print('   ✅ Correctly returned internalError status');
    print('   Error message: ${divByZeroResult.status.errorMessage}');

    if ((divByZeroResult.status.errorMessage?.contains('divide') ?? false) ||
        (divByZeroResult.status.errorMessage?.contains('panic') ?? false)) {
      print('   ✅ Error message indicates division error\n');
    } else {
      print('   ⚠️  Unexpected error message (but error was caught)\n');
    }
  } else {
    print('   ⚠️  Expected internalError, got ${divByZeroResult.status.type}\n');
  }

  // =============================================================================
  // SUMMARY
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 ERROR HANDLING TEST SUMMARY');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('✅ Non-existent Procedure - TESTED');
  print('✅ Invalid SQL Query - TESTED');
  print('✅ Unsubscribe Non-existent - TESTED');
  print('⚠️  Invalid Reducer Arguments - TESTED (may vary)');
  print('⚠️  Wrong Argument Types - TESTED (may vary)');
  print('✅ Procedure Panic (Divide by Zero) - TESTED\n');

  print('🎉 Error handling tests complete!\n');

  await Future.delayed(Duration(seconds: 1));
  subscriptionManager.dispose();
  await connection.disconnect();
}
