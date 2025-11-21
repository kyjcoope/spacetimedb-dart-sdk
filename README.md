# SpacetimeDB Dart SDK

A complete Dart SDK for building real-time multiplayer applications with SpacetimeDB.

## Features

### Core SDK ✅
- **WebSocket Connection** - Auto-reconnect with exponential backoff
- **Observable Connection Status** - Real-time status monitoring with ping/pong heartbeat
- **Connection Quality** - Health metrics, latency tracking, and error reporting
- **Flexible Configuration** - Mobile, stable, and custom connection presets
- **BSATN Encoding/Decoding** - Binary serialization for all SpacetimeDB types
- **Registry Pattern Cache** - Name-based decoder registration with runtime activation
- **Subscription Management** - Real-time SQL query subscriptions with timeout safety
- **Reducer Calling** - Type-safe server-side function calls
- **All Server Messages** - Complete protocol implementation (including transactions)
- **Transaction Support** - Full transaction event handling with context
- **Event Streams** - Zero-overhead broadcast streams for table changes with transaction context
- **Type-Safe Casts** - No unsafe `as` casts, all type checks with promotion
- **Comprehensive Tests** - 170+ tests, all passing with full E2E coverage

### Code Generation ✅
- **Schema Extraction** - Extract from network, WASM, or project builds
- **Table Generation** - Auto-generate typed table classes with BSATN codecs
- **Sum Types (Rust Enums)** - Sealed class hierarchies with pattern matching:
  - Unit variants (no payload)
  - Tuple variants (single/multiple unnamed fields)
  - Struct variants (named fields)
  - Compile-time exhaustiveness checking
  - Proper Ref type resolution in table fields
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

// Connect to SpacetimeDB with timeout safety and custom connection config
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'your_database',
  initialSubscriptions: ['SELECT * FROM your_table'],
  subscriptionTimeout: Duration(seconds: 10), // Optional, defaults to 10s
  config: ConnectionConfig.mobile, // Optional: mobile, stable, or custom
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

### Sum Types (Rust Enums)

The SDK automatically generates Dart sealed classes for Rust enums with full type safety:

```dart
// Rust enum definition
enum NoteStatus {
    Draft,
    Published { published_at: u64 },
    Archived,
}

// Generated Dart code (sealed class hierarchy)
sealed class NoteStatus {
  const NoteStatus();
  factory NoteStatus.decode(BsatnDecoder decoder) { /* ... */ }
  void encode(BsatnEncoder encoder);
}

class NoteStatusDraft extends NoteStatus { /* ... */ }
class NoteStatusPublished extends NoteStatus {
  final int value; // The u64 field
  const NoteStatusPublished(this.value);
}
class NoteStatusArchived extends NoteStatus { /* ... */ }

// Usage: Pattern matching with compile-time exhaustiveness
final note = client.notes.iter().first;

final statusText = switch (note.status) {
  NoteStatusDraft() => 'This note is a draft',
  NoteStatusPublished(:final value) => 'Published at $value',
  NoteStatusArchived() => 'This note is archived',
}; // Compiler ensures all variants are handled!

// Type-safe construction
const draft = NoteStatusDraft();
final published = NoteStatusPublished(DateTime.now().millisecondsSinceEpoch);

// Strongly typed in table fields (not dynamic!)
// Generated Note class has: final NoteStatus status;
```

### Observable Connection Status

The SDK provides real-time connection monitoring for building responsive UIs:

```dart
// Listen to connection status changes
client.connection.connectionStatus.listen((status) {
  switch (status) {
    case ConnectionStatus.connecting:
      showSpinner();
    case ConnectionStatus.connected:
      hideSpinner();
    case ConnectionStatus.reconnecting:
      showReconnectingBanner();
    case ConnectionStatus.disconnected:
      showDisconnectedError();
    case ConnectionStatus.fatalError:
      showRetryButton();
  }
});

// Monitor connection quality
client.connection.connectionQuality.listen((quality) {
  print('Health: ${quality.qualityDescription}');
  print('Score: ${quality.healthScore}');
  print('Attempts: ${quality.reconnectAttempts}');
});

// Manual retry after fatal error
if (client.connection.status == ConnectionStatus.fatalError) {
  await client.connection.retryConnection();
}

// Custom connection configuration
final client = await SpacetimeDbClient.connect(
  host: 'api.example.com:3000',
  database: 'production',
  config: ConnectionConfig.mobile, // Aggressive reconnection for mobile
);

// Or create custom config
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'dev',
  config: ConnectionConfig(
    maxReconnectAttempts: 5,
    pingInterval: Duration(seconds: 20),
    pongTimeout: Duration(seconds: 5),
    autoReconnect: true,
  ),
);
```

