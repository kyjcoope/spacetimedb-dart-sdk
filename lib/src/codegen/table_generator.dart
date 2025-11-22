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
    buf.writeln("import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");

    final productType = schema.typeSpace.types[table.productTypeRef].product;
    if (productType == null) {
      throw Exception('Table ${table.name} has no product type');
    }

    // Collect imports for Ref types
    final imports = <String>{};
    for (final element in productType.elements) {
      if (TypeMapper.isRefType(element.algebraicType)) {
        final refTypeName = TypeMapper.getRefTypeName(
          element.algebraicType,
          schema.types,
        );
        if (refTypeName != null) {
          final fileName = _toSnakeCase(refTypeName);
          imports.add("import '$fileName.dart';");
        }
      }
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
      final fieldName = element.name ?? 'unknown';
      final dartType = TypeMapper.toDartType(
        element.algebraicType,
        typeSpace: schema.typeSpace,
        typeDefs: schema.types,
      );
      buf.writeln('  final $dartType $fieldName;');
    }
    buf.writeln();

    // Constructor
    buf.writeln('  $className({');
    for (final element in productType.elements) {
      final fieldName = element.name ?? 'unknown';
      buf.writeln('    required this.$fieldName,');
    }
    buf.writeln('  });');
    buf.writeln();

    // encodeBsatn method
    buf.writeln('  void encodeBsatn(BsatnEncoder encoder) {');
    for (final element in productType.elements) {
      final fieldName = element.name ?? 'unknown';

      if (TypeMapper.isRefType(element.algebraicType)) {
        // For Ref types, call the type's encode method
        buf.writeln('    $fieldName.encode(encoder);');
      } else {
        final method = TypeMapper.getEncoderMethod(element.algebraicType);
        buf.writeln('    encoder.$method($fieldName);');
      }
    }
    buf.writeln('  }');
    buf.writeln();

    // decodeBsatn method
    buf.writeln('  static $className decodeBsatn(BsatnDecoder decoder) {');
    buf.writeln('    return $className(');
    for (final element in productType.elements) {
      final fieldName = element.name ?? 'unknown';

      if (TypeMapper.isRefType(element.algebraicType)) {
        // For Ref types, call the type's decode factory
        final typeName = TypeMapper.toDartType(
          element.algebraicType,
          typeSpace: schema.typeSpace,
          typeDefs: schema.types,
        );
        buf.writeln('      $fieldName: $typeName.decode(decoder),');
      } else {
        final method = TypeMapper.getDecoderMethod(element.algebraicType);
        buf.writeln('      $fieldName: decoder.$method(),');
      }
    }
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();

    // Close class
    buf.writeln('}');
    buf.writeln();

    // Generate Decoder class
    buf.writeln('class ${className}Decoder implements RowDecoder<$className> {');
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
        final pkFieldName = pkElement.name ?? 'unknown';
        final pkDartType = TypeMapper.toDartType(
          pkElement.algebraicType,
          typeSpace: schema.typeSpace,
          typeDefs: schema.types,
        );
        // Use dynamic to support any PK type (int, String, etc.)
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
    buf.writeln('}');

    return buf.toString();
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
}
