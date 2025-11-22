import 'dart:async';
import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/subscription/subscription_manager.dart';
import '../generated/note.dart';
import '../generated/reducer_args.dart';
import '../helpers/integration_test_helper.dart';

@Tags(['integration'])

void main() {
  setUpAll(ensureTestEnvironment);

  test('Multi-delete in single transaction emits multiple delete events', () async {
    final connection = SpacetimeDbConnection(
      host: 'localhost:3000',
      database: 'notesdb',
    );

    final subManager = SubscriptionManager(connection);

    // 1. Register Table Decoder
    subManager.cache.registerDecoder<Note>('note', NoteDecoder());

    // 2. Register Reducer Argument Decoders
    subManager.reducerRegistry.registerDecoder('create_note', CreateNoteArgsDecoder());
    subManager.reducerRegistry.registerDecoder('delete_all_notes', DeleteAllNotesArgsDecoder());

    print('📡 Connecting...');
    await connection.connect();

    // 3. Subscribe and Wait for the "Synced" state
    subManager.subscribe(['SELECT * FROM note']);
    await subManager.onInitialSubscription.first;

    final noteTable = subManager.cache.getTableByTypedName<Note>('note');
    final initialCount = noteTable.count();
    print('✅ Connected & Subscribed. Initial count: $initialCount');

    // =========================================================================
    // SETUP: Create multiple notes to delete
    // =========================================================================
    const notesToCreate = 5;
    final createdNotes = <Note>[];

    for (var i = 0; i < notesToCreate; i++) {
      final uniqueTitle = 'MultiDeleteTest-${DateTime.now().millisecondsSinceEpoch}-$i';

      final insertFuture = noteTable.insertStream.first;

      await subManager.reducers.callWith('create_note', (encoder) {
        encoder.writeString(uniqueTitle);
        encoder.writeString('Content $i');
      });

      final note = await insertFuture.timeout(const Duration(seconds: 5));
      createdNotes.add(note);
      print('   Created note ${note.id}: ${note.title}');
    }

    final countAfterInserts = noteTable.count();
    print('📝 Created $notesToCreate notes. Total count: $countAfterInserts');
    expect(createdNotes.length, equals(notesToCreate));

    // =========================================================================
    // TEST: Delete all notes and verify deleteStream fires for each
    // =========================================================================
    final deletedNotes = <Note>[];
    final deleteCompleter = Completer<void>();

    // Subscribe to delete stream BEFORE calling reducer
    final deleteSubscription = noteTable.deleteStream.listen((note) {
      deletedNotes.add(note);
      print('   📡 Delete event received for note ${note.id}: ${note.title}');

      // Complete when we've received delete events for all notes in table
      // (both initial notes from init + our created notes)
      if (deletedNotes.length >= countAfterInserts) {
        deleteCompleter.complete();
      }
    });

    print('🗑️  Action: Delete All Notes');
    await subManager.reducers.callWith('delete_all_notes', (encoder) {
      // No arguments
    });

    // Wait for all delete events (with timeout)
    await deleteCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('⏱️  Timeout! Only received ${deletedNotes.length}/$countAfterInserts delete events');
      },
    );

    await deleteSubscription.cancel();

    // =========================================================================
    // ASSERTIONS
    // =========================================================================
    print('');
    print('📊 Results:');
    print('   Notes in table before delete: $countAfterInserts');
    print('   Delete events received: ${deletedNotes.length}');
    print('   Notes in cache after delete: ${noteTable.count()}');

    // The core assertion: we should receive a delete event for EVERY deleted note
    expect(
      deletedNotes.length,
      equals(countAfterInserts),
      reason: 'deleteStream should fire once for each deleted note in a multi-delete transaction',
    );

    // Cache should be empty after delete_all_notes
    expect(
      noteTable.count(),
      equals(0),
      reason: 'Cache should be empty after deleting all notes',
    );

    // Cleanup
    subManager.dispose();
    await connection.disconnect();

    print('✅ Test passed! All ${deletedNotes.length} delete events were received.');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
