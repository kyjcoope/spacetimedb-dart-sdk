import 'dart:async';

import 'package:spacetimedb_dart_sdk/src/cache/row_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/messages/shared_types.dart';

/// Client-side cache for a single SpacetimeDB table
///
/// Stores decoded rows in memory and provides:
/// - Fast lookups by primary key
/// - Real-time change streams (insertStream, updateStream, deleteStream, changeStream)
/// - Automatic update detection
///
/// The cache automatically processes transaction updates from the server
/// and emits changes to streams with zero overhead when no listeners are present.
///
/// Example:
/// ```dart
/// final noteTable = subscriptionManager.cache.getTable<Note>(4096);
///
/// // Listen to changes
/// noteTable.insertStream.listen((note) {
///   print('New note: ${note.title}');
/// });
///
/// noteTable.updateStream.listen((update) {
///   print('Updated: ${update.oldRow.title} → ${update.newRow.title}');
/// });
///
/// noteTable.deleteStream.listen((note) {
///   print('Deleted: ${note.title}');
/// });
///
/// // Query cached data
/// final note = noteTable.find(42);
/// print('Note count: ${noteTable.count()}');
///
/// for (final note in noteTable.iter()) {
///   print(note.title);
/// }
/// ```
class TableCache<T> {
  final int tableId;
  final String tableName;
  final RowDecoder<T> decoder;

  final Map<dynamic, T> _rowsByPrimaryKey = {};

  final List<T> _rows = [];

  // Stream controllers for real-time change notifications
  final StreamController<T> _insertController = StreamController<T>.broadcast();
  final StreamController<T> _deleteController = StreamController<T>.broadcast();
  final StreamController<TableUpdate<T>> _updateController =
      StreamController<TableUpdate<T>>.broadcast();
  final StreamController<TableChange<T>> _changeController =
      StreamController<TableChange<T>>.broadcast();

  TableCache(
      {required this.tableId, required this.tableName, required this.decoder});

  /// Stream of inserted rows
  ///
  /// Zero-overhead broadcast stream that emits rows as they're inserted.
  /// Multiple listeners supported with no performance penalty.
  ///
  /// Example:
  /// ```dart
  /// noteTable.insertStream.listen((note) {
  ///   print('New note: ${note.title}');
  /// });
  /// ```
  Stream<T> get insertStream => _insertController.stream;

  /// Stream of deleted rows
  ///
  /// Example:
  /// ```dart
  /// noteTable.deleteStream.listen((note) {
  ///   print('Deleted: ${note.title}');
  /// });
  /// ```
  Stream<T> get deleteStream => _deleteController.stream;

  /// Stream of updated rows
  ///
  /// Emits TableUpdate objects containing both old and new row values.
  ///
  /// Example:
  /// ```dart
  /// noteTable.updateStream.listen((update) {
  ///   print('Updated: ${update.oldRow.title} → ${update.newRow.title}');
  /// });
  /// ```
  Stream<TableUpdate<T>> get updateStream => _updateController.stream;

  /// Combined stream of all changes
  ///
  /// Emits TableChange objects for inserts, updates, and deletes.
  /// Useful when you need to react to any change regardless of type.
  ///
  /// Example:
  /// ```dart
  /// noteTable.changeStream.listen((change) {
  ///   switch (change.type) {
  ///     case ChangeType.insert:
  ///       print('Inserted: ${change.row!.title}');
  ///     case ChangeType.update:
  ///       print('Updated: ${change.oldRow!.title} → ${change.newRow!.title}');
  ///     case ChangeType.delete:
  ///       print('Deleted: ${change.row!.title}');
  ///   }
  /// });
  /// ```
  Stream<TableChange<T>> get changeStream => _changeController.stream;

  void _emitChanges(_RowChanges<T> changes) {
    // Emit to streams (async, non-blocking, zero-overhead for no listeners)
    for (final row in changes.inserted) {
      _insertController.add(row);
      _changeController.add(TableChange.insert(row));
    }

    for (final row in changes.deleted) {
      _deleteController.add(row);
      _changeController.add(TableChange.delete(row));
    }

    for (final (oldRow, newRow) in changes.updated) {
      _updateController.add(TableUpdate(oldRow, newRow));
      _changeController.add(TableChange.update(oldRow, newRow));
    }
  }

  void applyTransactionUpdate(BsatnRowList deletes, BsatnRowList inserts) {
    final changes = _applyChanges(deletes, inserts);
    _emitChanges(changes);
  }

  /// Returns the number of rows in the cache
  ///
  /// Example:
  /// ```dart
  /// print('Total notes: ${noteTable.count()}');
  /// ```
  int count() {
    return _rowsByPrimaryKey.isNotEmpty
        ? _rowsByPrimaryKey.length
        : _rows.length;
  }

