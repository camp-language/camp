---
# camp-sirt
title: Structural Ord for records and tag unions
status: todo
type: task
priority: high
created_at: 2026-06-06T22:45:01Z
updated_at: 2026-06-06T22:45:31Z
---

Generate lexicographic comparison for records/tag unions/tuples when <, >, <=, >= is used. Approach: In lower_tbinop, detect comparison operators on record/tag-union/tuple types. Generate nested if-then-else chains using field access + BinOp for each field in canonical (alphabetical) order. For records: Compare first field; if Equal, compare next. For tag unions: Compare tag indices first, then payloads. For tuples: Compare elements in order. Key file: src/ir/lower.odin — lower_tbinop function. Structural Eq already implemented for records/tuples.
