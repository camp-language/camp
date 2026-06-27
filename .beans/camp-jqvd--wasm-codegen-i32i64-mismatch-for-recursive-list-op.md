---
# camp-jqvd
title: WASM codegen i32/i64 mismatch for recursive list operations
status: in-progress
type: bug
priority: high
tags:
    - codegen
    - wasm
    - list
created_at: 2026-06-22T02:24:34Z
updated_at: 2026-06-27T04:27:59Z
---

## Problem

Recursive list operations that return `List` trigger a WASM codegen bug: `type mismatch: expected i64 but nothing on stack`. This blocks multiple stdlib features.

**Symptom:** Compilation to WASM succeeds, but `wasmtime` rejects the binary with a translation error. The affected function has an i32/i64 stack mismatch — the WASM codegen emits code that expects i64 on the stack but the list operations produce i32 (or vice versa).

## Affected features

- **List.filter** — `filter` uses an `if` inside a `match` arm that returns `List`, triggering the mismatch. Commented out in `stdlib/List.camp:57-63`.
- **List.is IntoIter** — `Iter.from_list(list)` on a List value triggers the same bug. Cannot add `List is IntoIter` trait impl.
- **List.is FromIter** — `Iter.fold(iter, [], |acc, x| append(acc, [x]))` where `append` is recursive and returns List. Cannot add `List is FromIter` trait impl.
- Any pattern where a match arm calls a recursive function returning a tag-union type (List is `[Cons(a, List(a)) | Nil]`).

## Related beans

- `camp-ty9s` — Ord trait ABI mismatch (different manifestation of i32/i64 issues in container runtimes)
- `camp-yxts` — Container eq/compare/hash runtime funcs do i32.load on unboxed I64 payloads
- `camp-3h2i` — Enable WASM execution for closure tests (some tests skip WASM due to similar issues)

## Root cause (hypothesis)

The WASM codegen lowerer doesn't correctly handle the stack type for recursive functions whose return type is a heap-allocated tag union. The tag union representation may use i32 for the tag discriminant but the codegen expects i64 for the overall value, or the recursive call's return is not properly coerced.

## Steps to investigate

1. Isolate a minimal reproduction: a recursive function returning a tag union used inside a match arm
2. Inspect the generated WASM for the affected function (the i32/i64 mismatch point)
3. Check `src/lower/lower.odin` and `src/lower/wasm.odin` for how recursive tag-union-returning calls are lowered
4. Fix the codegen to emit the correct WASM type for the return value

## Impact

Blocks: List.filter, List.sort, List.last, List is IntoIter, List is FromIter, and any stdlib code using recursive-list-in-match-arm patterns.


## Resolution (2026-06-27)

### Codegen fix — DONE

Root cause confirmed: the `IR_Call` node's `type_.wasm_type` was a stale
snapshot taken mid-typecheck (`src/semantics/check_expr.odin:148
type_ = lower_type(store, return_var)`), before late unification resolved
the recursive call's return var to a concrete heap-backed tag union (List →
I32). Codegen's `coerce_ret_to` (`src/codegen/emit_expr.odin:1625`) then
treated the stale I64 as `expected` and emitted `i64.extend_i32_s` after the
i32 call result, breaking downstream `if (result i32)` / match-arm / store
typing (`type mismatch: expected i32, found i64`).

This is the same class of staleness already fixed for `TExpr_Name`
(`src/ir/lower.odin:339-354`, "Re-resolve the wasm type from the final type
var"). Applied the identical pattern to call lowering via a new
`rederive_call_type` helper (`src/ir/lower.odin`) wired into every IR_Call
construction site that previously copied the stale `e.type_` snapshot. Scoped
to plain/method calls only — NOT resume/handle continuation types, since
re-snapshotting those changed `resume`'s Funcref and broke call_indirect
dispatch (the camp-9xi6 parallel-map regression documented at
`src/semantics/typed.odin:841-872`). Function signatures (func_type results)
are unaffected (computed from `d.return_type` at `src/codegen/codegen.odin:1219`).

### Verification
- Filter pattern now compiles, validates, and runs correctly:
  `filter([1,2,3,4,5], |x| x < 3)` → head 1, exit code 1.
- New E2E: `tests/e2e/execution/recursive-list-filter/` (single recursive
  filter + non-recursive main consumer). All 205 e2e + 523 unit tests green.
- New unit test `test_lower_recursive_list_call_type_not_stale`
  (`src/test_ir.odin`) verifies the recursive call's `type.wasm_type == .I32`
  and fails (stale I64) without the fix.

### NOT done — blocked by separate pre-existing bug (camp-mntv)

Re-enabling `List.filter` in `stdlib/List.camp` is blocked by a pre-existing
typecheck segfault (signal 11) that triggers when two recursive top-level
functions interact via a call (`n(append(...))`). Adding `filter` (an 8th
recursive stdlib decl) tips List's import into the segfault, breaking
`list-length-stdlib`, `list-compare-method`, `language/import-new-syntax`.
Confirmed on `main` independent of this bean's fix. Tracked in camp-mntv.
`List is IntoIter` / `FromIter` are likewise blocked on camp-mntv.

### `just check` gate

The gate is red on `main` BEFORE and AFTER this change due to an unrelated
environment issue: `os.make_directory_all` returns `Permission_Denied` for
`/tmp/camp-test-*` paths on this host (bash `mkdir` works; Odin runtime does
not), so `camp test` cannot write its temp wasm and every stdlib doc-test
fails with "compilation failed" (`src/build/build.odin:825` ignores the
`make_directory_all` error). Unit + e2e suites (which use a different tmp
path) are fully green.
