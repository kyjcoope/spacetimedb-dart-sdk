# SpacetimeDB Dart SDK

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.5.4-blue.svg)](https://dart.dev)

Dart SDK for SpacetimeDB with WebSocket sync, BSATN encoding, and code generation.

## Features

- WebSocket connection with auto-reconnect and SSL/TLS
- Connection status monitoring and quality metrics
- BSATN binary encoding/decoding
- Client-side table cache with change streams
- Subscription management with SQL queries
- Type-safe reducer calling
- Code generation (tables, reducers, sum types, views)
- Authentication with OIDC and token persistence
- Transaction events with context

## Quick Start

### 1. Install SpacetimeDB CLI

```bash
curl --proto '=https' --tlsv1.2 -sSf https://install.spacetimedb.com | sh
```

### 2. Add dependency

```yaml
dependencies:
  spacetimedb_dart_sdk:
    git: https://github.com/mikaelwills/spacetimedb_dart_sdk.git
```

### 3. Generate client code

```bash
# From running server
dart run spacetimedb_dart_sdk:generate -s http://localhost:3000 -d your_database -o lib/generated

# Or from local Rust project
dart run spacetimedb_dart_sdk:generate -p path/to/module -o lib/generated
```

### 4. Use it

```dart
import 'package:your_app/generated/client.dart';

final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'your_database',
  ssl: false,
  authStorage: InMemoryTokenStore(), // or your persistent store
  initialSubscriptions: ['SELECT * FROM users'],
);

// Call reducers
await client.reducers.createUser(name: 'Alice', email: 'alice@example.com');

// Read data
for (final user in client.users.iter()) {
  print(user.name);
}

// Listen to changes
client.users.insertStream.listen((user) => print('New: ${user.name}'));

await client.disconnect();
```

## SSL Configuration

```dart
// Development
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'myapp',
  ssl: false, // ws:// and http://
);

// Production
final client = await SpacetimeDbClient.connect(
  host: 'spacetimedb.com',
  database: 'myapp',
  ssl: true, // wss:// and https://
);
```

## Sum Types

Rust enums become Dart sealed classes with pattern matching:

```dart
// Rust
enum NoteStatus {
    Draft,
    Published { published_at: u64 },
}

// Dart usage
final text = switch (note.status) {
  NoteStatusDraft() => 'Draft',
  NoteStatusPublished(:final value) => 'Published at $value',
};
```

## Authentication

```dart
// Persistent token storage
final client = await SpacetimeDbClient.connect(
  host: 'spacetimedb.com',
  database: 'myapp',
  ssl: true,
  authStorage: YourTokenStore(), // implements AuthTokenStore
);

// Access identity
print(client.identity?.toHexString);

// OAuth login
final authUrl = client.getAuthUrl('google', redirectUri: 'myapp://callback');
```

## Connection Status

```dart
client.connection.connectionStatus.listen((status) {
  switch (status) {
    case ConnectionStatus.connecting: showSpinner();
    case ConnectionStatus.connected: hideSpinner();
    case ConnectionStatus.reconnecting: showBanner();
    case ConnectionStatus.disconnected: showError();
    case ConnectionStatus.fatalError: showRetry();
  }
});
```

## Transaction Events

```dart
client.users.insertEventStream.listen((event) {
  if (event.context.event is ReducerEvent) {
    print('From reducer: ${event.context.event.reducerName}');
  }
  print('New row: ${event.row.name}');
});

// Filter to only this client's transactions
client.users.myInserts.listen((event) { ... });
```

## Testing

```bash
dart test
```

See [TESTING.md](TESTING.md) for details.

## License

Apache 2.0
