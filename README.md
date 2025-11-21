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
- Type-safe reducer calling with results
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

### 4. Connect

```dart
import 'package:your_app/generated/client.dart';

final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'your_database',
  ssl: false,
  authStorage: InMemoryTokenStore(),
  initialSubscriptions: ['SELECT * FROM users'],
  subscriptionTimeout: Duration(seconds: 10),
);
```

## Tables

```dart
// Iterate
for (final user in client.users.iter()) {
  print(user.name);
}

// Count and check
print(client.users.count);
print(client.users.isEmpty);

// All change streams
client.users.insertStream.listen((user) => print('Added: ${user.name}'));
client.users.updateStream.listen((update) => print('${update.oldRow.name} → ${update.newRow.name}'));
client.users.deleteStream.listen((user) => print('Removed: ${user.name}'));

// With transaction context
client.users.insertEventStream.listen((event) {
  print('Row: ${event.row.name}');
  print('Timestamp: ${event.context.timestamp}');
  print('Energy: ${event.context.energyConsumed}');
});

// Filter to only my transactions
client.users.myInserts.listen((event) => showToast('Created ${event.row.name}'));
client.users.myUpdates.listen((event) => showToast('Updated'));
client.users.myDeletes.listen((event) => showToast('Deleted'));
```

## Reducers

```dart
// Call and get result
final result = await client.reducers.createUser(name: 'Alice', email: 'alice@example.com');
print(result.isSuccess);
print(result.energyConsumed);
print(result.executionDuration);

// Listen to reducer events (from any client)
client.reducers.onCreateUser((ctx, name, email) {
  print('User created: $name');
  print('By: ${ctx.callerIdentity}');
});
```

## Views

```dart
// Vec<T> view - multiple rows
for (final user in client.activeUsers.iter()) {
  print(user.name);
}

// Option<T> view - single optional row
final admin = client.currentAdmin; // User?
if (admin != null) {
  print('Admin: ${admin.name}');
}

// T view - single required row (throws if empty)
final config = client.appConfig; // Config
print(config.version);
```

## Subscriptions

```dart
// Subscribe to more queries after connect
await client.subscriptions.subscribe([
  'SELECT * FROM messages WHERE room_id = 123',
]);
```

## Sum Types (Rust Enums)

```dart
// Rust enum becomes Dart sealed class
enum Status {
    Pending,
    Active { since: u64 },
    Banned { reason: String },
}

// Pattern match with exhaustiveness checking
final message = switch (user.status) {
  StatusPending() => 'Waiting for approval',
  StatusActive(:final since) => 'Active since $since',
  StatusBanned(:final reason) => 'Banned: $reason',
};

// Construct
final status = StatusActive(DateTime.now().millisecondsSinceEpoch);
```

## Authentication

```dart
// Connect with persistent storage
final client = await SpacetimeDbClient.connect(
  host: 'spacetimedb.com',
  database: 'myapp',
  ssl: true,
  authStorage: YourTokenStore(), // implements AuthTokenStore
);

// Access identity after connect
print(client.identity?.toHexString);  // Full 32-byte hex
print(client.identity?.toAbbreviated); // "2ab4...9f1c"
print(client.address);
print(client.token);

// OAuth flow
final authUrl = client.getAuthUrl('google', redirectUri: 'myapp://callback');
// Open authUrl in browser, then handle callback:
final token = client.parseTokenFromCallback(callbackUrl);

// Logout
await client.logout();
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

client.connection.connectionQuality.listen((quality) {
  print('Health: ${quality.healthScore}');
  print('Latency: ${quality.latency}');
  print('Reconnects: ${quality.reconnectAttempts}');
});
```

## SSL

```dart
// Development - ws:// and http://
ssl: false

// Production - wss:// and https://
ssl: true
```

## Testing

```bash
dart test
```

See [TESTING.md](TESTING.md) for details.

## License

Apache 2.0
