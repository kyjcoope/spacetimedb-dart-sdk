import 'models/type_models.dart';

class TypeMapper {
  // Type mappings
  static const _dartTypeMap = {
    'U8': 'int',
    'U16': 'int',
    'U32': 'int',
    'U64': 'int',
    'I8': 'int',
    'I16': 'int',
    'I32': 'int',
    'I64': 'int',
    'F32': 'double',
    'F64': 'double',
    'Bool': 'bool',
    'String': 'String',
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
  };

  /// Map algebraic type to Dart type string
  /// Pass typeSpace and typeDefs to resolve Ref types
  static String toDartType(
    Map<String, dynamic> algebraicType, {
    TypeSpace? typeSpace,
    List<TypeDef>? typeDefs,
  }) {
    // 1. Handle Ref types (references to other types)
    if (algebraicType.containsKey('Ref')) {
      final typeIndex = algebraicType['Ref'] as int;

      if (typeSpace != null && typeDefs != null) {
        // Find the TypeDef that references this type
        final typeDef = typeDefs.firstWhere(
          (td) => td.typeRef == typeIndex,
          orElse: () => TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
        );

        if (typeDef.name.isNotEmpty) {
          return _toPascalCase(typeDef.name);
        }
      }

      return 'dynamic'; // Fallback if we can't resolve
    }

    // 2. Handle Array types (recursive)
    if (algebraicType.containsKey('Array')) {
      final elementType = algebraicType['Array'];
      final dartInnerType = toDartType(
        elementType,
        typeSpace: typeSpace,
        typeDefs: typeDefs,
      );
      return 'List<$dartInnerType>';
    }

    // 3. Handle primitive types
    for (final key in _dartTypeMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _dartTypeMap[key]!;
      }
    }

    return 'dynamic';
  }

  static String getEncoderMethod(Map<String, dynamic> algebraicType) {
    for (final key in _encoderMethodMap.keys) {
      if (algebraicType.containsKey(key)) {
        return _encoderMethodMap[key]!;
      }
    }
    return 'write';
  }

  static String getDecoderMethod(Map<String, dynamic> algebraicType) {
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
      orElse: () => TypeDef(scope: [], name: '', typeRef: -1, customOrdering: false),
    );

    return typeDef.name.isNotEmpty ? typeDef.name : null;
  }

  static String _toPascalCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  static String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}
