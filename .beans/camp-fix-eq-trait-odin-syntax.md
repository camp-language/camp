# Fix Eq Trait Odin Syntax Issues

## Status
Eq trait implementation is 80% complete. Working components:
- ✓ Eq trait registered in prelude
- ✓ Typechecker enforces Eq conformance
- ✓ Stdlib `is Eq` blocks added

Remaining 20% requires Odin syntax fixes.

## Known Issues

### `src/semantics/canonicalize.odin`
**Problem:** Eq code generation functions have syntax errors
- `generate_struct_eq` function
- `generate_record_eq_body` function  
- `generate_tag_union_eq_body` function

**Required Fixes:**
- Fix struct initialization syntax (Odin requires specific field-by-field assignment)
- Fix type variable dereferencing in switch statements
- Ensure proper pointer handling in `scope.generated_decl` appends

### `src/ir/lower.odin`
**Problem:** Eq dispatch in `lower_tbinop` and helper functions have syntax errors

**Eq dispatch in `lower_tbinop` (after Str concat case at line ~1380):**
- Fix `e.left^` and `e.right^` arguments to `lower_texpr` (Odin can't auto-dereference)
- Fix IR struct literal formatting (Odin requires trailing commas)
- Fix `IR_PrefixOp` - doesn't exist, use `IR_BinOp` with `.Bang_Eq` for negation
- Ensure proper variable declarations (`eq_result: IR_Expr = ...`)

**`lower_eq_via_trait` helper function:**
- Fix `v_ptr.link.(semantics.Inferred_Type)` pattern (Odin's type switch syntax)
- Fix struct field names (`type_` not `type`)
- Fix IR struct literals with trailing commas

**`compute_struct_eq_name` helper function:**
- Fix type switch dereferencing
- Fix struct field names

## Odin Syntax Rules Discovered

1. **Struct literals:** Require trailing commas for each field
2. **Pointer dereferencing:** `left^` syntax required in function arguments
3. **Type switch:** `v_ptr.link.(T)` pattern needs careful handling
4. **Field names:** IR structs use `type_` not `type`
5. **Variable declarations:** Must specify type: `var: T = value`
6. **No `..` elision:** Odin doesn't support struct elision in implementation

## Test Cases to Validate

```camp
// Test Eq for primitives
test "I64 eq" {
    expect 42 == 42
    expect (42 != 0)
}

// Test Eq for strings
test "Str eq" {
    expect "hello" == "hello"
    expect ("hello" != "world")
}

// Test Eq for records (auto-derive)
type Point = { x: I64, y: I64 }
test "Record eq" {
    p1 = { x: 1, y: 2 }
    p2 = { x: 1, y: 2 }
    p3 = { x: 1, y: 3 }
    expect p1 == p2
    expect (p1 != p3)
}

// Test Eq for tag unions (auto-derive)
type Option(a) = [Some(a) | None]
test "Tag union eq" {
    o1 = Some(42)
    o2 = Some(42)
    o3 = None
    expect o1 == o2
    expect (o1 != o3)
}
```

## Success Criteria
- Compiler builds without errors
- Eq trait works for all primitive types
- Eq auto-derives for records, tag unions, and tuples
- `==` and `!=` operators work correctly
- Typechecker rejects operations on non-Eq types

## Dependencies
- Odin compiler version must match project requirements
- All existing tests must pass
- No changes to AST/IR structure