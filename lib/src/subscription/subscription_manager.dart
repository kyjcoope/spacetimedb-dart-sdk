import 'dart:async';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:spacetimedb_dart_sdk/src/cache/client_cache.dart';
import 'package:spacetimedb_dart_sdk/src/utils/custom_log_printer.dart';

import '../connection/spacetimedb_connection.dart';
import '../messages/message_decoder.dart';
import '../messages/server_messages.dart';
import '../messages/client_messages.dart';
import '../reducers/reducer_caller.dart';
import '../reducers/reducer_registry.dart';
import '../reducers/reducer_emitter.dart';
import '../reducers/transaction_result.dart';
import '../events/event.dart';
import '../events/event_context.dart';
import '../auth/identity.dart';

/// Manages table subscriptions and processes real-time updates from SpacetimeDB
///
/// The SubscriptionManager handles:
/// - SQL subscription management (subscribe/unsubscribe)
/// - Real-time database updates via WebSocket
/// - Client-side caching of subscribed data
/// - Reducer and procedure calls
///
/// Example:
/// ```dart
/// final connection = SpacetimeDbConnection(
///   host: 'localhost:3000',
///   database: 'mydb',
/// );
///
/// final subscriptionManager = SubscriptionManager(connection);
///
/// // Register table decoder
/// subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());
///
/// await connection.connect();
///
/// // Subscribe to updates (this activates the table)
/// await subscriptionManager.subscribe(['SELECT * FROM note']);
///
/// // Listen for initial data
/// await subscriptionManager.onInitialSubscription.first;
///
/// // Access cached data
/// final noteTable = subscriptionManager.cache.getTable<Note>(4096);
/// for (final note in noteTable.iter()) {
///   print(note.title);
/// }
///
/// // Call a reducer
/// await subscriptionManager.reducers.callWith('create_note', (encoder) {
///   encoder.writeString('My Note');
///   encoder.writeString('Content here');
/// });
/// ```
class SubscriptionManager {
  final SpacetimeDbConnection _connection;
  final ClientCache cache = ClientCache();
  late final ReducerCaller reducers;
  final ReducerRegistry reducerRegistry = ReducerRegistry();
  final ReducerEmitter reducerEmitter = ReducerEmitter();
  final Logger _logger = Logger(printer: CustomLogPrinter());

  // Identity and connection info
  Identity? _identity;
  String? _address;

  // Track table names from pending subscriptions
  // Used to activate empty tables that don't appear in InitialSubscription
  List<String> _pendingTableNames = [];

  final _initialSubscriptionController =
      StreamController<InitialSubscriptionMessage>.broadcast();
  final _transactionUpdateController =
      StreamController<TransactionUpdateMessage>.broadcast();
  final _transactionUpdateLightController =
      StreamController<TransactionUpdateLightMessage>.broadcast();
  final _identityTokenController =
      StreamController<IdentityTokenMessage>.broadcast();
  final _oneOffQueryResponseController =
      StreamController<OneOffQueryResponse>.broadcast();
  final _subscribeAppliedController =
      StreamController<SubscribeApplied>.broadcast();
  final _unsubscribeAppliedController =
      StreamController<UnsubscribeApplied>.broadcast();
  final _subscriptionErrorController =
      StreamController<SubscriptionErrorMessage>.broadcast();
  final _subscribeMultiAppliedController =
      StreamController<SubscribeMultiApplied>.broadcast();
  final _unsubscribeMultiAppliedController =
      StreamController<UnsubscribeMultiApplied>.broadcast();
  final _procedureResultController =
      StreamController<ProcedureResultMessage>.broadcast();

  StreamSubscription<Uint8List>? _messageSubscription;
  SubscriptionManager(this._connection) {
    reducers = ReducerCaller(_connection);
    _startListening();
  }

  Stream<InitialSubscriptionMessage> get onInitialSubscription =>
      _initialSubscriptionController.stream;
  Stream<TransactionUpdateMessage> get onTransactionUpdate =>
      _transactionUpdateController.stream;
  Stream<TransactionUpdateLightMessage> get onTransactionUpdateLight =>
      _transactionUpdateLightController.stream;
  Stream<IdentityTokenMessage> get onIdentityToken =>
      _identityTokenController.stream;
  Stream<OneOffQueryResponse> get onOneOffQueryResponse =>
      _oneOffQueryResponseController.stream;
  Stream<SubscribeApplied> get onSubscribeApplied =>
      _subscribeAppliedController.stream;
  Stream<UnsubscribeApplied> get onUnsubscribeApplied =>
      _unsubscribeAppliedController.stream;
  Stream<SubscriptionErrorMessage> get onSubscriptionError =>
      _subscriptionErrorController.stream;
  Stream<SubscribeMultiApplied> get onSubscribeMultiApplied =>
      _subscribeMultiAppliedController.stream;
  Stream<UnsubscribeMultiApplied> get onUnsubscribeMultiApplied =>
      _unsubscribeMultiAppliedController.stream;
  Stream<ProcedureResultMessage> get onProcedureResult =>
      _procedureResultController.stream;

