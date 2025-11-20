// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

class Note {
  final int id;
  final String title;
  final String content;
  final int timestamp;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.timestamp,
  });

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(id);
    encoder.writeString(title);
    encoder.writeString(content);
    encoder.writeU64(timestamp);
  }

  static Note decodeBsatn(BsatnDecoder decoder) {
    return Note(
      id: decoder.readU32(),
      title: decoder.readString(),
      content: decoder.readString(),
      timestamp: decoder.readU64(),
    );
  }

}

class NoteDecoder implements RowDecoder<Note> {
  @override
  Note decode(BsatnDecoder decoder) {
    return Note.decodeBsatn(decoder);
  }

  @override
  int? getPrimaryKey(Note row) {
    return row.id;
  }
}