**Connection Config Presets**:
- `ConnectionConfig.mobile` - Aggressive reconnection for unstable mobile networks
- `ConnectionConfig.stable` - Less aggressive for WiFi/Ethernet
- `ConnectionConfig.development` - No auto-reconnect for faster feedback

### Transaction Support

The SDK provides full transaction support with event context:

```dart
// Listen to all transactions
client.onTransactionUpdate.listen((update) {
  print('Transaction status: ${update.status}');
  if (update.reducerInfo != null) {
    print('Caused by: ${update.reducerInfo!.reducerName}');
  }
});

// Table event streams include transaction context
client.yourTable.insertEventStream.listen((event) {
  final ctx = event.context;

  // Check if this was caused by a reducer
  if (ctx.event is ReducerEvent) {
    final reducerEvent = ctx.event as ReducerEvent;
    print('Insert from reducer: ${reducerEvent.reducerName}');
  }

  // Access the inserted row
  print('New row: ${event.row.name}');
});

// Filter to only reducer-caused events
client.yourTable.eventsFromReducers.listen((event) {
  // Only events caused by reducer calls, not subscriptions
});

// Filter to only this client's transactions
client.yourTable.myInserts.listen((event) {
  // Only inserts from this client's reducer calls
});
```

## Testing

The SDK includes comprehensive testing with 170+ tests covering all functionality:

- **Unit Tests** - Core SDK components (BSATN, cache, messages)
- **Integration Tests** - Live SpacetimeDB server interactions
- **Codegen Tests** - Code generation and validation
- **E2E Tests** - Full CRUD cycle with generated code in subprocess

See [TESTING.md](TESTING.md) for detailed testing instructions.

Quick start:
```bash
# Start SpacetimeDB
spacetime start

# Publish test module
cd spacetime_test_module
spacetime publish notesdb --server http://localhost:3000

# Run all tests
dart test
```

### E2E Test

The E2E test (`test/integration/codegen_e2e_test.dart`) is the "final boss" that validates:
- ✅ Schema extraction from live server
- ✅ Code generation produces valid, compilable Dart code
- ✅ Generated client connects and auto-registers decoders
- ✅ Full CRUD cycle (Create, Read, Update, Delete) works
- ✅ **Sum types** - Pattern matching, strong typing, payload access
- ✅ Primary key detection and update coalescing
- ✅ All table streams (insert, update, delete) fire correctly
- ✅ Generated code runs in isolated subprocess (production-ready)

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
- [x] **Observable Connection Status** - Public status stream with ping/pong heartbeat and quality metrics
- [x] **Connection Configuration** - Mobile, stable, and custom presets with full customization
- [x] Complete BSATN codec implementation
- [x] Client-side table cache with change detection
- [x] Subscription management
- [x] Reducer calling
- [x] All server message types
- [x] **Transaction Support** - Full transaction event handling with context
- [x] **Event Streams** - Zero-overhead broadcast streams for table changes
- [x] Code generation from schema (CLI tool)
- [x] **Sum Types (Rust Enums)** - Sealed class hierarchies with exhaustive pattern matching
- [x] View support (Vec, Option, single-row)
- [x] Registry pattern architecture
- [x] Type-safe casts throughout (zero unsafe `as` casts)
- [x] Timeout safety for subscriptions
- [x] **E2E Testing** - Full CRUD + Sum Types validation in subprocess
- [x] **Primary Key Generation** - Auto-detect and generate getPrimaryKey()
- [x] **Update Coalescing** - Delete+Insert pairs become Update events

### Potential Future Work
- [ ] **Authentication & Persistence** - HIGH PRIORITY - Platform-agnostic token storage with OIDC support (see [AUTHENTICATION_PLAN.md](AUTHENTICATION_PLAN.md))
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
