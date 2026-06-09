---
id: camp-stdlib-compile-single
title: run_build_single doesn't compile stdlib dependencies, so module-qualified calls fail
status: todo
type: bug
priority: high
created_at: 2026-06-09T00:00:00Z
---

`run_build_single` (the `camp build` / `camp run` code path for single files, no
project) only compiles the user's file — it never compiles stdlib modules. This means
module-qualified calls like `List.length(xs)` fail at codegen because `List.length`
isn't in `func_map`.

## What works

- **`Str.length(s)`** — codegen has a runtime intercept for `Str.length` that calls
  `Runtime_Func.Str_Len`. This is correct because Camp strings use the same internal
  representation as the runtime string struct.
- **Project build path** — compiles all stdlib dependencies, so `List.length(xs)` would
  resolve to the pure Camp implementation in `stdlib/List.camp`.

## What doesn't work

- **`List.length(xs)`** — no intercept (previously had one, but it called `List_Len`
  which reads from the **internal growable array** struct, not the Camp tag union
  `Nil | Cons`). The correct implementation is the pure Camp recursive function in
  `stdlib/List.camp`.
- **`List.get(xs, i)`, `List.is_empty(xs)`, `List.push(xs, x)`** — same issue.
- **`Map.get(m, k)`, `Result.map(x, f)`** — any module-qualified call on a prelude type
  that doesn't have a codegen runtime intercept.

## Root cause

`src/build/build.odin`: `run_build_single`:
1. Parses and canonicalizes only the user's source file
2. Typechecks it (no import resolution — the prelude types are found via `store.bindings`)
3. Compiles to WASM directly — never resolves imports, never compiles dependencies

## Background

The runtime `List_Len`, `List_Get`, `List_Push`, `List_Alloc` functions in
`src/codegen/runtime.odin` operate on an **internal growable array** struct
(`[len: i32, capacity: i32, data_ptr: i32, ...]`). This is NOT the same as the Camp
`List(a)` type, which is a tag union (`Nil | Cons(h: a, t: List(a))`). Using `List_Len`
on a tag-union list reads the tag byte (at offset 0) as the length, producing wrong
results silently.

The pure Camp implementations in `stdlib/List.camp` use pattern matching on the tag
union and are correct for all use cases.

## Fix direction

Option A: Have `run_build_single` use the project build path (resolve imports, compile
stdlib dependencies). This is the "right" fix but potentially a large refactor.

Option B: Add tag-union-aware runtime functions for common List operations (length,
is_empty, get, map) that walk the `Nil | Cons` chain directly in WASM. Simpler but
creates maintenance burden.

Option C: Pre-compile the stdlib as a WASM module and link it in for the simple build
path. Medium effort, clean separation.

## Test
`./camp run` with `List.length([1,2,3])` should return 3 (currently fails with empty
stack at codegen).