  /// Current user identity (32-byte public key hash)
  ///
  /// Available after connection is established and IdentityToken message is received.
  /// Use `identity?.toHexString` for ownership checks or `identity?.toAbbreviated` for UI display.
  Identity? get identity => _identity;

  /// Current connection address (16-byte connection ID as hex string)
  ///
  /// Available after connection is established and IdentityToken message is received.
  String? get address => _address;

  void _startListening() {
    _messageSubscription = _connection.onMessage.listen(_handleMessage);
  }

  /// Handle incoming binary messages
  void _handleMessage(Uint8List bytes) {
    try {
      final message = MessageDecoder.decode(bytes);
      _routeMessage(message);
    } catch (e) {
      _logger.e('Error decoding message: $e');
    }
  }

  /// Route decoded messages to appropriate streams
  void _routeMessage(ServerMessage message) {
    switch (message) {
      case IdentityTokenMessage():
        // Store identity and address for public access
        _identity = Identity(message.identity);
        _address = message.connectionId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        _identityTokenController.add(message);
      case InitialSubscriptionMessage():
        _handleInitialSubscription(message);
        _initialSubscriptionController.add(message);
      case TransactionUpdateMessage():
        _handleTransactionUpdate(message);
        _transactionUpdateController.add(message);
      case TransactionUpdateLightMessage():
        _handleTransactionUpdateLight(message);
        _transactionUpdateLightController.add(message);
      case OneOffQueryResponse():
        _oneOffQueryResponseController.add(message);
      case SubscribeApplied():
        _subscribeAppliedController.add(message);
      case UnsubscribeApplied():
        _unsubscribeAppliedController.add(message);
      case SubscriptionErrorMessage():
        _subscriptionErrorController.add(message);
      case SubscribeMultiApplied():
        _subscribeMultiAppliedController.add(message);
      case UnsubscribeMultiApplied():
        _unsubscribeMultiAppliedController.add(message);
      case ProcedureResultMessage():
        _procedureResultController.add(message);
    }
  }

  void _handleInitialSubscription(InitialSubscriptionMessage message) {
    _logger.i('Handling InitialSubscription with ${message.tableUpdates.length} table updates');

    // Phase 1: Activate all tables that have data (link decoders to runtime IDs)
    for (final tableUpdate in message.tableUpdates) {
      _logger.i('  Activating table "${tableUpdate.tableName}" with ID ${tableUpdate.tableId}');
      cache.activateTable(tableUpdate.tableId, tableUpdate.tableName);
    }

    // Phase 1.5: Activate empty tables that weren't included in tableUpdates
    // The server doesn't include tables with 0 rows in the InitialSubscription
    final activatedTableNames = message.tableUpdates.map((t) => t.tableName).toSet();
    for (final tableName in _pendingTableNames) {
      if (!activatedTableNames.contains(tableName)) {
        // Table was subscribed but has no rows - activate it as empty
        if (cache.activateEmptyTable(tableName)) {
          _logger.i('  Activating empty table "$tableName"');
        }
      }
    }
    // Clear pending table names
    _pendingTableNames = [];

    // Phase 2: Create EventContext with SubscribeAppliedEvent
    final event = SubscribeAppliedEvent();
    final context = EventContext(
      client: null, // Will be set properly by generated client code
      event: event,
    );

    // Phase 3: Process the data with context
    for (final tableUpdate in message.tableUpdates) {
      if (!cache.hasTable(tableUpdate.tableId)) {
        // Table not registered - ignore silently (decoder wasn't registered)
        continue;
      }

      final table = cache.getTable(tableUpdate.tableId);
      _logger.i('  Table ${tableUpdate.tableId} ("${tableUpdate.tableName}"): ${tableUpdate.updates.length} updates');

      for (final update in tableUpdate.updates) {
        final rows = update.update.inserts.getRows();
        _logger.i('    Inserting ${rows.length} rows');
        table.applyInitialData(update.update.inserts, context);
      }
    }
  }

