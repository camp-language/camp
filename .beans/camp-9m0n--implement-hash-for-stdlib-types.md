---
id: camp-9m0n
title: Implement Hash trait for stdlib types
status: todo
type: task
priority: low
created_at: 2026-05-30T16:27:00Z
updated_at: 2026-06-06T18:30:00Z
---

## ✅ Done (PR #95)
- `@Hasher : {}` defined in `stdlib/Hash.camp`
- `Hash : { hash : |Self, Hasher| -> Hasher }` trait defined
- Stdlib: `is Hash` blocks for all 25 types (via `crash "intrinsic: X_hash"`)
- Codegen infrastructure ready to wire runtime functions

## ❌ Remaining

### 1. Hasher runtime implementation
`Hasher` is opaque — its internal state is a u64 hash value.
Need runtime functions:

- **`Hasher_New`**: allocate Hasher struct with initial FNV-1a offset basis (`0xcbf29ce484222325`)
- **`Hasher_Write_U64`**: XOR 8 bytes into hash state, multiply by FNV prime
- **`Hasher_Write_Bytes`**: iterate bytes, XOR and multiply
- **`Hasher_Finish`**: return final u64 hash value
- **`*_hash` codegen**: recognize `X_hash` calls and route to Hasher_Write

### 2. `Hasher.finish` API
Current trait has no `finish` method. Need to add `Hasher.finish(h: Hasher) -> U64` to stdlib.
Or make the final hash extraction an intrinsic.

### 3. FN V-1a vs SipHash
FNV-1a is simple (~50 lines WASM) but collision-prone.
SipHash-1-3 is secure but ~200 lines WASM.
Start with FNV-1a, document as non-cryptographic.
