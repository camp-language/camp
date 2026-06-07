---
id: camp-generic-recursive-codegen
title: Intercepted List/Str builtins called as `List.foo(x)` produce invalid WASM
status: todo
type: bug
priority: high
created_at: 2026-06-07T00:00:00Z
updated_at: 2026-06-07T12:00:00Z
---

Several `List` calls compile to invalid WASM (`implicit return expected i64 got i32`):

```
List.length([1,2,3])     // INVALID
List.get([1,2,3], 1)     // INVALID
List.map([1,2,3], f)     // INVALID
List.is_empty([1,2,3])   // VALID
```

## Root cause (precise)

`List.foo(xs)` is lowered as a **method call** (`lower_tmethod_call`), not a direct
`IR_Call`. The method-call path:
- prepends the receiver `List` (a module name) as arg 0, producing
  `IR_Call{ callee = {module: NO_NAME, name: foo}, args: [List, xs] }`;
- the resolved callee module is `NO_NAME` (not `List`).

At codegen (`emit_expr.odin`, `case ^ir.IR_Call`), the `List_Len`/`List_Get`/`Str_Len`
builtin intercepts are gated on `e.callee.module != NO_NAME && module_str == "List"`,
so they **never fire** for the method-call form. Then the generic path looks up
`func_map[name]`; for the **intercepted** builtins (`length`, `get`, `push`, `alloc`)
that entry is missing, so `call_idx` defaults to 0 and the call is emitted against
function 0 (`proc_exit`) / dropped → the list pointer (i32) is left where the i64
length is expected.

`is_empty` works because it is a normally-compiled function present in `func_map`, so
the generic path resolves it (the prepended module receiver lowers to nothing).

## Why identical user code works

A monomorphic OR generic *user* `mylen` runs fine — it is a direct call, not the
`List.foo` method-call/intercept path. So this is NOT a generic/recursive codegen bug
(as first suspected); it is the module-qualified-call ↔ builtin-intercept mismatch.

## Fix direction (needs care — regression risk)

Either:
1. Route module-qualified calls (`List.foo(args)` where the receiver is a module/type,
   not a value) to a proper `IR_Call{ module: List, name: foo, args: [args] }` — no
   prepended receiver — so the existing intercept fires with the list as `args[0]`.
   Must distinguish module receivers from UFCS value receivers without breaking the
   many List/Str functions that currently work through the method-call path.
2. Or make the intercepted builtins always compiled + resolvable in `func_map` (so the
   method-call form calls the real recursive `length` etc., like `is_empty`), and drop
   reliance on the intercept for the `List.foo` form.

`List.map` additionally involves a closure arg (higher-order) and may have a second,
separate issue once the above is fixed — re-test after.

## Test
`tests/e2e/execution/` — `List.length([1,2,3]) == 3`, `List.get`, once fixed.
