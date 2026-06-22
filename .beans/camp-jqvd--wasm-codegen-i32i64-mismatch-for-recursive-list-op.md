---
# camp-jqvd
title: WASM codegen i32/i64 mismatch for recursive list operations
status: todo
type: bug
priority: high
tags:
    - codegen
    - wasm
    - list
created_at: 2026-06-22T02:24:34Z
updated_at: 2026-06-22T02:24:34Z
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
