---
# camp-04nd
title: 'FFI design: research and design foreign-function interface'
status: draft
type: task
priority: deferred
created_at: 2026-06-27T17:13:12Z
updated_at: 2026-06-27T17:13:12Z
---

Source: was §14 of docs/language-spec.md (section removed 2026-06-27; this bean is now the sole tracker).

The recipe previously claimed "Bead task created (camp-14y)" but no such bean existed in .beans/. Recreating here as the authoritative tracker.

## Scope
Research + design for a foreign-function interface in Camp. Still needed:
- Calling convention / ABI story (WASM/WASI target)
- Syntax for declaring extern bindings (no FFI code currently exists in src/ — grep for ffi/extern/foreign returns nothing real)
- Interaction with Perceus ref-counting (ownership transfer across the FFI boundary)
- Interaction with strict typing + effect tracking (foreign calls as untracked effects vs a Foreign! effect)

## Out of scope until design lands
- Implementation. This bean is design-only; an implementation bean should be split off once the design is settled.

## Notes
Track under §14 "Open Items (Deferred)" lineage. When the design is decided, record the decision (per AGENTS.md) in docs/language-spec.md as a new section before implementing.
