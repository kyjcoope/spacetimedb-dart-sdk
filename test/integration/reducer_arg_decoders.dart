import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/reducers/reducer_arg_decoder.dart';

// ============================================================================
// CreateNote Reducer Args
// ============================================================================

class CreateNoteArgs {
  final String title;
  final String content;

  CreateNoteArgs({required this.title, required this.content});

  @override
  String toString() => 'CreateNoteArgs(title: $title, content: $content)';
}

class CreateNoteArgsDecoder implements ReducerArgDecoder<CreateNoteArgs> {
  @override
  CreateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final title = decoder.readString();
      final content = decoder.readString();
      return CreateNoteArgs(title: title, content: content);
    } catch (e) {
      // Note: SpacetimeDB may send empty args in TransactionUpdate messages
      // for efficiency. This is expected behavior.
      return null;
    }
  }
}

// ============================================================================
// UpdateNote Reducer Args
// ============================================================================

class UpdateNoteArgs {
  final int id;
  final String title;
  final String content;

  UpdateNoteArgs({
    required this.id,
    required this.title,
    required this.content,
  });

  @override
  String toString() =>
      'UpdateNoteArgs(id: $id, title: $title, content: $content)';
}

class UpdateNoteArgsDecoder implements ReducerArgDecoder<UpdateNoteArgs> {
  @override
  UpdateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final id = decoder.readU32();
      final title = decoder.readString();
      final content = decoder.readString();
      return UpdateNoteArgs(id: id, title: title, content: content);
    } catch (e) {
      return null;
    }
  }
}

// ============================================================================
// DeleteNote Reducer Args
// ============================================================================

class DeleteNoteArgs {
  final int id;

  DeleteNoteArgs({required this.id});

  @override
  String toString() => 'DeleteNoteArgs(id: $id)';
}

class DeleteNoteArgsDecoder implements ReducerArgDecoder<DeleteNoteArgs> {
  @override
  DeleteNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final id = decoder.readU32();
      return DeleteNoteArgs(id: id);
    } catch (e) {
      return null;
    }
  }
}
