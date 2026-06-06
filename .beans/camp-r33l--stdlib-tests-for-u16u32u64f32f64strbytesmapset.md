---
# camp-r33l
title: Stdlib tests for U16/U32/U64/F32/F64/Str/Bytes/Map/Set
status: todo
type: task
priority: normal
created_at: 2026-06-06T22:45:06Z
updated_at: 2026-06-06T22:46:14Z
blocked_by:
    - camp-llot
---

Add test blocks to stdlib modules that currently lack them: U16.camp, U32.camp, U64.camp, F32.camp, F64.camp, Str.camp, Bytes.camp, Map.camp, Set.camp. Follow existing test patterns (single test block per file to avoid camp test hang). Test order: happy path, boundary values, identity.
