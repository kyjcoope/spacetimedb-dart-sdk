# SpacetimeDB Dart SDK Test Generation Protocol

## Prime Directive
Tests must:
- Never use print statements for verification
- Never use `Future.delayed` for timing
- Always register full codec infrastructure (Phase 0)

---

## 1. File Structure

### Naming & Location
- **Filename**: Must end in `_test.dart` (e.g., `transaction_test.dart`)
- **Location**:
  - `test/integration/` - Requires running SpacetimeDB instance
  - `test/unit/` - Pure unit tests

### Required Imports
```dart
import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';
```

---

## 2. Critical Rules

### Phase 0: Registry Setup (MANDATORY)
Must register decoders in `setUp()`:

```dart
// Tables
subManager.cache.registerDecoder<T>('name', Decoder());

// Reducers
subManager.reducerRegistry.registerDecoder('name', ArgsDecoder());
```

**If generated decoders unavailable**: Create mock decoders in test file.

### No Flakiness: Async Patterns

**❌ BANNED**: `await Future.delayed(Duration(seconds: 1))`
**Reason**: Race conditions in CI/CD

**✅ REQUIRED**: Event-driven waiting with timeouts
```dart
// Always add .timeout() to prevent hanging tests
await stream.first.timeout(Duration(seconds: 2));
await stream.firstWhere((e) => condition).timeout(Duration(seconds: 2));
expect(stream, emits(matcher))
// Use Completer for complex flows
```

**⚠️ CRITICAL**: All async awaits MUST have `.timeout()` to fail fast instead of hanging indefinitely.

### Real Assertions

**❌ BANNED**: `if (x == y) print('Success')`
**Reason**: Test runner sees as pass even on logic failure

**✅ REQUIRED**: `expect(actual, matcher, reason: '...')`
```dart
expect(x, equals(y))
expect(list, isNotEmpty)
expect(obj, isA<Type>())
```

### No Casts

**❌ BANNED**: `final args = event.reducerArgs as CreateNoteArgs;`

**✅ REQUIRED**: Type guards with promotion
```dart
final args = event.reducerArgs;
if (args is! CreateNoteArgs) fail('Wrong args type');
// args is now promoted to CreateNoteArgs
```

---

## 3. Master Template

```dart
import 'dart:async';
import 'package:test/test.dart';
import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';

// Import or mock decoders
import 'note_decoder.dart';
import 'reducer_arg_decoders.dart';

void main() {
  late SpacetimeDbConnection connection;
  late SubscriptionManager subManager;

  setUp(() async {
    connection = SpacetimeDbConnection(
      host: 'localhost:3000',
      database: 'notesdb',
    );
    subManager = SubscriptionManager(connection);

    // PHASE 0: Register decoders
    subManager.cache.registerDecoder<Note>('note', NoteDecoder());
    subManager.reducerRegistry.registerDecoder('create_note', CreateNoteArgsDecoder());
    subManager.reducerRegistry.registerDecoder('update_note', UpdateNoteArgsDecoder());

    await connection.connect();
    await subManager.onIdentityToken.first.timeout(Duration(seconds: 5));
  });

  tearDown(() async {
    subManager.dispose();
    await connection.disconnect();
  });

  group('Feature Name Tests', () {
    test('Description of specific behavior', () async {
      // A. PREPARE LISTENER (before action to avoid race)
      final resultFuture = subManager.onTransactionUpdate.first;

      // B. ACTION
      subManager.reducers.callWith('create_note', (encoder) {
        encoder.writeString('Test Title');
        encoder.writeString('Test Content');
      });

      // C. WAIT (deterministic with timeout)
      final result = await resultFuture.timeout(Duration(seconds: 2));

      // D. ASSERT
      expect(result.status, isA<Committed>(),
        reason: 'Transaction should commit');
      expect(result.reducerInfo?.reducerName, equals('create_note'));

      final args = subManager.reducerRegistry.deserializeArgs(
        'create_note',
        result.reducerInfo!.args
      );
      expect(args, isA<CreateNoteArgs>());
    });
  });
}
```

---

## 4. Pre-Output Verification Checklist

- [ ] File ends in `_test.dart`
- [ ] Uses `test()` blocks (not standalone `main()`)
- [ ] ReducerRegistry populated in `setUp()`
- [ ] No `Future.delayed` calls
- [ ] No `as` casts (use `is!` checks or `expect(x, isA<T>())`)
- [ ] **All async awaits have `.timeout()` to prevent hanging**
