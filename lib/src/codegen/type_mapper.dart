import 'models/type_models.dart';

class TypeMapper {
  // Type mappings
  static const _dartTypeMap = {
    'U8': 'int',
    'U16': 'int',
    'U32': 'int',
    'U64': 'Int64',
    'U128': 'BigInt',
    'I8': 'int',
    'I16': 'int',
    'I32': 'int',
    'I64': 'Int64',
    'I128': 'BigInt',
    'F32': 'double',
    'F64': 'double',
    'Bool': 'bool',
    'String': 'String',
    'Timestamp': 'Int64',
  };

  static const _encoderMethodMap = {
    'U8': 'writeU8',
    'U16': 'writeU16',
    'U32': 'writeU32',
    'U64': 'writeU64',
    'I8': 'writeI8',
    'I16': 'writeI16',
    'I32': 'writeI32',
    'I64': 'writeI64',
    'F32': 'writeF32',
    'F64': 'writeF64',
    'Bool': 'writeBool',
    'String': 'writeString',
    'Timestamp': 'writeU64',
  };

  static const _decoderMethodMap = {
    'U8': 'readU8',
    'U16': 'readU16',
    'U32': 'readU32',
    'U64': 'readU64',
    'I8': 'readI8',
    'I16': 'readI16',
    'I32': 'readI32',
    'I64': 'readI64',
    'F32': 'readF32',
    'F64': 'readF64',
    'Bool': 'readBool',
    'String': 'readString',
    'Timestamp': 'readU64',
  };

  /// SDK-internal type names that generated decoder classes must not collide with.
  static const _reservedDecoderNames = {
    'MessageDecoder',
    'BsatnDecoder',
    'BsatnEncoder',
    'RowDecoder',
  };

  // ---------------------------------------------------------------------------
  // Option (Sum with some/none) detection
  // ---------------------------------------------------------------------------

  /// Checks whether [algebraicType] is a SpacetimeDB `Option<T>`.
  ///
  /// Safe detection: must be a Sum with exactly 2 variants, one named "some"
  /// (1 payload element) and one named "none" (0 payload elements).
  /// Finds the "some" variant by name, NOT by index.
  static bool isOptionType(Map<String, dynamic> algebraicType) {
    if (!algebraicType.containsKey('Sum')) return false;
    final sum = algebraicType['Sum'];
    if (sum is! Map || !sum.containsKey('variants')) return false;
    final variants = sum['variants'] as List;
    if (variants.length != 2) return false;

    bool hasSome = false;
    bool hasNone = false;

    for (final v in variants) {
      final nameObj = v['name'];
      final name = (nameObj is Map ? nameObj['some'] : nameObj)
              ?.toString()
              .toLowerCase() ??
          '';
      final elements = _variantPayloadElements(v);

      if (name == 'some' && elements == 1) hasSome = true;
      if (name == 'none' && elements == 0) hasNone = true;
    }

    return hasSome && hasNone;
  }

  /// Extracts the inner algebraic type from the "some" variant of an Option Sum.
  static Map<String, dynamic>? getOptionInnerType(
      Map<String, dynamic> algebraicType) {
    if (!isOptionType(algebraicType)) return null;
    final variants = (algebraicType['Sum'] as Map)['variants'] as List;

    for (final v in variants) {
      final nameObj = v['name'];
      final name = (nameObj is Map ? nameObj['some'] : nameObj)
              ?.toString()
              .toLowerCase() ??
          '';
      if (name == 'some') {
        final at = v['algebraic_type'];
        if (at is Map && at.containsKey('Product')) {
          final product = at['Product'];
          if (product is Map && product.containsKey('elements')) {
            final elements = product['elements'] as List;
            if (elements.isNotEmpty) {
              return (elements[0]['algebraic_type'] as Map<String, dynamic>?) ??
                  {};
            }
          }
        }
        return at is Map<String, dynamic> ? at : {};
      }
    }
    return null;
  }

