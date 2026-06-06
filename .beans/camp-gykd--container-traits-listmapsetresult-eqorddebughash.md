---
# camp-gykd
title: 'Container traits: List/Map/Set/Result Eq/Ord/Debug/Hash'
status: todo
type: task
priority: high
created_at: 2026-06-06T22:45:01Z
updated_at: 2026-06-06T22:46:08Z
blocked_by:
    - camp-llot
---

Add Eq/Ord/Debug/Hash trait implementations for container types in stdlib. List: field-by-field element comparison. Map: key-value pair comparison. Set: element-wise equality. Result: Ok(a)==Ok(b) if a==b, Err(e1)==Err(e2) if e1==e2. Generic types require [T: Eq] bounds. Key files: stdlib/List.camp, stdlib/Map.camp, stdlib/Set.camp, stdlib/Result.camp. Depends on: Hash runtime (camp-llot) for Hash impls.
