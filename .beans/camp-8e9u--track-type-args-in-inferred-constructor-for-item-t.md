---
# camp-8e9u
title: Track type args in Inferred_Constructor for item-type-specific dispatch
status: todo
type: task
priority: low
tags:
    - type-system
    - traits
created_at: 2026-06-22T02:24:34Z
updated_at: 2026-06-22T02:24:34Z
---

## Problem

`Inferred_Constructor` only tracks `primitive_name` and `arity`, not the actual type arguments. `Iter(Item)` is represented as `Inferred_Constructor{Iter, 1}` regardless of what `Item` is. Unification checks name+arity only, so `Iter(I8)` unifies with `Iter(I64)`.

**Struct definition** (`src/semantics/types.odin:73-76`):
```odin
Inferred_Constructor :: struct {
    primitive_name: base.Intern_ID,
    arity:          int,
}
```

## Current impact

This is acceptable for trait conformance checking — when verifying `List is IntoIter`, the trait method's return type is `Iter(a)` (fresh var), and the impl's return is `Iter(I64)`. The `Inferred_Constructor` with `Iter, 1` matches the constructor, and the type arg `a` is unified separately via the function's `param_ids` / `return_id`.

The limitation only matters for item-type-specific dispatch of multi-param traits where the distinguishing parameter is inside a constructor. For example, if two `FromIter` impls existed for the same collection type with different item types, `find_trait_impl` couldn't distinguish them because the target type extraction (`extract_multi_param_target`) only handles `Inferred_Primitive` and `Inferred_Tag_Union_Row`, not `Inferred_Constructor` payloads.

## When this matters

- Multi-param traits where the target is a parameterized type (e.g., `From(Bool) -> Iter(I8)` vs `From(Bool) -> Iter(I16)`)
- Currently no such traits exist in the stdlib
- IntoIter and FromIter have one impl per collection type, so no disambiguation is needed

## Fix

Extend `Inferred_Constructor` to carry type arguments:
```odin
Inferred_Constructor :: struct {
    primitive_name: base.Intern_ID,
    arity:          int,
    type_args:      []base.Type_Var_ID, // NEW: track actual type arguments
}
```

Then update:
1. `unify` — when unifying two `Inferred_Constructor`s, also unify their type_args pairwise
2. `extract_multi_param_target` — handle `Inferred_Constructor` by extracting the first type arg's resolved name
3. `format_inferred_type` — include type args in the formatted output
4. Prelude injection — pass type args when creating `Inferred_Constructor` for Iter

## Priority

Low — no current use case is blocked by this. Will become relevant if multi-param traits with parameterized targets are added.
