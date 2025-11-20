import 'dart:io';

/// Finds the SDK root directory by searching upward for pubspec.yaml
/// containing 'name: spacetimedb_dart_sdk'.
///
/// This is needed because tests may run from different working directories
/// (root or test/), so relative paths don't work reliably.
String findSdkRoot() {
  var current = Directory.current;
  while (true) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      final content = pubspec.readAsStringSync();
      if (content.contains('name: spacetimedb_dart_sdk')) {
        return current.path;
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw Exception('Could not find spacetimedb_dart_sdk root');
    }
    current = parent;
  }
}