  /// Returns the number of payload elements in a Sum variant, or -1 on error.
  static int _variantPayloadElements(dynamic variant) {
    final at = variant['algebraic_type'];
    if (at is Map && at.containsKey('Product')) {
      final product = at['Product'];
      if (product is Map && product.containsKey('elements')) {
        return (product['elements'] as List).length;
      }
    }
    // A variant with no algebraic_type or an empty product has 0 elements.
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Identity detection
  // ---------------------------------------------------------------------------

  /// Checks whether [algebraicType] is an Identity type (resolves through Ref
  /// to a TypeDef named "Identity").
  static bool isIdentityType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    if (!algebraicType.containsKey('Ref')) return false;
    if (typeDefs == null) return false;

    final typeIndex = algebraicType['Ref'] as int;
    for (final td in typeDefs) {
      if (td.typeRef == typeIndex && td.name.toLowerCase() == 'identity') {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Array detection
  // ---------------------------------------------------------------------------

  /// Checks whether [algebraicType] is an Array/Vec type.
  static bool isArrayType(Map<String, dynamic> algebraicType) {
    return algebraicType.containsKey('Array');
  }

  /// Returns the element algebraic type for an Array, or null.
  static Map<String, dynamic>? getArrayElementType(
      Map<String, dynamic> algebraicType) {
    if (!isArrayType(algebraicType)) return null;
    final inner = algebraicType['Array'];
    return inner is Map<String, dynamic> ? inner : null;
  }

  // ---------------------------------------------------------------------------
  // Name collision avoidance
  // ---------------------------------------------------------------------------

  /// Returns the decoder class name for a table, avoiding SDK internal collisions.
  static String getDecoderClassName(String tableName) {
    final pascalName = _toPascalCase(tableName);
    final candidateName = '${pascalName}Decoder';

    if (_reservedDecoderNames.contains(candidateName)) {
      return '${pascalName}TableDecoder';
    }
    return candidateName;
  }

  // ---------------------------------------------------------------------------
  // Core type mapping
  // ---------------------------------------------------------------------------

  /// Map algebraic type to Dart type string.
  /// Pass typeSpace and typeDefs to resolve Ref types.
  static String toDartType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    // 1. Handle Option<T> → T?
    if (isOptionType(algebraicType)) {
      final innerType = getOptionInnerType(algebraicType);
      if (innerType != null) {
        final dartInner =
            toDartType(innerType, typeSpace: typeSpace, typeDefs: typeDefs);
        return '$dartInner?';
      }
    }

    // 2. Handle Timestamp (Product with __timestamp_micros_since_unix_epoch__)
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'Int64';
          }
        }
      }
    }

    // 3. Handle Ref types (Identity special case, then generic)
    if (algebraicType.containsKey('Ref')) {
      if (isIdentityType(algebraicType,
          typeSpace: typeSpace, typeDefs: typeDefs)) {
        return 'Identity';
      }

      final typeIndex = algebraicType['Ref'] as int;
      if (typeSpace != null && typeDefs != null) {
        final typeDef = typeDefs.firstWhere(
          (td) => td.typeRef == typeIndex,
          orElse: () =>
              TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
        );

        if (typeDef.name.isNotEmpty) {
          return _toPascalCase(typeDef.name);
        }
      }

      return 'dynamic';
    }

    // 4. Handle Array types (recursive)
    if (algebraicType.containsKey('Array')) {
      final elementType = algebraicType['Array'];
      final dartInnerType = toDartType(
        elementType is Map<String, dynamic> ? elementType : <String, dynamic>{},
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return 'List<$dartInnerType>';
    }

    // 5. Handle primitive types
    for (final key in _dartTypeMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _dartTypeMap[key]!;
      }
    }

    return 'dynamic';
  }

  /// Get the BSATN encoder method for a primitive algebraic type.
  /// For Option/Array/Identity, use the dedicated is*Type() helpers instead.
  static String getEncoderMethod(Map<String, dynamic> algebraicType) {
    // Handle Timestamp
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'writeI64';
          }
        }
      }
    }

    for (final key in _encoderMethodMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _encoderMethodMap[key]!;
      }
    }
    return 'write';
  }

  /// Get the BSATN decoder method for a primitive algebraic type.
  /// For Option/Array/Identity, use the dedicated is*Type() helpers instead.
  static String getDecoderMethod(Map<String, dynamic> algebraicType) {
    // Handle Timestamp
    if (algebraicType.containsKey('Product')) {
      final product = algebraicType['Product'];
      if (product is Map && product.containsKey('elements')) {
        final elements = product['elements'] as List;
        if (elements.length == 1) {
          final element = elements[0];
          if (element['name'] != null &&
              element['name']['some'] ==
                  '__timestamp_micros_since_unix_epoch__') {
            return 'readI64';
          }
        }
      }
    }

    for (final key in _decoderMethodMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _decoderMethodMap[key]!;
      }
    }
    return 'read';
  }

  /// Check if a type is a Ref (reference to another type)
  static bool isRefType(Map<String, dynamic> algebraicType) {
    return algebraicType.containsKey('Ref');
  }

  /// Get the type name for a Ref type
  static String? getRefTypeName(
    Map<String, dynamic> algebraicType,
    List<TypeDef> typeDefs,
  ) {
    if (!isRefType(algebraicType)) return null;

    final typeIndex = algebraicType['Ref'] as int;
    final typeDef = typeDefs.firstWhere(
      (td) => td.typeRef == typeIndex,
      orElse: () =>
          TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
    );

    return typeDef.name.isNotEmpty ? typeDef.name : null;
  }

  static String _toPascalCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }
}
