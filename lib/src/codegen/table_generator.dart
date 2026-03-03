import 'package:spacetimedb_dart_sdk/src/codegen/models.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/type_mapper.dart';

class TableGenerator {
  final DatabaseSchema schema;
  final TableSchema table;

  TableGenerator(this.schema, this.table);

  String generate() {
    final buf = StringBuffer();

    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln();
    buf.writeln(
        "import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");

    final productType = schema.typeSpace.types[table.productTypeRef].product;
    if (productType == null) {
      throw Exception('Table ${table.name} has no product type');
    }

    // Check if we need dart:typed_data (for Identity fields)
    bool needsTypedData = false;
    for (final element in productType.elements) {
      if (TypeMapper.isIdentityType(
        element.algebraicType,
        typeSpace: schema.typeSpace,
        typeDefs: schema.types,
      )) {
        needsTypedData = true;
        break;
      }
    }
    if (needsTypedData) {
      buf.writeln("import 'dart:typed_data';");
    }

    // Collect imports for Ref types (excluding Identity, which comes from the SDK)
    final imports = <String>{};
    for (final element in productType.elements) {
      _collectRefImports(element.algebraicType, imports);
    }

    // Add imports
    for (final import in imports) {
      buf.writeln(import);
    }
    buf.writeln();

    final className = _toPascalCase(table.name);
    buf.writeln('class $className {');

    // Fields
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      final dartType = TypeMapper.toDartType(
        element.algebraicType,
        typeSpace: schema.typeSpace,
        typeDefs: schema.types,
      );
      buf.writeln('  final $dartType $fieldName;');
    }
    buf.writeln();