  void _handleTransactionUpdate(TransactionUpdateMessage message) {
    // DUAL DISPATCH: This message serves two purposes:
    // 1. Complete pending reducer Future (if we initiated this call)
    // 2. Update table cache and emit events (always happens)

    // Route to ReducerCaller first (completes Future if request_id matches)
    final result = TransactionResult.fromTransactionUpdate(message);
    reducers.completeRequest(message.reducerCall.requestId, result);

    // Then handle table updates and events
    // Create Event from transaction message
    Event event;

    // Attempt to deserialize reducer arguments
    final reducerArgs = reducerRegistry.deserializeArgs(
      message.reducerCall.reducerName,
      message.reducerCall.args,
    );

    if (reducerArgs != null) {
      // Successfully deserialized - create ReducerEvent
      event = ReducerEvent(
        timestamp: message.timestamp,
        status: message.status,
        callerIdentity: message.callerIdentity,
        callerConnectionId: message.callerConnectionId,
        energyConsumed: message.energyQuantaUsed,
        reducerName: message.reducerCall.reducerName,
        reducerArgs: reducerArgs,
      );

      _logger.i('Transaction caused by reducer: ${message.reducerCall.reducerName}');
      _logger.i('Arguments: $reducerArgs');
      _logger.i('Status: ${message.status}');
    } else {
      // Deserialization failed - unknown reducer or corrupt data
      event = UnknownTransactionEvent();
      _logger.i('Failed to deserialize reducer args for: ${message.reducerCall.reducerName}');
    }

    // 3. Create EventContext
    // Note: Client reference will be wired up properly in Phase 5 (code generation)
    // For now, we use a placeholder that will be replaced by generated code
    final context = EventContext(
      client: null, // Will be set properly by generated client code
      event: event,
    );

    // 4. Emit reducer completion event (Phase 4)
    if (event is ReducerEvent) {
      reducerEmitter.emit(event.reducerName, context);
      _logger.i('Emitted reducer completion event for: ${event.reducerName}');
    }

    // 5. Apply table updates with context
    for (final tableUpdate in message.tableUpdates) {
      // Try to link table ID (handles empty tables that were activated by name)
      final table = cache.linkTableId(tableUpdate.tableId, tableUpdate.tableName);
      if (table == null) continue;

      for (final update in tableUpdate.updates) {
        table.applyTransactionUpdate(
          update.update.deletes,
          update.update.inserts,
          context, // Pass context to table cache
        );
      }
    }
  }

  void _handleTransactionUpdateLight(TransactionUpdateLightMessage message) {
    // DUAL DISPATCH: Handle both reducer completion and table updates

    // Route to ReducerCaller first (completes Future if request_id matches)
    final result = TransactionResult.fromTransactionUpdateLight(message);
    reducers.completeRequest(message.requestId, result);

    // Then handle table updates
    // Light messages don't include reducer info, so create UnknownTransactionEvent
    final event = UnknownTransactionEvent();
    final context = EventContext(
      client: null, // Will be set properly by generated client code
      event: event,
    );

    // 3. Apply table updates
    for (final tableUpdate in message.tableUpdates) {
      // Try to link table ID (handles empty tables that were activated by name)
      final table = cache.linkTableId(tableUpdate.tableId, tableUpdate.tableName);
      if (table == null) continue;

      for (final update in tableUpdate.updates) {
        table.applyTransactionUpdate(
          update.update.deletes,
          update.update.inserts,
          context,
        );
      }
    }
  }

  /// Subscribes to tables using SQL queries
  ///
  /// Returns a Future that completes when the initial subscription data
  /// has been received and cached. This ensures data is available
  /// immediately after the Future completes.
  ///
  /// Example:
  /// ```dart
  /// await subscriptionManager.subscribe(['SELECT * FROM note', 'SELECT * FROM user']);
  /// // Data is now available in cache
  /// ```
  Future<void> subscribe(List<String> queries) async {
    // Extract table names from queries for activation tracking
    _pendingTableNames = _extractTableNames(queries);

    final message = SubscribeMessage(queries);
    _connection.send(message.encode());

    // Wait for the initial subscription data to arrive
    await onInitialSubscription.first;
  }

