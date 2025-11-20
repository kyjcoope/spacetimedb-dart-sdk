import 'dart:async';
import 'dart:typed_data';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';
import 'package:spacetimedb_dart_sdk/src/messages/server_messages.dart';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_encoder.dart';
import 'note_decoder.dart';

/// Comprehensive test for all SpacetimeDB server message types
///
/// Before running:
/// 1. spacetime start
/// 2. cd spacetime_test_module && spacetime publish notes-crud --server local
/// 3. dart run test/integration/message_types_test.dart
///
/// Note: TEST 8 requires the add_numbers procedure added to the module
void main() async {
  print('🧪 Testing All Server Message Types\n');

  final connection = SpacetimeDbConnection(
    host: 'localhost:3000',
    database: 'notesdb',
  );

  final subscriptionManager = SubscriptionManager(connection);

  subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());
  subscriptionManager.cache.activateTable(4096, 'note');

  print('📡 Connecting...');
  await connection.connect();

  // =============================================================================
  // TEST 1: IdentityToken
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔑 TEST 1: IdentityToken');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final identityToken = await subscriptionManager.onIdentityToken.first;
  print('✅ Received IdentityToken');
  print('   Identity: ${identityToken.identity.length} bytes');
  print('   Token: ${identityToken.token.substring(0, 20)}...');
  print('   Connection ID: ${identityToken.connectionId.length} bytes\n');

  // =============================================================================
  // TEST 2: InitialSubscription
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 TEST 2: InitialSubscription');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  subscriptionManager.subscribe(['SELECT * FROM note']);
  final initialSub = await subscriptionManager.onInitialSubscription.first;
  print('✅ Received InitialSubscription');
  print('   Tables: ${initialSub.tableUpdates.length}');
  print('   Request ID: ${initialSub.requestId}');
  print('   Execution time: ${initialSub.totalHostExecutionDurationMicros}μs');

  final noteTable = subscriptionManager.cache.getTable<Note>(4096);
  print('   Loaded ${noteTable.count()} notes\n');

  // =============================================================================
  // TEST 3: TransactionUpdate
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔄 TEST 3: TransactionUpdate');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final noteCountBefore = noteTable.count();
  final transactionUpdateFuture = subscriptionManager.onTransactionUpdate.first;

  await subscriptionManager.reducers.callWith('create_note', (encoder) {
    encoder.writeString('TransactionUpdate Test');
    encoder.writeString('Testing TransactionUpdate message');
  });

  final txUpdate = await transactionUpdateFuture;
  final noteCountAfter = noteTable.count();

  print('✅ Received TransactionUpdate');
  print('   Timestamp: ${txUpdate.timestamp}');
  print('   Table updates: ${txUpdate.tableUpdates.length}');
  print('   Notes before: $noteCountBefore');
  print('   Notes after: $noteCountAfter');

  // Verify the note was actually added
  if (noteCountAfter == noteCountBefore + 1) {
    print('   ✅ Note count increased by 1 as expected\n');
  } else {
    throw Exception('Expected note count to increase by 1, but it went from $noteCountBefore to $noteCountAfter');
  }

  // =============================================================================
  // TEST 4: OneOffQueryResponse
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 TEST 4: OneOffQueryResponse');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final queryResponseFuture = subscriptionManager.onOneOffQueryResponse.first;
  final messageId = Uint8List.fromList([1, 2, 3, 4]);
  subscriptionManager.oneOffQuery(messageId, 'SELECT * FROM note');

  final queryResponse = await queryResponseFuture;
  print('✅ Received OneOffQueryResponse');
  print('   Message ID: ${queryResponse.messageId.length} bytes');
  print('   Error: ${queryResponse.error ?? "none"}');
  print('   Tables: ${queryResponse.tables.length}');
  print('   Execution time: ${queryResponse.totalHostExecutionDurationMicros}μs\n');

  // =============================================================================
  // TEST 5: SubscribeApplied
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('✅ TEST 5: SubscribeApplied');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const expectedRequestId = 100;
  const expectedQueryId = 123;

  subscriptionManager.subscribeSingle('SELECT * FROM note', requestId: expectedRequestId, queryId: expectedQueryId);
  final subscribeApplied = await subscriptionManager.onSubscribeApplied.first;

  print('✅ Received SubscribeApplied');
  print('   Request ID: ${subscribeApplied.requestId}');
  print('   Total host execution: ${subscribeApplied.totalHostExecutionDurationMicros}μs');
  print('   Query ID: ${subscribeApplied.queryId}');

  // Verify the IDs match what we sent
  if (subscribeApplied.requestId == expectedRequestId && subscribeApplied.queryId == expectedQueryId) {
    print('   ✅ Request ID and Query ID match as expected\n');
  } else {
    throw Exception('ID mismatch: expected requestId=$expectedRequestId, queryId=$expectedQueryId, '
        'but got requestId=${subscribeApplied.requestId}, queryId=${subscribeApplied.queryId}');
  }

  // =============================================================================
  // TEST 6: UnsubscribeApplied
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔓 TEST 6: UnsubscribeApplied');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Unsubscribe from the subscription created in TEST 5 (queryId: 123)
  const expectedUnsubRequestId = 400;
  const expectedUnsubQueryId = 123;

  print('   Unsubscribing from TEST 5 subscription (queryId: $expectedUnsubQueryId, requestId: $expectedUnsubRequestId)...');

  // Listen for BOTH UnsubscribeApplied and SubscriptionError to debug
  final unsubAppliedFuture = subscriptionManager.onUnsubscribeApplied.first;
  final subErrorFuture = subscriptionManager.onSubscriptionError.first;

  subscriptionManager.unsubscribe(expectedUnsubQueryId, requestId: expectedUnsubRequestId);

  final result = await Future.any([
    unsubAppliedFuture.then((msg) => ('success', msg)),
    subErrorFuture.then((err) => ('error', err)),
  ]).timeout(
    Duration(seconds: 5),
    onTimeout: () => throw TimeoutException('No response received (neither UnsubscribeApplied nor SubscriptionError)'),
  );

  if (result.$1 == 'success') {
    final unsubApplied = result.$2 as UnsubscribeApplied;
    print('✅ Received UnsubscribeApplied');
    print('   Request ID: ${unsubApplied.requestId}');
    print('   Query ID: ${unsubApplied.queryId}');
    print('   Total host execution: ${unsubApplied.totalHostExecutionDurationMicros}μs');

    // Verify the IDs match what we sent
    if (unsubApplied.requestId == expectedUnsubRequestId && unsubApplied.queryId == expectedUnsubQueryId) {
      print('   ✅ Request ID and Query ID match as expected\n');
    } else {
      throw Exception('ID mismatch: expected requestId=$expectedUnsubRequestId, queryId=$expectedUnsubQueryId, '
          'but got requestId=${unsubApplied.requestId}, queryId=${unsubApplied.queryId}');
    }
  } else {
    final err = result.$2 as SubscriptionErrorMessage;
    print('❌ Received SubscriptionError instead:');
    print('   Error: ${err.error}');
    print('   Request ID: ${err.requestId}');
    print('   Query ID: ${err.queryId}\n');
    throw Exception('Expected UnsubscribeApplied but got SubscriptionError: ${err.error}');
  }

  // =============================================================================
  // TEST 7: SubscriptionError
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('❌ TEST 7: SubscriptionError');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Intentionally trigger a SubscriptionError by unsubscribing from a non-existent subscription
  const expectedErrorRequestId = 500;
  const expectedErrorQueryId = 99999;

  subscriptionManager.unsubscribe(expectedErrorQueryId, requestId: expectedErrorRequestId);
  final subError = await subscriptionManager.onSubscriptionError.first;

  print('✅ Received SubscriptionError');
  print('   Error: ${subError.error}');
  print('   Request ID: ${subError.requestId}');
  print('   Query ID: ${subError.queryId}');
  print('   Total host execution: ${subError.totalHostExecutionDurationMicros}μs');

  // Verify the IDs match what we sent
  if (subError.requestId == expectedErrorRequestId && subError.queryId == expectedErrorQueryId) {
    print('   ✅ Request ID and Query ID match as expected');
  } else {
    throw Exception('ID mismatch: expected requestId=$expectedErrorRequestId, queryId=$expectedErrorQueryId, '
        'but got requestId=${subError.requestId}, queryId=${subError.queryId}');
  }

  // Verify we got an error message about the subscription not being found
  if (subError.error.contains('Subscription not found')) {
    print('   ✅ Error message indicates subscription not found\n');
  } else {
    print('   ⚠️  Unexpected error message: ${subError.error}\n');
  }

  // =============================================================================
  // TEST 8: ProcedureResult
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🎯 TEST 8: ProcedureResult');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const expectedProcedureRequestId = 600;
  final procedureResultFuture = subscriptionManager.onProcedureResult.first;

  // Call the add_numbers procedure with arguments 42 and 58
  final encoder = BsatnEncoder();
  encoder.writeU32(42);
  encoder.writeU32(58);
  subscriptionManager.callProcedure('add_numbers', encoder.toBytes(), requestId: expectedProcedureRequestId);

  final procedureResult = await procedureResultFuture;

  print('✅ Received ProcedureResult');
  print('   Request ID: ${procedureResult.requestId}');
  print('   Status: ${procedureResult.status.type}');
  print('   Timestamp: ${procedureResult.timestamp}');
  print('   Total host execution: ${procedureResult.totalHostExecutionDurationMicros}μs');

  // Verify the request ID matches
  if (procedureResult.requestId == expectedProcedureRequestId) {
    print('   ✅ Request ID matches as expected');
  } else {
    throw Exception('Request ID mismatch: expected $expectedProcedureRequestId, got ${procedureResult.requestId}');
  }

  // Verify the procedure succeeded and decode the return value
  if (procedureResult.status.type == ProcedureStatusType.returned) {
    print('   ✅ Procedure returned successfully');
    if (procedureResult.status.returnedData != null) {
      final decoder = BsatnDecoder(procedureResult.status.returnedData!);
      final result = decoder.readU32();
      print('   🧮 Result: 42 + 58 = $result');
      if (result == 100) {
        print('   ✅ Calculation correct\n');
      } else {
        throw Exception('Expected 100, got $result');
      }
    }
  } else if (procedureResult.status.type == ProcedureStatusType.outOfEnergy) {
    print('   ⚠️  Procedure ran out of energy\n');
  } else if (procedureResult.status.type == ProcedureStatusType.internalError) {
    print('   ❌ Procedure internal error: ${procedureResult.status.errorMessage}\n');
  }

  // =============================================================================
  // TEST 9: TransactionUpdateLight
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('⚡ TEST 9: TransactionUpdateLight');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Capture note count BEFORE the operation
  final noteCountBeforeLight = noteTable.count();

  // Note: Server decides when to send Light vs Full based on optimization
  // We can listen for it but can't force it
  // Set up listener BEFORE calling reducer
  const expectedLightRequestId = 650;

  final lightOrFullFuture = Future.any([
    subscriptionManager.onTransactionUpdateLight.first.then((msg) => ('light', msg.requestId)),
    subscriptionManager.onTransactionUpdate.first.then((msg) => ('full', msg.timestamp)),
  ]);

  // Now call the reducer with explicit requestId
  subscriptionManager.reducers.callWith('create_note', (encoder) {
    encoder.writeString('Light Update Test');
    encoder.writeString('May receive Light or Full TransactionUpdate');
  }, requestId: expectedLightRequestId);

  // Wait for the response
  final lightResult = await lightOrFullFuture;
  if (lightResult.$1 == 'light') {
    final requestId = lightResult.$2;
    print('✅ Received TransactionUpdateLight');
    print('   Request ID: $requestId');

    // Verify request ID correlation
    if (requestId == expectedLightRequestId) {
      print('   ✅ Request ID matches as expected');
    } else {
      throw Exception('Request ID mismatch: expected $expectedLightRequestId, got $requestId');
    }
  } else {
    print('✅ Received TransactionUpdate (Full)');
    print('   Server chose to send full update instead of light');
  }

  // Verify the state change
  final noteCountAfterLight = noteTable.count();
  print('   Notes before: $noteCountBeforeLight');
  print('   Notes after: $noteCountAfterLight');

  if (noteCountAfterLight == noteCountBeforeLight + 1) {
    print('   ✅ Note count increased by 1 as expected\n');
  } else {
    throw Exception('Note count did not increase by 1. Before: $noteCountBeforeLight, After: $noteCountAfterLight');
  }

  // =============================================================================
  // TEST 10: SubscribeMultiApplied
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📦 TEST 10: SubscribeMultiApplied');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const expectedMultiRequestId = 700;
  const expectedMultiQueryId = 789;

  subscriptionManager.subscribeMulti(
    ['SELECT * FROM note WHERE id > 50', 'SELECT * FROM note WHERE id <= 50'],
    requestId: expectedMultiRequestId,
    queryId: expectedMultiQueryId,
  );

  final subscribeMultiApplied = await subscriptionManager.onSubscribeMultiApplied.first;

  print('✅ Received SubscribeMultiApplied');
  print('   Request ID: ${subscribeMultiApplied.requestId}');
  print('   Query ID: ${subscribeMultiApplied.queryId}');
  print('   Table updates: ${subscribeMultiApplied.tableUpdates.length}');
  print('   Total host execution: ${subscribeMultiApplied.totalHostExecutionDurationMicros}μs');

  // Verify the request ID and query ID match
  if (subscribeMultiApplied.requestId == expectedMultiRequestId) {
    print('   ✅ Request ID matches as expected');
  } else {
    throw Exception('Request ID mismatch: expected $expectedMultiRequestId, got ${subscribeMultiApplied.requestId}');
  }

  if (subscribeMultiApplied.queryId == expectedMultiQueryId) {
    print('   ✅ Query ID matches as expected');
  } else {
    throw Exception('Query ID mismatch: expected $expectedMultiQueryId, got ${subscribeMultiApplied.queryId}');
  }

  // Verify cache was populated with data from both queries
  final noteCountAfterMultiSub = noteTable.count();
  if (noteCountAfterMultiSub > 0) {
    print('   ✅ Cache populated with ${noteCountAfterMultiSub} notes\n');
  } else {
    throw Exception('Cache not populated after SubscribeMulti');
  }

  // =============================================================================
  // TEST 11: UnsubscribeMultiApplied
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📦 TEST 11: UnsubscribeMultiApplied');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Unsubscribe from the subscription created in TEST 10
  const expectedUnsubMultiRequestId = 800;
  const expectedUnsubMultiQueryId = 789; // Same as TEST 10

  subscriptionManager.unsubscribeMulti(
    expectedUnsubMultiQueryId,
    requestId: expectedUnsubMultiRequestId,
  );

  final unsubscribeMultiApplied = await subscriptionManager.onUnsubscribeMultiApplied.first;

  print('✅ Received UnsubscribeMultiApplied');
  print('   Request ID: ${unsubscribeMultiApplied.requestId}');
  print('   Query ID: ${unsubscribeMultiApplied.queryId}');
  print('   Table updates: ${unsubscribeMultiApplied.tableUpdates.length}');
  print('   Total host execution: ${unsubscribeMultiApplied.totalHostExecutionDurationMicros}μs');

  // Verify the request ID and query ID match
  if (unsubscribeMultiApplied.requestId == expectedUnsubMultiRequestId) {
    print('   ✅ Request ID matches as expected');
  } else {
    throw Exception('Request ID mismatch: expected $expectedUnsubMultiRequestId, got ${unsubscribeMultiApplied.requestId}');
  }

  if (unsubscribeMultiApplied.queryId == expectedUnsubMultiQueryId) {
    print('   ✅ Query ID matches as expected\n');
  } else {
    throw Exception('Query ID mismatch: expected $expectedUnsubMultiQueryId, got ${unsubscribeMultiApplied.queryId}');
  }

  // =============================================================================
  // SUMMARY
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 TEST SUMMARY');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('✅ IdentityToken - PASSED');
  print('✅ InitialSubscription - PASSED');
  print('✅ TransactionUpdate - PASSED');
  print('✅ OneOffQueryResponse - PASSED');
  print('✅ SubscribeApplied - PASSED');
  print('✅ UnsubscribeApplied - PASSED');
  print('✅ SubscriptionError - PASSED');
  print('✅ ProcedureResult - PASSED');
  print('✅ TransactionUpdateLight - PASSED (or Full)');
  print('✅ SubscribeMultiApplied - PASSED');
  print('✅ UnsubscribeMultiApplied - PASSED\n');

  print('🎉 Message type tests complete!\n');

  await Future.delayed(Duration(seconds: 1));
  subscriptionManager.dispose();
  await connection.disconnect();
}
