---
# camp-llot
title: 'Hash runtime: SipHash-1-3 in WASM + codegen for all primitive types'
status: in-progress
type: task
priority: high
created_at: 2026-06-06T22:44:38Z
updated_at: 2026-06-06T22:46:08Z
blocked_by:
    - camp-9m0n
---

Implement SipHash-1-3 runtime functions in WASM bytecode (`src/codegen/runtime.odin`) and wire up codegen for all primitive types.
**Architecture:**
**Functions needed in `Runtime_Func` enum:**
**Key blocker from prior attempt:**
**Dependencies:** Hasher type `@Hasher : {}` is already defined in `stdlib/Hash.camp`. Hash trait `Hash : { hash : |Self, Hasher| -> Hasher }` registered in prelude. Stdlib `is Hash` blocks already exist for all types.
