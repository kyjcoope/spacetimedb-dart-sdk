import '../codec/bsatn_decoder.dart';

/// Interface for decoding table rows from BSATN bytes.
///
/// Each table type needs a decoder that knows:
/// 1. The schema (field order and types)
/// 2. How to construct instances from decoded fields
/// 3. How to extract the primary key (if the table has one)
///
/// Example:
/// ```dart
/// class Player {
///   final int id;
///   final String name;
///   final int level;
///   Player(this.id, this.name, this.level);
/// }
///
/// class PlayerDecoder implements RowDecoder<Player> {
///   @override
///   Player decode(BsatnDecoder decoder) {
///     return Player(
///       decoder.readU32(),
///       decoder.readString(),
///       decoder.readU32(),
///     );
///   }
///
///   @override
///   int getPrimaryKey(Player row) => row.id;
/// }
/// ```
abstract class RowDecoder<T> {
  /// Decode a single row from BSATN bytes.
  ///
  /// The decoder will be positioned at the start of a row.
  /// Read fields in the order they appear in the SpacetimeDB table schema.
  T decode(BsatnDecoder decoder);

  /// Extract the primary key value from a row.
  ///
  /// Returns null if the table has no primary key.
  /// This is used for efficient lookups and update detection.
  dynamic getPrimaryKey(T row);
}
