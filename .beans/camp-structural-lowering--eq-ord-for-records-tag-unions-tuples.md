---
id: camp-structural-lowering
title: Structural Eq/Ord lowering for records, tag unions, tuples
status: todo
type: task
priority: medium
created_at: 2026-06-06T18:30:00Z
updated_at: 2026-06-06T18:30:00Z
---

Implement field-by-field comparison of structural types (records, tag unions, tuples) at the IR lowering level.

## Motivation
`{a:1, b:"x"} == {a:1, b:"x"}` currently compares POINTER values (heap-allocated records), giving wrong result.

## Approach (Per Q2 decision: Inline at lowering)

### Records
In `lower_tbinop` (src/ir/lower.odin), detect structural types:
- `Inferred_Record_Row` → emit `IR_Field_Access` for each field, chain `IR_BinOp(Eq)` + `IR_BinOp(And)`
- `Inferred_Tag_Union_Row` → emit discriminant comparison + payload comparison
- `Inferred_Tuple` → positional field access + chain

### Tag Unions
```
match [left, right] {
  [Tag1(x), Tag1(y)] => x == y
  [Tag1(_), _] => False
  ...
}
```
If IR_Match can't handle two-scrutinee matching, fall back to:
```
if tag_index(left) == tag_index(right) {
  match_payloads(left, right)
} else {
  False
}
```

### Tuples
Same as records with positional field access (`IR_Tuple_Access`).

## Files
- `src/ir/lower.odin`: `lower_tbinop` — detect structural types, emit field-wise comparison
- `src/ir/ir.odin`: May need `IR_Tuple_Access` variant (check if it exists)

## Test
```camp
test "record equality" {
  expect { x: 1, y: "a" } == { x: 1, y: "a" }
  expect { x: 1, y: "a" } != { x: 2, y: "a" }
}
test "tag union equality" {
  expect Ok(1) == Ok(1)
  expect Ok(1) != Err("no")
}
```
