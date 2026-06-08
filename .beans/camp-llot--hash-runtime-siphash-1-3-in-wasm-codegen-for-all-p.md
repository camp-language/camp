---
# camp-llot
title: 'Hash runtime: SipHash-1-3 in WASM + codegen for all primitive types'
status: completed
type: task
priority: high
created_at: 2026-06-06T22:44:38Z
updated_at: 2026-06-08T05:00:00Z
blocked_by:
    - camp-9m0n
---

## Completed

Implemented SipHash-1-3 runtime in WASM bytecode (`src/codegen/siphash.odin`).

### What was implemented:
- `Hash_Init`: allocates 52-byte Hasher with SipHash state constants
- `Hash_Write_I64`: full 8-byte block compression (no buffering)
- `Hash_Write_I32/I16/I8`: byte buffering with tail accumulation
- `Hash_Write_F64`: IEEE 754 bit reinterpret via memory store/load
- `Hash_Write_F32`: promote to f64, then hash as f64 block
- `Hash_Write_Str`: byte-by-byte iteration with buffering
- `Hash_Finish`: pad tail, compress, 3 finalization rounds, XOR result

### Codegen wiring:
- 9 `Runtime_Func` entries added to enum
- WASM function types registered in codegen.odin
- Intrinsic dispatch for 14 primitive Hash types in emit_expr.odin
- `Hash.new` and `Hash.finish` module-level functions added to stdlib
- `Wasm_F32_Store` and `Wasm_F64_Promote` instructions added to wasm.odin

### Known issue (tracked as camp-hash-intercept):
`Hash.new`/`Hash.finish` module-qualified call interception doesn't fire.
The SipHash runtime functions work correctly but are not yet wired to the
user-facing API. See `.beans/camp-hash-intercept.md`.

### Dependencies resolved:
- camp-9m0n: Hash trait + stdlib impls (already registered in prelude)
