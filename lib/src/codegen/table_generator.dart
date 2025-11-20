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
    buf.writeln();

    final productType = schema.typeSpace.types[table.productTypeRef].product;
    if (productType == null) {
      throw Exception('Table ${table.name} has no product type');
    }

    final className = _toPascalCase(table.name);
    buf.writeln('class $className {');

    // Fields
    for (final element in productType.elements) {
      final fieldName = element.name ?? 'unknown';
      final dartType = TypeMapper.toDartType(element.algebraicType);
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
      final method = TypeMapper.getEncoderMethod(element.algebraicType);
      buf.writeln('    encoder.$method($fieldName);');
    }
    buf.writeln('  }');
    buf.writeln();

    // decodeBsatn method
    buf.writeln('  static $className decodeBsatn(BsatnDecoder decoder) {');
    buf.writeln('    return $className(');
    for (final element in productType.elements) {
      final fieldName = element.name ?? 'unknown';
      final method = TypeMapper.getDecoderMethod(element.algebraicType);
      buf.writeln('      $fieldName: decoder.$method(),');
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
    buf.writeln('  int? getPrimaryKey($className row) {');

    // Find primary key column (first element for now)
    if (productType.elements.isNotEmpty) {
      final firstField = productType.elements.first.name ?? 'unknown';
      buf.writeln('    return row.$firstField;');
    } else {
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
}