  /// Extract table names from SQL subscription queries
  ///
  /// Parses simple SELECT statements to find table names.
  /// Supports: "SELECT * FROM tablename" and "SELECT * FROM tablename WHERE ..."
  List<String> _extractTableNames(List<String> queries) {
    final tableNames = <String>[];
    // Regex to find "FROM tablename" (case insensitive)
    final regex = RegExp(r'FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false);

    for (final query in queries) {
      final match = regex.firstMatch(query);
      if (match != null) {
        tableNames.add(match.group(1)!);
      }
    }
    return tableNames;
  }

  /// Subscribes to a single SQL query
  ///
  /// Returns a [SubscribeApplied] message on success.
  ///
  /// Example:
  /// ```dart
  /// subscriptionManager.subscribeSingle('SELECT * FROM note WHERE id > 100', queryId: 1);
  ///
  /// // Listen for confirmation
  /// await subscriptionManager.onSubscribeApplied.first;
  /// ```
  void subscribeSingle(String query, {int requestId = 0, int queryId = 0}) {
    final message =
        SubscribeSingleMessage(query, requestId: requestId, queryId: queryId);
    _connection.send(message.encode());
  }

  /// Subscribes to multiple SQL queries at once
  ///
  /// Returns a [SubscribeMultiApplied] message on success.
  ///
  /// Example:
  /// ```dart
  /// subscriptionManager.subscribeMulti([
  ///   'SELECT * FROM note',
  ///   'SELECT * FROM user WHERE active = true'
  /// ], queryId: 1);
  ///
  /// // Listen for confirmation
  /// await subscriptionManager.onSubscribeMultiApplied.first;
  /// ```
  void subscribeMulti(List<String> queries,
      {int requestId = 0, int queryId = 0}) {
    final message =
        SubscribeMultiMessage(queries, requestId: requestId, queryId: queryId);
    _connection.send(message.encode());
  }

  /// Executes a one-off SQL query without creating a subscription
  ///
  /// Use this for queries that don't need real-time updates.
  /// Results are delivered via [onOneOffQueryResponse] stream.
  ///
  /// Example:
  /// ```dart
  /// final messageId = Uint8List.fromList([1, 2, 3, 4]);
  /// subscriptionManager.oneOffQuery(messageId, 'SELECT COUNT(*) FROM note');
  ///
  /// final response = await subscriptionManager.onOneOffQueryResponse.first;
  /// print('Result: ${response.tables}');
  /// ```
  void oneOffQuery(Uint8List messageId, String query) {
    final message = OneOffQueryMessage(
      messageId: messageId,
      queryString: query,
    );
    _connection.send(message.encode());
  }

  /// Unsubscribes from a query by its queryId
  ///
  /// Stops receiving real-time updates for the specified query.
  ///
  /// Example:
  /// ```dart
  /// subscriptionManager.unsubscribe(1);
  ///
  /// // Listen for confirmation
  /// await subscriptionManager.onUnsubscribeApplied.first;
  /// ```
  void unsubscribe(int queryId, {int requestId = 0}) {
    final message = UnsubscribeMessage(
      queryId: queryId,
      requestId: requestId,
    );
    _connection.send(message.encode());
  }

  /// Unsubscribes from multiple queries
  ///
  /// Returns a [UnsubscribeMultiApplied] message on success.
  ///
  /// Example:
  /// ```dart
  /// subscriptionManager.unsubscribeMulti(1);
  ///
  /// // Listen for confirmation
  /// await subscriptionManager.onUnsubscribeMultiApplied.first;
  /// ```
  void unsubscribeMulti(int queryId, {int requestId = 0}) {
    final message = UnsubscribeMultiMessage(
      queryId: queryId,
      requestId: requestId,
    );
    _connection.send(message.encode());
  }

  /// Calls a read-only procedure on the server
  ///
  /// Procedures are read-only operations that don't modify database state.
  /// For state-modifying operations, use [reducers] instead.
  ///
  /// Returns a [ProcedureResultMessage] with the result.
  ///
  /// Example:
  /// ```dart
  /// final encoder = BsatnEncoder();
  /// encoder.writeU32(10);
  /// encoder.writeU32(20);
  ///
  /// subscriptionManager.callProcedure('add_numbers', encoder.toBytes());
  ///
  /// final result = await subscriptionManager.onProcedureResult.first;
  /// if (result.status.type == ProcedureStatusType.returned) {
  ///   print('Success!');
  /// }
  /// ```
  void callProcedure(String procedureName, Uint8List args,
      {int requestId = 0}) {
    final message = CallProcedureMessage(
      procedureName: procedureName,
      args: args,
      requestId: requestId,
    );
    _connection.send(message.encode());
  }

  /// Disposes all resources and closes all streams
  ///
  /// Call this when you're done with the SubscriptionManager to clean up resources.
  ///
  /// Example:
  /// ```dart
  /// subscriptionManager.dispose();
  /// await connection.disconnect();
  /// ```
  void dispose() {
    _messageSubscription?.cancel();
    _initialSubscriptionController.close();
    _transactionUpdateController.close();
    _transactionUpdateLightController.close();
    _identityTokenController.close();
    _oneOffQueryResponseController.close();
    _subscribeAppliedController.close();
    _unsubscribeAppliedController.close();
    _subscriptionErrorController.close();
    _subscribeMultiAppliedController.close();
    _unsubscribeMultiAppliedController.close();
    _procedureResultController.close();
    reducerEmitter.dispose(); // Clean up reducer event listeners
  }
}
