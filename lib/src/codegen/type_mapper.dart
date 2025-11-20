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

  static String toDartType(Map<String, dynamic> algebraicType) {
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
}
