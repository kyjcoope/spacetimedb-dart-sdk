import 'dart:typed_data';

import 'package:spacetimedb_dart_sdk/src/codec/bsatn_encoder.dart';
import 'package:spacetimedb_dart_sdk/src/connection/spacetimedb_connection.dart';
import 'package:spacetimedb_dart_sdk/src/messages/client_messages.dart';

class ReducerCaller {
  final SpacetimeDbConnection _connection;
  int _nextRequestId = 1;

  ReducerCaller(this._connection);

  /// Call a reducer with BSATN-encoded arguments
  ///
  /// Example:
  /// ```dart
  /// final encoder = BsatnEncoder();
  /// encoder.writeString("My Note");
  /// encoder.writeString("Note content here");
  /// await reducer.call("create_note", encoder.toBytes());
  /// ```
  Future<void> call(String reducerName, Uint8List args, {int? requestId}) async {
    final message = CallReducerMessage(
      reducerName: reducerName,
      args: args,
      requestId: requestId ?? _nextRequestId++,
    );

    _connection.send(message.encode());
  }

  /// Helper to call reducer with a callback to encode arguments
  ///
  /// Example:
  /// ```dart
  /// await reducer.callWith("create_note", (encoder) {
  ///   encoder.writeString("My Note");
  ///   encoder.writeString("Note content here");
  /// });
  /// ```
  Future<void> callWith(
    String reducerName,
    void Function(BsatnEncoder encoder) encodeArgs, {
    int? requestId,
  }) async {
    final encoder = BsatnEncoder();
    encodeArgs(encoder);
    await call(reducerName, encoder.toBytes(), requestId: requestId);
  }
}
