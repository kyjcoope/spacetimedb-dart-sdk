// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';

import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'reducers.dart';
import 'note.dart';

class SpacetimeDbClient {
  final SpacetimeDbConnection connection;
  final SubscriptionManager subscriptions;
  late final Reducers reducers;

  TableCache<Note> get note {
    return subscriptions.cache.getTableByTypedName<Note>('note');
  }

  TableCache<Note> get allNotes {
    return subscriptions.cache.getTableByTypedName<Note>('all_notes');
  }

  Note? get firstNote {
    final cache = subscriptions.cache.getTableByTypedName<Note>('first_note');
    final rows = cache.iter().toList();
    return rows.isEmpty ? null : rows.first;
  }

  SpacetimeDbClient._({
    required this.connection,
    required this.subscriptions,
  }) {
    reducers = Reducers(connection);
  }

  static Future<SpacetimeDbClient> connect({
    required String host,
    required String database,
    String? authToken,
    List<String>? initialSubscriptions,
    Duration subscriptionTimeout = const Duration(seconds: 10),
  }) async {
    final connection = SpacetimeDbConnection(
      host: host,
      database: database,
      authToken: authToken,
    );

    final subscriptionManager = SubscriptionManager(connection);

    // Auto-register table decoders
    subscriptionManager.cache.registerDecoder<Note>('note', NoteDecoder());

    // Auto-register view decoders
    subscriptionManager.cache.registerDecoder<Note>('all_notes', NoteDecoder());
    subscriptionManager.cache.registerDecoder<Note>('first_note', NoteDecoder());

    final client = SpacetimeDbClient._(
      connection: connection,
      subscriptions: subscriptionManager,
    );

    await connection.connect();

    if (initialSubscriptions != null && initialSubscriptions.isNotEmpty) {
      try {
        // Wait for initial subscription data to load with timeout
        await subscriptionManager.subscribe(initialSubscriptions).timeout(subscriptionTimeout);
      } on TimeoutException {
        // Log warning and continue - client is still usable with partial data
        print('Warning: Initial subscriptions timed out after ${subscriptionTimeout.inSeconds}s. Data may be incomplete.');
      }
    }

    return client;
  }

  Future<void> disconnect() async {
    await connection.disconnect();
  }
}
