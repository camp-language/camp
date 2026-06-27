---
# camp-mntv
title: Typecheck segfault on multiple recursive List-returning top-level decls
status: todo
type: task
priority: high
created_at: 2026-06-27T04:27:34Z
updated_at: 2026-06-27T04:27:34Z
---


## Problem

Defining two (or more) recursive top-level functions where one consumes the
result of the other crashes the compiler with a segfault (signal 11) during
typecheck, after `canonicalized` prints but before `typecheck passed`.

## Minimal reproduction

```
append = |xs: List(I64), ys: List(I64)| -> List(I64) {
  match xs {
    Nil => ys
    Cons(h, t) => Cons(h, append(t, ys))
  }
}
n = |xs: List(I64)| -> I64 {
  match xs {
    Nil => 0
    Cons(h, t) => 1 + n(t)
  }
}
pub main! = || -> I64 { n(append([1,2],[3])) }
```

`camp build` segfaults (exit 139) after "canonicalized ... 3 declaration(s)".

## Key findings

- Confirmed pre-existing on `main` (independent of camp-jqvd's codegen fix).
- Single recursive function works: `append` alone + a non-recursive main
  consumer compiles and runs. `n` alone works. `recursive-list-sum` (single
  recursive function) is green.
- The crash requires BOTH recursive decls AND a call site where one recursive
  function's result feeds the other: `n(append(...))`.
- Trace (with debug prints in `src/semantics/check_expr.odin` `typecheck_call`
  and `src/semantics/typecheck.odin` `typecheck_file`): the crash occurs
  inside `unify(store, callee_result.var_id, expected_fn_var)` for the OUTER
  call (`n`) whose argument is the recursive `append(...)` call. The inner
  `append(...)` call typechecks to completion ("DBG call exit"); the outer
  call crashes at the `unify` step that ties `n`'s recursive-self var to the
  expected function type.
- Non-recursive `g(f([1]))` (same shape, no recursion) typechecks fine, so the
  crash is specific to recursive-self vars interacting across calls.

## Suspected area

- `src/semantics/unify.odin` `unify` + `occurs_check` /
  `is_rec_var_reachable` handling of `store.rec_vars` (set in
  `check_decl.odin:15` for self-recursive top-level consts).
- Likely a null deref or array OOB in `occurs_check`/`resolve_var` when a
  recursive-self var unifies against a function whose return has already been
  refined by an inner recursive call.

## Impact / blockers

- Blocks re-enabling `List.filter` in `stdlib/List.camp` (camp-jqvd): adding
  `filter` (an 8th recursive stdlib decl) tips List's import into the
  segfault, breaking `list-length-stdlib`, `list-compare-method`, and
  `language/import-new-syntax` e2e tests.
- Blocks `List is IntoIter` / `List is FromIter` (also camp-jqvd dependents).
- Independently blocks any program with two mutually-consuming recursive
  functions.

## Reproduction commands

```
odin build src -collection:camp=src -out:camp
./camp build <file-with-above-source> -o /tmp/out.wasm   # exit 139
```

## Notes

Found while working camp-jqvd (the WASM codegen i32/i64 mismatch). camp-jqvd's
codegen fix is independent and landed; this typecheck crash is a separate
root cause in the semantics layer.
