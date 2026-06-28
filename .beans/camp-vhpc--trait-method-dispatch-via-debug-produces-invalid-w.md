---
# camp-vhpc
title: Trait-method dispatch via .debug() produces invalid WASM for primitive Self types
status: todo
type: task
priority: high
tags:
    - codegen
    - traits
    - ir
created_at: 2026-06-28T02:57:37Z
updated_at: 2026-06-28T02:57:37Z
---

Calling a Debug trait method via member dispatch (e.g. `u.debug()` where `u: Unit`,
or `b.debug()` where `b: Bool`) produces WASM that fails validation with a type
mismatch. Direct calls (`Unit_debug({})`, `Bool_debug(True)`) fail identically.

## Symptoms

`camp run` / `camp test` fail with:
```
type mismatch in i32.store, expected [i32, i32] but got [i32, i64]
type mismatch in call_indirect, expected [i32, i64] but got [i32, i32]
```

## Reproduction

```camp
import Unit {}
pub main! = || -[Console!]-> Unit {
  u: Unit = {}
  Console.println!(u.debug())
}
```

Compiles fine (`camp check` passes) but the emitted WASM is invalid.

## Root cause (preliminary)

The lowered `Unit_debug` function (from `Unit is Debug { debug = |_self: Self| -> Str { "()" } }`)
ends up with closure-converted signature `(param i32 i32 i32)` and a body that
emits `i64.const 0` followed by `i32.store` — the `Self` (Unit/Void) parameter
is represented as `i64` through closure conversion / CPS, then stored via
`i32.store`. The `call_indirect` site similarly expects `[i32, i64]` but the
table entry provides `[i32, i32]`.

Affects every primitive Debug impl that goes through member/trait dispatch:
Unit, Bool (`b.debug()` — note Bool's existing `test "Bool traits"` passes only
because it calls free functions like `not_(True)`, never `.debug()`), Char, Str.

## Scope

This blocks runtime execution of any `expect` that calls a primitive's Debug
method. surfaced while working bean camp-d3k4 (Unit.camp). The `Unit is Debug`
impl in `stdlib/Unit.camp` is correct and typechecks; only runtime codegen is
broken.

## Related files

- `src/ir/lower.odin:728` (`lower_tdecl_is_impl`) — lowers impl methods
- `src/ir/closure_convert.odin` — suspected i64 origin
- `src/codegen/emit_expr.odin:1614+` — general trait-method call fallback path
- `src/semantics/prelude.odin:490` — primitive `Unit_debug` registration

## Prerequisite for

Runtime passing of `expect` blocks that exercise primitive Debug dispatch in
`stdlib/Unit.camp`, `stdlib/Bool.camp`, etc.
