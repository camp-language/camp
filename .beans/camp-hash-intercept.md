---
# camp-hash-intercept
title: Fix Hash.new/Hash.finish module-qualified call interception
status: completed
type: bug
priority: high
created_at: 2026-06-08T05:00:00Z
updated_at: 2026-06-08T06:30:00Z
blocked_by: []
---

## Resolution

Fixed by changing the approach entirely. Instead of exposing `Hash.new()` and
`Hash.finish()` as module-level functions (which failed due to `Hash` being both
a module name and a trait name), the hash trait method dispatch now handles the
full pipeline internally:

1. `I64.hash(42, Hasher{})` — intercepted at emit_expr level
2. Calls `Hash_Init()` to create fresh hasher (ignoring passed Hasher{})
3. Calls `Hash_Write_I64(hasher, 42)` to hash the value
4. Calls `Hash_Finish(hasher)` to finalize and get the 64-bit hash value
5. Returns the i64 hash value directly

The key discovery was that trait method dispatch (`I64.hash(...)`) resolves to an
unqualified call with `name == "hash"` and 4 args (2 user args + 2 dispatch args),
not a module-qualified call. The fix adds a unified handler matching `name_str == "hash"`
with `len(e.args) >= 2`.

### What was tried (and failed):
- `Hash.new()`/`Hash.finish()` via `HashOps` module — naming collision with `@Hasher` type
- Module-qualified interception (`module_str == "Hash"`) — `Hash` trait shadows module name
- Per-type unqualified handlers (`I64_hash`, `Str_hash`, etc.) — trait dispatch uses just `"hash"`, not type-prefixed names
