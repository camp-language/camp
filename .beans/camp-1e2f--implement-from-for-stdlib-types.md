---
id: camp-1e2f
title: Implement From trait for stdlib types
status: done
type: task
priority: medium
created_at: 2026-05-30T16:25:00Z
updated_at: 2026-05-30T16:25:00Z
---

Stdlib defines `From : { from : |Self| -> target }` in `stdlib/From.camp`.
No types implement it. `From` enables lossless conversions between related types.

Useful impls:
- I8 → I16, I32, I64, F32, F64 (widening)
- I16 → I32, I64, F32, F64
- I32 → I64, F64
- U8 → U16, U32, U64, I16, I32, I64, F32, F64
- U16 → U32, U64, I32, I64, F32, F64
- U32 → U64, I64, F64
- F32 → F64
- All ints → F64 (safe for 53-bit mantissa range)
- Str → Bytes, Path, Uri
- String → Json
- Uuid → Str, Bytes

Note: `From` for numeric types must handle sign extension correctly. Unsigned → signed widening is fine (no truncation). Float widening is exact.
## Status: Done
From trait defined in stdlib/From.camp. All lossless numeric widens + Bool→numeric + Str→Bytes/Path + Uuid→Str/Bytes. Compiler builds. 464 tests pass.
