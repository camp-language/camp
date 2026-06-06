---
id: camp-record-annotation
title: Annotated nominal record params type-error (resolve to newtype, not constructor)
status: todo
type: bug
priority: medium
created_at: 2026-06-06T20:00:00Z
updated_at: 2026-06-06T20:00:00Z
---

A function parameter annotated with a nominal record type fails to typecheck:

```camp
@Pt : pub { x : I64, y : I64 }
addp = |p: Pt| -> I64 { p.x + p.y }   // C0300: `Pt` does not match `record`
```

## Root cause

`convert_type_to_var` (src/semantics/typecheck.odin) turns the bare name `Pt` into
`make_primitive_type(Pt)` → `Inferred_Primitive{Pt}`. Field access (check_expr.odin
~610) unwraps a `Inferred_Newtype` to its inner record, but `p` is a primitive, so
the unwrap never fires and the `{x | rest}` constraint can't unify.

PR #97 fixed the tag-union analog (`expand_named_tag_union`); the record case was
attempted but reverted because resolving `Pt` via `env_lookup` returns the **value**
binding (the `@Pt` constructor function), so `instantiate_rec` produced a function
type → `C0304 ARITY MISMATCH` even for `|p: Pt| { 99 }`.

## Approach

Resolve a record-newtype annotation to its **type** binding (an `Inferred_Newtype`
whose inner is the record row), so field access unwraps it. Key sub-task: distinguish
the type-name binding from the value/constructor binding — `env_lookup`/`store.bindings`
currently conflate them. Then add a `resolve_record_newtype` that returns the
instantiated newtype (with type-param substitution, mirroring `expand_named_tag_union`),
wired into the `CType_Primitive`/`CType_Variable`/`CType_Applied` paths.

## Test
`tests/e2e/execution/` — annotated record param + field access returning a known exit.
