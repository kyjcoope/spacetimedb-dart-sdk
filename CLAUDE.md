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


USE THE system_protocol.md
