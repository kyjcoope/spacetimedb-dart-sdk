# Testing Guide

## Prerequisites

1. **Install SpacetimeDB CLI**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://install.spacetimedb.com | sh
   ```
   Or visit: https://spacetimedb.com/install

2. **Verify Installation**
   ```bash
   spacetime --version
   ```

## Identity Management

**Important**: Each developer gets their own local SpacetimeDB identity and database instance.

### How It Works

When you run the setup script for the first time:
1. A local identity named `spacetimedb_dart_sdk_test` is created
2. Cryptographic keys are stored in `~/.config/spacetime/` (outside the repo)
3. Your local `notesdb` database is created and owned by your identity
4. **No credentials are stored in or shared via the repository**

### What This Means

- ✅ Each developer has an **isolated local database**
- ✅ No conflicts between developers
- ✅ No credentials to manage or share
- ✅ Keys are **never committed** to git (they're in your home directory)
- ✅ Setup is automatic - just run the script

### Identity Storage Location

Your identity keys are stored locally at:
- **macOS/Linux**: `~/.config/spacetime/` or `~/.spacetime/`
- **Windows**: `%LocalAppData%\SpacetimeDB\`

These files are **outside the repository** and are unique to your machine.

## Quick Start

### Option 1: Fully Automated (Recommended)

Just run the tests - setup happens automatically:

```bash
dart test
```

**How it works:**
- Integration tests use `setUpAll(ensureTestEnvironment)` from `test/helpers/integration_test_helper.dart`
- On first run, automatically:
  1. Checks SpacetimeDB CLI is installed
  2. Ensures local server is running
  3. Builds the `spacetime_test_module`
  4. Publishes the module as `notesdb` database
  5. Generates Dart code from the schema to `test/generated/`
- Uses a `.test_setup_done` marker with 5-minute TTL to avoid redundant setups
- Subsequent test runs skip setup if done recently

### Option 2: Manual Setup Scripts

If you prefer manual control, run the setup script before testing:

```bash
# Using bash script
./tool/setup_test_db.sh

# Or using Dart
dart run tool/setup_tests.dart

# Then run tests
dart test
```

### Option 3: Fully Manual Setup

```bash
# 1. Start SpacetimeDB
spacetime start

# 2. Build and publish test module
cd spacetime_test_module
spacetime build
spacetime publish --clear-database notesdb
cd ..

# 3. Generate test code from schema
dart run spacetimedb_dart_sdk:generate \
  -d notesdb \
  -s http://localhost:3000 \
  -o test/generated

# 4. Run tests
dart test
```

## Test Structure

### Unit Tests (No DB Required)
- `test/codec/bsatn_test.dart` - BSATN encoding/decoding
- `test/messages/message_decoder_test.dart` - Message decoding
- `test/connection/connection_test.dart` - Connection state

### Integration Tests (Require DB)
- `test/integration/live_test.dart` - Live connection and sync
- `test/integration/crud_test.dart` - Create, update, delete operations
- `test/integration/reducer_test.dart` - Reducer calling
- `test/integration/error_handling_test.dart` - Error scenarios
- `test/integration/message_types_test.dart` - Message handling
- `test/integration/sum_types_test.dart` - Sum types (enums) with generated code

### Code Generation Tests (Require DB)
- `test/codegen/schema_fetcher_test.dart` - Schema fetching
- `test/codegen/generation_integration_test.dart` - Code generation + analysis

**CRITICAL: Generated Code Policy**

**All integration tests MUST use code from `test/generated/` - NO manual decoders allowed.**

**Why this matters:**
1. **Tests the Real Product**: Developers use generated code, so tests should too
   - Generator syntax errors → tests fail to compile ✓
   - Generator missing imports → tests fail ✓
   - Generator wrong types → tests fail assertions ✓

2. **Eliminates Drift**: Manual test fixtures can get out of sync with generator
   - You change generator logic → manual fixtures unchanged → tests pass but product breaks ✗
   - Using `test/generated/` → always synchronized ✓

3. **Dogfooding**: We use our own generator's output, catching issues early

**Correct Usage:**
```dart
// ✅ CORRECT - Import from test/generated/
import '../generated/note.dart';
import '../generated/reducer_args.dart';
import '../helpers/integration_test_helper.dart';

@Tags(['integration'])

void main() {
  setUpAll(ensureTestEnvironment); // Auto-generates code to test/generated/

  // Use the actual generated classes
  subManager.cache.registerDecoder<Note>('note', NoteDecoder());
}
```

**Forbidden:**
```dart
// ❌ WRONG - Manual decoder files create drift
import 'note_decoder.dart'; // DON'T create these!
```

**Files using generated code:**
- All tests in `test/integration/` (except `codegen_e2e_test.dart` which generates to temp dir)
- Automatically generated before tests run via `setUpAll(ensureTestEnvironment)`

## Running Specific Tests

```bash
# Run only unit tests (fast, no DB needed)
dart test test/codec/
dart test test/messages/message_decoder_test.dart

# Run only integration tests
dart test test/integration/

# Run only codegen tests
dart test test/codegen/

# Run a specific test file
dart test test/integration/crud_test.dart

# Run with verbose output
dart test -r expanded
```

## Troubleshooting

### "Connection refused" errors
SpacetimeDB is not running. Start it with:
```bash
spacetime start
```

### "Database 'notesdb' not found"
Test module not published. Run setup:
```bash
./tool/setup_test_db.sh
```

### Tests timeout
Integration tests may take longer. They have 60s timeout by default (configured in `dart_test.yaml`).

### "spacetime: command not found"
SpacetimeDB CLI not installed or not in PATH. Install from https://spacetimedb.com/install

## Clean Up

```bash
# Stop SpacetimeDB
spacetime server stop

# Delete test database
spacetime delete notesdb

# Remove setup marker
rm .test_setup_done
```

## CI/CD Integration

For GitHub Actions or other CI systems, use the setup script in your workflow:

```yaml
- name: Setup SpacetimeDB
  run: |
    curl --proto '=https' --tlsv1.2 -sSf https://install.spacetimedb.com | sh
    export PATH="$HOME/.spacetime/bin:$PATH"
    ./tool/setup_test_db.sh

- name: Run tests
  run: dart test
```

## Test Module

The test module is located in `spacetime_test_module/` and provides:
- `Note` table (id, title, content, timestamp, status)
- `NoteStatus` enum (Draft, Published, Archived) - for testing sum types
- `create_note` reducer
- `update_note` reducer
- `delete_note` reducer
- `init` reducer

This module must be running on the local SpacetimeDB instance for integration tests to pass.

## Generated Test Code

The `test/generated/` directory contains Dart code generated from the `notesdb` schema:
- `note.dart` - Note table class with proper Ref type resolution
- `note_status.dart` - NoteStatus sealed class hierarchy (sum type)
- `reducers.dart` - Type-safe reducer methods
- `reducer_args.dart` - Strongly-typed reducer argument classes
- `client.dart` - High-level SpacetimeDbClient

**Important**: This directory is generated by the setup scripts and is required for `test/integration/sum_types_test.dart` to compile and run. If you see import errors, run the setup script.
