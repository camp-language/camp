---
id: camp-a1b2
title: Implement Clone trait for stdlib types
status: todo
type: task
priority: high
created_at: 2026-05-30T16:20:00Z
updated_at: 2026-05-30T16:20:00Z
---

Stdlib defines `Clone : { clone : |Self| -> Self }` in `stdlib/Clone.camp`. 
No types implement it.

Types needing `Clone` impls:
- All Num types: I8, I16, I32, I64, U8, U16, U32, U64, F32, F64
- Bool, Str, Bytes, List, Result, Map, Set, Path, Duration, Uri, Uuid, Regex
- Json value type

Each impl: `impl Clone for T { clone = |x| -> T { x } }` — copy by value semantics.
For heap types (Str, Bytes, List, Map, Set, Path, Regex): needs proper refcount increment, not bitwise copy. Requires `camp_clone` intrinsic or manual RC bump.
