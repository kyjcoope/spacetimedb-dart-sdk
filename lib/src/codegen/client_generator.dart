import 'package:spacetimedb_dart_sdk/src/codegen/models.dart';
import 'package:spacetimedb_dart_sdk/src/codegen/view_generator.dart';

/// Generates main client class
class ClientGenerator {
  final DatabaseSchema schema;
  late final ViewGenerator _viewGenerator;

  ClientGenerator(this.schema) {
    _viewGenerator = ViewGenerator(schema);
  }

  /// Generate client class
  String generate() {
    final buf = StringBuffer();

    // Header
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln();
    buf.writeln("import 'dart:async';");
    buf.writeln();
    buf.writeln("import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");
    buf.writeln("import 'reducers.dart';");

    // Import all table files
    for (final table in schema.tables) {
      buf.writeln("import '${table.name}.dart';");
    }
    buf.writeln();

    // Client class name (always SpacetimeDbClient for consistency)
    final clientName = 'SpacetimeDbClient';

    buf.writeln('class $clientName {');
    buf.writeln('  final SpacetimeDbConnection connection;');
    buf.writeln('  final SubscriptionManager subscriptions;');
    buf.writeln('  late final Reducers reducers;');
    buf.writeln();

    // Table cache getters
    for (final table in schema.tables) {
      final tableName = _toCamelCase(table.name);
      final className = _toPascalCase(table.name);
      buf.writeln('  TableCache<$className> get $tableName {');
      buf.writeln("    return subscriptions.cache.getTableByTypedName<$className>('${table.name}');");
      buf.writeln('  }');
      buf.writeln();
    }

    // View cache getters (views that return table rows)
    for (final view in schema.views) {
      final rowType = _viewGenerator.getViewRowType(view);
      if (rowType != null) {
        final viewName = _toCamelCase(view.name);
        final pattern = _viewGenerator.getViewReturnPattern(view);

        switch (pattern) {
          case ViewReturnType.array:
            // Vec<T> - returns TableCache<T>
            buf.writeln('  TableCache<$rowType> get $viewName {');
            buf.writeln("    return subscriptions.cache.getTableByTypedName<$rowType>('${view.name}');");
            buf.writeln('  }');
            break;

          case ViewReturnType.option:
            // Option<T> - returns T? (single optional row)
            buf.writeln('  $rowType? get $viewName {');
            buf.writeln("    final cache = subscriptions.cache.getTableByTypedName<$rowType>('${view.name}');");
            buf.writeln('    final rows = cache.iter().toList();');
            buf.writeln('    return rows.isEmpty ? null : rows.first;');
            buf.writeln('  }');
            break;

          case ViewReturnType.single:
            // T - returns T (single row, non-optional)
            buf.writeln('  $rowType get $viewName {');
            buf.writeln("    final cache = subscriptions.cache.getTableByTypedName<$rowType>('${view.name}');");
            buf.writeln('    return cache.iter().first;');
            buf.writeln('  }');
            break;

          case ViewReturnType.unknown:
            // Skip unknown patterns
            continue;
        }
        buf.writeln();
      }
    }

    // Constructor
    buf.writeln('  $clientName._({');
    buf.writeln('    required this.connection,');
    buf.writeln('    required this.subscriptions,');
    buf.writeln('  }) {');
    buf.writeln('    reducers = Reducers(connection);');
    buf.writeln('  }');
    buf.writeln();

    // Static connect method
    buf.writeln('  static Future<$clientName> connect({');
    buf.writeln('    required String host,');
    buf.writeln('    required String database,');
    buf.writeln('    String? authToken,');
    buf.writeln('    List<String>? initialSubscriptions,');
    buf.writeln('    Duration subscriptionTimeout = const Duration(seconds: 10),');
    buf.writeln('  }) async {');
    buf.writeln("    final connection = SpacetimeDbConnection(");
    buf.writeln('      host: host,');
    buf.writeln('      database: database,');
    buf.writeln('      authToken: authToken,');
    buf.writeln('    );');
    buf.writeln();
    buf.writeln('    final subscriptionManager = SubscriptionManager(connection);');
    buf.writeln();

    // Auto-register table decoders (Phase 1: Static Registration)
    buf.writeln('    // Auto-register table decoders');
    for (final table in schema.tables) {
      final className = _toPascalCase(table.name);
      buf.writeln("    subscriptionManager.cache.registerDecoder<$className>('${table.name}', ${className}Decoder());");
    }
    buf.writeln();

    // Auto-register view decoders (Phase 1: Static Registration)
    buf.writeln('    // Auto-register view decoders');
    for (final view in schema.views) {
      final rowType = _viewGenerator.getViewRowType(view);
      if (rowType != null) {
        buf.writeln("    subscriptionManager.cache.registerDecoder<$rowType>('${view.name}', ${rowType}Decoder());");
      }
    }
    buf.writeln();

    buf.writeln('    final client = $clientName._(');
    buf.writeln('      connection: connection,');
    buf.writeln('      subscriptions: subscriptionManager,');
    buf.writeln('    );');
    buf.writeln();
    buf.writeln('    await connection.connect();');
    buf.writeln();
    buf.writeln('    if (initialSubscriptions != null && initialSubscriptions.isNotEmpty) {');
    buf.writeln('      try {');
    buf.writeln('        // Wait for initial subscription data to load with timeout');
    buf.writeln('        await subscriptionManager.subscribe(initialSubscriptions).timeout(subscriptionTimeout);');
    buf.writeln('      } on TimeoutException {');
    buf.writeln('        // Log warning and continue - client is still usable with partial data');
    buf.writeln(r"        print('Warning: Initial subscriptions timed out after ${subscriptionTimeout.inSeconds}s. Data may be incomplete.');");
    buf.writeln('      }');
    buf.writeln('    }');
    buf.writeln();
    buf.writeln('    return client;');
    buf.writeln('  }');
    buf.writeln();

    // Disconnect method
    buf.writeln('  Future<void> disconnect() async {');
    buf.writeln('    await connection.disconnect();');
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  String _toPascalCase(String input) {
    return input.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join('');
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
