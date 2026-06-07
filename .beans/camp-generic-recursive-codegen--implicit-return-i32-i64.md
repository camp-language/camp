---
id: camp-generic-recursive-codegen
title: Generic stdlib List fns produce invalid WASM (implicit return i64 vs i32)
status: todo
type: bug
priority: high
created_at: 2026-06-07T00:00:00Z
updated_at: 2026-06-07T00:00:00Z
---

Several generic stdlib `List` functions compile to invalid WASM:

```
List.length([1,2,3])               // INVALID: implicit return, expected [i64] but got [i32]
List.length(List.reverse([1,2,3])) // INVALID
List.length(List.map([1,2,3], |x| x + 1)) // INVALID
List.is_empty([1,2,3])             // VALID
```

## Key clue

An **identical monomorphic** user function works:

```camp
mylen = |xs: List(I64)| -> I64 { match xs { Nil => 0  Cons(_h, t) => 1 + mylen(t) } }
pub main! = || -> I64 { mylen([1,2,3]) }   // runs, = 3
```

The stdlib `length`/`reverse`/`map` are **generic** (`|xs|` polymorphic over the element
type). So this is a generic/polymorphic codegen issue, not the recursive-closure trap
(fixed in #100): the generic element/return width is treated as i32 somewhere while the
declared/return type is i64 (or vice versa). Adjacent to #92's `coerce_arg_to`/
`coerce_ret_to` — likely the same coercion is needed for the generic recursive return,
or generic functions need monomorphization at the call site.

## Where to look

- `src/codegen/emit_expr.odin` — IR_Call return coercion (`coerce_ret_to`, #92) and the
  `module_str == "List"` builtin intercept (does the stdlib `length` function still get
  compiled even when the call uses `Runtime_Func.List_Len`?).
- How generic functions are lowered/monomorphized — the element type var defaulting to
  i64 vs i32 in the function body vs at call sites.
- `lower_type` for an unresolved/generic var (defaults to .I64).

## Test
`tests/e2e/execution/` — `List.length([1,2,3]) == 3` returning a known exit, once fixed.
