import 'dart:async';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';
import 'note_decoder.dart';

/// Test calling reducers to create and update notes
///
/// Before running:
/// 1. spacetime start
/// 2. cd spacetime_test_module
/// 3. spacetime publish notesdb --server http://localhost:3000 --anonymous
/// 4. dart run test/integration/reducer_test.dart
void main() async {
  print('🧪 Testing Reducer Calls\n');

  final connection = SpacetimeDbConnection(
    host: 'localhost:3000',
    database: 'notesdb',
  );

  final subscriptionManager = SubscriptionManager(connection);

  subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());
  subscriptionManager.cache.activateTable(4096, 'note');

  // Get table by name (type-safe)
  final noteTable = subscriptionManager.cache.getTableByTypedName<Note>('note');

  // Track new notes
  noteTable.insertStream.listen((note) {
    print('✅ New note created: $note');
  });

  // Track transaction updates
  subscriptionManager.onTransactionUpdate.listen((update) {
    print('🔄 Transaction update received!');
  });

  print('📡 Connecting...');
  await connection.connect();

  // Wait for identity
  await subscriptionManager.onIdentityToken.first;
  print('✅ Connected!\n');

  // Subscribe to notes
  subscriptionManager.subscribe(['SELECT * FROM note']);
  await subscriptionManager.onInitialSubscription.first;

  print('📚 Initial notes: ${noteTable.count()}\n');

  // Test: Create a new note
  print('📝 Calling create_note reducer...');
  await subscriptionManager.reducers.callWith('create_note', (encoder) {
    encoder.writeString('Dart SDK Test');
    encoder.writeString('Created via Dart SDK reducer call!');
  });

  // Wait for the transaction update
  print('⏳ Waiting for transaction update...');
  await Future.delayed(Duration(seconds: 2));

  print('\n📚 Notes after create: ${noteTable.count()}');
  for (final note in noteTable.iter()) {
    print('   - $note');
  }

  print('\n🎉 Reducer test complete!');

  await Future.delayed(Duration(seconds: 1));
  subscriptionManager.dispose();
  await connection.disconnect();
}
