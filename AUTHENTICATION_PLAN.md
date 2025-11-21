# Authentication & Persistence Implementation Plan

## Overview

Implement a flexible, platform-agnostic authentication system with automatic token persistence and OIDC support for SpacetimeDB.

**Priority**: HIGH - Essential for production apps (users shouldn't lose their identity on app restart)

**Estimated Complexity**: Medium - Requires careful interface design and integration with existing connection flow

---

## Current State

### ✅ What Works
- `onIdentityToken` stream receives identity tokens from server
- Tokens are available in memory during connection lifetime
- Anonymous identity works (server assigns identity on first connect)

### ❌ What's Missing
- No token persistence between app restarts
- No abstraction for storage backends (would need to hardcode `shared_preferences`)
- No helper for OIDC authentication flows
- No automatic token refresh/saving
- Users lose their identity on app restart (terrible UX for games)

---

## User Story

**As a game developer**, I need:
1. Players to keep their identity across app restarts
2. Support for both anonymous and authenticated users
3. Easy integration with Google/Discord/Steam login
4. Platform-agnostic SDK (works in CLI, Flutter, server-side Dart)
5. Automatic token management (save new tokens, load on reconnect)

**Current Problem**:
```dart
// ❌ User loses identity on app restart
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'mygame',
);

// Player builds up game state...
// App restarts
// Player gets NEW identity, loses all progress!
```

**Desired API**:
```dart
// ✅ Identity persists across restarts
final client = await SpacetimeDbClient.connect(
  host: 'localhost:3000',
  database: 'mygame',
  authStorage: SecureTokenStore(), // User provides storage
);

// Token automatically loaded and saved
// Player keeps their identity!
```

---

## Architecture: Zero-Dependency Interface Pattern

**Key Principle**: The SDK should NOT depend on Flutter packages.

Instead, define an **interface** that users implement with their preferred storage:
- Flutter apps → `shared_preferences` or `flutter_secure_storage`
- CLI apps → File-based or in-memory
- Server-side Dart → Database or Redis

---

## Implementation Phases

### Phase 1: AuthTokenStore Interface

**Goal**: Define platform-agnostic storage contract

**Files to Create**:
- `lib/src/auth/auth_token_store.dart`
- `lib/src/auth/in_memory_token_store.dart`

**Tasks**:

#### Step 1.1: Create AuthTokenStore Interface
```dart
// lib/src/auth/auth_token_store.dart

/// Platform-agnostic interface for storing authentication tokens.
///
/// Implementations can use any storage backend:
/// - Flutter: SharedPreferences, FlutterSecureStorage
/// - CLI: File system
/// - Server: Database, Redis
/// - Testing: In-memory
abstract class AuthTokenStore {
  /// Load the stored authentication token, if any.
  ///
  /// Returns null if no token is stored or if loading fails.
  Future<String?> loadToken();

  /// Save an authentication token.
  ///
  /// This is called automatically when the server sends a new identity token.
  Future<void> saveToken(String token);

  /// Clear the stored token (e.g., on logout).
  Future<void> clearToken();
}
```

#### Step 1.2: Create InMemoryTokenStore (Default Implementation)
```dart
// lib/src/auth/in_memory_token_store.dart

import 'auth_token_store.dart';

/// Default in-memory token storage.
///
/// Tokens are NOT persisted across app restarts.
/// Use this for:
/// - Testing
/// - CLI tools that don't need persistence
/// - Temporary anonymous sessions
///
/// For production Flutter apps, implement AuthTokenStore with
/// SharedPreferences or FlutterSecureStorage.
class InMemoryTokenStore implements AuthTokenStore {
  String? _token;

  @override
  Future<String?> loadToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }
}
```

#### Step 1.3: Export Public API
```dart
// lib/spacetimedb_dart_sdk.dart

// ... existing exports ...

// Auth
export 'src/auth/auth_token_store.dart';
export 'src/auth/in_memory_token_store.dart';
```

---

### Phase 2: Connection-Level Token Support

**Goal**: Wire token loading/saving into connection lifecycle

**Files to Modify**:
- `lib/src/connection/spacetimedb_connection.dart`

**Tasks**:

#### Step 2.1: Add Token to Connection Constructor
```dart
class SpacetimeDbConnection {
  final String host;
  final String database;
  final String? initialToken; // NEW

  SpacetimeDbConnection({
    required this.host,
    required this.database,
    this.initialToken, // NEW
  }) {
    _logger = Logger('SpacetimeDB [$database]');
  }
}
```

#### Step 2.2: Send Token in Connection Request

SpacetimeDB expects the token in the WebSocket URL or headers. Check the protocol:

**Option A: Token in URL**
```dart
Future<void> connect() async {
  if (_state == ConnectionState.connected) return;

  // Build URL with optional token
  final baseUrl = 'ws://$host/database/subscribe/$database';
  final uri = initialToken != null
      ? Uri.parse('$baseUrl?token=$initialToken')
      : Uri.parse(baseUrl);

  _logger.i('Connecting to SpacetimeDB at $uri');
  _channel = WebSocketChannel.connect(uri);

  _setupMessageListener();
}
```

**Option B: Token in WebSocket Headers** (if supported)
```dart
Future<void> connect() async {
  final uri = Uri.parse('ws://$host/database/subscribe/$database');

  _logger.i('Connecting to SpacetimeDB at $uri');

  // Create WebSocket with custom headers
  final socket = await WebSocket.connect(
    uri.toString(),
    headers: initialToken != null ? {'Authorization': 'Bearer $initialToken'} : null,
  );

  _channel = IOWebSocketChannel(socket);
  _setupMessageListener();
}
```

**Note**: Need to verify SpacetimeDB's actual auth protocol. For now, assume URL-based.

#### Step 2.3: Expose Current Token
```dart
class SpacetimeDbConnection {
  String? _currentToken;

  /// The current authentication token, if any
  String? get token => _currentToken;

  // Update when IdentityToken is received
  void _handleIdentityToken(IdentityTokenMessage message) {
    _logger.i('Received identity token');
    _currentToken = message.token; // NEW
    _reconnectAttempts = 0;
    _updateStatus(ConnectionStatus.connected);
    _identityTokenController.add(message);
  }
}
```

---

### Phase 3: Client-Level Token Management

**Goal**: Automatic token persistence in generated client

**Files to Modify**:
- `lib/src/codegen/generators/client_generator.dart`

**Tasks**:

#### Step 3.1: Add AuthTokenStore to Generated Client

Update the client template to accept and use AuthTokenStore:

```dart
// In ClientGenerator._generateClientClass()

String _generateClientClass() {
  return '''
class ${schema.databaseName.toPascalCase()}Client {
  final SpacetimeDbConnection connection;
  final SubscriptionManager _subscriptionManager;
  final AuthTokenStore _authStorage; // NEW

  ${schema.databaseName.toPascalCase()}Client._(
    this.connection,
    this._subscriptionManager,
    this._authStorage, // NEW
  );

  /// Connect to SpacetimeDB with automatic token persistence
  static Future<${schema.databaseName.toPascalCase()}Client> connect({
    required String host,
    required String database,
    List<String> initialSubscriptions = const [],
    Duration subscriptionTimeout = const Duration(seconds: 10),
    AuthTokenStore? authStorage, // NEW
  }) async {
    // 1. Setup storage (default to in-memory)
    final storage = authStorage ?? InMemoryTokenStore();

    // 2. Try to load existing token
    final savedToken = await storage.loadToken();

    // 3. Connect with token
    final connection = SpacetimeDbConnection(
      host: host,
      database: database,
      initialToken: savedToken, // Pass loaded token
    );

    await connection.connect();

    final subscriptionManager = SubscriptionManager(connection);

    // Register all decoders
    ${_generateDecoderRegistration()}

    final client = ${schema.databaseName.toPascalCase()}Client._(
      connection,
      subscriptionManager,
      storage,
    );

    // 4. Auto-save new tokens
    connection.onIdentityToken.listen((msg) async {
      await storage.saveToken(msg.token);
    });

    // Initial subscriptions
    if (initialSubscriptions.isNotEmpty) {
      await subscriptionManager.subscribe(
        initialSubscriptions,
        timeout: subscriptionTimeout,
      );
    }

    return client;
  }

  /// Logout - clear stored token and disconnect
  Future<void> logout() async {
    await _authStorage.clearToken();
    await connection.disconnect();
  }

  // ... rest of generated client ...
}
''';
}
```

#### Step 3.2: Add Logout Method

The logout method (shown above) should:
1. Clear the stored token
2. Disconnect from the server
3. Server will assign a new anonymous identity on next connect

---

### Phase 4: OIDC Authentication Helpers

**Goal**: Simplify OAuth/OIDC flows (Google, Discord, Steam, etc.)

**Files to Create**:
- `lib/src/auth/oidc_helper.dart`

**Files to Modify**:
- Client generator template (add `getAuthUrl` method)

**Tasks**:

#### Step 4.1: Create OIDC Helper Class
```dart
// lib/src/auth/oidc_helper.dart

/// Helper for OAuth/OIDC authentication flows with SpacetimeDB.
///
/// SpacetimeDB handles authentication via HTTP, not WebSocket:
/// 1. Client requests auth URL from this helper
/// 2. Client opens browser with that URL (using url_launcher, etc.)
/// 3. User authenticates with provider (Google, Discord, etc.)
/// 4. Server redirects to callback with token
/// 5. Client extracts token and connects
class OidcHelper {
  final String host;
  final String database;
  final bool ssl;

  OidcHelper({
    required this.host,
    required this.database,
    this.ssl = false,
  });

  /// Generate the authentication URL for a given provider.
  ///
  /// Supported providers (depends on SpacetimeDB server config):
  /// - 'google'
  /// - 'discord'
  /// - 'steam'
  /// - 'github'
  /// etc.
  ///
  /// Example:
  /// ```dart
  /// final helper = OidcHelper(host: 'api.game.com', database: 'mygame', ssl: true);
  /// final url = helper.getAuthUrl('google');
  /// // Open url in browser: await launchUrl(Uri.parse(url));
  /// ```
  String getAuthUrl(String provider, {String? redirectUri}) {
    final protocol = ssl ? 'https' : 'http';
    final baseUrl = '$protocol://$host/database/auth/$provider';

    if (redirectUri != null) {
      return '$baseUrl?init&redirect_uri=${Uri.encodeComponent(redirectUri)}';
    }

    return '$baseUrl?init';
  }

  /// Parse the token from a callback URL.
  ///
  /// After successful authentication, the server redirects to a callback URL
  /// with the token as a query parameter or fragment.
  ///
  /// Example callback URLs:
  /// - `myapp://callback?token=abc123`
  /// - `myapp://callback#token=abc123`
  String? parseTokenFromCallback(String callbackUrl) {
    final uri = Uri.parse(callbackUrl);

    // Check query parameters
    if (uri.queryParameters.containsKey('token')) {
      return uri.queryParameters['token'];
    }

    // Check fragment (for implicit flow)
    if (uri.fragment.isNotEmpty) {
      final fragmentParams = Uri.splitQueryString(uri.fragment);
      if (fragmentParams.containsKey('token')) {
        return fragmentParams['token'];
      }
    }

    return null;
  }
}
```

#### Step 4.2: Add OIDC Methods to Generated Client
```dart
// In ClientGenerator, add to generated client class:

