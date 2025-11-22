// GENERATED REDUCER ARGUMENT CLASSES AND DECODERS - DO NOT MODIFY BY HAND

import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

/// Arguments for the create_note reducer
class CreateNoteArgs {
  final String title;
  final String content;
  CreateNoteArgs({required this.title, required this.content, });
}

/// Decoder for create_note reducer arguments
class CreateNoteArgsDecoder implements ReducerArgDecoder<CreateNoteArgs> {
  @override
  CreateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final title = decoder.readString();
      final content = decoder.readString();

      return CreateNoteArgs(
        title: title,
        content: content,
      );
    } catch (e) {
      return null; // Deserialization failed
    }
  }
}

/// Arguments for the delete_all_notes reducer
class DeleteAllNotesArgs {
  DeleteAllNotesArgs();
}

/// Decoder for delete_all_notes reducer arguments
class DeleteAllNotesArgsDecoder implements ReducerArgDecoder<DeleteAllNotesArgs> {
  @override
  DeleteAllNotesArgs? decode(BsatnDecoder decoder) {
    try {

      return DeleteAllNotesArgs(
      );
    } catch (e) {
      return null; // Deserialization failed
    }
  }
}

/// Arguments for the delete_note reducer
class DeleteNoteArgs {
  final int noteId;
  DeleteNoteArgs({required this.noteId, });
}

/// Decoder for delete_note reducer arguments
class DeleteNoteArgsDecoder implements ReducerArgDecoder<DeleteNoteArgs> {
  @override
  DeleteNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final noteId = decoder.readU32();

      return DeleteNoteArgs(
        noteId: noteId,
      );
    } catch (e) {
      return null; // Deserialization failed
    }
  }
}

/// Arguments for the init reducer
class InitArgs {
  InitArgs();
}

/// Decoder for init reducer arguments
class InitArgsDecoder implements ReducerArgDecoder<InitArgs> {
  @override
  InitArgs? decode(BsatnDecoder decoder) {
    try {

      return InitArgs(
      );
    } catch (e) {
      return null; // Deserialization failed
    }
  }
}

/// Arguments for the update_note reducer
class UpdateNoteArgs {
  final int noteId;
  final String title;
  final String content;
  UpdateNoteArgs({required this.noteId, required this.title, required this.content, });
}

/// Decoder for update_note reducer arguments
class UpdateNoteArgsDecoder implements ReducerArgDecoder<UpdateNoteArgs> {
  @override
  UpdateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final noteId = decoder.readU32();
      final title = decoder.readString();
      final content = decoder.readString();

      return UpdateNoteArgs(
        noteId: noteId,
        title: title,
        content: content,
      );
    } catch (e) {
      return null; // Deserialization failed
    }
  }
}

