---
# camp-a6je
title: Kitchen-sink integration tests for trait impls
status: todo
type: task
priority: normal
created_at: 2026-06-06T22:45:06Z
updated_at: 2026-06-22T06:30:00Z
---

Update `tests/e2e/language/kitchen-sink/Main.camp` to exercise all trait
implementations. The kitchen-sink test is the living example of every Camp
language feature — trait impls must be represented.

Coverage needed:
- **Structural Eq**: `==` on records, tuples, tag unions (operator path, not trait method)
- **Primitive Ord**: `List.compare` with Bool, Char, I64 elements (dispatches through runtime)
- **Primitive Debug**: `debug` method calls on Bool, Char, I64, Str
- **Primitive Hash**: `hash` method calls on Bool, Char, I64, Str
- **Container trait dispatch**: `List.compare`, `Result.eq`, `Map.eq` with various element types
- **Custom trait impl**: a user-defined trait with a user-defined impl (e.g. `is Show { show = ... }`)
- **Multi-param From**: `Bool is From` dispatching to correct target type

Run `just update-snapshots` after updating. Verify all e2e pass.

Note: `camp-sirt` (original blocker) may be stale — check if resolved before
starting.
