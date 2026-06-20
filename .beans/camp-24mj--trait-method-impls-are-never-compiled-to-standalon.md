---
# camp-24mj
title: Trait method impls are never compiled to standalone WASM functions, blocking container runtime dispatch
status: todo
type: bug
priority: high
tags:
    - codegen
    - traits
    - ir
created_at: 2026-06-20T03:02:41Z
updated_at: 2026-06-20T03:02:54Z
blocked_by:
    - camp-stdlib-compile-single
---

## Problem

Trait-impl method bodies (e.g. `Bool is Ord { compare = |a,b| ... }` in
`stdlib/Bool.camp`) are never lowered to standalone WASM functions. Only the
hand-written runtime intrinsic `I64_compare` exists as a real compiled function.

The prelude (`src/semantics/prelude.odin` lines ~406-565) registers trait impl
**names** (`Bool_compare`, `Char_compare`, `Str_compare`, etc.) in
`store.trait_impls`, but with no associated function body. The actual method
bodies live in stdlib `.camp` files that aren't compiled in single-file builds.

## Consequence

The container runtime functions (`Result.eq/compare/hash`, `List.compare/hash`,
`Map.eq`, `Set.eq`) take element trait-method function pointers via `call_indirect`.
`resolve_container_trait_fn` now correctly resolves the element type (after the
`Inferred_Tag_Union_Row` extraction fix), but the resolved name (e.g.
`Bool_compare`) is absent from `func_map` → `cmp_fn_idx` stays 0 → `call_indirect`
calls table[0] = `proc_exit` → "indirect call type mismatch" trap.

This means `List.compare(a, b)`, `Result.eq(a, b)`, etc. (the method-call path, not
the `==`/`<` operator path) trap for ALL non-I64 payload types. The operator path
(`a == b`, `a < b`) uses structural lowering and works fine.

## Infrastructure already in place

`src/ir/lower.odin`: `lower_tdecl_is_impl` lowers source-level `TDecl_Is_Impl`
declarations into `IR_Decl_Fn`s registered in `func_map`, using Canonical_Names from
the `trait_impls` registry (matches `resolve_trait_method`). This works for
project builds (`run_build_project` → `combine_module_irs` typechecks each stdlib
module), but is unreachable in single-file builds.

## Blockers

1. **Single-file builds don't compile stdlib** (bean `camp-stdlib-compile-single`).
   The e2e test harness uses single-file builds, so no stdlib trait impls reach
   lowering.
2. **Project builds are broken** by pre-existing stdlib parse errors (e.g.
   `stdlib/Num/F64.camp` line 116 `pub to_i64 : F64 -> I64` uses function-type-
   annotation syntax the parser rejects).

## Fix direction

Resolve `camp-stdlib-compile-single` (so stdlib `.camp` trait-impl bodies are
compiled in single-file builds) — then `lower_tdecl_is_impl` will emit real
`Bool_compare`/`Char_compare`/etc. functions and the container runtime dispatch
will work.

## Test

```
import List { compare }
import Order { [Less, Equal, Greater] }
main! = || -> I64 {
  match List.compare(['a','b','c'], ['a','b','c']) { Equal => 1; _ => 0 }
}
```
Currently traps; should exit 1 after the fix.
