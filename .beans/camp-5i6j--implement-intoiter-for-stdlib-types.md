---
id: camp-5i6j
title: Implement IntoIter trait for stdlib types
status: todo
type: task
priority: medium
created_at: 2026-05-30T16:27:00Z
updated_at: 2026-05-30T16:27:00Z
---

Stdlib defines `IntoIter : { to_iter : |Self| -> Iter(a) }` in `stdlib/IntoIter.camp`.
No types implement it. `IntoIter` enables `for` loops and iterator combinators.

Types needing impls:
- List(T): iterate elements in order — returns `Iter(T)` consuming the list
- Map(K, V): iterate (key, value) pairs — returns `Iter((K, V))`
- Set(T): iterate elements — returns `Iter(T)`
- Str: iterate characters/bytes — returns `Iter(U8)` or `Iter(Rune)`
- Bytes: iterate bytes — returns `Iter(U8)`
- Range: if Range type exists, iterate values from start to end
- Result(T, E): iterate 0 or 1 values of T
- Option(T): iterate 0 or 1 values (if Option type exists)

`Iter(a)` is an opaque iterator type in `stdlib/Iter.camp`. Need to understand Iter's concrete representation before implementing. May require `Iter` to be a trait itself or a concrete type with `next` method.
