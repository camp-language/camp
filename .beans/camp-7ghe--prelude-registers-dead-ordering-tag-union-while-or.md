---
# camp-7ghe
title: Prelude registers dead 'Ordering' tag union while @Order is the live type in stdlib/Ord.camp
status: todo
type: bug
priority: normal
created_at: 2026-06-21T02:15:54Z
updated_at: 2026-06-21T02:15:54Z
---

## Problem

Discovered during camp-9xi6 Phase 1 investigation (see
`.beans/camp-9xi6--*.md` section "L. Other facts discovered").

The prelude registers a tag union named `Ordering`:

- `src/semantics/prelude.odin:47` — `{"Ordering", 0}` in `PRELUDE_CONSTRUCTOR_TYPES`
- `src/semantics/prelude.odin:84-88` — `PRELUDE_TAG_UNIONS` entry
  `{"Ordering", 0, [{"Less"...},{"Equal"...},{"Greater"...}]}`

But the live Ord trait return type is `Order`, not `Ordering`:

- `src/semantics/prelude.odin:516` — `prelude_resolve_type_ref(store, "Order", ...)`
  for the ord `compare` return type
- `src/semantics/prelude.odin:552` — `{"Bool", "Bool_compare"}` etc. register
  `*_compare` impls that return `Order`

`Order` only resolves to a concrete type because `stdlib/Ord.camp:4` declares
`@Order : pub [Less | Equal | Greater]` and binds `@Order` in `store.bindings`
when the stdlib is loaded. If `Ord.camp` is not loaded, `"Order"` falls through
`prelude_resolve_type_ref` (`prelude.odin:122`) and returns a fresh unresolved
var — the Ord trait's `compare` return type silently becomes free.

Meanwhile the prelude's own `Ordering` registration is effectively dead: nothing
in `src/`, `stdlib/`, or `tests/` resolves `"Ordering"` to a usable tag-union
type. The live name everywhere (`stdlib/*.camp`, kitchen-sink comments at
`tests/e2e/language/kitchen-sink/Main.camp:240`) is `Order`.

## Scope (not in 9xi6)

camp-9xi6 (unboxed enums) treats `@Order` as the canonical no-payload closed
tag union target and does NOT depend on the prelude `Ordering` registration
working. So this wart is out of 9xi6's scope — filed here so the dead
registration / name split is tracked rather than rediscovered.

## Fix sketch (when picked up)

Either:

1. Rename the prelude registration `Ordering` -> `Order` (and drop the
   `@Order` declaration from `stdlib/Ord.camp`, letting the prelude own
   `Order`); or
2. Delete the dead `Ordering` registration from `PRELUDE_CONSTRUCTOR_TYPES`
   and `PRELUDE_TAG_UNIONS` and let `stdlib/Ord.camp`'s `@Order` be the
   sole definition (preferred — keeps the prelude minimal).

Verify no test or stdlib module references `"Ordering"` by name before
deleting. (Phase 1 grep found only the prelude self-references.)

## Related

- camp-9xi6 — discovered here
