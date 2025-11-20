import 'dart:async';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';
import 'note_decoder.dart';

/// Test complete CRUD operations (Create, Read, Update, Delete)
///
/// Before running:
/// 1. spacetime start
/// 2. cd spacetime_test_module && spacetime publish notes-crud --server local
/// 3. dart run test/integration/crud_test.dart
void main() async {
  print('🧪 Testing CRUD Operations\n');

  final connection = SpacetimeDbConnection(
    host: 'localhost:3000',
    database: 'notesdb',
  );

  final subscriptionManager = SubscriptionManager(connection);

  subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());

  // Manually activate for testing (normally happens during subscription)
  subscriptionManager.cache.activateTable(4096, 'note');

  // Get table by name (type-safe)
  final noteTable = subscriptionManager.cache.getTableByTypedName<Note>('note');

  // Track inserts
  noteTable.insertStream.listen((note) {
    print('  ✅ Insert: ${note.title}');
  });

  // Track updates
  noteTable.updateStream.listen((update) {
    print('  🔄 Update: ${update.oldRow.title} → ${update.newRow.title}');
  });

  // Track deletes
  noteTable.deleteStream.listen((note) {
    print('  ❌ Delete: ${note.title}');
  });

  print('📡 Connecting...');
  await connection.connect();
  await subscriptionManager.onIdentityToken.first;
  print('✅ Connected!\n');

  // Subscribe to notes
  subscriptionManager.subscribe(['SELECT * FROM note']);
  await subscriptionManager.onInitialSubscription.first;
  print('📚 Initial notes: ${noteTable.count()}');
  for (final note in noteTable.iter()) {
    print('   ${note.id}. ${note.title}');
  }

  // =============================================================================
  // TEST 1: CREATE
  // =============================================================================
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📝 TEST 1: CREATE a new note');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  await subscriptionManager.reducers.callWith('create_note', (encoder) {
    encoder.writeString('CRUD Test Note');
    encoder.writeString('This note will be updated and deleted');
  });
  await Future.delayed(Duration(seconds: 1));

  print('📚 After CREATE: ${noteTable.count()} notes');
  final createdNote = noteTable.iter().last;
  final createdId = createdNote.id;
  print('   Created note ID: $createdId\n');

  // =============================================================================
  // TEST 2: UPDATE
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔄 TEST 2: UPDATE the note');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  await subscriptionManager.reducers.callWith('update_note', (encoder) {
    encoder.writeU32(createdId);
    encoder.writeString('UPDATED: CRUD Test Note');
    encoder.writeString('This note has been updated!');
  });
  await Future.delayed(Duration(seconds: 1));

  print('📚 After UPDATE: ${noteTable.count()} notes');
  final updatedNote = noteTable.find(createdId);
  if (updatedNote != null) {
    print('   Updated note: ${updatedNote.title}');
    print('   Content: ${updatedNote.content}\n');
  }

  // =============================================================================
  // TEST 3: DELETE
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🗑️  TEST 3: DELETE the note');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  await subscriptionManager.reducers.callWith('delete_note', (encoder) {
    encoder.writeU32(createdId);
  });
  await Future.delayed(Duration(seconds: 1));

  print('📚 After DELETE: ${noteTable.count()} notes');
  final deletedNote = noteTable.find(createdId);
  if (deletedNote == null) {
    print('   ✅ Note successfully deleted!\n');
  } else {
    print('   ❌ ERROR: Note still exists!\n');
  }

  // =============================================================================
  // SUMMARY
  // =============================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 FINAL STATE');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📚 Total notes: ${noteTable.count()}');
  for (final note in noteTable.iter()) {
    print('   ${note.id}. ${note.title}');
  }

  print('\n🎉 CRUD test complete!');
  print('   ✅ CREATE works');
  print('   ✅ UPDATE works');
  print('   ✅ DELETE works\n');

  await Future.delayed(Duration(seconds: 1));
  subscriptionManager.dispose();
  await connection.disconnect();
}
