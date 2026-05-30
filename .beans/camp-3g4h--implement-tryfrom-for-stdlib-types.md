---
id: camp-3g4h
title: Implement TryFrom trait for stdlib types
status: todo
type: task
priority: medium
created_at: 2026-05-30T16:26:00Z
updated_at: 2026-05-30T16:26:00Z
---

Stdlib defines `TryFrom : { try_from : |Self| -> Result(target, e) }` in `stdlib/TryFrom.camp`.
No types implement it. `TryFrom` enables fallible conversions that may overflow or fail.

Useful impls:
- I64 → I32, I16, I8 (overflow check)
- I32 → I16, I8
- U64 → U32, U16, U8, I64, I32, I16, I8
- U32 → U16, U8, I32, I16, I8
- F64 → F32 (precision/overflow)
- F64 → I64, I32 (fractional truncation + overflow)
- F32 → I32, I16, I8
- Str → I64, I32, I16, I8, U64, U32, U16, U8, F64, F32 (parse)
- Str → Uuid (parse)
- Str → Regex (compile — may fail for invalid pattern)
- Bytes → Json (parse)
- Str → Json (parse)

Error type `e` should be a meaningful error variant. For numeric overflows, use `Throw.Overflow`. For parse failures, use a dedicated `Parse.Error` type or `Str` message.
