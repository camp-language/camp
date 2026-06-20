---
# camp-9xi6
title: 'Unboxed enums: represent no-payload tag unions (Order, Bool, Result tag) as immediate values, eliminating per-element alloc in compare/hash loops'
status: todo
type: task
priority: high
created_at: 2026-06-20T07:30:00Z
updated_at: 2026-06-20T07:30:00Z
related:
    - camp-ty9s
    - camp-24mj
---

## Problem

Camp represents *every* tag union value — including no-payload enums like
`Order = [Less | Equal | Greater]` — as a heap-allocated cell with a tag byte
(`src/semantics/lower_type.odin:39-40` `Inferred_Tag_Union_Row` → `i32, is_heap=true`;
`src/codegen/emit_expr.odin:2261-2360` `IR_Construct_Tag` always allocs, even for
zero-payload tags). `Bool` is the lone exception (immediate `i32 0/1`,
`lower_type.odin:26-27`).

This makes `Order` heap-allocated, so every element compare in a `List.compare` /
`Map.insert` walk allocates a one-use `Less`/` Equal`/`Greater` cell and drops it
inside the loop. That allocation is pure overhead and an RC hazard, and it is the
underlying reason the A-vs-B `camp-ty9s` debate was awkward.

## Goal

Tag unions with **no payload across all variants** (e.g. `Order`, user-defined
`[Red | Green | Blue]`, `Result` *tag* but not its payloads) should lower to an
**immediate scalar** (small `i32` tag value), not a heap cell. Matching reads the
scalar directly (`i32.eq` / `br_table` on the value) instead of `load8u` at a tag
offset. Construction is a constant. No alloc, no RC, no drop.

This is the long-run destination of `camp-ty9s` Design C: with unboxed `Order`,
container `compare`/`eq`/`hash` can be written as plain Camp generics calling the
element trait methods, monomorphized per type — `call_indirect` + `func_map`
bridging + runtime intrinsics all deleted. `Order` (and any user enum) flows by
value through every layer with one representation.

## Scope (design TBD)

- Type-system/lowering: how to detect an "all-variants-no-payload" tag union and
  mark it `is_heap=false`, scalar `i32`.
- Codegen: `IR_Construct_Tag` picks immediate-const path for these; match
  dispatch reads the scalar; drop is a no-op.
- Interaction with polymorphism: an enum-typed value of statically-unknown
  variant set (e.g. an open row) must still be boxed — only *closed* no-payload
  tag unions qualify.
- Interaction with RC/reuse analysis (Perceus): immediate values are
  non-reference-counted; reuse nodes must not target them.
- Migration: `Bool`'s existing immediate path is the prior art to generalize.

## Not blocking

`camp-ty9s` Design B (container intrinsics return `Order`) proceeds without this;
it just carries the per-element-alloc cost until unboxed enums land. Filing this
so the cost is recorded rather than rediscovered as a "performance bug" later.
