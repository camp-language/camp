---
id: camp-9c0d
title: Implement Ord trait for stdlib types
status: todo
type: task
priority: medium
created_at: 2026-05-30T16:24:00Z
updated_at: 2026-05-30T16:24:00Z
---

Stdlib defines `Ord : { compare : |Self, Self| -> Order }` in `stdlib/Ord.camp`.
Depends on `Order` type being defined (likely `enum Order { Less, Equal, Greater }`).
No types implement it.

Types needing impls:
- All Num types: standard numeric ordering
- Bool: `False < True`
- Str: lexicographic byte comparison
- Bytes: lexicographic comparison
- List: lexicographic element-by-element — requires Ord bounds on T
- Map: compare by sorted keys then values
- Set: compare sorted elements
- Path: lexicographic string comparison
- Duration: nanosecond count comparison
- Uri: lexicographic string comparison
- Uuid: numeric comparison
- Regex: pattern string comparison
- Json: defined ordering (Null < Bool < Num < Str < List < Map, then by value)

Requires `Order` enum definition before impls can be written.
