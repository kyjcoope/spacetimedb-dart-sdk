# SpacetimeDB Dart SDK - Learning Project

## SpacetimeDB CLI Reference (Quick Reference)

**IMPORTANT**: Only use commands listed here. Do NOT hallucinate or assume commands exist.

### Core Commands
- `spacetime start` - Start local SpacetimeDB instance
- `spacetime build` - Build module (use with `-p <path>`)
- `spacetime publish <name> [--server <url>] [--anonymous] [--delete-data] [-y]` - Publish module
- `spacetime delete <database> [--server <url>] [-y]` - Delete database
- `spacetime describe --json <database> [--server <url>]` - Get schema as JSON
- `spacetime list [--server <url>] [-y]` - List databases for identity
- `spacetime logs <database> [-n <lines>] [-f] [--server <url>]` - View logs

### Server Management
- `spacetime server list` - List server configs
- `spacetime server set-default <server>` - Set default server
- `spacetime server add --url <url> <name>` - Add server config
- `spacetime server clear [-y]` - **Delete all local database data**
- `spacetime server ping <server>` - Check if server is online

### Authentication
- `spacetime login [--server-issued-login <server>]` - Login (opens browser for cloud)
- `spacetime logout` - Logout
- `spacetime login show [--token]` - Show current login

### Other Commands
- `spacetime call <database> <reducer> [args...]` - Call reducer (UNSTABLE)
- `spacetime sql <database> <query>` - Run SQL query (UNSTABLE)
- `spacetime rename --to <new-name> <database-identity>` - Rename database
- `spacetime generate -l <lang> -o <dir> [-p <path>]` - Generate client code
- `spacetime subscribe <database> <query>...` - Subscribe to queries (UNSTABLE)

### Important Flags
- `-s, --server <url>` - Specify server (e.g., `http://localhost:3000`)
- `-y, --yes` - Non-interactive mode (answer yes to prompts)
- `--anonymous` - Use anonymous identity

### Local Development Pattern
```bash
# Login to local server (creates persistent identity)
echo "n" | spacetime list --server http://localhost:3000

# Publish to local
spacetime publish notesdb --server http://localhost:3000

# Delete from local
spacetime delete notesdb --server http://localhost:3000 -y

# Get schema from local
spacetime describe --json notesdb --server http://localhost:3000
```

### Config File Location
- macOS/Linux: `~/.config/spacetime/cli.toml`
- Contains: `spacetimedb_token`, `default_server`, `server_configs`

---

# SpacetimeDB Dart SDK - Learning Project

This is a **Dart LEARNING EXERCISE**. You are learning WebSocket communication, Dart Streams, BSATN encoding, and client-side caching by building a SpacetimeDB SDK.

## Teaching Structure:
- **Phases**: Major implementation milestones
- **Steps**: Small, focused tasks (≤35 lines each)
- **Approach**: You write code, I guide and explain concepts

## Teaching Approach:
- Each step fits on your screen (max 35 lines)
- You implement each step in your editor
- Ask questions about any concept before moving on
- I wait for "done" or "next" before continuing
- We test after each phase

## Phase Roadmap:

### Phase 7: Table Cache System ✅ COMPLETE
### Phase 8: Reducer Caller ✅ COMPLETE
### Phase 9: All Server Messages ✅ COMPLETE
### Phase 10: Code Generation (CLI Approach) ✅ COMPLETE
- [x] Step 43: Research schema endpoint and capture example
- [x] Step 44: Create schema model classes
- [x] Step 45: Implement schema fetcher
- [x] Step 46: Create type mapper
- [x] Step 47: Build table class generator
- [x] Step 48: Build reducer method generator
- [x] Step 49: Build client class generator
- [x] Step 50: Create main generator orchestrator
- [x] Step 51: Build CLI tool
- [x] Step 52: Update pubspec.yaml for CLI
- [x] Step 53: Integration test with comprehensive test suite

## Current Progress:
**Phase:** All SDK phases complete!
**Last Updated:** 2025-11-18
**Next:** Transaction Support implementation (see TRANSACTION_SUPPORT.md)

---

## 🚨 CODE GENERATION RULES - CRITICAL CONSTRAINTS

### ❌ FORBIDDEN: `as` CASTS ARE COMPLETELY BANNED

**UNDER NO CIRCUMSTANCES should you EVER use `as` casts in generated code.**

**❌ NEVER DO THIS - `as` cast on map values:**
```dart
// FORBIDDEN
final String argTitle = event.reducerArgs['title'] as String;
```

