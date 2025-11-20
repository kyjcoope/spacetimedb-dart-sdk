import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'note_decoder.dart';
import 'reducer_arg_decoders.dart';

/// Error handling and failure mode tests for SpacetimeDB Dart SDK
///
/// Before running:
/// 1. spacetime start
/// 2. cd spacetime_test_module && spacetime publish notesdb --server http://localhost:3000
/// 3. dart test test/integration/error_handling_test.dart

void main() {
  late SpacetimeDbConnection connection;
  late SubscriptionManager subManager;

  setUp(() async {
    connection = SpacetimeDbConnection(
      host: 'localhost:3000',
      database: 'notesdb',
    );
    subManager = SubscriptionManager(connection);

    // PHASE 0: Register decoders
    subManager.cache.registerDecoder<Note>('note', NoteDecoder());
    subManager.reducerRegistry.registerDecoder('create_note', CreateNoteArgsDecoder());
    subManager.reducerRegistry.registerDecoder('update_note', UpdateNoteArgsDecoder());
    subManager.reducerRegistry.registerDecoder('delete_note', DeleteNoteArgsDecoder());

    await connection.connect();
    await subManager.onIdentityToken.first.timeout(Duration(seconds: 5));
  });

  tearDown(() async {
    subManager.dispose();
    await connection.disconnect();
  });

  group('Error Handling Tests', () {
    test('Non-existent procedure returns internalError', () async {
      const requestId = 1001;

      // A. PREPARE LISTENER
      final resultFuture = subManager.onProcedureResult
          .firstWhere((msg) => msg.requestId == requestId);

      // B. ACTION
      subManager.callProcedure(
        'non_existent_procedure',
        Uint8List(0),
        requestId: requestId,
      );

      // C. WAIT
      final result = await resultFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(result.requestId, equals(requestId),
          reason: 'Request ID should match');
      expect(result.status.type, equals(ProcedureStatusType.internalError),
          reason: 'Non-existent procedure should return internalError');
      expect(result.status.errorMessage, isNotNull,
          reason: 'Error message should be present');

      final errorMsg = result.status.errorMessage!.toLowerCase();
      expect(
        errorMsg.contains('not found') || errorMsg.contains('no such procedure'),
        isTrue,
        reason: 'Error message should indicate procedure not found',
      );
    });

    test('Invalid SQL query returns SubscriptionError', () async {
      const requestId = 1002;
      const queryId = 9999;

      // A. PREPARE LISTENER
      final errorFuture = subManager.onSubscriptionError
          .firstWhere((err) => err.requestId == requestId);

      // B. ACTION
      subManager.subscribeSingle(
        'SELECT * FROM non_existent_table',
        requestId: requestId,
        queryId: queryId,
      );

      // C. WAIT
      final error = await errorFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(error.requestId, equals(requestId),
          reason: 'Request ID should match');
      expect(error.queryId, equals(queryId),
          reason: 'Query ID should match');
      expect(error.error, isNotEmpty,
          reason: 'Error message should not be empty');

      final errorMsg = error.error.toLowerCase();
      expect(
        errorMsg.contains('table') ||
            errorMsg.contains('not found') ||
            errorMsg.contains('does not exist'),
        isTrue,
        reason: 'Error should indicate table not found',
      );
    });

    test('Unsubscribe non-existent subscription returns error', () async {
      const requestId = 1003;
      const queryId = 88888;

      // A. PREPARE LISTENER
      final errorFuture = subManager.onSubscriptionError
          .firstWhere((err) => err.requestId == requestId);

      // B. ACTION
      subManager.unsubscribe(queryId, requestId: requestId);

      // C. WAIT
      final error = await errorFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(error.requestId, equals(requestId),
          reason: 'Request ID should match');
      expect(error.queryId, equals(queryId),
          reason: 'Query ID should match');
      expect(error.error, isNotEmpty,
          reason: 'Error message should not be empty');

      final errorMsg = error.error.toLowerCase();
      expect(
        errorMsg.contains('subscription not found') ||
            errorMsg.contains('not found'),
        isTrue,
        reason: 'Error should indicate subscription not found',
      );
    });

    test('Invalid reducer arguments are handled', () async {
      // A. PREPARE LISTENER - just wait for next transaction
      final updateFuture = subManager.onTransactionUpdate.first;

      // B. ACTION - send invalid args (0 arguments instead of 2 strings)
      await subManager.reducers.callWith('create_note', (encoder) {
        // Send nothing - wrong number of arguments
      });

      // C. WAIT
      final update = await updateFuture.timeout(Duration(seconds: 2));

      // D. ASSERT - server accepted with defaults
      expect(update, isA<TransactionUpdateMessage>(),
          reason: 'Server should send TransactionUpdate');
      expect(update.reducerCall.reducerName, equals('create_note'),
          reason: 'Reducer name should match');
    });

    test('Procedure with wrong argument types', () async {
      const requestId = 1005;

      // A. PREPARE LISTENER
      final resultFuture = subManager.onProcedureResult
          .firstWhere((msg) => msg.requestId == requestId);

      // B. ACTION - add_numbers expects (u32, u32), send strings instead
      final encoder = BsatnEncoder();
      encoder.writeString('not a number');
      encoder.writeString('also not a number');

      subManager.callProcedure(
        'add_numbers',
        encoder.toBytes(),
        requestId: requestId,
      );

      // C. WAIT
      final result = await resultFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(result.requestId, equals(requestId),
          reason: 'Request ID should match');
      expect(result.status.type, isA<ProcedureStatusType>(),
          reason: 'Should receive some procedure status');
    });

    test('Procedure panic (divide by zero) returns internalError', () async {
      const requestId = 1006;

      // A. PREPARE LISTENER
      final resultFuture = subManager.onProcedureResult
          .firstWhere((msg) => msg.requestId == requestId);

      // B. ACTION
      final encoder = BsatnEncoder();
      encoder.writeU32(100);

      subManager.callProcedure(
        'divide_by_zero',
        encoder.toBytes(),
        requestId: requestId,
      );

      // C. WAIT
      final result = await resultFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(result.requestId, equals(requestId),
          reason: 'Request ID should match');
      expect(result.status.type, equals(ProcedureStatusType.internalError),
          reason: 'Divide by zero should return internalError');
      expect(result.status.errorMessage, isNotNull,
          reason: 'Error message should be present');

      final errorMsg = result.status.errorMessage!.toLowerCase();
      expect(
        errorMsg.contains('divide') || errorMsg.contains('panic'),
        isTrue,
        reason: 'Error message should indicate division/panic error',
      );
    });
  });
}
