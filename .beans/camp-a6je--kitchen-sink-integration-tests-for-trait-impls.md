---
# camp-a6je
title: Kitchen-sink integration tests for trait impls
status: todo
type: task
priority: normal
created_at: 2026-06-06T22:45:06Z
updated_at: 2026-06-06T22:46:14Z
blocked_by:
    - camp-sirt
---

Update tests/e2e/language/kitchen-sink/Main.camp to exercise all trait implementations: structural Eq on records and tuples, all primitive Ord/Debug/Hash tests, container trait tests. Update expected.toml via just update-snapshots.
