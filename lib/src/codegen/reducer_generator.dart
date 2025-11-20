import 'package:spacetimedb_dart_sdk/src/codegen/models.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/type_mapper.dart';

/// Generates reducer call methods
class ReducerGenerator {
  final List<ReducerSchema> reducers;

  ReducerGenerator(this.reducers);

  /// Generate Reducers class
  String generate() {
    final buf = StringBuffer();

    // Header
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln();
    buf.writeln("import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");
    buf.writeln();

    // Class definition
    buf.writeln('class Reducers {');
    buf.writeln('  final SpacetimeDbConnection _connection;');
    buf.writeln();
    buf.writeln('  Reducers(this._connection);');
    buf.writeln();

    // Generate method for each reducer
    for (final reducer in reducers) {
      _generateReducerMethod(buf, reducer);
      buf.writeln();
    }

    buf.writeln('}');

    return buf.toString();
  }

  void _generateReducerMethod(StringBuffer buf, ReducerSchema reducer) {
    final methodName = _toCamelCase(reducer.name);

    // Method signature
    buf.write('  Future<void> $methodName(');

    if (reducer.params.elements.isEmpty) {
      buf.writeln(') async {');
    } else {
      buf.writeln('{');
      for (final param in reducer.params.elements) {
        final paramName = _toCamelCase(param.name ?? 'unknown');
        final dartType = TypeMapper.toDartType(param.algebraicType);
        buf.writeln('    required $dartType $paramName,');
      }
      buf.writeln('  }) async {');
    }

    // Encode arguments
    buf.writeln('    final encoder = BsatnEncoder();');
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      final method = TypeMapper.getEncoderMethod(param.algebraicType);
      buf.writeln('    encoder.$method($paramName);');
    }
    buf.writeln();

    // Call reducer
    buf.writeln("    await _connection.callReducer('${reducer.name}', encoder.toBytes());");
    buf.writeln('  }');
  }

  String _toCamelCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;

    return parts[0].toLowerCase() +
        parts.skip(1).map((word) {
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).join('');
  }
}
