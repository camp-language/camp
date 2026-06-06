---
id: camp-7a8b
title: Implement Eq trait for stdlib types
status: todo
type: task
priority: high
created_at: 2026-05-30T16:23:00Z
updated_at: 2026-06-06T18:30:00Z
---

## ✅ Done (PR #95 + earlier)
- Prelude: Eq registered + 15 primitive impls
- Typechecker: Eq conformance enforced on `==` / `!=`
- Canonicalize: `derives Eq` works for nominal types
- Codegen: `IR_BinOp(Eq)` works for scalars; `Str_Eq` runtime function exists
- Stdlib: `is Eq` blocks for all numeric types, Bool, Str, Bytes, Char
- Stdlib: `is Eq` blocks for opaque types (Map, Set, Json, Duration, Path, Uri, Uuid, Regex, Base64) — via `crash "intrinsic: X_eq"`

## ❌ Remaining

### 1. Structural Eq lowering (`lower.odin`)
Records, tag unions, tuples: `{a:1} == {a:1}` currently emits `IR_BinOp(Eq)` on pointer values (wrong for heap-allocated data).
Need field-by-field comparison inlining.

- **Record**: chain `IR_Field_Access` + `IR_BinOp(Eq)` + `IR_BinOp(And)` per field
- **Tag union**: compare discriminant (tag_index), then payloads
- **Tuple**: positional field comparison

Reference: `lower_tbinop` in `src/ir/lower.odin` line 1420

### 2. Opaque type Eq runtime functions
`*_eq` calls for Map, Set, Json, Duration, Path, Uri, Uuid, Regex, Base64 need runtime implementations.

Each requires:
1. Add to `Runtime_Func` enum in `emit_expr.odin`
2. Write body emission function in `runtime.odin`
3. Wire type, add function, append code in `codegen.odin`
4. Handle call in `emit_expr.odin` `IR_Call` handler
