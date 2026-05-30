---
id: camp-7k8l
title: Implement FromIter trait for stdlib types
status: todo
type: task
priority: low
created_at: 2026-05-30T16:28:00Z
updated_at: 2026-05-30T16:28:00Z
---

Stdlib defines `FromIter : { from_iter : |Iter(a)| -> Self }` in `stdlib/FromIter.camp`.
No types implement it. `FromIter` enables `.collect()` on iterators — the inverse of `IntoIter`.

Types needing impls:
- List(T): collect elements into a new list — pushes each element
- Map(K, V): collect (key, value) pairs into a new map
- Set(T): collect elements into a new set (deduplicates)
- Str: collect U8/Rune elements into a string
- Bytes: collect U8 elements into a byte buffer
- Json: collect into array

This depends on `Iter(a)` being defined (its concrete representation and next protocol). Also depends on `IntoIter` being implemented first since `FromIter` is the collection side of the consumer pattern.
