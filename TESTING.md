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

### Option 1: Automatic Setup (Recommended)

Run the setup script before testing:

```bash
# Using bash script
./tool/setup_test_db.sh

# Or using Dart
dart run tool/setup_tests.dart

# Then run tests
dart test
```

### Option 2: Manual Setup

```bash
# 1. Start SpacetimeDB
spacetime start

# 2. Build and publish test module
cd spacetime_test_module
spacetime build
spacetime publish --clear-database notesdb
cd ..

# 3. Run tests
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

### Code Generation Tests (Require DB)
- `test/codegen/schema_fetcher_test.dart` - Schema fetching
- `test/codegen/generation_integration_test.dart` - Code generation + analysis

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
- `Note` table (id, title, content, timestamp)
- `create_note` reducer
- `update_note` reducer
- `init` reducer

This module must be running on the local SpacetimeDB instance for integration tests to pass.
