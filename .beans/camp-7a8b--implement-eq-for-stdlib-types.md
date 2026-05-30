---
id: camp-7a8b
title: Implement Eq trait for stdlib types
status: todo
type: task
priority: high
created_at: 2026-05-30T16:23:00Z
updated_at: 2026-05-30T16:23:00Z
---

Stdlib defines `Eq : { eq : |Self, Self| -> Bool }` in `stdlib/Eq.camp`.
No types implement it. `==` operator currently works via compiler intrinsic for primitives, but trait dispatch would unify this.

Types needing impls:
- All Num types: bitwise/intrinsic equality
- Bool: `x == y` (using existing `x == y` or `if x { y } else { not y }`)
- Str: structural byte comparison
- Bytes: byte-by-byte comparison
- List: structural element-by-element — requires `Eq` bounds on element type T
- Result: structural — `Ok(a) == Ok(b)` if `a == b`, `Err(e1) == Err(e2)` if `e1 == e2`
- Map: key-value pair comparison
- Set: element-wise equality
- Path: string representation equality
- Duration: component-wise comparison
- Uri: string representation equality
- Uuid: byte-by-byte comparison
- Regex: pattern string equality (not language equivalence)
- Json: structural value comparison

For generic types (List, Result, Map, Set): requires trait bounds `[T: Eq]` or similar.
