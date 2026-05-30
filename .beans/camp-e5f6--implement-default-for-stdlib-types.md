---
id: camp-e5f6
title: Implement Default trait for stdlib types
status: todo
type: task
priority: medium
created_at: 2026-05-30T16:22:00Z
updated_at: 2026-05-30T16:22:00Z
---

Stdlib defines `Default : { default : |Self| -> Self }` in `stdlib/Default.camp`.
No types implement it.

Semantics per type:
- Num types: I8=0, I16=0, I32=0, I64=0, U8=0, U16=0, U32=0, U64=0, F32=0.0, F64=0.0
- Bool: `False`
- Str: `""` (empty string)
- Bytes: empty byte array
- List: `[]`
- Result: requires Ok variant with default of T — problematic for generic E. Maybe use `Result.Ok(|T -> T{ Default.default(T) })` — only if T: Default
- Map: empty map
- Set: empty set
- Path: `Path.empty` or `Path.root`
- Duration: zero duration
- Uri: empty/root URI
- Uuid: nil UUID (all zeros)
- Regex: empty pattern or always-fail regex
- Json: `Json.Null`
