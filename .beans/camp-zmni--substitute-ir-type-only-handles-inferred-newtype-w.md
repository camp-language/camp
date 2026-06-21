---
# camp-zmni
title: substitute_ir_type only handles Inferred_Newtype when monomorphizing generic params — payloaded tag unions get wrong is_heap
status: done
type: bug
priority: high
created_at: 2026-06-21T02:15:54Z
updated_at: 2026-06-21T02:15:54Z
---

## Problem

Discovered during camp-9xi6 Phase 1 investigation (see
`.beans/camp-9xi6--*.md` section "D. Monomorphization & representation
propagation").

`src/mono/mono.odin:903-939` `substitute_ir_type` has two gaps when
monomorphizing a generic type parameter `T` to a concrete type:

1. **Early return at `:915-917`:** if `ir_type.type_id` already resolves to
   an `Inferred_Type` (already-linked), the function returns `ir_type`
   unchanged — keeping whatever `wasm_type`/`is_heap` it had at the
   generic's original typecheck/lower time.

2. **`:925-936`:** for the generic-param-resolved case, it derives
   `wasm_type` from the concrete type but ONLY handles
   `Inferred_Newtype` (`:930-932`). It does NOT handle
   `Inferred_Tag_Union_Row`. It returns
   `base.IR_Type{wasm_type, type_id = concrete_resolved}` with `is_heap`
   defaulted to `false`.

### Latent bug (independent of unboxed enums)

A generic `T` monomorphized to a **payloaded** tag union (e.g.
`List(Result(I64, Str))` element type, or any generic container over a
`Result`/`List`/user-defined payloaded tag union) currently gets
`is_heap=false` from this path. That is wrong — a payloaded tag union IS
heap-allocated (`src/semantics/lower_type.odin:39-40`
`Inferred_Tag_Union_Row => wasm_type=.I32, is_heap=true`), but the
monomorphized generic sees it as non-heap. This means RC drop/dup logic
(`src/ir/rc.odin`, gated on `is_heap`) skips it, leaking the cell and its
payload fields.

The bug is latent because today no shipping code path exercises a
generic-over-payloaded-tag-union with observable drop behavior at runtime
(container compares go through `call_indirect` + Design B trampolines, not
through the generic-element-drop path).

## Resolution path

camp-9xi6 (Q5, owner signoff 2026-06-21) folds the fix for BOTH the
no-payload AND payloaded cases into 9xi6 itself, because 9xi6's goal
(eliminate per-element alloc in container compare/hash loops) requires
a generic `T` monomorphized to `Order` to correctly get `is_heap=false`,
and the cleanest fix handles both cases symmetrically.

**This bean is filed so the latent bug is tracked independently of
camp-9xi6.** If 9xi6 lands its `substitute_ir_type` fix, this bean is
resolved by 9xi6's commit and can be marked completed with a pointer to
it. If 9xi6's mono fix is descoped (e.g. owner later chooses Q5 option 2
"non-generic call sites only"), THIS bean remains open and the payloaded
case must be fixed separately.

## Fix sketch (what 9xi6 will do)

In `substitute_ir_type` (`src/mono/mono.odin:925-936`), when
`tp_resolved == resolved` (the generic param matches), re-derive the full
`IR_Type` by calling `semantics.lower_type(env.store, concrete_resolved)`
instead of hand-rolling only the `Inferred_Newtype` case. This respects
the `Inferred_Tag_Union_Row` `closed`+no-payload flag (added by 9xi6 phase
3 step 1) for the no-payload-immediate case AND correctly returns
`is_heap=true` for payloaded tag unions.

Also re-examine the early-return at `:915-917`: if `is_heap` was not set
correctly at first lowering (possible pre-9xi6), the early return
propagates the wrong value. Post-9xi6's `lower_type` fix should make the
first lowering correct, leaving the early return safe — verify during
impl.

## Related

- camp-9xi6 — fixing this as part of Q5
- camp-ty9s — Design C depends on the fix landing
