---
# camp-llot
title: 'Hash runtime: SipHash-1-3 in WASM + codegen for all primitive types'
status: completed
type: task
priority: high
created_at: 2026-06-06T22:44:38Z
updated_at: 2026-06-08T06:30:00Z
blocked_by:
    - camp-9m0n
---

## Completed

Implemented SipHash-1-3 runtime in WASM bytecode (`src/codegen/siphash.odin`)
and wired it to the hash trait dispatch.

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
- Unified hash handler in emit_expr matches `name_str == "hash"` with >= 2 args
  (handles both trait dispatch and module-qualified calls)
- Type-based dispatch: i64, f64, f32→f64, i32 (fallback)
- Hash pipeline: Init → Write → Finish, returns i64 hash value
- `Wasm_F32_Store` and `Wasm_F64_Promote` instructions added to wasm.odin

### Tests:
- `tests/e2e/execution/hash-basic/`: I64.hash(42) == I64.hash(42) → exit 1

### Dependencies resolved:
- camp-9m0n: Hash trait + stdlib impls (already registered in prelude)
- camp-hash-intercept: module-level interception issue (resolved by unified handler)
