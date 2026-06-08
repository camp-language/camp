---
# camp-hash-intercept
title: Fix Hash.new/Hash.finish module-qualified call interception
status: todo
type: bug
priority: high
created_at: 2026-06-08T05:00:00Z
updated_at: 2026-06-08T05:00:00Z
blocked_by: []
---

## Problem

`Hash.new()` and `Hash.finish(h)` are not intercepted by the codegen emit_expr.
When user code calls `Hash.new()`, it executes the crash body instead of calling
`Hash_Init`. Same for `Hash.finish(h)` — it executes the crash body instead of
calling `Hash_Finish`.

The interception code exists in emit_expr.odin (the `if module_str == "Hash"` block)
but it never fires.

## Root Cause

The issue is in how module-qualified calls to constants are represented in the IR.

`pub new = crash "intrinsic: Hash.new"` defines `new` as a module-level constant
whose value is a crash expression. When the user writes `Hash.new()`, the compiler
may NOT create an `IR_Call` with `callee.module == "Hash"` and `callee.name == "new"`.
Instead, it may resolve the constant and inline the crash expression.

For `Map.new`, this works because the kitchen-sink test uses `m = Map.new` (without
parens) and the compiler creates a proper IR_Call. For `Hash.new()` (with parens),
the behavior may differ.

Similarly, `pub finish = |h: Hasher| -> I64 { crash "intrinsic: Hash.finish" }` creates
a lambda. Calling `Hash.finish(h)` may go through `IR_Closure_Call` (which doesn't
have module info) instead of `IR_Call`.

## Evidence

The disassembly of a test program calling `Hash.new` and `Hash.finish` shows:
1. An 8-byte allocation (empty Hasher record, NOT the 52-byte Hash_Init allocation)
2. A `call_indirect` (closure dispatch, NOT a direct call to Hash_Finish)

If interception worked, there would be:
1. A direct call to `Hash_Init` (allocating 52 bytes)
2. A direct call to `Hash_Finish`

## Proposed Fix

Option A: Change how the compiler represents calls to module-level constants.
Make `Hash.new` generate an `IR_Call` with `callee.module = "Hash"` and
`callee.name = "new"`, even when the value is a constant/crash expression.

Option B: Handle the interception at a different level — e.g., in closure_convert
or in the IR lowering, replacing calls to `Hash.new` and `Hash.finish` with
direct references to the runtime functions.

Option C: Change the `Hash.new` / `Hash.finish` definitions to use a different
Camp syntax that the compiler handles as module-qualified function calls.

Option D: Intercept `Hasher{}` construction in emit_expr's `IR_Construct_Record`
handler, calling `Hash_Init` when the type is Hasher. For `finish`, add a
`finish` method to the `@Hasher` newtype directly.

## Related

- SipHash runtime: `src/codegen/siphash.odin` (implementation complete)
- Hash intrinsic dispatch: `src/codegen/emit_expr.odin` (code present but not firing)
- Module interception for Map: `src/codegen/emit_expr.odin:548` (works for Map.new)
- The `Map.new` pattern: `pub new = crash "intrinsic: Map.new"` — same as Hash
