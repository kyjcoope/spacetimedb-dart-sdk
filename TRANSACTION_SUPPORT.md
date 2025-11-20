# Transaction Support in SpacetimeDB Dart SDK

## 🎯 Quick Reference - Implementation Phases

| Phase | Description | Steps | Dependencies | Scope |
|-------|-------------|-------|--------------|-------|
| **Phase 0** | Reducer Registry & Message Protocol | 6 steps | None (BLOCKING) | 2-3 days |
| **Phase 1** | Core Event Types | 4 steps | Phase 0 | 1 day |
| **Phase 2** | Update Message Handling | 2 steps | Phase 0, Phase 1 | 1 day |
| **Phase 3** | Enhanced Stream Events | 3 steps | Phase 1, Phase 2 | 1-2 days |
| **Phase 4** | Reducer Completion API | 3 steps | Phase 0, Phase 1 | 1 day |
| **Phase 5** | Code Generation Updates | 4 steps | All previous | 2 days |
| **Phase 6** | Initial Subscription Handling | 2 steps | Phase 1, Phase 2 | 1 day |

**⚠️ Critical Path:** Phase 0 MUST be completed before any other phase. All other phases depend on it.

**Total Estimated Time:** 9-11 days of focused implementation

---

## Table of Contents
1. [Background: How Transactions Work](#background-how-transactions-work-in-spacetimedb)
2. [How SDKs Interact with Transactions](#how-sdks-interact-with-transactions)
3. [Current State in Dart SDK](#current-state-in-dart-sdk)
4. [Implementation Phases](#implementation-phases)
5. [Design Decisions Summary](#design-decisions-summary)
6. [Gold Standard Features](#gold-standard-features)

## Background: How Transactions Work in SpacetimeDB

In SpacetimeDB, **a transaction is the unit of work in which a reducer executes and modifies the database state atomically**, with all-or-nothing semantics.

### Key Concepts

1. **Reducers run inside database transactions**
   - When a reducer completes successfully, all changes it made (inserts, updates, deletes) are committed
   - If it returns an error or throws an exception, SpacetimeDB reverts all those changes

2. **No nested transactions**
   - If one reducer calls another directly, both execute within the same transaction
   - If the outer reducer completes successfully, changes from the inner reducer persist even if the inner one handled an error internally

3. **Transactions are server-side only**
   - Clients cannot manually begin/commit/rollback transactions
   - All transaction control happens inside SpacetimeDB on the server

## How SDKs Interact with Transactions

Client SDKs interact with transactions **indirectly** through:

### 1. Reducers = Transactional Operations
- When you call a reducer from the SDK, that call runs as a single database transaction on the server
- The SDK lets you invoke reducers and observe their completion, but the server decides commit/rollback semantics

### 2. Subscription Updates Are Per-Transaction
- Each committed transaction produces **at most one** `TransactionUpdate` message that the SDK receives over WebSocket
- The SDK applies this update **atomically** to the client cache (insert/delete/update rows) before firing row callbacks
- Every callback sees a **consistent post-transaction state**

### 3. Event Context Includes Transaction Cause
- Row callbacks receive context about what caused the change:
  - Which reducer caused it (reducer name)
  - Was it from a subscription being applied?
  - Unknown transaction source?
- Transaction metadata: offset, timestamp
- This lets client code react to the outcome of specific transactional operations

### Key Concepts from Other SDKs

The TypeScript, Rust, and C# SDKs provide:
- **EventContext everywhere**: Every callback receives transaction metadata
- **Broadcast pattern**: All clients receive transaction updates from any client
- **Event discrimination**: Can determine if change was from reducer, subscription, or unknown
- **Reducer completion callbacks**: Track when specific reducers complete
- **Fire-and-forget calls**: Client doesn't wait for response, result comes as broadcast

## Current State in Dart SDK

### ✅ What's Already Implemented

1. **Reducer Calls** - `client.reducers.callWith()` invokes server-side transactions
2. **Atomic Cache Updates** - `TransactionUpdateMessage` is received and applied atomically
3. **Row Callbacks** - Streams emit changes after transaction is applied
4. **Transaction Metadata Received** - `TransactionUpdateMessage` contains:
   - `transactionOffset` - Position in transaction log
   - `timestamp` - When transaction occurred
   - `tableUpdates` - What changed

### ❌ What's Missing (Future Work)

1. **EventContext in Stream Events**

   Currently, stream events only contain row data:
   ```dart
   // Current implementation:
   noteTable.insertStream.listen((note) {
     print('New note: ${note.title}');
     // No transaction metadata available!
   });
   ```

   What "Transaction Support" would add:
   ```dart
   // Future implementation:
   noteTable.insertStream.listen((event) {
     print('Note: ${event.row.title}');
     print('Caused by reducer: ${event.reducerName}');
     print('Transaction offset: ${event.transactionOffset}');
     print('Timestamp: ${event.timestamp}');
     print('Event type: ${event.cause}'); // Reducer, Subscription, Unknown
   });
   ```

2. **Reducer Completion Callbacks**

   Track when a specific reducer call completes:
   ```dart
   // Future implementation:
   await client.reducers.createNote(
     title: 'Test',
     content: 'Content',
     onSuccess: (result) {
       print('Reducer committed in transaction ${result.transactionOffset}');
       print('Timestamp: ${result.timestamp}');
     },
     onError: (error) {
       print('Reducer failed: ${error.message}');
     },
   );
   ```

3. **Enhanced TableChange Objects**

   Current `TableChange<T>` structure:
   ```dart
   class TableChange<T> {
     final ChangeType type;
     final T? row;
     final T? oldRow;
     final T? newRow;
   }
   ```

   Future enhancement with transaction context:
   ```dart
   class TableChangeEvent<T> {
     final ChangeType type;
     final T? row;
     final T? oldRow;
     final T? newRow;

     // Transaction metadata:
     final int transactionOffset;
     final int timestamp;
     final String? reducerName;
     final EventCause cause; // Reducer | Subscription | Unknown
   }
   ```

---

## Implementation Phases

## ⚠️ Phase 0: Critical Prerequisites - Reducer Registry & Message Protocol

**Prerequisites:** None (this is the foundation)
**Blocks:** ALL other phases depend on this
**Estimated Time:** 2-3 days

**THIS MUST BE COMPLETED FIRST** - All other phases depend on this foundation.

### Problem Statement

The current Dart SDK has a **critical gap** in the message protocol and architecture:

**What's Missing:**
- ❌ `TransactionUpdateMessage` doesn't include reducer metadata (`reducerInfo`)
- ❌ No `ReducerRegistry` to deserialize reducer arguments
- ❌ No generated `ReducerArgDecoder` classes
- ❌ No way to know which reducer caused a transaction

**Impact:**
Without this infrastructure, you **cannot**:
1. Know which reducer caused a transaction
2. Deserialize reducer arguments from the server
3. Create `ReducerEvent` objects with reducer name and args
4. Implement `onReducerName` completion callbacks
5. Tell users what modified their data in callbacks

**Comparison to TypeScript SDK:**

TypeScript SDK has:
```typescript
// TransactionUpdate message includes:
{
  reducerInfo: {
    reducerName: string,
    args: Uint8Array  // Raw BSATN bytes
  },
  // ... other fields
}

// Reducer registry:
const reducerTypeInfo = this.#remoteModule.reducers[reducerInfo.reducerName];
reducerArgs = reducerTypeInfo.argsType.deserialize(reader);
```

Dart SDK currently has:
```dart
class TransactionUpdateMessage {
  final int timestamp;
  final List<TableUpdate> tableUpdates;
  // ❌ NO reducerInfo field!
}
```

### Step 1: Add ReducerInfo to Message Protocol

**1.1. Create ReducerInfo class** (`lib/src/messages/reducer_info.dart`):

```dart
import 'dart:typed_data';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';

/// Metadata about which reducer caused a transaction
class ReducerInfo {
  final String reducerName;
  final Uint8List args;  // Raw BSATN-encoded arguments

  ReducerInfo({
    required this.reducerName,
    required this.args,
  });

  static ReducerInfo decode(BsatnDecoder decoder) {
    final reducerName = decoder.readString();
    final argsLength = decoder.readU32();
    final args = decoder.readBytes(argsLength);

    return ReducerInfo(
      reducerName: reducerName,
      args: args,
    );
  }
}
```

**1.2. Update TransactionUpdateMessage** (`lib/src/messages/server_messages.dart`):

```dart
class TransactionUpdateMessage implements ServerMessage {
  final int transactionOffset;
  final int timestamp;
  final List<TableUpdate> tableUpdates;

  // NEW: Reducer metadata (null for scheduled reducers or unknown)
  final ReducerInfo? reducerInfo;
  final Uint8List? callerIdentity;
  final Uint8List? callerConnectionId;
  final int? energyConsumed;
  final UpdateStatus status;

  TransactionUpdateMessage({
    required this.transactionOffset,
    required this.timestamp,
    required this.tableUpdates,
    this.reducerInfo,
    this.callerIdentity,
    this.callerConnectionId,
    this.energyConsumed,
    required this.status,
  });

  @override
  ServerMessageType get messageType => ServerMessageType.transactionUpdate;

  static TransactionUpdateMessage decode(BsatnDecoder decoder) {
    // Read UpdateStatus tag
    final statusTag = decoder.readU8();

    UpdateStatus status;
    final List<TableUpdate> tableUpdates;

    if (statusTag == 0) {
      // Committed
      status = Committed();
      tableUpdates = decoder.readList(() => TableUpdate.decode(decoder));
    } else if (statusTag == 1) {
      // Failed
      final errorMessage = decoder.readString();
      status = Failed(errorMessage);
      tableUpdates = [];
    } else if (statusTag == 2) {
      // OutOfEnergy
      final budgetInfo = decoder.readString();
      status = OutOfEnergy(budgetInfo);
      tableUpdates = [];
    } else {
      throw ArgumentError('Unknown UpdateStatus tag: $statusTag');
    }

    // Read timestamp
    final timestamp = decoder.readU64();

    // Read caller identity (optional)
    final callerIdentity = decoder.readOption(() => decoder.readBytes(32));

    // Read reducer info (optional)
    final reducerInfo = decoder.readOption(() => ReducerInfo.decode(decoder));

    // Read energy consumed (optional)
    final energyConsumed = decoder.readOption(() => decoder.readU64());

    // Read caller connection ID (optional)
    final callerConnectionId = decoder.readOption(() => decoder.readBytes(16));

    return TransactionUpdateMessage(
      transactionOffset: 0,  // TODO: Read from message if available
      timestamp: timestamp,
      tableUpdates: tableUpdates,
      reducerInfo: reducerInfo,
      callerIdentity: callerIdentity,
      callerConnectionId: callerConnectionId,
      energyConsumed: energyConsumed,
      status: status,
    );
  }
}
```

**1.3. Create UpdateStatus sealed class** (`lib/src/messages/update_status.dart`):

```dart
sealed class UpdateStatus {}

class Committed extends UpdateStatus {}

class Failed extends UpdateStatus {
  final String message;
  Failed(this.message);
}

class OutOfEnergy extends UpdateStatus {
  final String budgetInfo;
  OutOfEnergy(this.budgetInfo);
}
```

### Step 2: Create ReducerArgDecoder Interface

**2.1. Define decoder interface** (`lib/src/reducers/reducer_arg_decoder.dart`):

```dart
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';

/// Decodes BSATN-encoded reducer arguments into a strongly-typed args object
///
/// Each reducer gets a generated implementation that returns a specific args class.
abstract class ReducerArgDecoder<T> {
  /// Deserialize BSATN bytes into a strongly-typed args object
  ///
  /// Returns null if deserialization fails (e.g., schema mismatch)
  T? decode(BsatnDecoder decoder);
}
```

**2.2. Example generated decoder** (for reference - will be codegen):

```dart
// Args class for reducer: create_note(title: String, content: String)
class CreateNoteArgs {
  final String title;
  final String content;

  CreateNoteArgs({required this.title, required this.content});
}

class CreateNoteArgsDecoder implements ReducerArgDecoder<CreateNoteArgs> {
  @override
  CreateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final title = decoder.readString();
      final content = decoder.readString();
      return CreateNoteArgs(title: title, content: content);
    } catch (e) {
      // Deserialization failed - schema mismatch or corrupt data
      return null;
    }
  }
}

// Args class for reducer: update_note(id: u32, title: String, content: String)
class UpdateNoteArgs {
  final int id;
  final String title;
  final String content;

  UpdateNoteArgs({required this.id, required this.title, required this.content});
}

class UpdateNoteArgsDecoder implements ReducerArgDecoder<UpdateNoteArgs> {
  @override
  UpdateNoteArgs? decode(BsatnDecoder decoder) {
    try {
      final id = decoder.readU32();
      final title = decoder.readString();
      final content = decoder.readString();
      return UpdateNoteArgs(id: id, title: title, content: content);
    } catch (e) {
      return null;
    }
  }
}
```

### Step 3: Create ReducerRegistry

**3.1. Implement registry** (`lib/src/reducers/reducer_registry.dart`):

```dart
import 'dart:typed_data';
import 'package:spacetimedb_dart_sdk/src/codec/bsatn_decoder.dart';
import 'package:spacetimedb_dart_sdk/src/reducers/reducer_arg_decoder.dart';

/// Registry for reducer argument decoders
///
/// Mirrors the ClientCache pattern for tables, but for reducers.
/// Each reducer has a decoder that knows how to deserialize its arguments
/// into strongly-typed args objects.
class ReducerRegistry {
  // Store decoders with type erasure, but they return strongly-typed objects
  final Map<String, ReducerArgDecoder> _decoders = {};

  /// Register a decoder for a reducer's arguments
  ///
  /// Called during client initialization with generated decoders.
  ///
  /// Example:
  /// ```dart
  /// registry.registerDecoder('create_note', CreateNoteArgsDecoder());
  /// ```
  void registerDecoder(String reducerName, ReducerArgDecoder decoder) {
    if (_decoders.containsKey(reducerName)) {
      throw ArgumentError('Decoder for reducer "$reducerName" already registered');
    }
    _decoders[reducerName] = decoder;
  }

  /// Deserialize reducer arguments from BSATN bytes into strongly-typed args object
  ///
  /// Returns null if:
  /// - Reducer is not registered (unknown reducer)
  /// - Deserialization fails (schema mismatch, corrupt data)
  ///
  /// The returned object is strongly-typed (e.g., CreateNoteArgs, UpdateNoteArgs)
  /// but stored as dynamic due to type erasure in the map.
  ///
  /// Example:
  /// ```dart
  /// final args = registry.deserializeArgs('create_note', rawBytes);
  /// // args is a CreateNoteArgs object, but type is dynamic here
  /// ```
  dynamic deserializeArgs(String reducerName, Uint8List bytes) {
    final decoder = _decoders[reducerName];
    if (decoder == null) {
      // Unknown reducer - server might have reducers we don't know about
      return null;
    }

    return decoder.decode(BsatnDecoder(bytes));
  }

  /// Check if a reducer is registered
  bool hasDecoder(String reducerName) => _decoders.containsKey(reducerName);

  /// Get list of all registered reducer names (for debugging)
  List<String> get registeredReducers => _decoders.keys.toList();
}
```

### Step 4: Update Code Generator

**4.1. Update ReducerGenerator** to generate decoders with complex type support:

```dart
// In lib/src/codegen/reducer_generator.dart

String generateReducerDecoders() {
  final buf = StringBuffer();

  buf.writeln('// GENERATED REDUCER ARGUMENT DECODERS');
  buf.writeln();
  buf.writeln("import 'package:spacetimedb_dart_sdk/spacetimedb_dart_sdk.dart';");
  buf.writeln();

  // Generate args class and decoder for each reducer
  for (final reducer in reducers) {
    _generateReducerArgsClass(buf, reducer);
    buf.writeln();
    _generateReducerDecoder(buf, reducer);
    buf.writeln();
  }

  return buf.toString();
}

/// Generate the strongly-typed args class for a reducer
void _generateReducerArgsClass(StringBuffer buf, ReducerSchema reducer) {
  final className = _toPascalCase(reducer.name) + 'Args';

  buf.writeln('class $className {');

  // Generate fields
  for (final param in reducer.params.elements) {
    final paramName = _toCamelCase(param.name ?? 'unknown');
    final dartType = TypeMapper.getDartType(param.algebraicType);
    buf.writeln('  final $dartType $paramName;');
  }

  buf.writeln();

  // Generate constructor
  buf.write('  $className({');
  for (final param in reducer.params.elements) {
    final paramName = _toCamelCase(param.name ?? 'unknown');
    buf.write('required this.$paramName, ');
  }
  buf.writeln('});');

  buf.writeln('}');
}

/// Generate the decoder for a reducer's arguments
void _generateReducerDecoder(StringBuffer buf, ReducerSchema reducer) {
  final argsClassName = _toPascalCase(reducer.name) + 'Args';
  final decoderClassName = _toPascalCase(reducer.name) + 'ArgsDecoder';

  buf.writeln('class $decoderClassName implements ReducerArgDecoder<$argsClassName> {');
  buf.writeln('  @override');
  buf.writeln('  $argsClassName? decode(BsatnDecoder decoder) {');
  buf.writeln('    try {');

  // Decode each parameter
  for (final param in reducer.params.elements) {
    final paramName = _toCamelCase(param.name ?? 'unknown');
    _generateArgDecode(buf, paramName, param.algebraicType);
  }

  buf.writeln();
  buf.writeln('      return $argsClassName(');
  for (final param in reducer.params.elements) {
    final paramName = _toCamelCase(param.name ?? 'unknown');
    buf.writeln('        $paramName: $paramName,');
  }
  buf.writeln('      );');

  buf.writeln('    } catch (e) {');
  buf.writeln('      return null; // Deserialization failed');
  buf.writeln('    }');
  buf.writeln('  }');
  buf.writeln('}');
}

/// 🌟 GOLD STANDARD: Handle both primitive and complex types
///
/// This is the critical branching logic that makes the SDK "first in class".
/// It handles nested structs and enums inside reducer arguments.
void _generateArgDecode(StringBuffer buf, String fieldName, AlgebraicType type) {
  if (TypeMapper.isPrimitive(type)) {
    // Case A: Primitive type (int, String, bool, etc.)
    // Use BsatnDecoder's built-in read methods
    final method = TypeMapper.getDecoderMethod(type);
    buf.writeln('      final $fieldName = decoder.$method();');
  } else {
    // Case B: Complex type (custom struct or enum)
    // Use the static decode method of the generated class
    final typeName = TypeMapper.getDartClassName(type);
    buf.writeln('      final $fieldName = $typeName.decode(decoder);');
  }
}
```

**Example generated output for complex types:**

```dart
// For reducer: update_address(addr: Address)
class Address {
  final String street;
  final int zip;
  Address({required this.street, required this.zip});

  static Address decode(BsatnDecoder decoder) {
    return Address(
      street: decoder.readString(),
      zip: decoder.readU32(),
    );
  }
}

class UpdateAddressArgs {
  final Address addr;
  UpdateAddressArgs({required this.addr});
}

class UpdateAddressArgsDecoder implements ReducerArgDecoder<UpdateAddressArgs> {
  @override
  UpdateAddressArgs? decode(BsatnDecoder decoder) {
    try {
      // Uses Address.decode() for complex type
      final addr = Address.decode(decoder);

      return UpdateAddressArgs(addr: addr);
    } catch (e) {
      return null;
    }
  }
}
```

**4.2. Update ClientGenerator** to register decoders:

```dart
// In generated client initialization:

class SpacetimeDbClient {
  final ReducerRegistry reducerRegistry = ReducerRegistry();

  SpacetimeDbClient(...) {
    // Register table decoders
    cache.registerDecoder<Note>('note', NoteDecoder());

    // Register reducer decoders
    reducerRegistry.registerDecoder('create_note', CreateNoteArgsDecoder());
    reducerRegistry.registerDecoder('update_note', UpdateNoteArgsDecoder());
    reducerRegistry.registerDecoder('delete_note', DeleteNoteArgsDecoder());
  }
}
```

### Step 5: Integration with SubscriptionManager

**5.1. Add ReducerRegistry to SubscriptionManager**:

```dart
class SubscriptionManager {
  final ClientCache cache;
  final ReducerRegistry reducerRegistry;  // NEW

  SubscriptionManager(
    this._connection,
    this.cache,
    this.reducerRegistry,  // NEW
  );

  void _handleTransactionUpdate(TransactionUpdateMessage message) {
    // 1. Deserialize reducer arguments if present
    Map<String, dynamic>? reducerArgs;
    if (message.reducerInfo != null) {
      reducerArgs = reducerRegistry.deserializeArgs(
        message.reducerInfo!.reducerName,
        message.reducerInfo!.args,
      );
    }

    // 2. Create Event (will be used in Phase 1+)
    // For now, just log that we have the data
    if (message.reducerInfo != null && reducerArgs != null) {
      _logger.d('Transaction caused by reducer: ${message.reducerInfo!.reducerName}');
      _logger.d('Arguments: $reducerArgs');
      _logger.d('Status: ${message.status}');
      _logger.d('Caller: ${message.callerIdentity}');
    }

    // 3. Apply table updates (existing logic)
    for (final tableUpdate in message.tableUpdates) {
      // ... existing code ...
    }
  }
}
```

### Step 6: Testing Phase 0

Before proceeding to Phase 1, verify:

**6.1. Message decoding test**:
```dart
test('TransactionUpdateMessage includes reducer metadata', () {
  // Create message with reducer info
  // Verify all fields are decoded correctly
  // Verify optional fields handle null
});
```

**6.2. Reducer registry test**:
```dart
test('ReducerRegistry deserializes arguments', () {
  final registry = ReducerRegistry();
  registry.registerDecoder('create_note', CreateNoteArgsDecoder());

  final encoder = BsatnEncoder();
  encoder.writeString('Test Title');
  encoder.writeString('Test Content');

  final args = registry.deserializeArgs('create_note', encoder.toBytes());
  expect(args, isNotNull);
  expect(args!['title'], 'Test Title');
  expect(args['content'], 'Test Content');
});
```

**6.3. Integration test**:
```dart
test('TransactionUpdate with reducer info flows through system', () async {
  // Connect to test database
  // Call a reducer
  // Verify TransactionUpdate is received with reducerInfo
  // Verify arguments are deserialized correctly
});
```

### Completion Criteria for Phase 0

✅ **Phase 0 is complete when:**
1. `TransactionUpdateMessage` includes `reducerInfo` and metadata fields
2. `ReducerRegistry` successfully deserializes arguments
3. Code generator produces `ReducerArgDecoder` for each reducer
4. Generated client registers all reducer decoders
5. `SubscriptionManager` can access reducer name and deserialized args
6. All Phase 0 tests pass

**Only then** can you proceed to Phase 1 (Event types) and beyond.

---

---

### Phase 1: Core Event Types

**Prerequisites:** Phase 0 complete (ReducerRegistry and message protocol)
**Blocks:** Phase 2, Phase 3, Phase 4, Phase 6
**Estimated Time:** 1 day

**Goal:** Create the foundational event type system that represents transaction metadata.

#### Step 1.1: Create Event sealed class

**File:** `lib/src/events/event.dart`

Create the base Event type and its variants:

```dart
import 'dart:typed_data';
import 'update_status.dart';

sealed class Event {}

class ReducerEvent extends Event {
  final int timestamp;
  final UpdateStatus status;
  final Uint8List callerIdentity;
  final Uint8List? callerConnectionId;
  final int? energyConsumed;
  final String reducerName;

  /// Strongly-typed reducer arguments object
  ///
  /// This is the actual args class (e.g., CreateNoteArgs, UpdateNoteArgs)
  /// deserialized by the ReducerArgDecoder. Type is dynamic due to
  /// heterogeneous storage, but the actual runtime type is preserved.
  ///
  /// Generator knows the concrete type when creating listeners.
  final dynamic reducerArgs;

  ReducerEvent({
    required this.timestamp,
    required this.status,
    required this.callerIdentity,
    this.callerConnectionId,
    this.energyConsumed,
    required this.reducerName,
    required this.reducerArgs,
  });
}

class SubscribeAppliedEvent extends Event {}
class UnknownTransactionEvent extends Event {}
```

**Test:** Verify sealed class pattern matching works:
```dart
void testEvent(Event event) {
  switch (event) {
    case ReducerEvent():
      print('Reducer event');
    case SubscribeAppliedEvent():
      print('Subscription applied');
    case UnknownTransactionEvent():
      print('Unknown transaction');
  }
}
```

---

#### Step 1.2: Create UpdateStatus sealed class

**File:** `lib/src/events/update_status.dart`

Create the status enum for transaction outcomes:

```dart
sealed class UpdateStatus {}

class Committed extends UpdateStatus {}

class Failed extends UpdateStatus {
  final String message;
  Failed(this.message);
}

class OutOfEnergy extends UpdateStatus {
  final String budgetInfo;
  OutOfEnergy(this.budgetInfo);
}
```

**Test:** Verify pattern matching on status:
```dart
void handleStatus(UpdateStatus status) {
  switch (status) {
    case Committed():
      print('Success!');
    case Failed(:final message):
      print('Failed: $message');
    case OutOfEnergy(:final budgetInfo):
      print('Out of energy: $budgetInfo');
  }
}
```

---

#### Step 1.3: Create EventContext class with DX helper

**File:** `lib/src/events/event_context.dart`

Create the context object that wraps events with client access:

```dart
import 'dart:typed_data';
import 'event.dart';

class EventContext {
  final SpacetimeDbClient client;
  final Event event;

  EventContext({
    required this.client,
    required this.event,
  });

  // Convenience accessors
  RemoteTables get db => client.db;
  RemoteReducers get reducers => client.reducers;

  /// 🌟 GOLD STANDARD: DX Helper - Check if this event was triggered by current client
  ///
  /// Returns true if this transaction was initiated by the current connection.
  /// This is a common check that would otherwise require verbose boilerplate.
  ///
  /// Example:
  /// ```dart
  /// noteTable.insertEventStream.listen((event) {
  ///   if (event.context.isMyTransaction) {
  ///     print('I created this note!');
  ///   } else {
  ///     print('Someone else created this note');
  ///   }
  /// });
  /// ```
  bool get isMyTransaction {
    if (event is! ReducerEvent) return false;

    final reducerEvent = event;
    final myConnectionId = client.connection.connectionId;
    final callerConnectionId = reducerEvent.callerConnectionId;

    // Handle null cases
    if (myConnectionId == null || callerConnectionId == null) return false;

    // Compare byte arrays for equality
    return _bytesEqual(myConnectionId, callerConnectionId);
  }

  /// Helper to compare two byte arrays for equality
  static bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }
}
```

**Test:** Verify isMyTransaction helper:
```dart
test('isMyTransaction returns true for own transactions', () {
  final myConnectionId = Uint8List.fromList([1, 2, 3, 4]);
  final client = MockClient(connectionId: myConnectionId);

  final event = ReducerEvent(
    timestamp: 123,
    status: Committed(),
    callerIdentity: Uint8List(32),
    callerConnectionId: myConnectionId,
    energyConsumed: 100,
    reducerName: 'test',
    reducerArgs: {},
  );

  final ctx = EventContext(client: client, event: event);
  expect(ctx.isMyTransaction, isTrue);
});
```

---

#### Step 1.4: Create TableEvent hierarchy

**File:** `lib/src/events/table_event.dart`

Create the sealed class hierarchy for table change events:

```dart
import 'event_context.dart';

/// Base class for all table change events
/// Provides unified access to EventContext across all event types
sealed class TableEvent<T> {
  EventContext get context;
}

/// Row insertion event
class TableInsertEvent<T> extends TableEvent<T> {
  @override
  final EventContext context;
  final T row;

  TableInsertEvent(this.context, this.row);
}

/// Row update event (old value → new value)
class TableUpdateEvent<T> extends TableEvent<T> {
  @override
  final EventContext context;
  final T oldRow;
  final T newRow;

  TableUpdateEvent(this.context, this.oldRow, this.newRow);
}

/// Row deletion event
class TableDeleteEvent<T> extends TableEvent<T> {
  @override
  final EventContext context;
  final T row;

  TableDeleteEvent(this.context, this.row);
}
```

**Test:** Verify pattern matching works with generic handler:
```dart
void handleTableEvent<T>(TableEvent<T> event) {
  switch (event) {
    case TableInsertEvent(:final row, :final context):
      print('Inserted: $row, isMyTx: ${context.isMyTransaction}');
    case TableUpdateEvent(:final oldRow, :final newRow):
      print('Updated: $oldRow → $newRow');
    case TableDeleteEvent(:final row):
      print('Deleted: $row');
  }
}
```

---

#### Phase 1: Completion Criteria

✅ **Phase 1 is complete when:**
- [ ] All four files created (`event.dart`, `update_status.dart`, `event_context.dart`, `table_event.dart`)
- [ ] All classes compile without errors
- [ ] Pattern matching works on Event sealed class
- [ ] Pattern matching works on UpdateStatus sealed class
- [ ] Pattern matching works on TableEvent sealed class
- [ ] `isMyTransaction` helper correctly compares connection IDs
- [ ] Unit tests pass for `EventContext._bytesEqual()`
- [ ] Generic `handleTableEvent<T>()` function compiles and runs
- [ ] No `as` casts used anywhere (only type guards)

**Next:** Proceed to Phase 2 (Update Message Handling)

---

3. **Original EventContext code (moved to Step 1.3 above)**:
   ```dart
   import 'dart:typed_data';

   class EventContext {
     final SpacetimeDbClient client;
     final Event event;

     EventContext({
       required this.client,
       required this.event,
     });

     // Convenience accessors
     RemoteTables get db => client.db;
     RemoteReducers get reducers => client.reducers;

     /// 🌟 GOLD STANDARD: DX Helper - Check if this event was triggered by current client
     ///
     /// Returns true if this transaction was initiated by the current connection.
     /// This is a common check that would otherwise require verbose boilerplate.
     ///
     /// Example:
     /// ```dart
     /// noteTable.insertEventStream.listen((event) {
     ///   if (event.context.isMyTransaction) {
     ///     print('I created this note!');
     ///   } else {
     ///     print('Someone else created this note');
     ///   }
     /// });
     /// ```
     bool get isMyTransaction {
       if (event is! ReducerEvent) return false;

       final reducerEvent = event;
       final myConnectionId = client.connection.connectionId;
       final callerConnectionId = reducerEvent.callerConnectionId;

       // Handle null cases
       if (myConnectionId == null || callerConnectionId == null) return false;

       // Compare byte arrays for equality
       return _bytesEqual(myConnectionId, callerConnectionId);
     }

     /// Helper to compare two byte arrays for equality
     static bool _bytesEqual(Uint8List? a, Uint8List? b) {
       if (a == null || b == null) return false;
       if (a.length != b.length) return false;

       for (int i = 0; i < a.length; i++) {
         if (a[i] != b[i]) return false;
       }

       return true;
     }
   }
   ```

   **Before vs After:**
   ```dart
   // ❌ Before: Verbose boilerplate
   noteTable.insertEventStream.listen((event) {
     if (event.context.event is ReducerEvent) {
       final reducerEvent = event.context.event;
       if (reducerEvent.callerConnectionId != null &&
           client.connection.connectionId != null &&
           _bytesEqual(reducerEvent.callerConnectionId, client.connection.connectionId)) {
         print('I created this!');
       }
     }
   });

   // ✅ After: Clean DX
   noteTable.insertEventStream.listen((event) {
     if (event.context.isMyTransaction) {
       print('I created this!');
     }
   });
   ```

---

### Phase 2: Update Message Handling

**Prerequisites:** Phase 0 (ReducerRegistry), Phase 1 (Event types)
**Blocks:** Phase 3, Phase 6
**Estimated Time:** 1 day

**Goal:** Wire up the event system to process TransactionUpdate messages and create EventContext.

#### Step 2.1: Enhance TransactionUpdateMessage processing

**File:** `lib/src/subscription/subscription_manager.dart`

Update `_handleTransactionUpdate` to create Event and EventContext:

```dart
void _handleTransactionUpdate(TransactionUpdateMessage message) {
  // 1. Deserialize reducer info if present
  Event event;

  if (message.reducerInfo != null) {
    try {
      // Use ReducerRegistry to deserialize arguments
      final reducerArgs = reducerRegistry.deserializeArgs(
        message.reducerInfo!.reducerName,
        message.reducerInfo!.args,
      );

      event = ReducerEvent(
        timestamp: message.timestamp,
        status: message.status,
        callerIdentity: message.callerIdentity ?? Uint8List(0),
        callerConnectionId: message.callerConnectionId,
        energyConsumed: message.energyConsumed,
        reducerName: message.reducerInfo!.reducerName,
        reducerArgs: reducerArgs,
      );
    } catch (e) {
      // Deserialization failed - unknown reducer or corrupt data
      event = UnknownTransactionEvent();
    }
  } else {
    // No reducer info - unknown transaction source
    event = UnknownTransactionEvent();
  }

  // 2. Create EventContext
  final context = EventContext(client: _client, event: event);

  // 3. Apply table updates with context
  _applyTableUpdates(message.tableUpdates, context);

  // 4. Emit reducer completion callback (Phase 4)
  if (event is ReducerEvent) {
    _emitReducerCallback(event.reducerName, context);
  }
}
```

**Test:** Verify EventContext is created correctly for different event types:
```dart
test('creates ReducerEvent when reducerInfo present', () {
  final message = TransactionUpdateMessage(
    reducerInfo: ReducerInfo(reducerName: 'test', args: Uint8List(0)),
    timestamp: 123,
    status: Committed(),
    // ...
  );

  // After processing, verify event is ReducerEvent
  expect(capturedContext.event, isA<ReducerEvent>());
});
```

---

#### Step 2.2: Update TableCache to accept EventContext

**File:** `lib/src/cache/table_cache.dart`

Update the cache to receive and pass through EventContext:

```dart
/// Apply transaction update with event context
void applyTransactionUpdate(
  BsatnRowList deletes,
  BsatnRowList inserts,
  EventContext context,  // NEW: Add context parameter
) {
  final changes = _applyChanges(deletes, inserts);
  _emitChanges(changes, context);  // Pass context to emission
}

/// Emit changes to streams (Phase 3 will update this)
void _emitChanges(_RowChanges<T> changes, EventContext context) {
  // For now, emit to existing simple streams (Phase 3 adds event streams)
  for (final row in changes.inserted) {
    _insertController.add(row);
    _changeController.add(TableChange.insert(row));
  }

  for (final (oldRow, newRow) in changes.updated) {
    _updateController.add(TableUpdate(oldRow, newRow));
    _changeController.add(TableChange.update(oldRow, newRow));
  }

  for (final row in changes.deleted) {
    _deleteController.add(row);
    _changeController.add(TableChange.delete(row));
  }

  // Phase 3 will add: emit to event streams with context
}
```

**Test:** Verify context is passed through correctly:
```dart
test('applyTransactionUpdate passes context through', () {
  final context = EventContext(
    client: mockClient,
    event: ReducerEvent(/* ... */),
  );

  tableCache.applyTransactionUpdate(deletes, inserts, context);

  // Verify context was captured (Phase 3 will emit it)
  expect(capturedContext, equals(context));
});
```

---

#### Phase 2: Completion Criteria

✅ **Phase 2 is complete when:**
- [ ] `_handleTransactionUpdate` creates Event from TransactionUpdateMessage
- [ ] `ReducerEvent` created when reducerInfo present
- [ ] `UnknownTransactionEvent` created when reducerInfo missing
- [ ] EventContext wraps Event with client reference
- [ ] `TableCache.applyTransactionUpdate` accepts EventContext parameter
- [ ] Context is passed to `_emitChanges` method
- [ ] All existing tests still pass (simple streams still work)
- [ ] Unit tests verify correct Event type creation
- [ ] No `as` casts used (only type guards)

**Next:** Proceed to Phase 3 (Enhanced Stream Events)

---

---

### Phase 3: Enhanced Stream Events

**Prerequisites:** Phase 1 (Event types), Phase 2 (Message handling)
**Blocks:** None (independent feature)
**Estimated Time:** 1-2 days

**Goal:** Add enhanced event streams alongside simple streams (side-by-side approach for backward compatibility).

#### Step 3.1: Add event stream controllers to TableCache

**File:** `lib/src/cache/table_cache.dart`

Add new StreamControllers alongside existing ones:

```dart
class TableCache<T> {
  // === Existing simple streams (keep unchanged) ===
  final _insertController = StreamController<T>.broadcast();
  final _updateController = StreamController<TableUpdate<T>>.broadcast();
  final _deleteController = StreamController<T>.broadcast();

  Stream<T> get insertStream => _insertController.stream;
  Stream<TableUpdate<T>> get updateStream => _updateController.stream;
  Stream<T> get deleteStream => _deleteController.stream;

  // === NEW: Event streams with context ===
  final _insertEventController = StreamController<TableInsertEvent<T>>.broadcast();
  final _updateEventController = StreamController<TableUpdateEvent<T>>.broadcast();
  final _deleteEventController = StreamController<TableDeleteEvent<T>>.broadcast();
  final _eventController = StreamController<TableEvent<T>>.broadcast();

  Stream<TableInsertEvent<T>> get insertEventStream => _insertEventController.stream;
  Stream<TableUpdateEvent<T>> get updateEventStream => _updateEventController.stream;
  Stream<TableDeleteEvent<T>> get deleteEventStream => _deleteEventController.stream;
  Stream<TableEvent<T>> get eventStream => _eventController.stream;
}
```

**Test:** Verify controllers are created and streams are accessible.

---

#### Step 3.2: Update _emitChanges to emit to both stream types

**File:** `lib/src/cache/table_cache.dart`

Emit to both simple streams (existing) and event streams (new):

```dart
void _emitChanges(_RowChanges<T> changes, EventContext context) {
  // Emit inserts
  for (final row in changes.inserted) {
    // Simple stream (existing - no context)
    _insertController.add(row);

    // Event streams (new - with context)
    final insertEvent = TableInsertEvent(context, row);
    _insertEventController.add(insertEvent);
    _eventController.add(insertEvent);
  }

  // Emit updates
  for (final (oldRow, newRow) in changes.updated) {
    // Simple stream (existing - no context)
    _updateController.add(TableUpdate(oldRow, newRow));

    // Event streams (new - with context)
    final updateEvent = TableUpdateEvent(context, oldRow, newRow);
    _updateEventController.add(updateEvent);
    _eventController.add(updateEvent);
  }

  // Emit deletes
  for (final row in changes.deleted) {
    // Simple stream (existing - no context)
    _deleteController.add(row);

    // Event streams (new - with context)
    final deleteEvent = TableDeleteEvent(context, row);
    _deleteEventController.add(deleteEvent);
    _eventController.add(deleteEvent);
  }
}
```

**Test:** Verify both stream types receive events:
```dart
test('emits to both simple and event streams', () {
  var simpleReceived = false;
  var eventReceived = false;

  table.insertStream.listen((_) => simpleReceived = true);
  table.insertEventStream.listen((_) => eventReceived = true);

  table.applyTransactionUpdate(deletes, inserts, context);

  expect(simpleReceived, isTrue);
  expect(eventReceived, isTrue);
});
```

---

#### Step 3.3: Add convenience methods for filtering by transaction type

**File:** `lib/src/cache/table_cache.dart`

Add helper methods for common filtering patterns:

```dart
/// Stream of inserts from reducer events only (not subscriptions)
Stream<TableInsertEvent<T>> get insertsFromReducers =>
    insertEventStream.where((e) => e.context.event is ReducerEvent);

/// Stream of inserts from the current client only
Stream<TableInsertEvent<T>> get myInserts =>
    insertEventStream.where((e) => e.context.isMyTransaction);

/// Stream of all events from reducers
Stream<TableEvent<T>> get eventsFromReducers =>
    eventStream.where((e) => e.context.event is ReducerEvent);
```

**Usage example:**
```dart
// Only listen to notes I created
noteTable.myInserts.listen((event) {
  print('I created: ${event.row.title}');
});

// Only listen to reducer-caused changes (not subscription loads)
noteTable.eventsFromReducers.listen((event) {
  switch (event) {
    case TableInsertEvent(:final row):
      print('Note added by reducer: ${row.title}');
    case TableUpdateEvent(:final oldRow, :final newRow):
      print('Note updated: ${oldRow.title} → ${newRow.title}');
    case TableDeleteEvent(:final row):
      print('Note deleted: ${row.title}');
  }
});
```

---

#### Phase 3: Completion Criteria

✅ **Phase 3 is complete when:**
- [ ] Event stream controllers added to TableCache
- [ ] Simple streams still work (backward compatibility)
- [ ] Event streams emit TableEvent subclasses with context
- [ ] `insertEventStream`, `updateEventStream`, `deleteEventStream` work
- [ ] Unified `eventStream` emits all change types
- [ ] Convenience filters (`myInserts`, `insertsFromReducers`) work
- [ ] Pattern matching works on TableEvent sealed class
- [ ] All existing tests pass
- [ ] New tests verify both stream types emit
- [ ] User can access `context.isMyTransaction` from event streams

**Next:** Proceed to Phase 4 (Reducer Completion API)

---

### Phase 4: Reducer Completion API

**Design Decision: Typed Callback with StreamSubscription Return**

While the "pure Dart way" would be to expose `Stream<ReducerEventContext<CreateNoteArgs>>`, this creates significant codegen complexity:
- Must generate `CreateNoteArgs` class for EVERY reducer
- Type erasure challenges storing typed streams
- For schemas with 50+ reducers, generates hundreds of extra classes

**Chosen Approach: Typed Callback Pattern**

This is a pragmatic middle ground:
- ✅ **Type-safe arguments** - Strongly typed at the call site
- ✅ **Returns StreamSubscription** - Cancellable like streams
- ✅ **Minimal codegen** - No wrapper classes needed
- ✅ **Still "Dart-ish"** - Not just a void callback

**Implementation:**

1. **Add reducer event emitter** to generated reducers class:
   ```dart
   class RemoteReducers {
     final ReducerEmitter _emitter;

     void createNote(String title, String content) {
       // Existing call logic...
     }

     /// Listen for when createNote completes (broadcast to all clients)
     ///
     /// Returns a [StreamSubscription] that can be cancelled.
     ///
     /// **Important:** This callback fires for ALL clients when ANY client
     /// calls this reducer. Use [EventContext.event.callerConnectionId]
     /// to determine if this was your call.
     ///
     /// Example:
     /// ```dart
     /// final subscription = client.reducers.onCreateNote((ctx, title, content) {
     ///   if (ctx.event case ReducerEvent(:final status, :final callerConnectionId)) {
     ///     print('createNote completed: $status');
     ///     if (callerConnectionId == client.connectionId) {
     ///       print('This was OUR call!');
     ///     }
     ///   }
     /// });
     ///
     /// // Cancel when done
     /// subscription.cancel();
     /// ```
     StreamSubscription<void> onCreateNote(
       void Function(EventContext ctx, String title, String content) callback
     ) {
       return _emitter.on('create_note').listen((ctx) {
         if (ctx.event is ReducerEvent) {
           final event = ctx.event as ReducerEvent;
           final args = event.reducerArgs;
           callback(ctx, args['title'] as String, args['content'] as String);
         }
       });
     }
   }
   ```

2. **User code**:
   ```dart
   // Call reducer
   client.reducers.createNote('Test', 'Content');

   // Listen for completion (fires for ALL clients)
   final subscription = client.reducers.onCreateNote((ctx, title, content) {
     if (ctx.event case ReducerEvent(:final status, :final callerConnectionId, :final energyConsumed)) {
       print('createNote completed: $status');
       print('Arguments: title="$title", content="$content"');
       print('Energy used: $energyConsumed eV');

       // Check if this was OUR call
       if (callerConnectionId == client.connectionId) {
         print('Our reducer call completed!');
       } else {
         print('Another client called this reducer');
       }

       // Handle status
       switch (status) {
         case Committed():
           print('Reducer committed successfully');
         case Failed(:final message):
           print('Reducer failed: $message');
         case OutOfEnergy(:final budgetInfo):
           print('Out of energy: $budgetInfo');
       }
     }
   });

   // Cancel when no longer needed
   subscription.cancel();
   ```

**Alternative: If you want a pure Stream approach later**

If the codegen complexity becomes acceptable (e.g., with better tooling), the API can be extended:

```dart
// V2: Pure stream approach (future enhancement)
Stream<ReducerEvent> get createNoteStream => _emitter.on('create_note')
  .where((ctx) => ctx.event is ReducerEvent)
  .map((ctx) => ctx.event as ReducerEvent);

// Usage with Stream operators
client.reducers.createNoteStream
  .where((event) => event.status is Committed)
  .listen((event) {
    print('Successful createNote: ${event.reducerArgs}');
  });
```

But for **V1**, the typed callback approach is simpler and more practical.

**Implementation Guidance for Code Generator:**

The generated code extracts strongly-typed fields from the args object:

```dart
// GENERATED ARGS CLASS
class CreateNoteArgs {
  final String title;
  final String content;
  CreateNoteArgs({required this.title, required this.content});
}

// GENERATED CODE - Example for create_note reducer
StreamSubscription<void> onCreateNote(
  void Function(EventContext ctx, String title, String content) callback
) {
  // 1. Listen to the central event emitter
  return _reducerEmitter.on('create_note').listen((EventContext ctx) {
    // 2. Safety check - ensure this is a ReducerEvent
    if (ctx.event is! ReducerEvent) return;
    final event = ctx.event;

    // 3. Type-safe argument extraction using pattern matching
    // NO AS CASTS - args is already the correct type from decoder
    final args = event.reducerArgs;
    if (args is! CreateNoteArgs) return; // Type guard

    // 4. Extract fields directly from strongly-typed object
    callback(ctx, args.title, args.content);
  });
}
```

**Key implementation notes:**
- Generator creates an args class for each reducer (e.g., `CreateNoteArgs`)
- `ReducerArgDecoder<CreateNoteArgs>` returns strongly-typed object
- Generated listener uses type guard (`is!`) to ensure correct type
- Fields extracted directly from typed object - **NO `as` CASTS**
- Type safety through object structure, not runtime casting

**⚠️ CRITICAL: NO `as` CASTS ALLOWED**

**STRICTLY FORBIDDEN:** Do NOT use `as` casts anywhere:

```dart
// ❌ BANNED - as cast
final String argTitle = event.reducerArgs['title'] as String;
```

```dart
// ❌ BANNED - as cast on args object
final args = event.reducerArgs as CreateNoteArgs;
```

**WHY `as` CASTS ARE FORBIDDEN:**
- Unsafe if types don't match (runtime crash)
- Bypasses Dart's type system
- Hides type errors until runtime
- Makes code harder to reason about

**CORRECT APPROACH:** Type guards with early return:

```dart
// ✅ CORRECT - Type guard with early return
final args = event.reducerArgs;
if (args is! CreateNoteArgs) return;

// Now args is promoted to CreateNoteArgs automatically
callback(ctx, args.title, args.content);
```

**Type System Guarantee:** The `is!` check ensures the type is correct, and Dart's type promotion automatically treats `args` as `CreateNoteArgs` after the check. NO casting needed.

**For a reducer with different parameter types:**
```dart
// GENERATED ARGS CLASS
class UpdateNoteArgs {
  final int id;
  final String title;
  final String content;
  UpdateNoteArgs({required this.id, required this.title, required this.content});
}

// update_note(id: u32, title: String, content: String)
StreamSubscription<void> onUpdateNote(
  void Function(EventContext ctx, int id, String title, String content) callback
) {
  return _reducerEmitter.on('update_note').listen((EventContext ctx) {
    if (ctx.event is! ReducerEvent) return;
    final event = ctx.event;

    // Type guard - NO as cast
    final args = event.reducerArgs;
    if (args is! UpdateNoteArgs) return;

    // Extract fields from strongly-typed object
    callback(ctx, args.id, args.title, args.content);
  });
}
```

### Phase 5: Code Generation Updates

Update `client_generator.dart` to generate:

1. **EventContext-aware table accessors**
2. **Reducer completion callbacks** (`onReducerName` methods)
3. **Type-safe event context** for the specific schema

Example generated code:
```dart
class SpacetimeDbClient {
  // Existing...

  // Enhanced table accessors with event streams
  NoteTable get notes => _notes;

  // Reducers with completion callbacks
  RemoteReducers get reducers => _reducers;
}

class RemoteReducers {
  void createNote(String title, String content) { /* ... */ }

  StreamSubscription<EventContext> onCreateNote(
    void Function(EventContext, String title, String content) callback
  ) { /* ... */ }
}
```

### Phase 6: Initial Subscription Handling

Mark initial subscription data with special event:

```dart
void _handleInitialSubscription(InitialSubscriptionMessage message) {
  final event = SubscribeAppliedEvent();
  final context = EventContext(client: client, event: event);

  // Apply all table data with SubscribeApplied context
  for (final tableUpdate in message.tableUpdates) {
    cache.activateTable(tableUpdate.tableId, tableUpdate.tableName);
    final table = cache.getTable(tableUpdate.tableId);

    for (final update in tableUpdate.updates) {
      table.applyInitialData(update.update.inserts, context);
    }
  }
}
```

User can then differentiate:
```dart
noteTable.insertEventStream.listen((event) {
  if (event.context.event is SubscribeAppliedEvent) {
    print('Initial data load');
  } else if (event.context.event is ReducerEvent) {
    print('Real-time update from reducer');
  }
});
```

## Implementation Plan

## Recommended Approach: Side-by-Side Streams

Since the SDK hasn't been released publicly yet, we recommend **Option B (Non-Breaking)** from Phase 3:

### Benefits:
1. **Simple API remains simple** - `insertStream.listen((note) => ...)` for basic use cases
2. **Advanced users get full context** - `insertEventStream.listen((event) => ...)` for transaction metadata
3. **Zero breaking changes** - Existing code continues to work
4. **Progressive enhancement** - Users opt-in to complexity when needed
5. **Future-proof** - Can deprecate simple streams later if needed

### Implementation Timeline:

**Phase 1** (Immediate):
- Create Event types (`ReducerEvent`, `SubscribeAppliedEvent`, etc.)
- Create `EventContext` class
- Update message handling to create EventContext

**Phase 2** (Core):
- Add event streams alongside existing streams
- Create event wrapper classes (`InsertEvent`, `UpdateEvent`, `DeleteEvent`)
- Update code generator to emit both simple and event streams

**Phase 3** (Enhanced):
- Add reducer completion callbacks (`onReducerName`)
- Implement reducer argument deserialization
- Add broadcast event tracking

**Phase 4** (Polish):
- Documentation and examples
- Migration guide for users who want full context
- Performance testing

### Example API (Final State):

```dart
final client = await SpacetimeDbClient.connect(...);

// Simple API (no transaction context):
client.notes.insertStream.listen((note) {
  print('New note: ${note.title}');
});

// Advanced API (with transaction context):
client.notes.insertEventStream.listen((event) {
  print('Note: ${event.row.title}');

  if (event.context.event is ReducerEvent) {
    final reducerEvent = event.context.event as ReducerEvent;
    print('Inserted by: ${reducerEvent.reducerName}');
    print('Caller: ${reducerEvent.callerIdentity}');
    print('Timestamp: ${DateTime.fromMicrosecondsSinceEpoch(reducerEvent.timestamp)}');

    if (reducerEvent.status is Failed) {
      print('Reducer failed: ${(reducerEvent.status as Failed).message}');
    }
  } else if (event.context.event is SubscribeAppliedEvent) {
    print('Loaded from initial subscription');
  }
});

// Reducer completion tracking:
client.reducers.createNote('Title', 'Content');

client.reducers.onCreateNote((ctx, title, content) {
  if (ctx.event is ReducerEvent) {
    final event = ctx.event as ReducerEvent;
    print('Reducer completed: ${event.status}');
    print('Energy: ${event.energyConsumed} eV');
  }
});
```

## Conclusion

"Transaction Support" in the SpacetimeDB Dart SDK means:

- ✅ **NOT** client-side transaction control (begin/commit/rollback)
- ✅ **NOT** nested transactions (doesn't exist in SpacetimeDB)
- ✅ **NOT** client-side batching into transactions
- ✅ **YES** exposing transaction metadata (offset, timestamp, cause) in callbacks
- ✅ **YES** tracking reducer completion and results
- ✅ **YES** providing EventContext to match other SpacetimeDB SDKs

This aligns with how transactions work in SpacetimeDB and what other official SDKs (Rust, C#, TypeScript) provide.

---

## Design Decisions Summary

### 1. Table Change Events: Side-by-Side Streams (Phase 3)
**Decision:** Keep simple streams (`insertStream`, `updateStream`, `deleteStream`) and add enhanced event streams (`insertEventStream`, `updateEventStream`, `deleteEventStream`) with EventContext.

**Rationale:**
- Zero breaking changes
- Simple API stays simple for basic use cases
- Advanced users opt-in to transaction metadata
- Progressive enhancement pattern

### 2. Table Event Hierarchy: Sealed Classes (Phase 3)
**Decision:** Use sealed `TableEvent<T>` base class with `TableInsertEvent`, `TableUpdateEvent`, `TableDeleteEvent` subclasses.

**Rationale:**
- Enables exhaustive pattern matching
- Single unified `eventStream` for all change types
- Consistent naming convention
- Generic functions can accept `TableEvent<T>`

### 3. Reducer Completion API: Typed Callbacks (Phase 4)
**Decision:** Use typed callback functions that return `StreamSubscription<void>`, with strongly-typed args classes.

**Rationale:**
- ✅ Type-safe arguments at call site
- ✅ Returns StreamSubscription (cancellable, Dart-ish)
- ✅ Strongly-typed args classes (e.g., `CreateNoteArgs`)
- ✅ Type guards (`is!`) instead of `as` casts - completely safe
- ✅ Can add pure streams in V2 if needed

**Rejected Alternative:** `Stream<ReducerEventContext<CreateNoteArgs>>` would add unnecessary abstraction layers.

### 4. NO `as` CASTS - Type Guards Only
**Decision:** BANNED all `as` casts. Use type guards (`is!`) with strongly-typed args objects.

**Rationale:**
- ✅ Type guards are safe - fail gracefully with early return
- ✅ Dart's type promotion makes code after guard type-safe
- ✅ Strongly-typed args classes preserve type information
- ✅ No runtime crashes from incorrect casts
- ❌ `as` casts bypass type system and cause runtime failures

**Implementation:**
- Generate args class per reducer: `CreateNoteArgs`, `UpdateNoteArgs`, etc.
- `ReducerArgDecoder<T>` returns strongly-typed object
- Use `if (args is! CreateNoteArgs) return;` for type safety
- Extract fields directly: `args.title`, `args.content`

### 5. Phase 0 is Critical
**Decision:** Phase 0 (ReducerRegistry + message protocol updates) MUST be completed before any other phase.

**Rationale:**
- Without `reducerInfo` in `TransactionUpdateMessage`, can't know which reducer caused changes
- Without `ReducerRegistry`, can't deserialize reducer arguments
- All other phases depend on this foundation

### 6. 🌟 Complex Type Support in Reducer Arguments
**Decision:** Code generator branches on primitive vs complex types when decoding reducer arguments.

**Rationale:**
- ✅ Supports nested structs and enums in reducer arguments
- ✅ Users can structure SpacetimeDB modules naturally
- ✅ No SDK limitations on argument complexity
- ✅ Prevents "works for simple types, fails for complex types" issues

**Implementation:**
```dart
if (TypeMapper.isPrimitive(type)) {
  // Use BsatnDecoder: decoder.readString()
} else {
  // Use generated class: Address.decode(decoder)
}
```

### 7. 🌟 `isMyTransaction` DX Helper
**Decision:** Add convenience getter to `EventContext` for checking if current client triggered the event.

**Rationale:**
- ✅ Reduces 10 lines of boilerplate to 1 line
- ✅ Most common use case in broadcast pattern
- ✅ Handles null cases and byte array comparison internally
- ✅ Makes SDK delightful to use, not just functional

**User code:**
```dart
// Before: verbose boilerplate
if (ctx.event is ReducerEvent &&
    _bytesEqual(ctx.event.callerConnectionId, client.connectionId)) ...

// After: clean DX
if (ctx.isMyTransaction) ...
```

---

## Implementation Priority

**V1 MVP (Recommended):**
1. ✅ Phase 0: ReducerRegistry + message protocol
2. ✅ Phase 1: Event types (Event, ReducerEvent, EventContext, UpdateStatus)
3. ✅ Phase 3: Enhanced event streams (side-by-side with simple streams)
4. ✅ Phase 4: Reducer completion callbacks (typed callback approach)

**V2 Enhancements (Future):**
- Pure stream variants of reducer callbacks (`createNoteStream`)
- Advanced filtering/composition utilities
- Performance optimizations for high-throughput scenarios

**Verdict:** Proceed with this plan. It is pragmatic, type-safe, efficient on code size, and respects Dart's resource management patterns.

---

## 🌟 Gold Standard Features

These two refinements elevate the SDK from "functional" to "delightful":

### 1. Complex Type Support in Reducer Arguments (Phase 0, Step 4.1)

**The Problem:** Most SDKs assume all reducer arguments are primitives, failing when users pass nested structs or enums.

**Our Solution:** Branching logic in code generator handles both:
```dart
void _generateArgDecode(StringBuffer buf, String fieldName, AlgebraicType type) {
  if (TypeMapper.isPrimitive(type)) {
    // Primitive: decoder.readString()
    final method = TypeMapper.getDecoderMethod(type);
    buf.writeln('final $fieldName = decoder.$method();');
  } else {
    // Complex: Address.decode(decoder)
    final typeName = TypeMapper.getDartClassName(type);
    buf.writeln('final $fieldName = $typeName.decode(decoder);');
  }
}
```

**User Impact:**
```rust
// Rust reducer with complex type - "just works"
struct Address { street: String, zip: u32 }
fn update_address(addr: Address) { ... }
```

```dart
// Generated Dart code handles it correctly
class UpdateAddressArgs {
  final Address addr;
  UpdateAddressArgs({required this.addr});
}
```

**Why This Matters:** Users can structure their SpacetimeDB modules naturally without worrying about SDK limitations.

### 2. `isMyTransaction` Helper (Phase 1, EventContext)

**The Problem:** Checking if the current client triggered an event requires verbose boilerplate:
```dart
// 😓 Without helper (10 lines of boilerplate)
if (event.context.event is ReducerEvent) {
  final reducerEvent = event.context.event;
  if (reducerEvent.callerConnectionId != null &&
      client.connection.connectionId != null &&
      _bytesEqual(reducerEvent.callerConnectionId, client.connection.connectionId)) {
    print('I triggered this!');
  }
}
```

**Our Solution:** Single helper property on `EventContext`:
```dart
class EventContext {
  bool get isMyTransaction {
    if (event is! ReducerEvent) return false;
    final reducerEvent = event;
    return _bytesEqual(
      client.connection.connectionId,
      reducerEvent.callerConnectionId,
    );
  }
}
```

**User Impact:**
```dart
// 😊 With helper (1 line)
if (event.context.isMyTransaction) {
  print('I triggered this!');
}
```

**Why This Matters:** Broadcast pattern means ALL clients receive ALL transaction updates. This helper makes it trivial to filter "my actions" vs "other clients' actions", which is the most common use case.

---

## Implementation Checklist

When implementing, ensure these gold standard features are included:

**Phase 0 - Complex Type Support:**
- [ ] `TypeMapper.isPrimitive(type)` helper method
- [ ] `TypeMapper.getDartClassName(type)` for custom types
- [ ] `_generateArgDecode()` branches on primitive vs complex
- [ ] Test with nested struct in reducer argument
- [ ] Test with enum in reducer argument

**Phase 1 - DX Helper:**
- [ ] `EventContext.isMyTransaction` getter
- [ ] `EventContext._bytesEqual()` helper
- [ ] Handle null connection IDs gracefully
- [ ] Document in examples
- [ ] Test with multiple connected clients

These features save users from refactoring later and make the SDK "first in class".