**❌ NEVER DO THIS - `as` cast on objects:**
```dart
// FORBIDDEN
final args = event.reducerArgs as CreateNoteArgs;
```

**❌ NEVER DO THIS - Wrapper functions with `as` casts:**
```dart
// FORBIDDEN
Map<String, dynamic> _validateArgs(Map<String, dynamic> args) {
  return {
    'title': args['title'] as String,
  };
}
```

**✅ ALWAYS DO THIS - Type guards with strongly-typed objects:**
```dart
// GENERATED ARGS CLASS (one per reducer)
class CreateNoteArgs {
  final String title;
  final String content;
  CreateNoteArgs({required this.title, required this.content});
}

// GENERATED LISTENER - Uses type guards, NOT casts
StreamSubscription<void> onCreateNote(
  void Function(EventContext ctx, String title, String content) callback
) {
  return _reducerEmitter.on('create_note').listen((EventContext ctx) {
    // Type guard - ensures event is ReducerEvent
    if (ctx.event is! ReducerEvent) return;
    final event = ctx.event;

    // Type guard - ensures args is correct type
    final args = event.reducerArgs;
    if (args is! CreateNoteArgs) return;

    // Extract fields from strongly-typed object - NO CASTING
    callback(ctx, args.title, args.content);
  });
}
```

**Why `as` casts are banned:**
- Unsafe - causes runtime crashes if types don't match
- Bypasses Dart's type system
- Hides type errors until runtime
- Makes code impossible to reason about safely

**Type System Guarantee:**
- `ReducerArgDecoder<CreateNoteArgs>` returns strongly-typed object
- Type guard (`is!`) ensures correct type at runtime
- Dart automatically promotes `args` to `CreateNoteArgs` after the guard
- Fields accessed directly from typed object - completely type-safe

**See TRANSACTION_SUPPORT.md Phase 4 for full details.**

---

### Debugging BSATN Decoding Issues - Binary Protocol Reverse-Engineering

When a message type fails to decode (e.g., "Not enough bytes" errors), use this proven process:

### Step 1: Add Hex Dump Capability
Add to `BsatnDecoder` class:
```dart
String hexDump(int length) {
  final end = (_offset + length).clamp(0, _bytes.length);
  final bytes = _bytes.sublist(_offset, end);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  return 'offset=$_offset: $hex';
}

String hexDumpAll() {
  return hexDump(remaining);
}
```

### Step 2: Insert Debug Prints
In the failing decode method, add prints at each step:
```dart
static MyMessage decode(BsatnDecoder decoder) {
  print('FULL HEX DUMP:');
  print(decoder.hexDumpAll());

  final field1 = decoder.readU32();
  print('After field1 ($field1): ${decoder.hexDump(20)}');

  final field2 = decoder.readString();
  print('After field2 ("$field2"): ${decoder.hexDump(20)}');

  // Continue for each field...
}
```

### Step 3: Analyze Hex Output
Run the test and examine the hex bytes:
- Look for patterns: `04 00 00 00 6e 6f 74 65` = length(4) + "note"
- Check for Option discriminants: `00` = None, `01` = Some
- Identify u32 values in little-endian: `[01, 01, 00, 00]` = 257
- Watch offset progression to detect missing/extra fields

### Step 4: Form Hypotheses
Based on byte patterns, hypothesize:
- Missing fields (if offset jumps unexpectedly)
- Wrong field types (if values seem unreasonable)
- Vec vs single value (if "count" field looks like string length)

### Step 5: Test Hypotheses
Add/remove/reorder fields in decoder and re-run test:
```dart
// Hypothesis: Maybe there's a request_id field here?
final maybeRequestId = decoder.readU32();
print('Read u32: $maybeRequestId');
```

### Step 6: Clean Up
Once working, remove debug prints and update struct definition.

### Real Example: OneOffQueryResponse Fix
**Problem**: "Not enough bytes: need 1970499157, have 47 at offset 18"

**Analysis**:
- Hex at offset 9: `01 01 00 00 00 04 00 00 00 6e 6f 74 65`
- Pattern `01 01 00 00 00` as u32 = 257 (reasonable request_id!)
- Pattern `04 00 00 00 6e 6f 74 65` = length(4) + "note" (table name!)

**Discovery**:
1. Missing `request_id: u32` field between messageId and error
2. Not `Vec<OneOffTable>`, but single `OneOffTable` directly

**Fix**: Added requestId field, changed from reading Vec to single table

**Key Insight**: When docs/source unavailable, hex dumps reveal the truth!
