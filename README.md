# SpacetimeDB Dart SDK

A complete Dart SDK for building real-time multiplayer applications with SpacetimeDB.

## Features

### Core SDK ✅
- **WebSocket Connection** - Auto-reconnect with exponential backoff
- **BSATN Encoding/Decoding** - Binary serialization for all SpacetimeDB types
- **Registry Pattern Cache** - Name-based decoder registration with runtime activation
- **Subscription Management** - Real-time SQL query subscriptions with timeout safety
- **Reducer Calling** - Type-safe server-side function calls
- **All Server Messages** - Complete protocol implementation
- **Type-Safe Casts** - No unsafe `as` casts, all type checks with promotion
- **Comprehensive Tests** - All code passes `dart analyze`

### Code Generation ✅
- **Schema Extraction** - Extract from network, WASM, or project builds
- **Table Generation** - Auto-generate typed table classes with BSATN codecs
- **Reducer Generation** - Type-safe reducer method generation
- **View Support** - Full support for SpacetimeDB views:
  - `Vec<T>` views → `TableCache<T>` accessors
  - `Option<T>` views → `T?` single-row accessors
  - `T` views → `T` non-nullable single-row accessors
- **Client Generation** - Complete client class with table/view accessors
- **CLI Tool** - `dart run spacetimedb_dart_sdk:generate`

## Getting Started

### Prerequisites

1. Install SpacetimeDB CLI:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://install.spacetimedb.com | sh
   ```

2. Add dependency to `pubspec.yaml`:
   ```yaml
   dependencies:
     spacetimedb_dart_sdk:
       path: ../spacetimedb_dart_sdk
   ```

### Generate Client Code

Generate type-safe client code from your SpacetimeDB schema:

```bash
dart run spacetimedb_dart_sdk:generate -d your_database -o lib/generated
```

## Usage

```dart
import 'package:your_app/generated/client.dart';

// Connect to SpacetimeDB with timeout safety
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'your_database',
  initialSubscriptions: ['SELECT * FROM your_table'],
  subscriptionTimeout: Duration(seconds: 10), // Optional, defaults to 10s
);

// Call reducers
await client.reducers.createItem(
  name: 'Item name',
  value: 42,
);

// Access table data (TableCache<T>)
for (final item in client.yourTable.iter()) {
  print('Item: ${item.name}');
}

// Access views
// Vec<T> view - returns TableCache<T>
for (final item in client.allItems.iter()) {
  print('Item: ${item.name}');
}

// Option<T> view - returns T? (single optional row)
final firstItem = client.firstItem; // Note? or null
if (firstItem != null) {
  print('First item: ${firstItem.name}');
}

// T view - returns T (single row, throws if empty)
final latestItem = client.latestItem; // Note (non-nullable)
print('Latest: ${latestItem.name}');

// Listen to changes with streams
client.yourTable.insertStream.listen((item) {
  print('New item: ${item.name}');
});

client.yourTable.updateStream.listen((update) {
  print('Updated: ${update.oldRow.name} → ${update.newRow.name}');
});

client.yourTable.deleteStream.listen((item) {
  print('Deleted: ${item.name}');
});

// Disconnect when done
await client.disconnect();
```

## Testing

See [TESTING.md](TESTING.md) for detailed testing instructions.

Quick start:
```bash
# Setup test environment
./tool/setup_test_db.sh

# Run all tests
dart test
```

## Architecture Highlights

### Registry Pattern (Production-Grade)
The SDK uses a two-phase registration model that eliminates magic numbers and provides robust error handling:

**Phase 1 (Static)**: Register decoders by table name before connecting
```dart
cache.registerDecoder<Note>('note', NoteDecoder());
```

**Phase 2 (Dynamic)**: Server sends table metadata, SDK activates tables
```dart
// Automatic during subscription - links decoder to runtime table ID
cache.activateTable(tableId: 257, tableName: 'note');
```

**Benefits**:
- ✅ No magic numbers (productTypeRef) in generated code
- ✅ Single source of truth (table name)
- ✅ Collision-free (multiple tables can share same struct type)
- ✅ Graceful degradation (unknown tables silently ignored)
- ✅ Type-safe with runtime validation

### Type Safety
- **Zero unsafe `as` casts** - All type checks use `is!` with type promotion
- **Runtime validation** - Type mismatches caught with clear error messages
- **Fail-fast design** - Errors provide actionable feedback

## What's Next

### Completed ✅
- [x] WebSocket connection with auto-reconnect
- [x] Complete BSATN codec implementation
- [x] Client-side table cache with change detection
- [x] Subscription management
- [x] Reducer calling
- [x] All server message types
- [x] Code generation from schema (CLI tool)
- [x] View support (Vec, Option, single-row)
- [x] Registry pattern architecture
- [x] Type-safe casts throughout
- [x] Timeout safety for subscriptions
- [x] Event Streams - Zero-overhead broadcast streams for table changes

### Potential Future Work
- [ ] **Transaction Support** - Handle SpacetimeDB transactions
- [ ] **Identity Management** - Client identity and authentication helpers
- [ ] **Error Handling** - Structured error types from reducers
- [ ] **Advanced Queries** - Query builder API
- [ ] **Performance** - Benchmarking and optimization
- [ ] **Documentation** - API docs and examples
- [ ] **Flutter Integration** - Examples and best practices
- [ ] **Pub Package** - Publish to pub.dev

## Documentation

- [Testing Guide](TESTING.md) - How to run tests
- [CLAUDE.md](CLAUDE.md) - Project instructions and CLI reference

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `dart test`
5. Submit a pull request

## License

MIT License - see LICENSE file for details
