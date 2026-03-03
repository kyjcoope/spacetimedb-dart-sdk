import 'package:spacetimedb_dart_sdk/src/codegen/models.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/type_mapper.dart';

/// Generates reducer call methods and argument decoders
class ReducerGenerator {
  final List<ReducerSchema> reducers;
  final DatabaseSchema? schema;

  ReducerGenerator(this.reducers, {this.schema});

  /// Generate Reducers class with call methods and completion callbacks
  String generate() {
    final buf = StringBuffer();

    // Header
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln();
    buf.writeln("import 'dart:async';");
    buf.writeln(
        "import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");
    buf.writeln("import 'reducer_args.dart';");
    buf.writeln();

    // Class definition
    buf.writeln('/// Generated reducer methods with async/await support');
    buf.writeln('///');
    buf.writeln('/// All methods return Future<TransactionResult> containing:');
    buf.writeln('/// - status: Committed/Failed/OutOfEnergy');
    buf.writeln('/// - timestamp: When the reducer executed');
    buf.writeln(
        '/// - energyConsumed: Energy used (null for TransactionUpdateLight)');
    buf.writeln(
        '/// - executionDuration: How long it took (null for TransactionUpdateLight)');
    buf.writeln('class Reducers {');
    buf.writeln('  final ReducerCaller _reducerCaller;');
    buf.writeln('  final ReducerEmitter _reducerEmitter;');
    buf.writeln();
    buf.writeln('  Reducers(this._reducerCaller, this._reducerEmitter);');
    buf.writeln();

    // Generate call method for each reducer
    for (final reducer in reducers) {
      _generateReducerMethod(buf, reducer);
      buf.writeln();
    }

    // Generate completion callback for each reducer
    for (final reducer in reducers) {
      _generateCompletionCallback(buf, reducer);
      buf.writeln();
    }

    buf.writeln('}');

    return buf.toString();
  }

  /// Generate reducer argument classes and decoders
  ///
  /// This creates a separate file `reducer_args.dart` with:
  /// - Args classes (CreateNoteArgs, etc.)
  /// - Decoder classes (CreateNoteArgsDecoder, etc.)
  String generateArgDecoders() {
    final buf = StringBuffer();

    // Header
    buf.writeln(
        '// GENERATED REDUCER ARGUMENT CLASSES AND DECODERS - DO NOT MODIFY BY HAND');
    buf.writeln();
    buf.writeln(
        "import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");
    buf.writeln();

    // Generate args class and decoder for each reducer
    for (final reducer in reducers) {
      _generateReducerArgsClass(buf, reducer);
      buf.writeln();
      _generateReducerDecoder(buf, reducer);
      buf.writeln();
    }

    return buf.toString();
  }

  void _generateReducerMethod(StringBuffer buf, ReducerSchema reducer) {
    final methodName = _toCamelCase(reducer.name);

    buf.writeln('  /// Call the ${reducer.name} reducer');
    buf.writeln('  ///');
    buf.writeln('  /// Returns [TransactionResult] with execution metadata:');
    buf.writeln('  /// - `result.isSuccess` - Check if reducer committed');
    buf.writeln(
        '  /// - `result.energyConsumed` - Energy used (null for lightweight responses)');
    buf.writeln(
        '  /// - `result.executionDuration` - How long it took (null for lightweight responses)');
    buf.writeln('  ///');
    buf.writeln(
        '  /// Pass [optimisticChanges] to immediately update the local cache for offline-first UX.');
    buf.writeln('  /// Changes are rolled back if the server rejects them.');
    buf.writeln('  ///');
    buf.writeln(
        '  /// Throws [ReducerException] if the reducer fails or runs out of energy.');
    buf.writeln(
        "  /// Throws [TimeoutException] if the reducer doesn't complete within the timeout.");

    buf.write('  Future<TransactionResult> $methodName(');

    if (reducer.params.elements.isEmpty) {
      buf.writeln('{List<OptimisticChange>? optimisticChanges}) async {');
    } else {
      buf.writeln('{');
      for (final param in reducer.params.elements) {
        final paramName = _toCamelCase(param.name ?? 'unknown');
        final dartType = _resolveDartType(param.algebraicType);
        if (TypeMapper.isOptionType(param.algebraicType)) {
          buf.writeln('    $dartType $paramName,');
        } else {
          buf.writeln('    required $dartType $paramName,');
        }
      }
      buf.writeln('    List<OptimisticChange>? optimisticChanges,');
      buf.writeln('  }) async {');
    }

    buf.writeln('    final encoder = BsatnEncoder();');
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      _writeEncodeLine(buf, paramName, param.algebraicType);
    }
    buf.writeln();

