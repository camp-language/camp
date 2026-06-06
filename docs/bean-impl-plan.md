# Bean Implementation Technical Plan: Debug, Eq, Ord, Hash

> Hand-off document for implementing the four remaining stdlib trait beans.
> Follow exactly. Every file, function, line. No interpretation needed.

## Design Decisions (Settled)

| # | Decision | Rationale |
|---|----------|-----------|
| Q1 | Debug IS derivable via `derives` | Syntax recipe §11 lists it as built-in derivable |
| Q2 | Eq/Ord on structural types: **inline at lowering** (no generated functions) | Simplest compiler logic; WASM inliner eliminates call overhead anyway |
| Q3 | `<`/`>`/`<=`/`>=` desugar to `Ord.compare(a, b)` comparisons | Single trait method, matches Rust approach |
| Q4 | SipHash-1-3 for Hash, runtime intrinsic | Industry standard, collision-resistant |
| Q5 | Floats use `total_cmp` for Ord | IEEE 754 NaN requires total ordering; matches Rust `f32::total_cmp` |
| Q6 | Named functions for nominal `derives`, inline for structural Eq/Ord | Inline avoids naming/dedup complexity for anonymous types |
| Q7 | Unit tests in each module file + kitchen-sink integration tests | Module-level covers edges; kitchen-sink covers cross-type usage |
| Q8 | Map/Set Ord uses in-order comparison (not sort-then-compare) | Map is ordered tree internally; O(n) vs O(n log n) |
| Q9 | This plan: `is Debug` impls + `derives Debug`. Separate beans for expect/Display integration | Scope control |
| Q10 | Order: Debug → Eq → Ord → Hash | Dependency chain: Debug standalone, Eq needed for Ord, Hasher needed for Hash |
## Architecture Overview

Four trait implementation phases. Each phase touches the same subsystems in a layered pattern:

```
Prelude registration → Typechecker enforcement → Auto-derive/lowering → Stdlib impls → Tests
```

Key files modified across all phases:

| File | Role |
|------|------|
| `src/semantics/prelude.odin` | Register traits + primitive impls in compiler |
| `src/semantics/check_expr.odin` | Typechecker: enforce trait conformance on operators |
| `src/semantics/canonicalize.odin` | Auto-derive stubs for `derives` on nominal types |
| `src/ir/lower.odin` | IR lowering: inline structural comparisons, call named functions for nominals |
| `src/codegen/emit_expr.odin` | WASM codegen for intrinsic trait operations |
| `src/codegen/runtime.odin` | Runtime functions (SipHash, etc.) |
| `stdlib/*.camp` | Source-level `is Trait` blocks for each stdlib type |
| `tests/e2e/language/kitchen-sink/Main.camp` | Integration tests |

---

## Phase 1: Debug Trait

### 1.1 Prelude Registration

**File:** `src/semantics/prelude.odin`

Register Debug trait and primitive impls. Debug is NOT currently in prelude.

In `inject_prelude_effects_typecheck` (after Eq registration block):

```odin
// Register Debug trait with debug: (Self) -> Str
debug_name := base.intern(store.interner, "Debug")
debug_method_name := base.intern(store.interner, "debug")

if !is_trait_declared(store, debug_name) {
    debug_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)
    param_types := make([]base.Type_Var_ID, 1, store.allocator)
    param_types[0] = fresh_value_var(store, base.Source_Span_ZERO)
    return_type := prelude_resolve_type_ref(store, "Str", 0, &debug_generic_vars)
    append(&debug_methods, Trait_Method_Info{
        name = debug_method_name,
        param_types = param_types,
        return_type = return_type,
    })
    store.trait_registry[debug_name] = Trait_Info{
        name = debug_name, module = base.NO_NAME,
        parent = base.NO_NAME, methods = debug_methods[:],
    }
}

// Register Debug impls for primitive types
debug_primitive_types := []string{
    "I8","I16","I32","I64","U8","U16","U32","U64","F32","F64",
    "Bool","Char","Str","Bytes","Unit",
}
for prim_name in debug_primitive_types {
    type_id := base.intern(store.interner, prim_name)
    method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
    method_map[debug_method_name] = base.Canonical_Name{
        module = base.NO_NAME,
        name = base.intern(store.interner, fmt.tprintf("{}_debug", prim_name)),
    }
    append(&store.trait_impls, Trait_Impl{
        trait_name = debug_name, type_name = type_id,
        type_module = base.NO_NAME, methods = method_map,
    })
}
```