/// Get authentication URL for OAuth/OIDC provider.
///
/// Example:
/// ```dart
/// final url = client.getAuthUrl('google');
/// await launchUrl(Uri.parse(url)); // Open in browser
/// ```
String getAuthUrl(String provider, {String? redirectUri}) {
  final helper = OidcHelper(
    host: connection.host,
    database: '${schema.databaseName}',
    ssl: false, // TODO: Make configurable
  );
  return helper.getAuthUrl(provider, redirectUri: redirectUri);
}

/// Parse token from OAuth callback URL.
///
/// Example:
/// ```dart
/// // After user authenticates, your app receives callback:
/// final token = client.parseTokenFromCallback('myapp://callback?token=abc123');
/// if (token != null) {
///   await _authStorage.saveToken(token);
///   await connection.disconnect();
///   await connection.connect(); // Reconnect with new token
/// }
/// ```
String? parseTokenFromCallback(String callbackUrl) {
  final helper = OidcHelper(
    host: connection.host,
    database: '${schema.databaseName}',
  );
  return helper.parseTokenFromCallback(callbackUrl);
}
```

#### Step 4.3: Export OIDC Helper
```dart
// lib/spacetimedb_dart_sdk.dart

export 'src/auth/oidc_helper.dart';
```

---

### Phase 5: Example Implementations

**Goal**: Provide ready-to-use storage implementations for common platforms

**Files to Create**:
- `example/auth/flutter_preferences_store.dart`
- `example/auth/flutter_secure_store.dart`
- `example/auth/file_token_store.dart`

**Note**: These go in `example/` NOT `lib/` to avoid dependencies

**Tasks**:

#### Step 5.1: SharedPreferences Implementation (Flutter)
```dart
// example/auth/flutter_preferences_store.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

