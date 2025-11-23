// ignore_for_file: avoid_print
import 'dart:io';

/// Global test setup that runs once before all tests
///
/// This ensures SpacetimeDB is running and the test module is published.
/// Call this from dart_test.yaml's setupAll hook.
Future<void> setupTestEnvironment() async {
  // Check if already set up (to avoid multiple setups in parallel test runs)
  final marker = File('.test_setup_done');
  if (await marker.exists()) {
    final timestamp = await marker.readAsString();
    final setupTime = DateTime.parse(timestamp);

    // If setup was done less than 5 minutes ago, skip
    if (DateTime.now().difference(setupTime).inMinutes < 5) {
      print('✅ Test environment already set up ($setupTime)');
      return;
    }
  }

  print('🚀 Setting up SpacetimeDB test environment...');

  // Check if spacetime CLI is installed
  try {
    final result = await Process.run('spacetime', ['--version']);
    if (result.exitCode != 0) throw Exception('CLI check failed');
  } catch (e) {
    throw Exception(
      'SpacetimeDB CLI not found. Install from https://spacetimedb.com/install'
    );
  }

  // Check if SpacetimeDB is running
  final statusCheck = await Process.run('spacetime', ['server', 'status']);
  if (statusCheck.exitCode != 0) {
    print('Starting SpacetimeDB server...');
    Process.start('spacetime', ['start'], mode: ProcessStartMode.detached);
    await Future.delayed(const Duration(seconds: 3));
  }

  // Build and publish test module
  final testModuleDir = Directory('spacetime_test_module');
  if (!await testModuleDir.exists()) {
    throw Exception('Test module directory not found: ${testModuleDir.path}');
  }

  // Build
  print('Building test module...');
  final buildResult = await Process.run(
    'spacetime',
    ['build'],
    workingDirectory: testModuleDir.path,
  );
  if (buildResult.exitCode != 0) {
    throw Exception('Build failed: ${buildResult.stderr}');
  }

  // Check if database already exists
  final listResult = await Process.run('spacetime', ['list']);
  final dbExists = listResult.stdout.toString().contains('notesdb');

  if (dbExists) {
    print('Database "notesdb" already exists, skipping publish...');
  } else {
    // Publish
    print('Publishing test module...');
    final publishResult = await Process.run(
      'spacetime',
      ['publish', 'notesdb'],
      workingDirectory: testModuleDir.path,
    );
    if (publishResult.exitCode != 0) {
      throw Exception('Publish failed: ${publishResult.stderr}');
    }
  }

  // Generate test code from notesdb schema
  print('Generating test code from notesdb schema...');
  final generateResult = await Process.run(
    'dart',
    [
      'run',
      'spacetimedb_dart_sdk:generate',
      '-d', 'notesdb',
      '-s', 'http://localhost:3000',
      '-o', 'test/generated',
    ],
  );
  if (generateResult.exitCode != 0) {
    throw Exception('Code generation failed: ${generateResult.stderr}');
  }
  print('✅ Generated test code in test/generated/');

  // Mark setup as done
  await marker.writeAsString(DateTime.now().toIso8601String());

  print('✅ Test environment ready\n');
}
