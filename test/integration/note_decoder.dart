import 'package:spacetimedb_dart_sdk/src/cache/row_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';

class Note {
  final int id;
  final String title;
  final String content;
  final int timestamp;

  Note(this.id, this.title, this.content, this.timestamp);

  @override
  String toString() =>
      'Note(id: $id, title: "$title", ${content.length} chars)';
}

class NoteDecoder implements RowDecoder<Note> {
  @override
  Note decode(BsatnDecoder decoder) {
    return Note(
      decoder.readU32(),
      decoder.readString(),
      decoder.readString(),
      decoder.readU64(),
    );
  }

  @override
  int getPrimaryKey(Note row) => row.id;
}

