import 'package:spacetimedb_dart_sdk/src/codegen/client_generator.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/reducer_generator.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/models.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/table_generator.dart';
import 'dart:io';

class DartGenerator {
  final DatabaseSchema schema;
  DartGenerator(this.schema);

  List<GeneratedFile> generateAll() {
    final files = <GeneratedFile>[];

    for (final table in schema.tables) {
      final generator = TableGenerator(schema, table);
      files.add(GeneratedFile(
        filename: '${table.name}.dart',
        content: generator.generate(),
      ));
    }

    if (schema.reducers.isNotEmpty) {
      final generator = ReducerGenerator(schema.reducers);
      files.add(GeneratedFile(
          filename: 'reducers.dart', content: generator.generate()));

      // Generate reducer argument classes and decoders
      files.add(GeneratedFile(
          filename: 'reducer_args.dart',
          content: generator.generateArgDecoders()));
    }

    final clientGenerator = ClientGenerator(schema);
    files.add(GeneratedFile(
        filename: 'client.dart', content: clientGenerator.generate()));

    return files;
  }

  Future<void> writeToDirectory(String outputPath) async {
    final dir = Directory(outputPath);
    await dir.create(recursive: true);

    final files = generateAll();

    for (final file in files) {
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsString(file.content);
      print('  ✓ Generated $path');
    }
  }
}

class GeneratedFile {
  final String filename;
  final String content;

  GeneratedFile({required this.filename, required this.content});
}