    // Constructor — Option fields are optional (no 'required')
    buf.writeln('  $className({');
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      if (TypeMapper.isOptionType(element.algebraicType)) {
        buf.writeln('    this.$fieldName,');
      } else {
        buf.writeln('    required this.$fieldName,');
      }
    }
    buf.writeln('  });');
    buf.writeln();

    // encodeBsatn method
    buf.writeln('  void encodeBsatn(BsatnEncoder encoder) {');
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      _writeEncodeLine(buf, fieldName, element.algebraicType);
    }
    buf.writeln('  }');
    buf.writeln();

    // decodeBsatn method
    buf.writeln('  static $className decodeBsatn(BsatnDecoder decoder) {');
    buf.writeln('    return $className(');
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      final decodeExpr = _getDecodeExpression(element.algebraicType);
      buf.writeln('      $fieldName: $decodeExpr,');
    }
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();

    // toJson method
    buf.writeln('  Map<String, dynamic> toJson() {');
    buf.writeln('    return {');
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      final jsonValue = _getToJsonExpression(fieldName, element.algebraicType);
      buf.writeln("      '$fieldName': $jsonValue,");
    }
    buf.writeln('    };');
    buf.writeln('  }');
    buf.writeln();

    // fromJson factory
    buf.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buf.writeln('    return $className(');
    for (final element in productType.elements) {
      final fieldName = _toCamelCase(element.name ?? 'unknown');
      final fromJsonExpr =
          _getFromJsonExpression(fieldName, element.algebraicType);
      buf.writeln('      $fieldName: $fromJsonExpr,');
    }
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();

    // Close class
    buf.writeln('}');
    buf.writeln();

    // Generate Identity parser helper if needed
    if (needsTypedData) {
      buf.writeln(
          '/// Parse identity from various formats (hex string with optional 0x prefix, or raw bytes).');
      buf.writeln('Identity _parseIdentity(dynamic value) {');
      buf.writeln('  if (value is Identity) return value;');
      buf.writeln('  if (value is String) {');
      buf.writeln(
          "    final hex = value.startsWith('0x') ? value.substring(2) : value;");
      buf.writeln('    final bytes = List<int>.generate(');
      buf.writeln('      hex.length ~/ 2,');
      buf.writeln(
          '      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),');
      buf.writeln('    );');
      buf.writeln('    return Identity(Uint8List.fromList(bytes));');
      buf.writeln('  }');
      buf.writeln('  // Fallback: zero identity');
      buf.writeln('  return Identity(Uint8List(32));');
      buf.writeln('}');
      buf.writeln();
    }

    // Generate Decoder class with collision-safe name
    final decoderClassName = TypeMapper.getDecoderClassName(table.name);
    buf.writeln('class $decoderClassName extends RowDecoder<$className> {');
    buf.writeln('  @override');
    buf.writeln('  $className decode(BsatnDecoder decoder) {');
    buf.writeln('    return $className.decodeBsatn(decoder);');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');

    // Find the actual primary key column and its type
    if (table.primaryKey.isNotEmpty && productType.elements.isNotEmpty) {
      final pkIndex = table.primaryKey.first;
      if (pkIndex < productType.elements.length) {
        final pkElement = productType.elements[pkIndex];
        final pkFieldName = _toCamelCase(pkElement.name ?? 'unknown');
        final pkDartType = TypeMapper.toDartType(
          pkElement.algebraicType,
          typeSpace: schema.typeSpace,
          typeDefs: schema.types,
        );
        buf.writeln('  $pkDartType? getPrimaryKey($className row) {');
        buf.writeln('    return row.$pkFieldName;');
      } else {
        buf.writeln('  dynamic getPrimaryKey($className row) {');
        buf.writeln('    return null;');
      }
    } else {
      buf.writeln('  dynamic getPrimaryKey($className row) {');
      buf.writeln('    return null;');
    }

    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln(
        '  Map<String, dynamic>? toJson($className row) => row.toJson();');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln(
        '  $className? fromJson(Map<String, dynamic> json) => $className.fromJson(json);');
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  bool get supportsJsonSerialization => true;');
    buf.writeln('}');

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Encode generation
  // ---------------------------------------------------------------------------

  void _writeEncodeLine(
      StringBuffer buf, String fieldName, Map<String, dynamic> algebraicType) {
    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (TypeMapper.isIdentityType(innerType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          buf.writeln(
              '    encoder.writeOption<Identity>($fieldName, (v) => encoder.writeBytes(v.bytes));');
        } else if (TypeMapper.isArrayType(innerType)) {
          final elemType = TypeMapper.getArrayElementType(innerType);
          final elemEncoder = elemType != null
              ? TypeMapper.getEncoderMethod(elemType)
              : 'write';
          buf.writeln(
              '    encoder.writeOption<List>($fieldName, (v) => encoder.writeArray(v, (item) => encoder.$elemEncoder(item)));');
        } else {
          final encoderMethod = TypeMapper.getEncoderMethod(innerType);
          final dartType = TypeMapper.toDartType(innerType,
              typeSpace: schema.typeSpace, typeDefs: schema.types);
          buf.writeln(
              '    encoder.writeOption<$dartType>($fieldName, (v) => encoder.$encoderMethod(v));');
        }
        return;
      }
    }

    // Identity
    if (TypeMapper.isIdentityType(algebraicType,
        typeSpace: schema.typeSpace, typeDefs: schema.types)) {
      buf.writeln('    encoder.writeBytes($fieldName.bytes);');
      return;
    }

    // Array<T>
    if (TypeMapper.isArrayType(algebraicType)) {
      final elemType = TypeMapper.getArrayElementType(algebraicType);
      if (elemType != null) {
        if (TypeMapper.isIdentityType(elemType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          buf.writeln(
              '    encoder.writeArray($fieldName, (item) => encoder.writeBytes(item.bytes));');
        } else if (TypeMapper.isRefType(elemType)) {
          buf.writeln(
              '    encoder.writeArray($fieldName, (item) => item.encode(encoder));');
        } else {
          final innerEncoder = TypeMapper.getEncoderMethod(elemType);
          buf.writeln(
              '    encoder.writeArray($fieldName, (item) => encoder.$innerEncoder(item));');
        }
      } else {
        buf.writeln(
            '    encoder.writeArray($fieldName, (item) => encoder.write(item));');
      }
      return;
    }

    // Ref types (non-Identity)
    if (TypeMapper.isRefType(algebraicType)) {
      buf.writeln('    $fieldName.encode(encoder);');
      return;
    }

    // Primitive
    final method = TypeMapper.getEncoderMethod(algebraicType);
    buf.writeln('    encoder.$method($fieldName);');
  }

  // ---------------------------------------------------------------------------
  // Decode generation
  // ---------------------------------------------------------------------------

  String _getDecodeExpression(Map<String, dynamic> algebraicType) {
    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (TypeMapper.isIdentityType(innerType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          return 'decoder.readOption<Identity>(() => Identity(decoder.readBytes(32)))';
        }
        if (TypeMapper.isArrayType(innerType)) {
          final elemType = TypeMapper.getArrayElementType(innerType);
          final elemDecoder =
              elemType != null ? TypeMapper.getDecoderMethod(elemType) : 'read';
          return 'decoder.readOption<List>(() => decoder.readArray(() => decoder.$elemDecoder()))';
        }
        final decoderMethod = TypeMapper.getDecoderMethod(innerType);
        final dartType = TypeMapper.toDartType(innerType,
            typeSpace: schema.typeSpace, typeDefs: schema.types);
        return 'decoder.readOption<$dartType>(() => decoder.$decoderMethod())';
      }
    }

    // Identity
    if (TypeMapper.isIdentityType(algebraicType,
        typeSpace: schema.typeSpace, typeDefs: schema.types)) {
      return 'Identity(decoder.readBytes(32))';
    }

    // Array<T>
    if (TypeMapper.isArrayType(algebraicType)) {
      final elemType = TypeMapper.getArrayElementType(algebraicType);
      if (elemType != null) {
        if (TypeMapper.isIdentityType(elemType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          return 'decoder.readArray<Identity>(() => Identity(decoder.readBytes(32)))';
        }
        if (TypeMapper.isRefType(elemType)) {
          final typeName = TypeMapper.toDartType(elemType,
              typeSpace: schema.typeSpace, typeDefs: schema.types);
          return 'decoder.readArray<$typeName>(() => $typeName.decode(decoder))';
        }
        final innerDecoder = TypeMapper.getDecoderMethod(elemType);
        final dartType = TypeMapper.toDartType(elemType,
            typeSpace: schema.typeSpace, typeDefs: schema.types);
        return 'decoder.readArray<$dartType>(() => decoder.$innerDecoder())';
      }
    }

    // Ref types (non-Identity)
    if (TypeMapper.isRefType(algebraicType)) {
      final typeName = TypeMapper.toDartType(algebraicType,
          typeSpace: schema.typeSpace, typeDefs: schema.types);
      return '$typeName.decode(decoder)';
    }

    // Primitive
    final method = TypeMapper.getDecoderMethod(algebraicType);
    return 'decoder.$method()';
  }

  // ---------------------------------------------------------------------------
  // toJson generation
  // ---------------------------------------------------------------------------

  String _getToJsonExpression(
      String fieldName, Map<String, dynamic> algebraicType) {
    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (TypeMapper.isIdentityType(innerType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          return '$fieldName?.toHexString';
        }
        if (innerType.containsKey('U64') || innerType.containsKey('I64')) {
          return '$fieldName?.toInt()';
        }
        if (_isTimestamp(innerType)) {
          return '$fieldName?.toInt()';
        }
        if (TypeMapper.isRefType(innerType)) {
          return '$fieldName?.toJson()';
        }
      }
      return fieldName;
    }

    // Identity
    if (TypeMapper.isIdentityType(algebraicType,
        typeSpace: schema.typeSpace, typeDefs: schema.types)) {
      return '$fieldName.toHexString';
    }

    if (_isTimestamp(algebraicType)) {
      return '$fieldName.toInt()';
    }
    if (algebraicType.containsKey('U64') || algebraicType.containsKey('I64')) {
      return '$fieldName.toInt()';
    }
    if (TypeMapper.isRefType(algebraicType)) {
      return '$fieldName.toJson()';
    }
    if (algebraicType.containsKey('Array')) {
      final elementType = algebraicType['Array'] as Map<String, dynamic>;
      if (TypeMapper.isIdentityType(elementType,
          typeSpace: schema.typeSpace, typeDefs: schema.types)) {
        return '$fieldName.map((e) => e.toHexString).toList()';
      }
      if (TypeMapper.isRefType(elementType)) {
        return '$fieldName.map((e) => e.toJson()).toList()';
      }
      if (elementType.containsKey('U64') || elementType.containsKey('I64')) {
        return '$fieldName.map((e) => e.toInt()).toList()';
      }
    }
    return fieldName;
  }

  // ---------------------------------------------------------------------------
  // fromJson generation
  // ---------------------------------------------------------------------------

  String _getFromJsonExpression(
      String fieldName, Map<String, dynamic> algebraicType) {
    final dartType = TypeMapper.toDartType(
      algebraicType,
      typeSpace: schema.typeSpace,
      typeDefs: schema.types,
    );

    // Option<T>
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        if (TypeMapper.isIdentityType(innerType,
            typeSpace: schema.typeSpace, typeDefs: schema.types)) {
          return "json['$fieldName'] != null ? _parseIdentity(json['$fieldName']) : null";
        }
        if (innerType.containsKey('U64') || innerType.containsKey('I64')) {
          return "json['$fieldName'] != null\n          ? Int64((json['$fieldName'] as int))\n          : null";
        }
        if (_isTimestamp(innerType)) {
          return "json['$fieldName'] != null\n          ? Int64((json['$fieldName'] as int))\n          : null";
        }
        if (TypeMapper.isRefType(innerType)) {
          final innerDartType = TypeMapper.toDartType(innerType,
              typeSpace: schema.typeSpace, typeDefs: schema.types);
          return "json['$fieldName'] != null\n          ? $innerDartType.fromJson(json['$fieldName'] as Map<String, dynamic>)\n          : null";
        }
      }
      return "json['$fieldName']";
    }

    // Identity
    if (TypeMapper.isIdentityType(algebraicType,
        typeSpace: schema.typeSpace, typeDefs: schema.types)) {
      return "_parseIdentity(json['$fieldName'])";
    }

    if (_isTimestamp(algebraicType)) {
      return "Int64((json['$fieldName'] as int?) ?? 0)";
    }
    if (algebraicType.containsKey('U64') || algebraicType.containsKey('I64')) {
      return "Int64((json['$fieldName'] as int?) ?? 0)";
    }
    if (TypeMapper.isRefType(algebraicType)) {
      return "$dartType.fromJson(json['$fieldName'] as Map<String, dynamic>)";
    }
    if (algebraicType.containsKey('Array')) {
      final elementType = algebraicType['Array'] as Map<String, dynamic>;
      final innerDartType = TypeMapper.toDartType(
        elementType,
        typeSpace: schema.typeSpace,
        typeDefs: schema.types,
      );
      if (TypeMapper.isIdentityType(elementType,
          typeSpace: schema.typeSpace, typeDefs: schema.types)) {
        return "(json['$fieldName'] as List?)?.map((e) => _parseIdentity(e)).toList() ?? []";
      }
      if (TypeMapper.isRefType(elementType)) {
        return "(json['$fieldName'] as List?)?.map((e) => $innerDartType.fromJson(e as Map<String, dynamic>)).toList() ?? []";
      }
      if (elementType.containsKey('U64') || elementType.containsKey('I64')) {
        return "(json['$fieldName'] as List?)?.map((e) => Int64(e as int)).toList() ?? []";
      }
      return "(json['$fieldName'] as List?)?.cast<$innerDartType>() ?? []";
    }
    if (algebraicType.containsKey('String')) {
      return "(json['$fieldName'] as String?) ?? ''";
    }
    if (algebraicType.containsKey('Bool')) {
      return "(json['$fieldName'] as bool?) ?? false";
    }
    if (algebraicType.containsKey('F32') || algebraicType.containsKey('F64')) {
      return "(json['$fieldName'] as num?)?.toDouble() ?? 0.0";
    }
    if (_isIntType(algebraicType)) {
      return "(json['$fieldName'] as int?) ?? 0";
    }
    return "json['$fieldName']";
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Recursively collect import statements for Ref types (excluding Identity).
  void _collectRefImports(
      Map<String, dynamic> algebraicType, Set<String> imports) {
    // Option inner type
    if (TypeMapper.isOptionType(algebraicType)) {
      final innerType = TypeMapper.getOptionInnerType(algebraicType);
      if (innerType != null) {
        _collectRefImports(innerType, imports);
      }
      return;
    }

    // Array element type
    if (TypeMapper.isArrayType(algebraicType)) {
      final elemType = TypeMapper.getArrayElementType(algebraicType);
      if (elemType != null) {
        _collectRefImports(elemType, imports);
      }
      return;
    }

    // Ref types — Identity comes from SDK, skip import
    if (TypeMapper.isRefType(algebraicType)) {
      if (TypeMapper.isIdentityType(algebraicType,
          typeSpace: schema.typeSpace, typeDefs: schema.types)) {
        return; // Identity is re-exported from the SDK
      }
      final refTypeName =
          TypeMapper.getRefTypeName(algebraicType, schema.types);
      if (refTypeName != null) {
        final fileName = _toSnakeCase(refTypeName);
        imports.add("import '$fileName.dart';");
      }
    }
  }

  bool _isTimestamp(Map<String, dynamic> algebraicType) {
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _isIntType(Map<String, dynamic> algebraicType) {
    return algebraicType.containsKey('U8') ||
        algebraicType.containsKey('U16') ||
        algebraicType.containsKey('U32') ||
        algebraicType.containsKey('I8') ||
        algebraicType.containsKey('I16') ||
        algebraicType.containsKey('I32');
  }

  String _toPascalCase(String input) {
    return input.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join('');
  }

  String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }

  String _toCamelCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;

    final first = parts.first.toLowerCase();
    final rest = parts.skip(1).map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join('');

    return first + rest;
  }
}