### 1.2 Add Debug to `derives`

**File:** `src/semantics/canonicalize.odin` — `generate_derive_stubs`

Add `"Debug"` case after `"Ord"` case (before the default case):

```odin
case "Debug":
    stub_name := fmt.tprintf("{}_debug", type_name_str)
    if !generated[stub_name] {
        generated[stub_name] = true
        append(&result,
            make_derive_method_decl(d, "debug", 1, false, scope, interner, collector),
        )
    }
```

The existing `make_derive_method_decl` with `param_count=1, wrap_in_newtype=false` generates:
`|x| -> Str { x.inner.debug() }` — which delegates to inner type's debug. Works for newtypes.

### 1.3 Stdlib `is Debug` Impls

**Pattern for primitives (Num types):** Add to each `stdlib/Num/*.camp`:

```camp
I64 is Debug {
    debug = |a: Self| -> Str { crash "intrinsic: I64_debug" }
}
```

Same for I8, I16, I32, U8, U16, U32, U64, F32, F64.

**Bool** (`stdlib/Bool.camp`):
```camp
Bool is Debug {
    debug = |a: Self| -> Str { crash "intrinsic: Bool_debug" }
}
```

**Str** (`stdlib/Str.camp`):
```camp
Str is Debug {
    debug = |a: Self| -> Str { a }  // identity
}
```

**Bytes** (`stdlib/Bytes.camp`): intrinsic (hex dump or similar).
**Char** (`stdlib/Char.camp`): intrinsic.

**Opaque types** (Map, Set, Json, Duration, Path, Uri, Uuid, Regex, Base64): intrinsic:
```camp
Map is Debug { debug = |a: Self| -> Str { crash "intrinsic: Map_debug" } }
```

**Order** (`stdlib/Ord.camp`): Pure Camp:
```camp
Order is Debug {
    debug = |a: Self| -> Str {
        match a {
            Less => "Less"
            Equal => "Equal"
            Greater => "Greater"
        }
    }
}
```

