---
id: camp-9c0d
title: Implement Ord trait for stdlib types
status: todo
type: task
priority: medium
created_at: 2026-05-30T16:26:00Z
updated_at: 2026-06-06T18:30:00Z
---

## ✅ Done (PR #95)
- Ord trait registered in prelude (parent: none, Eq not formally registered)
- Typechecker: `<` `>` `<=` `>=` enforce Ord conformance
- Canonicalize: `derives Ord` works
- Stdlib: `is Ord` blocks for all 25 types
- **Scalar compare works via pure Camp**: I64, I32, I16, I8, U64, U32, U16, U8, Bool, Char, F32, F64 all use `if a < b { Less } else if a == b { Equal } else { Greater }` in stdlib — compiles to working WASM. No codegen magic needed.

## ❌ Remaining

### 1. Str / Bytes compare runtime functions
`Str < Str` compares pointers (wrong). Need lexicographic byte comparison.
- Add `Runtime_Func.Str_Compare` 
- Write body in `runtime.odin` (byte-by-byte loop, return Order tag)
- Wire in `codegen.odin`
- Handle `Str_compare` / `Bytes_compare` calls in `emit_expr.odin`

### 2. Float total_cmp
F32/F64 `<` uses IEEE semantics (NaN compares unordered). Need `total_cmp` for total ordering:
- -NaN < -inf < ... < +inf < +NaN
- Implement as runtime function that bit-casts F64→I64 and uses i64 comparison

### 3. Structural Ord lowering (`lower.odin`)
Records, tag unions, tuples: lexicographic comparison.
Same approach as Eq lowering but with `IR_BinOp(Lt/Gt/Le/Ge)` chaining.