    buf.writeln(
        "    return await _reducerCaller.call('${reducer.name}', encoder.toBytes(), optimisticChanges: optimisticChanges);");
    buf.writeln('  }');
  }

  /// Generate completion callback method for a reducer
  void _generateCompletionCallback(StringBuffer buf, ReducerSchema reducer) {
    final methodName = 'on${_toPascalCase(reducer.name)}';
    final argsClassName = '${_toPascalCase(reducer.name)}Args';

    // Build callback signature
    buf.write('  StreamSubscription<void> $methodName(');
    buf.write('void Function(EventContext ctx');

    // Add typed parameters to callback
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      final dartType = _resolveDartType(param.algebraicType);
      buf.write(', $dartType $paramName');
    }
    buf.writeln(') callback) {');

    // Implementation
    buf.writeln(
        "    return _reducerEmitter.on('${reducer.name}').listen((EventContext ctx) {");
    buf.writeln('      // Pattern match to extract ReducerEvent');
    buf.writeln('      final event = ctx.event;');
    buf.writeln('      if (event is! ReducerEvent) return;');
    buf.writeln();
    buf.writeln('      // Type guard - ensures args is correct type');
    buf.writeln('      final args = event.reducerArgs;');
    buf.writeln('      if (args is! $argsClassName) return;');
    buf.writeln();
    buf.writeln(
        '      // Extract fields from strongly-typed object - NO CASTING');
    buf.write('      callback(ctx');

    // Extract each arg field
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      buf.write(', args.$paramName');
    }
    buf.writeln(');');
    buf.writeln('    });');
    buf.writeln('  }');
  }

  /// Generate the strongly-typed args class for a reducer
  void _generateReducerArgsClass(StringBuffer buf, ReducerSchema reducer) {
    final className = '${_toPascalCase(reducer.name)}Args';

    buf.writeln('/// Arguments for the ${reducer.name} reducer');
    buf.writeln('class $className {');

    // Generate fields
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      final dartType = _resolveDartType(param.algebraicType);
      buf.writeln('  final $dartType $paramName;');
    }

    // Generate constructor
    if (reducer.params.elements.isEmpty) {
      // Empty constructor for reducers with no parameters
      buf.writeln('  $className();');
    } else {
      // Constructor with parameters — Option fields are optional
      buf.write('  $className({');
      for (final param in reducer.params.elements) {
        final paramName = _toCamelCase(param.name ?? 'unknown');
        if (TypeMapper.isOptionType(param.algebraicType)) {
          buf.write('this.$paramName, ');
        } else {
          buf.write('required this.$paramName, ');
        }
      }
      buf.writeln('});');
    }

    buf.writeln('}');
  }

  /// Generate the decoder for a reducer's arguments
  void _generateReducerDecoder(StringBuffer buf, ReducerSchema reducer) {
    final argsClassName = '${_toPascalCase(reducer.name)}Args';
    final decoderClassName = '${_toPascalCase(reducer.name)}ArgsDecoder';

    buf.writeln('/// Decoder for ${reducer.name} reducer arguments');
    buf.writeln(
        'class $decoderClassName implements ReducerArgDecoder<$argsClassName> {');
    buf.writeln('  @override');
    buf.writeln('  $argsClassName? decode(BsatnDecoder decoder) {');
    buf.writeln('    try {');

    // Decode each parameter
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      _generateArgDecode(buf, paramName, param.algebraicType);
    }

    buf.writeln();
    buf.writeln('      return $argsClassName(');
    for (final param in reducer.params.elements) {
      final paramName = _toCamelCase(param.name ?? 'unknown');
      buf.writeln('        $paramName: $paramName,');
    }
    buf.writeln('      );');

    buf.writeln('    } catch (e) {');
    buf.writeln('      return null; // Deserialization failed');
    buf.writeln('    }');
    buf.writeln('  }');
    buf.writeln('}');
  }

  // ---------------------------------------------------------------------------
  // Encode helpers (for reducer call methods)
  // ---------------------------------------------------------------------------

  void _writeEncodeLine(
      StringBuffer buf, String paramName, Map<String, dynamic> algebraicType) {
    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (_isIdentity(innerType)) {
          buf.writeln(
              '    encoder.writeOption<Identity>($paramName, (v) => encoder.writeBytes(v.bytes));');
        } else if (TypeMapper.isArrayType(innerType)) {
          final elemType = TypeMapper.getArrayElementType(innerType);
          final elemEncoder = elemType != null
              ? TypeMapper.getEncoderMethod(elemType)
              : 'write';
          buf.writeln(
              '    encoder.writeOption<List>($paramName, (v) => encoder.writeArray(v, (item) => encoder.$elemEncoder(item)));');
        } else if (TypeMapper.isRefType(innerType)) {
          final typeName = _resolveDartType(innerType);
          buf.writeln(
              '    encoder.writeOption<$typeName>($paramName, (v) => v.encode(encoder));');
        } else {
          final encoderMethod = TypeMapper.getEncoderMethod(innerType);
          final dartType = _resolveDartType(innerType);
          buf.writeln(
              '    encoder.writeOption<$dartType>($paramName, (v) => encoder.$encoderMethod(v));');
        }
        return;
      }
    }

    // Identity
    if (_isIdentity(algebraicType)) {
      buf.writeln('    encoder.writeBytes($paramName.bytes);');
      return;
    }

    // Array<T>
    if (TypeMapper.isArrayType(algebraicType)) {
      final elemType = TypeMapper.getArrayElementType(algebraicType);
      if (elemType != null) {
        if (_isIdentity(elemType)) {
          buf.writeln(
              '    encoder.writeArray($paramName, (item) => encoder.writeBytes(item.bytes));');
        } else if (TypeMapper.isRefType(elemType)) {
          buf.writeln(
              '    encoder.writeArray($paramName, (item) => item.encode(encoder));');
        } else {
          final innerEncoder = TypeMapper.getEncoderMethod(elemType);
          buf.writeln(
              '    encoder.writeArray($paramName, (item) => encoder.$innerEncoder(item));');
        }
      } else {
        buf.writeln(
            '    encoder.writeArray($paramName, (item) => encoder.write(item));');
      }
      return;
    }

    // Ref types (non-Identity)
    if (TypeMapper.isRefType(algebraicType)) {
      buf.writeln('    $paramName.encode(encoder);');
      return;
    }

    // Primitive
    final method = TypeMapper.getEncoderMethod(algebraicType);
    buf.writeln('    encoder.$method($paramName);');
  }

  // ---------------------------------------------------------------------------
  // Decode helpers (for reducer arg decoders)
  // ---------------------------------------------------------------------------

  void _generateArgDecode(
      StringBuffer buf, String fieldName, Map<String, dynamic> algebraicType) {
    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (_isIdentity(innerType)) {
          buf.writeln(
              '      final $fieldName = decoder.readOption<Identity>(() => Identity(decoder.readBytes(32)));');
        } else if (TypeMapper.isArrayType(innerType)) {
          final elemType = TypeMapper.getArrayElementType(innerType);
          final elemDecoder =
              elemType != null ? TypeMapper.getDecoderMethod(elemType) : 'read';
          buf.writeln(
              '      final $fieldName = decoder.readOption<List>(() => decoder.readArray(() => decoder.$elemDecoder()));');
        } else if (_isPrimitive(innerType)) {
          final decoderMethod = TypeMapper.getDecoderMethod(innerType);
          final dartType = _resolveDartType(innerType);
          buf.writeln(
              '      final $fieldName = decoder.readOption<$dartType>(() => decoder.$decoderMethod());');
        } else {
          final typeName = _getDartClassName(innerType);
          buf.writeln(
              '      final $fieldName = decoder.readOption<$typeName>(() => $typeName.decode(decoder));');
        }
        return;
      }
    }

    // Identity
    if (_isIdentity(algebraicType)) {
      buf.writeln('      final $fieldName = Identity(decoder.readBytes(32));');
      return;
    }

    // Array<T>
    if (TypeMapper.isArrayType(algebraicType)) {
      final elemType = TypeMapper.getArrayElementType(algebraicType);
      if (elemType != null) {
        if (_isIdentity(elemType)) {
          buf.writeln(
              '      final $fieldName = decoder.readArray<Identity>(() => Identity(decoder.readBytes(32)));');
        } else if (_isPrimitive(elemType)) {
          final decoderMethod = TypeMapper.getDecoderMethod(elemType);
          final dartType = _resolveDartType(elemType);
          buf.writeln(
              '      final $fieldName = decoder.readArray<$dartType>(() => decoder.$decoderMethod());');
        } else {
          final typeName = _getDartClassName(elemType);
          buf.writeln(
              '      final $fieldName = decoder.readArray<$typeName>(() => $typeName.decode(decoder));');
        }
      } else {
        buf.writeln(
            '      final $fieldName = decoder.readArray(() => decoder.read());');
      }
      return;
    }

    // Primitive
    if (_isPrimitive(algebraicType)) {
      final method = TypeMapper.getDecoderMethod(algebraicType);
      buf.writeln('      final $fieldName = decoder.$method();');
      return;
    }

    // Complex type (Ref to struct/enum)
    final typeName = _getDartClassName(algebraicType);
    buf.writeln('      final $fieldName = $typeName.decode(decoder);');
  }

  // ---------------------------------------------------------------------------
  // Type resolution helpers
  // ---------------------------------------------------------------------------

  /// Check if a type is a primitive (built-in BsatnDecoder method exists)
  bool _isPrimitive(Map<String, dynamic> algebraicType) {
    const primitiveKeys = [
      'U8',
      'U16',
      'U32',
      'U64',
      'U128',
      'I8',
      'I16',
      'I32',
      'I64',
      'I128',
      'F32',
      'F64',
      'Bool',
      'String',
    ];
    return primitiveKeys.any((key) => algebraicType.containsKey(key));
  }

  /// Check if algebraicType resolves to Identity
  bool _isIdentity(Map<String, dynamic> algebraicType) {
    return TypeMapper.isIdentityType(
      algebraicType,
      typeSpace: schema?.typeSpace,
      typeDefs: schema?.types,
    );
  }

  /// Resolve a Dart type string, using schema context if available
  String _resolveDartType(Map<String, dynamic> algebraicType) {
    return TypeMapper.toDartType(
      algebraicType,
      typeSpace: schema?.typeSpace,
      typeDefs: schema?.types,
    );
  }

  /// Get the Dart class name for a complex (Ref) type, resolving through schema.
  String _getDartClassName(Map<String, dynamic> algebraicType) {
    if (algebraicType.containsKey('Ref') && schema != null) {
      final typeIndex = algebraicType['Ref'] as int;
      for (final td in schema!.types) {
        if (td.typeRef == typeIndex && td.name.isNotEmpty) {
          return _toPascalCase(td.name);
        }
      }
    }
    // Fallback: use TypeMapper which also resolves Refs
    final resolved = _resolveDartType(algebraicType);
    return resolved != 'dynamic' ? resolved : 'dynamic /* unresolved type */';
  }

  String _toCamelCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;

    return parts[0].toLowerCase() +
        parts.skip(1).map((word) {
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).join('');
  }

  String _toPascalCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;

    return parts.map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join('');
  }
}