**List, Result, Option** (tag unions): Auto-derived via Phase 1.2 (they're nominal types with structural inners — `derives` generates delegation through `.inner`). But List and Result are compiler-declared nominals without `derives` clauses in source. They need explicit `is Debug` in stdlib:

```camp
// In List.camp:
List is Debug {
    debug = |xs: Self| -> Str { crash "intrinsic: List_debug" }
}

// In Result.camp:
Result is Debug {
    debug = |r: Self| -> Str { crash "intrinsic: Result_debug" }
}
```

### 1.4 Codegen: Intrinsic `*_debug` Recognition

**File:** `src/codegen/emit_expr.odin`

In the `IR_Call` handler (around line 758), add recognition for `*_debug` intrinsic names, alongside existing `*_to_str` handling:

```odin
// Handle *_debug intrinsic calls
if strings.has_suffix(name_str, "_debug") {
    // delegate to existing to_str intrinsics
    if name_str == "I64_debug" { /* emit I64_To_Str */ }
    // ... etc for each type
}
```

Actually simpler: make `*_debug` names resolve to the same WASM runtime functions as the existing `*_to_str` intrinsics. Add a mapping in the `IR_Call` handler.

### 1.5 Debug Tests

**In each stdlib module:** Add `test` blocks for Debug:

```camp
test "I64 debug" {
    expect 42->debug() == "42"
}
test "Bool debug" {
    expect True->debug() == "True"
    expect False->debug() == "False"
}
test "Order debug" {
    expect Less->debug() == "Less"
}
```

**Kitchen-sink:** Add Debug section with cross-type tests.

---

## Phase 2: Eq Trait (Complete)

### What's Already Done (DO NOT TOUCH)

- Prelude: Eq trait registered, 15 primitive impls registered
- Typechecker: `check_expr.odin` line 227-260 enforces Eq conformance on `==`/`!=`
- Stdlib: All Num types have `is Eq` blocks with intrinsic bodies. Bool, Bytes, Str have `is Eq`.
- Canonicalize: `derives Eq` works for nominal types via `generate_derive_stubs`/`make_derive_method_decl`
- Codegen: `IR_BinOp` with `.Eq`/`.Ne` emits WASM `i32.eq`/`i64.eq`/`f64.eq` for scalar types

### What's Missing

1. **Structural Eq at lowering**: `{a:1} == {a:1}` hits `lower_tbinop` which emits `IR_BinOp(Eq)`, and codegen emits `i32.eq` — nonsense for heap-allocated records
2. **Stdlib impls for opaque types**: Map, Set, Json, Duration, Path, Uri, Uuid, Regex, Base64

### 2.1 Lowering: Inline Structural Eq

**File:** `src/ir/lower.odin` — `lower_tbinop`

Current `lower_tbinop` (line 1420) unconditionally emits `IR_BinOp` for all comparison operators. This works for WASM scalars but is wrong for structural types.

**Insert before `left_ir := lower_texpr(e.left, env)` (line 1450):**

```odin
// Handle Eq/Ne for structural (non-scalar) types via inline lowering
if e.op == .Eq_Eq || e.op == .Bang_Eq {
    operand_type := semantics.resolve_var(env.store, texpr_type_id(e.left))
    v := &env.store.vars[int(operand_type)]
    if inf, is_inf := v.link.(semantics.Inferred_Type); is_inf {
        switch concrete in inf {
        case semantics.Inferred_Record_Row:
            return lower_record_eq(e.left, e.right, concrete, e, env)
        case semantics.Inferred_Tag_Union_Row:
            return lower_tag_union_eq(e.left, e.right, concrete, e, env)
        case semantics.Inferred_Tuple:
            return lower_tuple_eq(e.left, e.right, concrete, e, env)
        case semantics.Inferred_Primitive:
            // Falls through to IR_BinOp below (scalar comparison)
        case semantics.Inferred_Newtype:
            // Falls through to IR_BinOp below (newtypes erase to inner)
        }
    }
}
```

**Add helper: `lower_record_eq`**

```odin
lower_record_eq :: proc(
    left, right: ^semantics.TExpr,
    row: semantics.Inferred_Record_Row,
    e: ^semantics.TExpr_BinOp,
    env: ^Lower_Env,
) -> IR_Expr {
    // Generate: x.field1 == y.field1 and x.field2 == y.field2 and ...
    if len(row.record_fields) == 0 {
        return make_ir_lit_bool(true, e.type_, e.span)
    }
    
    left_ir := lower_texpr(left, env)
    right_ir := lower_texpr(right, env)
    
    var current: IR_Expr
    for i, field in row.record_fields {
        // Extract field from left: IR_Field_Access(left_ir, field.name, field.type)
        left_field := new(IR_Field_Access)
        left_field^ = IR_Field_Access{
            record = left_ir, field = field.name,
            type = field.type, span = e.span,
        }
        right_field := new(IR_Field_Access)
        right_field^ = IR_Field_Access{
            record = right_ir, field = field.name,
            type = field.type, span = e.span,
        }
        
        // Recursively lower field comparison (handles nested structurals)
        field_eq := new(IR_BinOp)
        field_eq^ = IR_BinOp{
            op = .Eq, left = left_field, right = right_field,
            type = e.type_, span = e.span,
        }
        
        if i == 0 {
            current = field_eq
        } else {
            current = new(IR_BinOp){
                op = .And, left = current, right = field_eq,
                type = e.type_, span = e.span,
            }
        }
    }
    return current
}
```

**Add helper: `lower_tag_union_eq`**

```odin
lower_tag_union_eq :: proc(
    left, right: ^semantics.TExpr,
    row: semantics.Inferred_Tag_Union_Row,
    e: ^semantics.TExpr_BinOp,
    env: ^Lower_Env,
) -> IR_Expr {
    // Generate: match [left, right] {
    //   [Tag1(x), Tag1(y)] => x == y    // for tags with payload
    //   [Tag2, Tag2] => True            // for tags without payload
    //   [_, _] => False
    // }
    
    left_ir := lower_texpr(left, env)
    right_ir := lower_texpr(right, env)
    
    arms := make([dynamic]IR_Match_Arm, 0, len(row.tag_entries) + 1)
    
    for tag in row.tag_entries {
        if tag.type != nil && !is_unit_type(tag.type) {
            // Tag with payload: match payloads
            // Pattern: Tag(x), Tag(y) → compare x == y
            // Build as IR_Match with payload binding + comparison
            // ... (detailed IR construction)
        } else {
            // Tag without payload: Tag vs Tag → True
        }
    }
    // Wildcard arm → False
    
    match_expr := new(IR_Match)
    match_expr^ = IR_Match{
        scrutinee = /* pair of left_ir, right_ir */,
        arms = arms, type = e.type_, span = e.span,
    }
    return match_expr
}
```

> **NOTE:** Tag union Eq is the most complex lowering. The exact IR shape depends on how `IR_Match` currently handles tag patterns. The approach: emit a two-element tuple/list as scrutinee, match on tag patterns for each position, compare payloads in the body. If `IR_Match` can't handle this directly, fall back to comparing tag indices (`IR_Tag_Index`) then payloads.

**Add helper: `lower_tuple_eq`**

```odin
lower_tuple_eq :: proc(
    left, right: ^semantics.TExpr,
    tup: semantics.Inferred_Tuple,
    e: ^semantics.TExpr_BinOp,
    env: ^Lower_Env,
) -> IR_Expr {
    // Same approach as record_eq but with positional field access
    left_ir := lower_texpr(left, env)
    right_ir := lower_texpr(right, env)
    
    var current: IR_Expr
    for i in 0 ..< tup.element_count {
        left_el := new(IR_Tuple_Access){tuple = left_ir, index = i, ...}
        right_el := new(IR_Tuple_Access){tuple = right_ir, index = i, ...}
        el_eq := new(IR_BinOp){op = .Eq, left = left_el, right = right_el, ...}
        if i == 0 { current = el_eq }
        else { current = new(IR_BinOp){op = .And, left = current, right = el_eq, ...} }
    }
    return current
}
```

**For `!=`:** Wrap the Eq result with `not`. In lowering, `not(x)` is `x == false`, so emit:

```odin
if e.op == .Bang_Eq {
    eq_result := /* above logic */
    not_result := new(IR_BinOp)
    not_result^ = IR_BinOp{
        op = .Eq, left = eq_result,
        right = make_ir_lit_bool(false, e.type_, e.span),
        type = e.type_, span = e.span,
    }
    return not_result
}
```

### 2.2 Stdlib Eq Impls For Opaque Types

Add to each file:

| File | Impl |
|------|------|
| `stdlib/Map.camp` | `Map is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Map_eq" } }` |
| `stdlib/Set.camp` | `Set is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Set_eq" } }` |
| `stdlib/Json.camp` | `Json is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Json_eq" } }` |
| `stdlib/Duration.camp` | `Duration is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Duration_eq" } }` |
| `stdlib/Path.camp` | `Path is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Path_eq" } }` |
| `stdlib/Uri.camp` | `Uri is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Uri_eq" } }` |
| `stdlib/Uuid.camp` | `Uuid is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Uuid_eq" } }` |
| `stdlib/Regex.camp` | `Regex is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Regex_eq" } }` |
| `stdlib/Base64.camp` | `Base64 is Eq { eq = \|a: Self, b: Self\| -> Bool { crash "intrinsic: Base64_eq" } }` |

Each intrinsic name (`Map_eq`, etc.) is recognized in lowering/codegen and emitted as a runtime function call. The actual WASM runtime functions for Map_eq, Set_eq, etc. need to be added to `Runtime_Func` enum and `src/codegen/runtime.odin`.

### 2.3 Codegen: Intrinsic Eq Recognition

**File:** `src/codegen/emit_expr.odin`

In `IR_Call` handler, recognize `*_eq` intrinsic calls for opaque types, similar to how `Str_Eq` is already handled (line 484).

Add to `Runtime_Func` enum: `Map_Eq`, `Set_Eq`, `JsonValue_Eq`, etc.

### 2.4 Eq Tests

Module-level tests + kitchen-sink:

- Record equality (including nested)
- Tag union equality (Result.Ok(1) == Result.Ok(1), cross-variant false)
- Tuple equality
- Empty record/tuple
- `!=` operator
- Opaque types: Map equality, Set equality, etc.

---

## Phase 3: Ord Trait

### 3.1 Prelude Registration

**File:** `src/semantics/prelude.odin`

Register Ord trait + primitive impls. Ord is NOT currently in prelude.

```odin
// Register Ord trait with compare: (Self, Self) -> Order
ord_name := base.intern(store.interner, "Ord")
compare_method_name := base.intern(store.interner, "compare")

if !is_trait_declared(store, ord_name) {
    ord_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)
    param_types := make([]base.Type_Var_ID, 2, store.allocator)
    param_types[0] = fresh_value_var(store, base.Source_Span_ZERO)
    param_types[1] = fresh_value_var(store, base.Source_Span_ZERO)
    return_type := prelude_resolve_type_ref(store, "Order", 0, &ord_generic_vars)
    append(&ord_methods, Trait_Method_Info{
        name = compare_method_name,
        param_types = param_types,
        return_type = return_type,
    })
    store.trait_registry[ord_name] = Trait_Info{
        name = ord_name, module = base.NO_NAME,
        parent = eq_name,  // Ord extends Eq
        methods = ord_methods[:],
    }
}

// Register Ord impls for scalar types
ord_primitive_types := []string{
    "I8","I16","I32","I64","U8","U16","U32","U64","Bool","Char","Str","Bytes","Unit",
}
for prim_name in ord_primitive_types {
    type_id := base.intern(store.interner, prim_name)
    method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
    method_map[compare_method_name] = base.Canonical_Name{
        module = base.NO_NAME,
        name = base.intern(store.interner, fmt.tprintf("{}_compare", prim_name)),
    }
    append(&store.trait_impls, Trait_Impl{
        trait_name = ord_name, type_name = type_id,
        type_module = base.NO_NAME, methods = method_map,
    })
}
// F32, F64 use total_cmp — register them separately
// Mark with a flag so lowering knows to use total_cmp semantics
```

### 3.2 Typechecker: `<`/`>`/`<=`/`>=` Check Ord

**File:** `src/semantics/check_expr.odin`

Current code (line 227) bundles `<`/`>`/`<=`/`>=` with `==`/`!=` and only checks Eq. Split them:

```odin
case .Eq_Eq, .Bang_Eq:
    // Existing Eq check (already done)
    unify(store, left_result.var_id, right_result.var_id)
    bool_var := make_primitive_type(store, base.intern(store.interner, "Bool"), e.span)
    result_var = bool_var
    check_trait_conformance(store, left_result.var_id, "Eq", e.span)
case .Lt, .Gt, .Lt_Eq, .Gt_Eq:
    // These require Ord conformance
    unify(store, left_result.var_id, right_result.var_id)
    bool_var := make_primitive_type(store, base.intern(store.interner, "Bool"), e.span)
    result_var = bool_var
    check_trait_conformance(store, left_result.var_id, "Ord", e.span)
```

Extract the existing Eq conformance check into a helper `check_trait_conformance`:

```odin
check_trait_conformance :: proc(
    store: ^Type_Store, var_id: base.Type_Var_ID,
    trait_name_str: string, span: base.Source_Span,
) {
    resolved := resolve_var(store, var_id)
    v := &store.vars[int(resolved)]
    if inf, is_inf := v.link.(Inferred_Type); is_inf {
        if prim, is_prim := inf.(Inferred_Primitive); is_prim {
            type_name := prim.primitive_name
            trait_name := base.intern(store.interner, trait_name_str)
            _, has_impl := find_trait_impl(store, trait_name, type_name)
            if !has_impl {
                type_str := base.intern_get(store.interner, type_name)
                diagnostics.collector_add_diag(store.collector,
                    diagnostics.diag_missing_trait_method(
                        type_str, trait_name_str, trait_name_str, span))
            }
        }
    }
}
```

### 3.3 Lowering: Inline Structural + Float total_cmp

**File:** `src/ir/lower.odin` — `lower_tbinop`

Same pattern as Eq but for `<`/`>`/`<=`/`>=`:

```odin
if e.op == .Lt || e.op == .Gt || e.op == .Lt_Eq || e.op == .Gt_Eq {
    operand_type := semantics.resolve_var(env.store, texpr_type_id(e.left))
    v := &env.store.vars[int(operand_type)]
    if inf, is_inf := v.link.(semantics.Inferred_Type); is_inf {
        switch concrete in inf {
        case semantics.Inferred_Record_Row:
            return lower_record_compare(e.left, e.right, concrete, e.op, e, env)
        case semantics.Inferred_Tag_Union_Row:
            return lower_tag_union_compare(...)
        case semantics.Inferred_Tuple:
            return lower_tuple_compare(...)
        case semantics.Inferred_Primitive:
            name_str := base.intern_get(env.interner, concrete.primitive_name)
            if name_str == "F32" || name_str == "F64" {
                // Emit total_cmp IR instead of raw WASM float comparison
                return lower_float_total_cmp(e.left, e.right, e.op, e, env)
            }
            // Falls through to IR_BinOp for integer comparisons
        }
    }
}
```

Structural comparison (record/tag-union/tuple) is lexicographic: compare field 1, if `Less` or `Greater` return that, otherwise compare field 2, etc.

**Float total_cmp:** In codegen, the `IR_Call` handler recognizes `F32_total_cmp`/`F64_total_cmp` intrinsic names and emits the IEEE 754 totalOrder sequence (or calls a runtime helper).

### 3.4 Stdlib Ord Impls

| Type | Mechanism |
|------|-----------|
| I8-I64, U8-U64 | Intrinsic (WASM `lt_s`/`lt_u` etc.) |
| F32, F64 | Intrinsic (total_cmp) |
| Bool | `False < True` — pure Camp or intrinsic |
| Str | Lexicographic byte comparison — intrinsic (`Str.compare`) |
| Bytes | Lexicographic — intrinsic |
| Char | Unicode codepoint — intrinsic |
| Order | Auto-derived via `derives Ord` (already in `generate_derive_stubs`) |
| List(T) | Intrinsic (lexicographic element comparison) |
| Result(T,E) | Intrinsic |
| Map(K,V) | Intrinsic (in-order key comparison) |
| Set(T) | Intrinsic (in-order element comparison) |
| Duration | Intrinsic (nanosecond count) |
| Path, Uri, Uuid, Regex | Intrinsic (string/byte representation comparison) |
| Json | Intrinsic |
| Base64 | Intrinsic |

Each gets `is Ord { compare = |a: Self, b: Self| -> Order { crash "intrinsic: Type_compare" } }`.

### 3.5 Ord Tests

- `<`/`>`/`<=`/`>=` on all primitive types
- Float total ordering (NaN handling)
- Lexicographic record comparison
- Lexicographic tuple comparison
- Tag union ordering (by discriminant)
- Sort a list using Ord (integration with List.sort)

---

## Phase 4: Hash Trait

### 4.1 Runtime: SipHash-1-3 Implementation

**File:** `src/codegen/runtime.odin`

Add SipHash-1-3 WASM implementation. This is a ~200 line function implementing the SipHash algorithm with c=1, d=3 rounds.

```odin
// SipHash-1-3 state: 4 x u64 (v0, v1, v2, v3)
// Operations: sip_round (2 rounds), compress, finalize
// 
// Hasher is opaque — represented as 32 bytes (4 x u64 state + u64 length)
// hash(val, hasher) → new hasher with val mixed in
// finalize(hasher) → u64 hash value
```

Add to `Runtime_Func` enum:
```odin
Hasher_New,      // → hasher_ptr (alloc 40 bytes zeroed)
Hasher_Write_U64, // hasher_ptr, u64 → hasher_ptr (mutated in place)
Hasher_Write_Bytes, // hasher_ptr, bytes_ptr, len → hasher_ptr
Hasher_Finish,   // hasher_ptr → u64
```

### 4.2 Prelude Registration

**File:** `src/semantics/prelude.odin`

Register Hash trait + primitive impls. The Hasher type (`@Hasher : {}`) is already defined in `stdlib/Hash.camp`. Register it as an opaque compiler type.

```odin
hash_name := base.intern(store.interner, "Hash")
hash_method_name := base.intern(store.interner, "hash")

if !is_trait_declared(store, hash_name) {
    hash_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)
    param_types := make([]base.Type_Var_ID, 2, store.allocator)
    param_types[0] = fresh_value_var(store, base.Source_Span_ZERO)  // Self
    param_types[1] = prelude_resolve_type_ref(store, "Hasher", 0, &hash_generic_vars)
    return_type := prelude_resolve_type_ref(store, "Hasher", 0, &hash_generic_vars)
    append(&hash_methods, Trait_Method_Info{
        name = hash_method_name,
        param_types = param_types,
        return_type = return_type,
    })
    store.trait_registry[hash_name] = Trait_Info{
        name = hash_name, module = base.NO_NAME,
        parent = base.NO_NAME, methods = hash_methods[:],
    }
}
// Register Hash impls for scalar types
hash_primitive_types := []string{
    "I8","I16","I32","I64","U8","U16","U32","U64",
    "Bool","Char","Str","Bytes",
}
// F32, F64: hash the in-memory bits (via reinterpret as u32/u64)
```

### 4.3 Lowering: Inline Structural Hash

Unlike Eq/Ord, Hash is NOT triggered by an operator. It's called explicitly as `x->hash(hasher)` via trait dispatch. So the lowering for structural Hash goes through the normal call path — the auto-derived function (or inline lowering for structurals) gets called.

**For nominal `derives Hash`:** Already handled by `generate_derive_stubs` (generates `x.inner.hash(y)` delegation).

**For structural types:** Since Hash is called explicitly (not via operator desugar), we need to generate Hash functions. Unlike Eq/Ord, these CAN'T be inlined — they're functions called by name. So for structural types, we need lazy named function generation (Option A from Q2).

Wait — per Q2/D decision, structural Eq/Ord are inlined at the operator site. But Hash has no operator. It's called as `my_record->hash(h)`. This goes through UFCS → resolves to a function call. The function must exist.

**Decision:** For Hash on structural types, generate named functions lazily (when first referenced). Register in `trait_impls`. This is Option A from Q2, but ONLY for Hash (not Eq/Ord).

Actually, structural types can't have `is Hash` blocks (no name). And `derives` only works on nominal types. So structural Hash requires auto-generation.

**Approach:** In `check_expr.odin`, when `obj->hash(args)` is called on a structural type, canonicalize generates a named function for that shape. But this mixes phases. Better: pre-generate during canonicalization (like Option B).

Actually the cleanest: at the end of module canonicalization (in `canonicalize_file`), walk all type expressions. For each unique structural type, generate Hash function. Register in `scope.generated_decl`.

**File:** `src/semantics/canonicalize.odin` — in `canonicalize_file`, after the loop that processes decls:

```odin
// Generate Hash functions for structural types found in this module
for shape in scope.structural_types_seen {
    hash_decl := generate_struct_hash(shape, &scope, interner, collector)
    append(&scope.generated_decl, hash_decl)
}
```

### 4.4 Stdlib Hash Impls

Each type gets `is Hash` with intrinsic body:

```camp
I64 is Hash { hash = |a: Self, h: Hasher| -> Hasher { crash "intrinsic: I64_hash" } }
```

### 4.5 Codegen: Intrinsic Hash Recognition

**File:** `src/codegen/emit_expr.odin`

In `IR_Call` handler, recognize `*_hash` intrinsic calls. Emit calls to `Hasher_Write_U64`/`Hasher_Write_Bytes` runtime functions.

### 4.6 Hash Tests

- Hash consistency: `a == b` implies `hash(a) == hash(b)`
- Hash different values produce different hashes (with high probability)
- Cross-type: hashing List, Map keys
- Hash + Eq invariant tests

---

## Complete File Change Index

### Compiler (Odin)

| File | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|------|---------|---------|---------|---------|
| `src/semantics/prelude.odin` | Register Debug trait + impls | — | Register Ord trait + impls | Register Hash trait + impls |
| `src/semantics/check_expr.odin` | — | (already done) | Split Ord check from Eq check | — |
| `src/semantics/canonicalize.odin` | Add Debug to `derive_stubs` | — | — | Generate Hash for structurals |
| `src/ir/lower.odin` | — | Inline structural Eq | Inline structural Ord + float total_cmp | — |
| `src/codegen/emit_expr.odin` | Recognize `*_debug` intrinsics | Recognize `*_eq` intrinsics | Recognize `*_compare` + total_cmp | Recognize `*_hash` intrinsics |
| `src/codegen/runtime.odin` | — | Map/Set/Json eq functions | — | SipHash-1-3 implementation |
| `src/codegen/codegen.odin` | Wire runtime funcs | Wire runtime funcs | Wire runtime funcs | Wire runtime funcs |
### Stdlib (Camp)
| File | Trait Impls |
|------|-------------|
| `stdlib/Num/I8.camp` | Debug |
| `stdlib/Num/I16.camp` | Debug |
| `stdlib/Num/I32.camp` | Debug |
| `stdlib/Num/I64.camp` | Debug |
| `stdlib/Num/U8.camp` | Debug |
| `stdlib/Num/U16.camp` | Debug |
| `stdlib/Num/U32.camp` | Debug |
| `stdlib/Num/U64.camp` | Debug |
| `stdlib/Num/F32.camp` | Debug |
| `stdlib/Num/F64.camp` | Debug |
| `stdlib/Bool.camp` | Debug |
| `stdlib/Str.camp` | Debug |
| `stdlib/Bytes.camp` | Debug |
| `stdlib/Char.camp` | Debug |
| `stdlib/List.camp` | Debug, Ord, Hash |
| `stdlib/Result.camp` | Debug, Ord, Hash |
| `stdlib/Map.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Set.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Json.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Duration.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Path.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Uri.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Uuid.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Regex.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Base64.camp` | Debug, Eq, Ord, Hash |
| `stdlib/Ord.camp` | Debug, Eq (Order type) |
### Tests
| File | Content |
|------|---------|
| Each `stdlib/*.camp` | Module-level tests for each trait impl |
| `tests/e2e/language/kitchen-sink/Main.camp` | Integration tests: Debug, Eq, Ord, Hash sections |
---

## Runtime Functions Needed
| Function | Purpose | Phase |
|----------|---------|-------|
| `Map_Eq` | Structural equality for Map | 2 |
| `Set_Eq` | Structural equality for Set | 2 |
| `JsonValue_Eq` | Structural equality for Json | 2 |
| `Duration_Eq` | Component-wise equality | 2 |
| `F64_Total_Cmp` | IEEE 754 totalOrder comparison | 3 |
| `F32_Total_Cmp` | IEEE 754 totalOrder comparison | 3 |
| `Hasher_New` | Allocate SipHash state | 4 |
| `Hasher_Write_U64` | Mix u64 into SipHash | 4 |
| `Hasher_Write_Bytes` | Mix byte sequence into SipHash | 4 |
| `Hasher_Finish` | Finalize and return u64 | 4 |
---

## Risk Areas
1. **Tag union Eq lowering**: The IR_Match construct may need extending to handle two-scrutinee matching (comparing two tag values simultaneously). Fallback: compare tag indices first (`IR_Tag_Index`), then if same, compare payloads.

2. **Float total_cmp**: WASM has no direct total_cmp instruction. Need a ~30-instruction sequence handling NaN, -0 vs +0, infinities. Acceptable to implement as a runtime helper function.

3. **Hash for F32/F64**: Must hash the raw bits, not the numeric value. -0.0 and +0.0 have different bit patterns but compare equal under total_cmp. The Hash contract says `a == b → hash(a) == hash(b)`. Since Camp uses total_cmp for floats (where -0.0 and +0.0 are NOT equal), hashing raw bits is correct.

4. **`derives` for List/Result**: These are compiler-declared nominal types. They can't have `derives` in source code. The compiler must auto-generate trait impls for them, or they need explicit `is` blocks in stdlib. Current plan: explicit `is` blocks with intrinsic markers.

5. **SipHash in WASM**: The algorithm uses 64-bit rotates and XORs. WASM has full i64 support (including `rotl` via `i64.rotl`), so no issues.