  /// Finds a row by its primary key
  ///
  /// Returns null if the row is not found or if the table has no primary key.
  ///
  /// Example:
  /// ```dart
  /// final note = noteTable.find(42);
  /// if (note != null) {
  ///   print('Found: ${note.title}');
  /// }
  /// ```
  T? find(dynamic primaryKey) => _rowsByPrimaryKey[primaryKey];

  /// Returns an iterable of all rows in the cache
  ///
  /// Example:
  /// ```dart
  /// for (final note in noteTable.iter()) {
  ///   print('${note.id}. ${note.title}');
  /// }
  /// ```
  Iterable<T> iter() {
    return _rowsByPrimaryKey.isNotEmpty ? _rowsByPrimaryKey.values : _rows;
  }

  void _decodeAndStoreRows(BsatnRowList rowList) {
    final rowBytes = rowList.getRows();

    for (final bytes in rowBytes) {
      final bsatnDecoder = BsatnDecoder(bytes);
      final row = decoder.decode(bsatnDecoder);

      final primaryKey = decoder.getPrimaryKey(row);
      if (primaryKey != null) {
        _rowsByPrimaryKey[primaryKey] = row;
      } else {
        _rows.add(row);
      }
    }
  }

  void applyDeletes(BsatnRowList deletes) {
    final rowBytes = deletes.getRows();
    for (final bytes in rowBytes) {
      final bsatnDecoder = BsatnDecoder(bytes);
      final row = decoder.decode(bsatnDecoder);
      final primaryKey = decoder.getPrimaryKey(row);
      if (primaryKey != null) {
        _rowsByPrimaryKey.remove(primaryKey);
      } else {
        // For tables without primary key, remove by equality
        _rows.remove(row);
      }
    }
  }

  _RowChanges<T> _applyChanges(BsatnRowList deletes, BsatnRowList inserts) {
    final changes = _RowChanges<T>();
    final oldValues = <dynamic, T>{};

    final deleteBytes = deletes.getRows();
    for (final bytes in deleteBytes) {
      final bsatnDecoder = BsatnDecoder(bytes);
      final row = decoder.decode(bsatnDecoder);
      final primaryKey = decoder.getPrimaryKey(row);
      if (primaryKey != null) {
        final old = _rowsByPrimaryKey.remove(primaryKey);
        if (old != null) {
          oldValues[primaryKey] = old;
          changes.deleted.add(old);
        }
      } else {
        _rows.remove(row);
        changes.deleted.add(row);
      }
    }

    final insertBytes = inserts.getRows();
    for (final bytes in insertBytes) {
      final bsatnDecoder = BsatnDecoder(bytes);
      final row = decoder.decode(bsatnDecoder);
      final primaryKey = decoder.getPrimaryKey(row);

      if (primaryKey != null) {
        // Check if same key was deleted = update
        if (oldValues.containsKey(primaryKey)) {
          changes.updated.add((oldValues[primaryKey]!, row));
        } else {
          changes.inserted.add(row);
        }
        _rowsByPrimaryKey[primaryKey] = row;
      } else {
        changes.inserted.add(row);
        _rows.add(row);
      }
    }

    return changes;
  }

  /// Clears all rows from the cache
  ///
  /// Example:
  /// ```dart
  /// noteTable.clear();
  /// ```
  void clear() {
    _rowsByPrimaryKey.clear();
    _rows.clear();
  }

  void applyInitialData(BsatnRowList inserts) {
    _decodeAndStoreRows(inserts);
  }

  void applyInserts(BsatnRowList inserts) {
    _decodeAndStoreRows(inserts);
  }

  /// Dispose of stream controllers when table cache is no longer needed
  ///
  /// Call this when disconnecting or cleaning up to prevent memory leaks.
  void dispose() {
    _insertController.close();
    _deleteController.close();
    _updateController.close();
    _changeController.close();
  }
}

class _RowChanges<T> {
  final List<T> inserted = [];
  final List<T> deleted = [];
  final List<(T, T)> updated = [];
}

/// Represents an update to a row (old value → new value)
class TableUpdate<T> {
  final T oldRow;
  final T newRow;

  TableUpdate(this.oldRow, this.newRow);
}

/// Types of changes that can occur to a table
enum ChangeType { insert, update, delete }

/// Represents any change to a table row
class TableChange<T> {
  final ChangeType type;
  final T? row; // For insert/delete
  final T? oldRow; // For update
  final T? newRow; // For update

  TableChange.insert(this.row)
      : type = ChangeType.insert,
        oldRow = null,
        newRow = null;

  TableChange.update(this.oldRow, this.newRow)
      : type = ChangeType.update,
        row = null;

  TableChange.delete(this.row)
      : type = ChangeType.delete,
        oldRow = null,
        newRow = null;
}
