---
# camp-p7cc
title: Unrecognized @derive attribute emits C9000 internal error instead of user-facing diagnostic
status: todo
type: bug
priority: normal
tags:
    - diagnostics
    - typecheck
created_at: 2026-06-28T02:16:59Z
updated_at: 2026-06-28T02:16:59Z
---

Source: error-path sweep (docs/discovering-gaps.md §4) + spec §15 derive attribute.

`src/semantics/canonicalize.odin:1647-1654` — the derive-name `switch` in `generate_derive_stubs` handles only `Eq`, `Hash`, `Ord`, `Debug`. Any other derive name (e.g. `@derive(Display)`, typos like `@derive(Dbug)`, or future traits) falls through to `case:` and emits `diag_internal("unrecognized derive: \`{}\`")` (C9000). This is a user mistake, not a compiler bug.

Notably `Display` is missing from the switch despite being a documented built-in trait (docs/language-spec.md:270-276 "derives generates compiler-internal implementations for built-in traits only"). Either Display derive should be wired (separate concern, may belong in camp-335w/camp-d3k3) or at minimum the unrecognized-name path must emit a user-facing error.

## Gap
Catalog has no diagnostic for "unrecognized derive attribute." The C0702-range (Newtype/Nominal errors) is the natural home — propose a new code (C0705 or similar):
> `@derive({name})` is not a recognized derive. Supported derives are: `Debug`, `Eq`, `Hash`, `Ord`.
Severity: Error.

## Work
1. Add a new constructor in `src/diagnostics/constructors.odin` (model on existing diag constructors; include the supported-derive list in the hint).
2. Replace the `diag_internal(...)` call at `canonicalize.odin:1650` with the new constructor.
3. Add the C-code to `docs/diagnostics-catalog.md` §8 (Newtype/Nominal Type Errors).
4. E2E snapshot test: `@Name(pub x: I64) derives Foo` emits the new code with the supported-derive hint.
5. Decide whether `Display` should join the switch (cross-ref camp-335w / camp-d3k3) — if not, document it as out of scope in the hint.

## Done looks like
`@derive(UnknownName)` produces a user-facing error naming the unsupported derive and listing the supported set, with an e2e snapshot. Catalog §8 gains the new row.