/// Token storage using Flutter's SharedPreferences.
///
/// This is NOT secure - tokens are stored in plain text.
/// Use FlutterSecureStore for sensitive data.
///
/// Good for:
/// - Anonymous user sessions
/// - Non-sensitive game data
/// - Development/testing
class FlutterPreferencesStore implements AuthTokenStore {
  static const _key = 'spacetimedb_token';

  @override
  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  @override
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

#### Step 5.2: FlutterSecureStorage Implementation (Flutter)
```dart
// example/auth/flutter_secure_store.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

/// Secure token storage using Flutter's secure storage.
///
/// Tokens are encrypted and stored in:
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences
/// - Web: Local storage (not truly secure)
///
/// Use this for:
/// - Production apps
/// - Sensitive user data
/// - Authenticated sessions
class FlutterSecureStore implements AuthTokenStore {
  static const _key = 'spacetimedb_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> loadToken() async {
    return await _storage.read(key: _key);
  }

  @override
  Future<void> saveToken(String token) async {
    await _storage.write(key: _key, value: token);
  }

  @override
  Future<void> clearToken() async {
    await _storage.delete(key: _key);
  }
}
```

#### Step 5.3: File-Based Storage (CLI/Desktop)
```dart
// example/auth/file_token_store.dart

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

/// File-based token storage for CLI and desktop apps.
///
/// Stores token in:
/// - Linux/Mac: ~/.config/spacetimedb/token
/// - Windows: %APPDATA%/spacetimedb/token
class FileTokenStore implements AuthTokenStore {
  final String? customPath;

  FileTokenStore({this.customPath});

  Future<File> get _tokenFile async {
    if (customPath != null) {
      return File(customPath!);
    }

    // Get platform-specific config directory
    String configDir;
    if (Platform.isWindows) {
      configDir = Platform.environment['APPDATA']!;
    } else {
      final home = Platform.environment['HOME']!;
      configDir = path.join(home, '.config');
    }

    final dir = Directory(path.join(configDir, 'spacetimedb'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return File(path.join(dir.path, 'token'));
  }

  @override
  Future<String?> loadToken() async {
    final file = await _tokenFile;
    if (!await file.exists()) return null;

    try {
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> saveToken(String token) async {
    final file = await _tokenFile;
    await file.writeAsString(token);
  }

  @override
  Future<void> clearToken() async {
    final file = await _tokenFile;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
```

---

### Phase 6: Documentation & Examples

**Goal**: Comprehensive usage examples for all platforms

**Files to Create**:
- `example/flutter_auth_example.dart`
- `example/cli_auth_example.dart`
- `example/oidc_login_example.dart`

**Tasks**:

#### Step 6.1: Flutter Example
```dart
// example/flutter_auth_example.dart

import 'package:flutter/material.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'auth/flutter_secure_store.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  SpacetimeDbClient? client;
  String? identityToken;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    // Use secure storage for token persistence
    client = await SpacetimeDbClient.connect(
      host: 'localhost:3000',
      database: 'mygame',
      authStorage: FlutterSecureStore(), // 🔐 Tokens persist across restarts
      initialSubscriptions: ['SELECT * FROM player'],
    );

    // Listen for identity updates
    client!.connection.onIdentityToken.listen((msg) {
      setState(() {
        identityToken = msg.token;
      });
      print('Identity: ${msg.identity}');
      print('Token saved securely!');
    });
  }

  Future<void> _logout() async {
    await client?.logout(); // Clears token and disconnects
    setState(() {
      identityToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SpacetimeDB Auth Example'),
        actions: [
          if (identityToken != null)
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: _logout,
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (identityToken != null)
              Text('Logged in! Token persisted.')
            else
              Text('Connecting...'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    client?.connection.disconnect();
    super.dispose();
  }
}
```

#### Step 6.2: OIDC Login Example
```dart
// example/oidc_login_example.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'auth/flutter_secure_store.dart';

class OidcLoginScreen extends StatefulWidget {
  @override
  State<OidcLoginScreen> createState() => _OidcLoginScreenState();
}

class _OidcLoginScreenState extends State<OidcLoginScreen> {
  SpacetimeDbClient? client;
  final storage = FlutterSecureStore();

  Future<void> _loginWithGoogle() async {
    // 1. Create temporary client to get auth URL
    final tempClient = await SpacetimeDbClient.connect(
      host: 'api.mygame.com',
      database: 'production',
      authStorage: InMemoryTokenStore(), // Don't save anonymous token
    );

    // 2. Get Google OAuth URL
    final authUrl = tempClient.getAuthUrl(
      'google',
      redirectUri: 'myapp://callback',
    );

    // 3. Open in browser
    await launchUrl(Uri.parse(authUrl));

    // 4. Listen for callback (handled by deep linking)
    // See _handleCallback() below
  }

  Future<void> _handleCallback(Uri callbackUri) async {
    // Extract token from callback URL
    final tempClient = await SpacetimeDbClient.connect(
      host: 'api.mygame.com',
      database: 'production',
    );

    final token = tempClient.parseTokenFromCallback(callbackUri.toString());

    if (token != null) {
      // Save token
      await storage.saveToken(token);

      // Reconnect with authenticated token
      client = await SpacetimeDbClient.connect(
        host: 'api.mygame.com',
        database: 'production',
        authStorage: storage,
      );

      print('Logged in with Google!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Center(
        child: ElevatedButton.icon(
          icon: Icon(Icons.login),
          label: Text('Login with Google'),
          onPressed: _loginWithGoogle,
        ),
      ),
    );
  }
}
```

#### Step 6.3: CLI Example
```dart
// example/cli_auth_example.dart

import 'dart:io';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
import 'auth/file_token_store.dart';

Future<void> main() async {
  print('SpacetimeDB CLI Auth Example\n');

  // Use file-based storage for CLI
  final storage = FileTokenStore();

  print('Connecting to SpacetimeDB...');
  final client = await SpacetimeDbClient.connect(
    host: 'localhost:3000',
    database: 'cli_app',
    authStorage: storage, // Token saved to ~/.config/spacetimedb/token
  );

  // Display identity
  client.connection.onIdentityToken.listen((msg) {
    print('Identity: ${msg.identity}');
    print('Token: ${msg.token.substring(0, 20)}...');
    print('Token saved to: ${storage._tokenFile}');
  });

  // Keep running
  print('\nPress Ctrl+C to exit');
  await ProcessSignal.sigint.watch().first;

  await client.connection.disconnect();
  print('Disconnected');
}
```

---

### Phase 7: Testing

**Goal**: Comprehensive tests for auth system

**Files to Create**:
- `test/auth/token_store_test.dart`
- `test/auth/auth_integration_test.dart`

**Tasks**:

#### Step 7.1: Token Store Interface Tests
```dart
// test/auth/token_store_test.dart

import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

void main() {
  group('InMemoryTokenStore', () {
    late InMemoryTokenStore store;

    setUp(() {
      store = InMemoryTokenStore();
    });

    test('Initially returns null', () async {
      final token = await store.loadToken();
      expect(token, isNull);
    });

    test('Saves and loads token', () async {
      await store.saveToken('test-token-123');
      final loaded = await store.loadToken();
      expect(loaded, 'test-token-123');
    });

    test('Clears token', () async {
      await store.saveToken('test-token-123');
      await store.clearToken();
      final loaded = await store.loadToken();
      expect(loaded, isNull);
    });

    test('Overwrites existing token', () async {
      await store.saveToken('token-1');
      await store.saveToken('token-2');
      final loaded = await store.loadToken();
      expect(loaded, 'token-2');
    });
  });
}
```

#### Step 7.2: Auth Integration Test
```dart
// test/auth/auth_integration_test.dart

import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

void main() {
  group('Authentication Integration', () {
    test('Client saves token automatically', () async {
      final store = InMemoryTokenStore();

      final client = await SpacetimeDbClient.connect(
        host: 'localhost:3000',
        database: 'notesdb',
        authStorage: store,
      );

      // Wait for identity token
      final tokenMsg = await client.connection.onIdentityToken.first
          .timeout(Duration(seconds: 5));

      // Verify token was saved
      final savedToken = await store.loadToken();
      expect(savedToken, isNotNull);
      expect(savedToken, tokenMsg.token);

      await client.connection.disconnect();
    });

    test('Client loads saved token on reconnect', () async {
      final store = InMemoryTokenStore();
      await store.saveToken('existing-token-123');

      final client = await SpacetimeDbClient.connect(
        host: 'localhost:3000',
        database: 'notesdb',
        authStorage: store,
      );

      // Connection should have used the saved token
      expect(client.connection.initialToken, 'existing-token-123');

      await client.connection.disconnect();
    });

    test('Logout clears token', () async {
      final store = InMemoryTokenStore();

      final client = await SpacetimeDbClient.connect(
        host: 'localhost:3000',
        database: 'notesdb',
        authStorage: store,
      );

      await client.connection.onIdentityToken.first
          .timeout(Duration(seconds: 5));

      // Verify token exists
      expect(await store.loadToken(), isNotNull);

      // Logout
      await client.logout();

      // Verify token cleared
      expect(await store.loadToken(), isNull);
    });
  });
}
```

#### Step 7.3: OIDC Helper Tests
```dart
test('getAuthUrl generates correct URL', () {
  final helper = OidcHelper(
    host: 'api.game.com',
    database: 'mygame',
    ssl: true,
  );

  final url = helper.getAuthUrl('google');
  expect(url, 'https://api.game.com/database/auth/google?init');
});

test('getAuthUrl with redirect URI', () {
  final helper = OidcHelper(
    host: 'localhost:3000',
    database: 'dev',
  );

  final url = helper.getAuthUrl('discord', redirectUri: 'myapp://callback');
  expect(url, contains('redirect_uri=myapp%3A%2F%2Fcallback'));
});

test('parseTokenFromCallback extracts query parameter', () {
  final helper = OidcHelper(host: 'localhost', database: 'test');

  final token = helper.parseTokenFromCallback(
    'myapp://callback?token=abc123&other=param'
  );

  expect(token, 'abc123');
});

test('parseTokenFromCallback extracts fragment', () {
  final helper = OidcHelper(host: 'localhost', database: 'test');

  final token = helper.parseTokenFromCallback(
    'myapp://callback#token=xyz789'
  );

  expect(token, 'xyz789');
});

test('parseTokenFromCallback returns null when missing', () {
  final helper = OidcHelper(host: 'localhost', database: 'test');

  final token = helper.parseTokenFromCallback('myapp://callback');

  expect(token, isNull);
});
```

---

## Edge Cases & Considerations

### 1. Token Refresh / Expiration
**Problem**: Saved token might be expired

**Solution**: Auto-healing pattern
- Client connects with saved token
- If token is invalid, server sends new anonymous identity token
- `onIdentityToken` listener saves the new token
- User seamlessly gets new identity (though loses old one)

For "logged in" users, implement proper token refresh logic server-side.

### 2. Multiple Database Connections
**Problem**: Different tokens for different databases

**Solution**: Namespace tokens by database name
```dart
class NamespacedTokenStore implements AuthTokenStore {
  final AuthTokenStore _underlying;
  final String _namespace;

  Future<String?> loadToken() =>
      _underlying.loadToken().then((t) => /* extract namespace */);

  Future<void> saveToken(String token) =>
      _underlying.saveToken('$_namespace:$token');
}
```

### 3. Concurrent Token Updates
**Problem**: Multiple clients/tabs saving tokens simultaneously

**Solution**: Use atomic writes if available
```dart
// For file-based storage
await file.writeAsString(token, flush: true);

// For SharedPreferences (already atomic)
await prefs.setString(key, token);
```

### 4. Security Considerations
**Problem**: Tokens stored in plain text

**Solutions**:
- Use `FlutterSecureStorage` for mobile
- For web, use `localStorage` (no better option)
- For CLI, use file permissions (chmod 600)
- Never log tokens
- Use HTTPS/WSS in production

### 5. Anonymous → Authenticated Transition
**Problem**: User has anonymous token, then logs in with Google

**Solution**:
```dart
// 1. User logs in with OIDC
final authenticatedToken = parseTokenFromCallback(callbackUri);

// 2. Save new token (overwrites anonymous)
await storage.saveToken(authenticatedToken);

// 3. Reconnect
await client.connection.disconnect();
final newClient = await SpacetimeDbClient.connect(
  host: host,
  database: database,
  authStorage: storage, // Will use authenticated token
);
```

Server-side: Implement identity merging if needed (copy anonymous user's data to authenticated identity).

---

## Success Criteria

- ✅ `AuthTokenStore` interface defined
- ✅ `InMemoryTokenStore` default implementation
- ✅ Connection accepts `initialToken` parameter
- ✅ Generated client accepts `authStorage` parameter
- ✅ Automatic token saving on `onIdentityToken`
- ✅ `logout()` method clears token
- ✅ OIDC helper generates auth URLs
- ✅ Token parsing from callback URLs
- ✅ Example implementations (Flutter, CLI, Secure)
- ✅ Comprehensive tests
- ✅ All existing tests still pass

---

## Documentation Updates

After implementation:

1. **README.md**:
   - Add "Authentication & Persistence" to completed features
   - Add usage example with token storage

2. **Create AUTHENTICATION.md**:
   - Detailed guide on token persistence
   - Platform-specific storage recommendations
   - OIDC flow step-by-step
   - Security best practices
   - Migrating anonymous → authenticated

3. **Update CLAUDE.md**:
   - Add authentication to feature list

---

## Timeline Estimate

- **Phase 1**: 2-3 hours (Interface design)
- **Phase 2**: 2-3 hours (Connection integration)
- **Phase 3**: 3-4 hours (Client generator updates)
- **Phase 4**: 2-3 hours (OIDC helpers)
- **Phase 5**: 2-3 hours (Example implementations)
- **Phase 6**: 2-3 hours (Documentation & examples)
- **Phase 7**: 3-4 hours (Testing)

**Total**: ~16-23 hours

---

## Future Enhancements (Out of Scope for Initial Implementation)

1. **Token Refresh**: Automatic refresh before expiration
2. **Multi-User Support**: Multiple identities on one device
3. **Biometric Auth**: Face ID / Fingerprint integration
4. **Session Management**: Track active sessions, remote logout
5. **Account Linking**: Link multiple OAuth providers to one identity
6. **Offline Mode**: Queue operations while offline, replay on reconnect
7. **Token Encryption**: Additional encryption layer for extra security

---

## References

- [SpacetimeDB Authentication Docs](https://spacetimedb.com/docs/modules/authentication)
- [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)
- [SharedPreferences](https://pub.dev/packages/shared_preferences)
- [OAuth 2.0 PKCE Flow](https://oauth.net/2/pkce/)
- [URL Launcher (Flutter)](https://pub.dev/packages/url_launcher)
