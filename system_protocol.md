# SpacetimeDB Wire Protocol - BSATN Decoder Implementation Guide

## Prime Directives
1. **Source of Truth**: `/Users/mikaelwills/Productivity/Development/Dart/SpacetimeDB/crates/client-api-messages/src/websocket.rs`
2. **Never guess**: Field order, types, and optionality come ONLY from Rust struct definitions
3. **Field order is sacred**: Rust serialization order = struct field definition order (never reorder)

---

## BSATN Type Translation Table

| Rust Type | Dart Decoder | Critical Notes |
|-----------|--------------|----------------|
| `u8`, `u16`, `u32`, `u64` | `readU8()`, `readU16()`, `readU32()`, `readU64()` | Little-endian |
| `u128` | `readBytes(16)` | 16 bytes, little-endian |
| `bool` | `readBool()` | 1 byte: 0=false, 1=true |
| `String` | `readString()` | u32 length prefix + UTF-8 bytes |
| `Vec<u8>` | `readBytes()` | u32 length prefix + raw bytes |
| `Identity` | `readBytes(32)` | **NO length prefix**, always 32 bytes |
| `Address` | `readBytes(16)` | **NO length prefix**, always 16 bytes |
| `ConnectionId` | `readBytes(16)` | Usually `u128`, **NO length prefix** |
| `Option<T>` | `readOption(() => readT())` | 1 tag byte: 0=None, 1=Some(T) |
| `Vec<T>` | `readList(() => readT())` | u32 length prefix, then loop |
| Simple Enum | `readU8()` | Discriminant order: 0, 1, 2... |
| Algebraic Enum | `readU8()` + switch | Tag byte, then variant payload |
| Struct | `MyStruct.decode(decoder)` | Recursive call |

---

## Critical Traps to Avoid

### 1. The Identity Trap
```rust
// Rust: pub caller_identity: Identity
// Dart: decoder.readBytes(32)  // NOT readOption!
```
**Only use `readOption` if Rust says `Option<Identity>`**

### 2. The Sentinel Trap
- Rust docs: "All-zeros is a sentinel value"
- **This refers to semantics, NOT serialization**
- Zero u128 still serializes as 16 bytes of zeros (NOT as Option::None)

### 3. The Hidden Field Trap
- SpacetimeDB adds telemetry fields (e.g., `execution_duration: u64`)
- **Must decode ALL fields** even if unused
- Failing to consume bytes breaks batch message parsing

### 4. The Option Confusion Trap
```rust
// Rust: pub energy: Option<u64>
// Dart: decoder.readOption(() => decoder.readU64())

// Rust: pub identity: Identity
// Dart: decoder.readBytes(32)  // NOT readOption!
```

---

## Implementation Workflow

### Phase 1: Discovery
1. Identify Rust struct name (e.g., `TransactionUpdate`)
2. Locate definition in `websocket.rs`
3. Find dependency types (e.g., `EventStatus`, `ReducerInfo`)

### Phase 2: Structural Analysis
1. Go line-by-line through Rust struct fields
2. Map each field using translation table above
3. Check for `Option<T>` wrappers
4. Verify fixed-size types (Identity, Address, ConnectionId)

### Phase 3: Implementation
1. Write Dart decoder matching field order exactly
2. Use verification checklist:
   - [ ] All `Option<T>` fields wrapped with `readOption`?
   - [ ] Non-optional fixed-size types NOT wrapped?
   - [ ] All struct fields decoded (even unused ones)?
   - [ ] u128 types handled as 16-byte reads?

---

## Common Enum Patterns

### Simple Enum (Discriminant Only)
```rust
// Rust
pub enum EventStatus {
    Committed,  // 0
    Failed,     // 1
    OutOfEnergy, // 2
}

// Dart
enum EventStatus {
  committed,  // 0
  failed,     // 1
  outOfEnergy; // 2

  static EventStatus decode(BsatnDecoder decoder) {
    final tag = decoder.readU8();
    return EventStatus.values[tag];
  }
}
```

### Algebraic Enum (Tag + Payload)
```rust
// Rust
pub enum UpdateStatus {
    Committed(u32),
    Failed(String),
}

// Dart
sealed class UpdateStatus {
  static UpdateStatus decode(BsatnDecoder decoder) {
    final tag = decoder.readU8();
    switch (tag) {
      case 0: return Committed(decoder.readU32());
      case 1: return Failed(decoder.readString());
      default: throw Exception('Invalid UpdateStatus tag: $tag');
    }
  }
}

class Committed extends UpdateStatus {
  final int requestId;
  Committed(this.requestId);
}

class Failed extends UpdateStatus {
  final String error;
  Failed(this.error);
}
```

---

## Debugging Checklist

When "Not enough bytes" errors occur:

1. **Add hex dump** to see raw bytes
   ```dart
   print('FULL HEX: ${decoder.hexDumpAll()}');
   ```

2. **Trace each field** with offset logging
   ```dart
   final field = decoder.readU32();
   print('After field ($field): ${decoder.hexDump(20)}');
   ```

3. **Check Rust source** for new fields (especially at end)

4. **Verify Option handling** - most common mistake

5. **Confirm fixed-size types** use exact byte counts (no length prefix)

---

## Quick Reference: Message Types

| Message | Rust File | Key Fields |
|---------|-----------|------------|
| `IdentityToken` | `websocket.rs` | `identity: Identity`, `token: String`, `address: Address` |
| `SubscriptionUpdate` | `websocket.rs` | `table_updates: Vec<TableUpdate>` |
| `TransactionUpdate` | `websocket.rs` | `event: Event`, `subscription_update: SubscriptionUpdate` |
| `OneOffQueryResponse` | `websocket.rs` | `message_id: Vec<u8>`, `error: Option<String>`, `table: OneOffTable` |
| `Event` | Check supporting files | `timestamp`, `caller_identity`, `function_call`, `status`, `energy_consumed` |
| `ReducerCallInfo` | Check supporting files | `reducer_name`, `reducer_id`, `args: Vec<u8>` |

---

## File Locations

**Primary**: `/Users/mikaelwills/Productivity/Development/Dart/SpacetimeDB/crates/client-api-messages/src/websocket.rs`

**Supporting**: Check `../src/lib.rs` or `../src/updates.rs` for type definitions like `Event`, `EventStatus`, `ReducerCallInfo`.
