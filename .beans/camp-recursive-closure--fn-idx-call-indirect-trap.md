---
id: camp-recursive-closure
title: Recursive functions trap at runtime (recursive-closure fn_idx / call_indirect)
status: todo
type: bug
priority: high
created_at: 2026-06-06T20:00:00Z
updated_at: 2026-06-06T20:00:00Z
---

After PR #97, recursive list functions typecheck and compile to valid WASM, but trap
at runtime:

```camp
sum = |xs: List(I64)| -> I64 { match xs { Nil => 0  Cons(h, t) => h + sum(t) } }
pub main! = || -> I64 { sum([1, 2, 3, 4]) }   // wasm trap: undefined element: out of bounds table access
```

## Root cause (to confirm)

The recursive self-call lowers to a `call_indirect` (the function is captured as a
self-referential closure). The closure's stored `fn_idx` (CAMP_TAG_FIELDS_OFFSET) is
wrong/uninitialized, so `call_indirect` indexes outside the element table →
"undefined element: out of bounds table access".

Note: recursion over a scalar (`count = |n: I64| ... count(n-1)`) does **not** trap —
so it is specific to functions compiled as self-capturing closures, not recursion in
general. This codegen path was never reachable before #97 because recursive list
functions never typechecked.

## Where to look

- `src/ir/closure_convert.odin` — how a function's self-reference is captured.
- `src/codegen/emit_expr.odin` IR_Closure_Call (~2398) — the `call_indirect` and how
  `fn_idx` is loaded from the closure record.
- The element/table section setup (cf. #70 "use-after-free in Elem section codegen").

## Test
`tests/e2e/execution/` — recursive `sum`/`List.length` returning a known exit.
