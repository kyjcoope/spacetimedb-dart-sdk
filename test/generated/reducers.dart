// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'reducer_args.dart';

class Reducers {
  final SpacetimeDbConnection _connection;
  final ReducerEmitter _reducerEmitter;

  Reducers(this._connection, this._reducerEmitter);

  Future<void> createNote({
    required String title,
    required String content,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(title);
    encoder.writeString(content);

    await _connection.callReducer('create_note', encoder.toBytes());
  }

  Future<void> deleteNote({
    required int noteId,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU32(noteId);

    await _connection.callReducer('delete_note', encoder.toBytes());
  }

  Future<void> init() async {
    final encoder = BsatnEncoder();

    await _connection.callReducer('init', encoder.toBytes());
  }

  Future<void> updateNote({
    required int noteId,
    required String title,
    required String content,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU32(noteId);
    encoder.writeString(title);
    encoder.writeString(content);

    await _connection.callReducer('update_note', encoder.toBytes());
  }

  StreamSubscription<void> onCreateNote(void Function(EventContext ctx, String title, String content) callback) {
    return _reducerEmitter.on('create_note').listen((EventContext ctx) {
      // Pattern match to extract ReducerEvent
      final event = ctx.event;
      if (event is! ReducerEvent) return;

      // Type guard - ensures args is correct type
      final args = event.reducerArgs;
      if (args is! CreateNoteArgs) return;

      // Extract fields from strongly-typed object - NO CASTING
      callback(ctx, args.title, args.content);
    });
  }

  StreamSubscription<void> onDeleteNote(void Function(EventContext ctx, int noteId) callback) {
    return _reducerEmitter.on('delete_note').listen((EventContext ctx) {
      // Pattern match to extract ReducerEvent
      final event = ctx.event;
      if (event is! ReducerEvent) return;

      // Type guard - ensures args is correct type
      final args = event.reducerArgs;
      if (args is! DeleteNoteArgs) return;

      // Extract fields from strongly-typed object - NO CASTING
      callback(ctx, args.noteId);
    });
  }

  StreamSubscription<void> onInit(void Function(EventContext ctx) callback) {
    return _reducerEmitter.on('init').listen((EventContext ctx) {
      // Pattern match to extract ReducerEvent
      final event = ctx.event;
      if (event is! ReducerEvent) return;

      // Type guard - ensures args is correct type
      final args = event.reducerArgs;
      if (args is! InitArgs) return;

      // Extract fields from strongly-typed object - NO CASTING
      callback(ctx);
    });
  }

  StreamSubscription<void> onUpdateNote(void Function(EventContext ctx, int noteId, String title, String content) callback) {
    return _reducerEmitter.on('update_note').listen((EventContext ctx) {
      // Pattern match to extract ReducerEvent
      final event = ctx.event;
      if (event is! ReducerEvent) return;

      // Type guard - ensures args is correct type
      final args = event.reducerArgs;
      if (args is! UpdateNoteArgs) return;

      // Extract fields from strongly-typed object - NO CASTING
      callback(ctx, args.noteId, args.title, args.content);
    });
  }

}
