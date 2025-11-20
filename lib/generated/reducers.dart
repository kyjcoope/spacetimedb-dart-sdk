// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

class Reducers {
  final SpacetimeDbConnection _connection;

  Reducers(this._connection);

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

}
