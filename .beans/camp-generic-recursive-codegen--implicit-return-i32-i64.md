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

UPDATE (deeper investigation): instrumenting `func_map` shows **neither** `length`
**nor** `is_empty` is resolved — both lower to `IR_Call{module: NO_NAME, name, args:
[receiver, list]}` with `in_func_map == false`, so both fall to `call_idx = 0`
(`proc_exit`). `is_empty` only *appeared* to work because the emitted WASM happened to
validate (wasm2wat), not because it executed correctly. **Adding `import List` does not
fix it** — `List.length([1,2,3])` still produces invalid WASM / traps with an explicit
import. So the stdlib `List` functions are not being compiled into the module / placed
in `func_map` for qualified calls at all.

## Why identical user code works

A monomorphic OR generic *user* `mylen` runs fine — it is a direct call, not the
`List.foo` method-call/intercept path. So this is NOT a generic/recursive codegen bug
(as first suspected). It is a combination of:
1. module-qualified `List.foo(x)` lowered as a method call (module dropped, receiver
   prepended) so the builtin intercept misses; and
2. the stdlib `List` functions not being compiled/resolved in `func_map` for the
   qualified-call path (even with `import List`).

## Attempt + outcome

A surgical reroute (lower module-qualified builtin calls to `IR_Call{module: List, …}`
without the prepended receiver) was tried — it **regressed `is_empty` and returned wrong
values** (`length` → 1), so the prepended-receiver convention is load-bearing for the
current path. Reverted. This needs a coordinated fix across canonicalize/typecheck
(distinguish module-qualified from UFCS) **and** stdlib module compilation/func_map
resolution — not a localized patch.

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
