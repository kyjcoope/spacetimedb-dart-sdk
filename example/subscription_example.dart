import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';

/// Example showing how to use the Subscription Manager
void main() async {
  // 1. Create connection
  final connection = SpacetimeDBConnection(
    host: 'localhost:3000',
    database: 'my_game',
  );

  // 2. Create subscription manager
  final subscriptionManager = SubscriptionManager(connection);

  // 3. Listen for identity token (authentication)
  subscriptionManager.onIdentityToken.listen((message) {
    print('Identity: ${message.identity}');
    print('Token: ${message.token}');
  });

  // 4. Listen for initial subscription data
  subscriptionManager.onInitialSubscription.listen((message) {
    print('Initial data received!');
    print('Request ID: ${message.requestId}');
    print('Execution time: ${message.totalHostExecutionDurationMicros}μs');

    for (final tableUpdate in message.tableUpdates) {
      print('Table: ${tableUpdate.tableName}');
      print('Operations: ${tableUpdate.operations.length}');

      for (final op in tableUpdate.operations) {
        print('  - ${op.type.name}: ${op.rowData.length} bytes');
      }
    }
  });

  // 5. Listen for real-time updates
  subscriptionManager.onTransactionUpdate.listen((message) {
    print('Real-time update!');
    print('Timestamp: ${message.timestamp}');

    for (final tableUpdate in message.tableUpdates) {
      print('Table ${tableUpdate.tableName} changed:');
      for (final op in tableUpdate.operations) {
        print('  - ${op.type.name}');
      }
    }
  });

  // 6. Connect to server
  await connection.connect();
  print('Connected to SpacetimeDB!');

  // 7. Subscribe to tables
  await subscriptionManager.subscribe([
    'SELECT * FROM Player',
    'SELECT * FROM Inventory',
  ]);
  print('Subscribed to tables!');

  // Keep running to receive updates
  await Future.delayed(Duration(seconds: 60));

  // Cleanup
  subscriptionManager.dispose();
  await connection.disconnect();
}
