# Eq Trait Implementation Plan

> Authoritative execution plan. Every file, every function, every line.
> No room for interpretation. Follow exactly.

## Overview

Implement Eq trait for all Camp types. Changes span 7 subsystems:

1. **Prelude** — register Eq trait + primitive impls
2. **Typechecker** — enforce Eq requirement on `==`/`!=`
3. **Canonicalizer** — auto-derive Eq for structural types
4. **IR Lowering** — dispatch `==` to intrinsic or eq call
5. **IR Codegen** — minimal (already handles Eq/Ne for scalars)
6. **Stdlib types** — add `is Eq` blocks or intrinsic declarations
7. **Existing derive** — fix nominal `derives Eq` to propagate where clauses

---

## Phase 1: Register Eq trait + primitive impls in prelude

### File: `src/semantics/prelude.odin`

#### Step 1.1: Add Eq trait registration in `inject_prelude_effects_typecheck`

After the Display registration block (around line 405, before closing `}`).

```odin
// Register Eq trait with eq: (Self, Self) -> Bool
eq_name := base.intern(store.interner, "Eq")
eq_method_name := base.intern(store.interner, "eq")

if !is_trait_declared(store, eq_name) {
    eq_generic_vars: map[int]base.Type_Var_ID
    eq_generic_vars = make(map[int]base.Type_Var_ID, 4, store.allocator)

    eq_methods := make([dynamic]Trait_Method_Info, 0, 4, store.allocator)

    // eq: (Self, Self) -> Bool
    param_types := make([]base.Type_Var_ID, 2, store.allocator)
    param_types[0] = fresh_value_var(store, base.Source_Span_ZERO)  // Self — first param
    param_types[1] = fresh_value_var(store, base.Source_Span_ZERO)  // Self — second param
    return_type := prelude_resolve_type_ref(store, "Bool", 0, &eq_generic_vars)

    append(
        &eq_methods,
        Trait_Method_Info{
            name = eq_method_name,
            param_types = param_types,
            return_type = return_type,
        },
    )

    store.trait_registry[eq_name] = Trait_Info{
        name    = eq_name,
        module  = base.NO_NAME,
        parent  = base.NO_NAME,
        methods = eq_methods[:],
    }

    delete(eq_generic_vars)
}
```

#### Step 1.2: Register Eq impls for primitive types

After the Eq trait registration block. Register for: I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Bool, Char, Str, Bytes, Unit.

```odin
primitive_eq_types := []string{
    "I8", "I16", "I32", "I64",
    "U8", "U16", "U32", "U64",
    "F32", "F64",
    "Bool", "Char", "Str", "Bytes", "Unit",
}

for prim_name in primitive_eq_types {
    type_id := base.intern(store.interner, prim_name)
    method_map := make(map[base.Intern_ID]base.Canonical_Name, 1, store.allocator)
    method_map[eq_method_name] = base.Canonical_Name{
        module = base.NO_NAME,
        name   = base.intern(store.interner, fmt.tprintf("{}_eq", prim_name)),
    }
    append(
        &store.trait_impls,
        Trait_Impl{
            trait_name  = eq_name,
            type_name   = type_id,
            type_module = base.NO_NAME,
            methods     = method_map,
        },
    )
}
```

**NOTE:** The canonical names `I64_eq`, `Bool_eq`, etc. are placeholders. These functions do NOT exist as source code — they are compiler-recognized intrinsics. The lowering pass specifically checks for these names and emits WASM instructions instead of function calls.

---

## Phase 2: Typechecker — enforce Eq on `==`/`!=`

### File: `src/semantics/check_expr.odin`

#### Step 2.1: Modify `typecheck_binop`

Find the `case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:` block (line ~220).

Current code unifies operands and produces Bool. After unification, add an Eq conformance check for `.Eq_Eq` and `.Bang_Eq`.

**Only check Eq_Eq and Bang_Eq** — Lt/Gt/Lt_Eq/Gt_Eq should NOT require Eq (they need Ord).

```odin
case .Eq_Eq, .Bang_Eq:
    unify(store, left_result.var_id, right_result.var_id)
    
    // Check that the unified type implements Eq trait
    resolved_left := resolve_var(store, left_result.var_id)
    resolved_right := resolve_var(store, right_result.var_id)
    // Use the resolved id (they unified, so same)
    resolved := resolve_var(store, left_result.var_id)
    
    // Find the concrete type name to check Eq conformance
    type_name := resolve_type_name_for_eq_check(store, resolved)
    if type_name != base.NO_NAME {
        eq_name := base.intern(store.interner, "Eq")
        found_impl := false
        for impl in store.trait_impls {
            if impl.trait_name == eq_name && impl.type_name == type_name {
                found_impl = true
                break
            }
        }
        if !found_impl {
            type_str := base.intern_get(store.interner, type_name)
            diagnostics.collector_add_diag(
                store.collector,
                diagnostics.diag_type_does_not_implement_trait(
                    type_str, "Eq", e.span,
                ),
            )
        }
    }
    // For unresolved type variables (generics), constraint propagation handles it
    
    bool_name := base.intern(store.interner, "Bool")
    bool_var := make_primitive_type(store, bool_name, e.span)
    result_var = bool_var
```

#### Step 2.2: Add helper function `resolve_type_name_for_eq_check`

Add to `check_expr.odin` (or `types.odin` — pick `types.odin` since it has similar helpers).

```odin
// resolve_type_name_for_eq_check resolves a Type_Var_ID to its concrete
// type name for the purpose of checking Eq conformance.
// Returns NO_NAME if the type is still a variable (generic), in which
// case constraint checking at monomorphization handles it.
resolve_type_name_for_eq_check :: proc(
    store: ^Type_Store,
    var_id: base.Type_Var_ID,
) -> base.Intern_ID {
    resolved := resolve_var(store, var_id)
    v := store.vars[int(resolved)]
    
    if inf, is_inf := v.link.(Inferred_Type); is_inf {
        switch concrete in inf {
        case Inferred_Primitive:
            return concrete.primitive_name
        case Inferred_Newtype:
            return concrete.primitive_name
        case Inferred_Constructor:
            return concrete.primitive_name
        case Inferred_Record_Row:
            // Record types don't have a single name for trait lookup.
            // Eq conformance for records is checked structurally during
            // auto-derive in canonicalization. Return NO_NAME — the
            // auto-derive handles it.
            return base.NO_NAME
        case Inferred_Tag_Union_Row:
            // Same as records — structural auto-derive handles.
            return base.NO_NAME
        case Inferred_Tuple:
            // Same as records — structural auto-derive handles.
            return base.NO_NAME
        case Inferred_Function:
            // Functions never have Eq. The type string for error msg.
            // Return NO_NAME for now; the constraint violation system
            // will catch it if a where clause demands it.
            return base.NO_NAME
        case Inferred_Handle:
            return base.NO_NAME
        }
    }
    
    return base.NO_NAME
}
```

#### Step 2.3: Add diagnostic function

### File: `src/diagnostics/constructors.odin`

Add new diagnostic constructor:

```odin
diag_type_does_not_implement_trait :: proc(
    type_name: string,
    trait_name: string,
    span: base.Source_Span,
) -> Diagnostic {
    return Diagnostic {
        category = .Error,
        code     = "E0401",
        message  = fmt.tprintf(
            "type `{}` does not implement trait `{}`",
            type_name, trait_name,
        ),
        span     = span,
    }
}
```

### File: `src/diagnostics/diagnostic.odin`

Add the function declaration to the appropriate section.

---

## Phase 3: Auto-derive Eq for structural types

### File: `src/semantics/canonicalize.odin`

#### Step 3.1: Add function `generate_struct_eq`

This function generates a `CDecl_Const` for an `eq` function given field/tag types.

```odin
// generate_struct_eq generates an Eq implementation for a structural type.
// For record types: compares each field with ==, chained with "and".
// For tag union types: match on [a, b], compare same-tag payloads.
// For tuple types: compares each element with ==, chained with "and".
// Returns nil if any element type doesn't implement Eq (error already emitted).
generate_struct_eq :: proc(
    type_name_hint: string,  // For naming the generated function
    element_types: []struct{name: base.Intern_ID, type_ref: ^CType},  // field or tag payload names+types
    is_tag_union: bool,  // true = generate tag-match, false = field-by-field
    scope: ^Canonicalize_Scope,
    interner: ^base.Intern_Table,
    collector: ^diagnostics.Diagnostic_Collector,
    span: base.Source_Span,
) -> CDecl {
    // Parameters x, y of Self type
    x_id := base.intern(interner, "x")
    y_id := base.intern(interner, "y")
    
    params := make([dynamic]CFunc_Param, 0, 2)
    append(&params, CFunc_Param{name = x_id, span = span})
    append(&params, CFunc_Param{name = y_id, span = span})
    
    // Infer type params from element_types
    // Collect type variable names from element type refs
    seen := make(map[base.Intern_ID]bool)
    type_param_names := make([dynamic]base.Intern_ID, 0, 4)
    defer delete(seen)
    defer delete(type_param_names)
    
    for el in element_types {
        collect_type_variable_names(el.type_ref^, &seen, &type_param_names)
    }
    
    type_params := make([dynamic]frontend.Type_Param, 0, len(type_param_names))
    for name in type_param_names {
        // Each type param gets an Eq constraint
        constraints := make([dynamic]base.Intern_ID, 0, 1)
        append(&constraints, base.intern(interner, "Eq"))
        append(&type_params, frontend.Type_Param{
            name = name,
            constraints = constraints[:],
        })
    }
    
    // Build body expression
    body: CExpr
    
    if is_tag_union {
        body = generate_tag_union_eq_body(element_types, x_id, y_id, interner, span)
    } else {
        body = generate_record_eq_body(element_types, x_id, y_id, interner, span)
    }
    
    lambda := new(CExpr_Lambda)
    lambda^ = CExpr_Lambda{
        type_params   = type_params,
        params        = params,
        return_type   = nil,
        effects       = nil,
        where_clauses = make([dynamic]frontend.Where_Clause, 0),
        body          = body,
        span          = span,
    }
    
    cdecl := new(CDecl_Const)
    cdecl^ = CDecl_Const{
        name = base.Canonical_Name{
            module   = base.NO_NAME,
            name     = base.intern(interner, fmt.tprintf("{}_eq", type_name_hint)),
            is_local = true,
        },
        is_pub         = true,
        is_effectful   = false,
        type_ann       = nil,
        body           = CExpr(lambda),
        derive_targets = make([dynamic]base.Intern_ID, 0),
        where_clauses  = make([dynamic]frontend.Where_Clause, 0),
        doc_comment    = "",
        span           = span,
    }
    
    return CDecl(cdecl)
}

// generate_record_eq_body builds `x.field1 == y.field1 and x.field2 == y.field2 and ...`
generate_record_eq_body :: proc(
    elements: []struct{name: base.Intern_ID, type_ref: ^CType},
    x_id, y_id: base.Intern_ID,
    interner: ^base.Intern_Table,
    span: base.Source_Span,
) -> CExpr {
    if len(elements) == 0 {
        // Empty record: always equal
        cexpr := new(CExpr_Bool)
        cexpr^ = CExpr_Bool{value = true, span = span}
        return CExpr(cexpr)
    }
    
    // Build chain: a.field1 == b.field1 and a.field2 == b.field2
    // Accumulator starts as first comparison
    eq_name := base.intern(interner, "eq")
    and_name := base.intern(interner, "and")
    
    // For each element: (x.field == y.field)
    // We generate the expression as a left-fold of "and"
    current: CExpr
    
    for i, el in elements {
        // Build x.field access
        x_name := base.Canonical_Name{
            module   = base.NO_NAME,
            name     = x_id,
            is_local = true,
        }
        x_expr := new(CExpr_Name)
        x_expr^ = CExpr_Name{name = x_name, span = span}
        
        x_field := new(CExpr_Field_Access)
        x_field^ = CExpr_Field_Access{
            record = x_expr,
            field  = el.name,
            span   = span,
        }
        
        // Build y.field access
        y_name := base.Canonical_Name{
            module   = base.NO_NAME,
            name     = y_id,
            is_local = true,
        }
        y_expr := new(CExpr_Name)
        y_expr^ = CExpr_Name{name = y_name, span = span}
        
        y_field := new(CExpr_Field_Access)
        y_field^ = CExpr_Field_Access{
            record = y_expr,
            field  = el.name,
            span   = span,
        }
        
        // Build x.field == y.field
        eq_binop := new(CExpr_BinOp)
        eq_binop^ = CExpr_BinOp{
            op    = .Eq_Eq,
            left  = CExpr(x_field),
            right = CExpr(y_field),
            span  = span,
        }
        
        if i == 0 {
            current = CExpr(eq_binop)
        } else {
            // chain with "and"
            and_binop := new(CExpr_BinOp)
            and_binop^ = CExpr_BinOp{
                op    = .Kw_And,
                left  = current,
                right = CExpr(eq_binop),
                span  = span,
            }
            current = CExpr(and_binop)
        }
    }
    
    return current
}

// generate_tag_union_eq_body builds
// match [x, y] {
//   [Tag1(xp), Tag1(yp)] => xp == yp
//   [Tag2, Tag2] => True
//   [_, _] => False
// }
generate_tag_union_eq_body :: proc(
    tags: []struct{name: base.Intern_ID, type_ref: ^CType},
    x_id, y_id: base.Intern_ID,
    interner: ^base.Intern_Table,
    span: base.Source_Span,
) -> CExpr {
    // Build scrutinee: tuple [x, y]
    x_name := base.Canonical_Name{
        module   = base.NO_NAME,
        name     = x_id,
        is_local = true,
    }
    x_expr := new(CExpr_Name)
    x_expr^ = CExpr_Name{name = x_name, span = span}
    
    y_name := base.Canonical_Name{
        module   = base.NO_NAME,
        name     = y_id,
        is_local = true,
    }
    y_expr := new(CExpr_Name)
    y_expr^ = CExpr_Name{name = y_name, span = span}
    
    scrutinee_elements := make([dynamic]CExpr, 0, 2)
    append(&scrutinee_elements, CExpr(x_expr))
    append(&scrutinee_elements, CExpr(y_expr))
    
    scrutinee := new(CExpr_List)
    scrutinee^ = CExpr_List{
        elements = scrutinee_elements,
        span     = span,
    }
    
    // Build arms
    arms := make([dynamic]CMatch_Arm, 0, len(tags) + 2)
    
    for tag in tags {
        // Pattern: [Tag(x_payload), Tag(y_payload)]
        x_pat_name := base.intern(interner, "xp")
        y_pat_name := base.intern(interner, "yp")
        
        x_tag_payload := make([dynamic]CPattern, 0, 1)
        x_payload_pat := new(CPattern_Name)
        x_payload_pat^ = CPattern_Name{
            name = x_pat_name,
            span = span,
        }
        append(&x_tag_payload, CPattern(x_payload_pat))
        
        x_tag := new(CPattern_Tag)
        x_tag^ = CPattern_Tag{
            name    = tag.name,
            payload = x_tag_payload,
            span    = span,
        }
        
        y_tag_payload := make([dynamic]CPattern, 0, 1)
        y_payload_pat := new(CPattern_Name)
        y_payload_pat^ = CPattern_Name{
            name = y_pat_name,
            span = span,
        }
        append(&y_tag_payload, CPattern(y_payload_pat))
        
        y_tag := new(CPattern_Tag)
        y_tag^ = CPattern_Tag{
            name    = tag.name,
            payload = y_tag_payload,
            span    = span,
        }
        
        list_payload := make([dynamic]CPattern, 0, 2)
        append(&list_payload, CPattern(x_tag))
        append(&list_payload, CPattern(y_tag))
        
        list_pat := new(CPattern_List)
        list_pat^ = CPattern_List{
            elements = list_payload,
            span     = span,
        }
        
        // Body: xp == yp
        xp_name := base.Canonical_Name{
            module   = base.NO_NAME,
            name     = x_pat_name,
            is_local = true,
        }
        xp_expr := new(CExpr_Name)
        xp_expr^ = CExpr_Name{name = xp_name, span = span}
        
        yp_name := base.Canonical_Name{
            module   = base.NO_NAME,
            name     = y_pat_name,
            is_local = true,
        }
        yp_expr := new(CExpr_Name)
        yp_expr^ = CExpr_Name{name = yp_name, span = span}
        
        eq_binop := new(CExpr_BinOp)
        eq_binop^ = CExpr_BinOp{
            op    = .Eq_Eq,
            left  = CExpr(xp_expr),
            right = CExpr(yp_expr),
            span  = span,
        }
        
        arm := CMatch_Arm{
            pattern = CPattern(list_pat),
            guard   = nil,
            body    = CExpr(eq_binop),
            span    = span,
        }
        append(&arms, arm)
    }
    
    // Wildcard arm: [_, _] => False
    wildcard := new(CPattern_Wildcard)
    wildcard^ = CPattern_Wildcard{span = span}
    
    wildcard2 := new(CPattern_Wildcard)
    wildcard2^ = CPattern_Wildcard{span = span}
    
    wc_list_payload := make([dynamic]CPattern, 0, 2)
    append(&wc_list_payload, CPattern(wildcard))
    append(&wc_list_payload, CPattern(wildcard2))
    
    wc_list_pat := new(CPattern_List)
    wc_list_pat^ = CPattern_List{
        elements = wc_list_payload,
        span     = span,
    }
    
    false_expr := new(CExpr_Bool)
    false_expr^ = CExpr_Bool{value = false, span = span}
    
    append(&arms, CMatch_Arm{
        pattern = CPattern(wc_list_pat),
        guard   = nil,
        body    = CExpr(false_expr),
        span    = span,
    })
    
    match_expr := new(CExpr_Match)
    match_expr^ = CExpr_Match{
        scrutinee = CExpr(scrutinee),
        arms      = arms,
        span      = span,
    }
    
    return CExpr(match_expr)
}
```

NOTE: The `collect_type_variable_names` function already exists at line ~1865 of `canonicalize.odin`. Use it directly.

#### Step 3.2: Hook into canonicalization of structural types

Find where records, tag unions, and tuples are canonicalized. Insert calls to `generate_struct_eq` after the type is processed.

**For record types:** In the function that canonicalizes `CType_Record` (around `canon_type` or similar), after building the record type, iterate fields and call `generate_struct_eq` with field names and types.

**For tag union types:** After processing `CType_Tag_Union`, invoke `generate_struct_eq` with tag names and payload types.

**For tuple types:** After processing `CType_Tuple`, invoke `generate_struct_eq` with element names `_1`, `_2`, `_3`.

The generated `CDecl` must be appended to the module's declaration list.

**Key insertion point:** In `src/semantics/canonicalize.odin`, find the function that processes type annotations
(around `canon_type` or `canon_type_ref`). After each call that produces a `CType_Record`, `CType_Tag_Union`, or tuple-related type, check if we should auto-derive.

Actually a cleaner approach: after ALL declarations are canonicalized (end of the main canonicalize pass), scan all type expressions in the module for structural types and generate eq functions. This avoids ordering issues.

**Simpler approach:** In `canonicalize_module` or equivalent top-level function, after processing all declarations, iterate through all types that appear in binding type annotations, function signatures, and type aliases. For each record/tag-union/tuple type found, generate eq.

**Even simpler:** Generate eq lazily. When `==` is used on a structural type in `typecheck_binop`, the Eq check triggers. At that point we can auto-derive. But this mixes phases.

**Pragmatic choice:** Add to `canon_type_ref` handler: when canon returns a `^CType_Record`, `^CType_Tag_Union`, or `^CType_Tuple`, generate and register the eq function. Store generated eq functions in a set to avoid duplicates (keyed by fingerprint of field names + types).

Exact location: In `canon_type_ref` (or a wrapper), after computing the result `CType`, check if it's a structural type. If yes, generate struct eq using field/tag information.

Wait — `canon_type_ref` is called for every type expression, including nested ones. We only want to generate eq for standalone structural types that appear as value types, not for function parameter types or return types.

Simplest correct approach:

```odin
// At the end of the module-level canonicalization function:
// Scan all top-level declarations for structural types used as value types.
// For each unique structural type, generate eq function.
```

Actually, the cleanest approach: look at how the module processes declarations. Each `CDecl_Const` has a `body` (usually a `CExpr_Lambda`). The body's parameter types and return type may reference structural types. We need to walk type expressions and collect structural types.

Let me reconsider. The REAL approach used by real compilers:

1. Walk all type expressions in the module
2. Collect all structural type shapes (records, tag unions, tuples)
3. Deduplicate
4. Generate eq functions for each
5. Register as trait implementations

But this means structural types defined in OTHER modules (e.g., `stdlib/List.camp`'s `[Cons(T, List(T)) | Nil]`) must generate eq when the List module is compiled, not at each use site.

**Final approach: Generate eq during canonicalization of the declaration that introduces the structural type.**

For records and tag unions: the structural type is defined inline in a type alias, function signature, or `is` block. We walk the CType tree during canonicalization. When we encounter a `^CType_Record`, `^CType_Tag_Union`, or `^CType_Tuple`, we add it to a "pending_eq" list. At the end of module canonicalization, we deduplicate and generate.

For type aliases like `List(a) : [Cons(T, List(T)) | Nil]`: the canonicalizer processes the `CDecl_Alias` and its `target` CType. When the target is a tag union, we generate eq for it.

For function parameter types like `f = |x: { a: I64, b: Str }|`: the inline record type gets eq generated.

---

**In practice, the simplest implementation that works:**

Modify `canon_type` (the main type canonicalization function) to maintain a global set of "seen structural type fingerprints". When canon produces a structural type, compute a fingerprint and check if already generated. If not, generate the eq function and add to a results list.

The fingerprint is computed from: the shape (record/tag-union/tuple), field/tag names and their type variable names (not resolved types).

---

#### Step 3.3: Register auto-derived Eq in trait registry

After generating the eq function `CDecl`, also register it in the module's type environment so other decls in the same module can find it.

Add to the `scope` or return from canonicalize_module as extra generated decls.

---

## Phase 4: IR Lowering — dispatch `==` to Eq

### File: `src/ir/lower.odin`

#### Step 4.1: Modify `lower_tbinop`

Find the `lower_tbinop` function (line ~1370). After the Str concat special case and before `IR_BinOp` construction, add an Eq dispatch check.

```odin
lower_tbinop :: proc(e: ^semantics.TExpr_BinOp, env: ^Lower_Env) -> IR_Expr {
    // String concat special case (unchanged)
    if e.op == .Plus { ... existing Str check ... }
    
    // Handle == and != for structural types
    if e.op == .Eq_Eq || e.op == .Bang_Eq {
        // Check if the operand type is a WASM scalar (primitive)
        operand_type_var := semantics.resolve_var(env.store, texpr_type_id(e.left))
        v := &env.store.vars[int(operand_type_var)]
        
        is_wasm_scalar := false
        type_name: base.Intern_ID = base.NO_NAME
        
        if inf, is_inf := v.link.(semantics.Inferred_Type); is_inf {
            if prim, prim_ok := inf.(semantics.Inferred_Primitive); prim_ok {
                type_name = prim.primitive_name
                name_str := base.intern_get(env.interner, type_name)
                // All integer types, float types, Bool, Char, Unit are WASM scalars
                is_wasm_scalar = is_int_primitive_name(env.store, type_name) ||
                    is_float_primitive_name(env.store, type_name) ||
                    name_str == "Bool" || name_str == "Char" || name_str == "Unit"
            }
        }
        
        if is_wasm_scalar {
            // Keep as IR_BinOp(Eq) — emits fast WASM instruction
            left_ir := lower_texpr(e.left, env)
            right_ir := lower_texpr(e.right, env)
            result := new(IR_BinOp)
            result^ = IR_BinOp{
                op    = lower_binop_kind(e.op),
                left  = left_ir,
                right = right_ir,
                type  = e.type_,
                span  = e.span,
            }
            return IR_Expr(result)
        } else {
            // Route through Eq trait: desugar to eq(left, right)
            // Find the eq trait method and emit a call
            eq_result := lower_eq_via_trait(e.left, e.right, e.type_, e.span, env)
            if e.op == .Bang_Eq {
                // Wrap in not(...)
                not_result := new(IR_PrefixOp)
                not_result^ = IR_PrefixOp{
                    op      = .Kw_Not,
                    operand = eq_result,
                    type    = e.type_,
                    span    = e.span,
                }
                return IR_Expr(not_result)
            }
            return eq_result
        }
    }
    
    // ... rest of existing lower_tbinop for arithmetic/comparison ops ...
}
```

#### Step 4.2: Add `lower_eq_via_trait` function

```odin
// lower_eq_via_trait emits a call to the eq method via trait dispatch.
// It looks up the trait_impls for the operand type's eq method.
lower_eq_via_trait :: proc(
    left, right: ^semantics.TExpr,
    result_type: base.IR_Type,
    span: base.Source_Span,
    env: ^Lower_Env,
) -> IR_Expr {
    left_ir := lower_texpr(left, env)
    right_ir := lower_texpr(right, env)
    
    // Determine the concrete type name
    type_var := semantics.resolve_var(env.store, texpr_type_id(left))
    v := &env.store.vars[int(type_var)]
    
    type_name: base.Intern_ID = base.NO_NAME
    if inf, is_inf := v.link.(semantics.Inferred_Type); is_inf {
        switch concrete in inf {
        case semantics.Inferred_Primitive:
            type_name = concrete.primitive_name
        case semantics.Inferred_Newtype:
            type_name = concrete.primitive_name
        case semantics.Inferred_Constructor:
            type_name = concrete.primitive_name
        case semantics.Inferred_Record_Row,
             semantics.Inferred_Tag_Union_Row,
             semantics.Inferred_Tuple,
             semantics.Inferred_Function,
             semantics.Inferred_Handle:
            // These types get eq via auto-derive. The eq function name
            // follows the pattern: struct_{fingerprint}_eq
            type_name = compute_struct_eq_name(env.store, type_var)
        }
    }
    
    // Look up eq method in trait_impls
    eq_name := base.intern(env.interner, "eq")
    
    for impl in env.store.trait_impls {
        if impl.type_name == type_name {
            if fn_name, has := impl.methods[eq_name]; has {
                args := make([dynamic]IR_Expr, 0, 2)
                append(&args, left_ir)
                append(&args, right_ir)
                
                call := new(IR_Call)
                call^ = IR_Call{
                    callee           = fn_name,
                    args             = args,
                    type             = result_type,
                    span             = span,
                    ord_compare_func = base.Canonical_Name{},
                }
                return IR_Expr(call)
            }
        }
    }
    
    // Fallback: emit unreachable (should not happen if typechecker verified Eq conformance)
    unreachable := new(IR_Crash)
    unreachable^ = IR_Crash{
        message = IR_Expr(new(IR_Literal_String)),
        type    = result_type,
        span    = span,
    }
    return IR_Expr(unreachable)
}

// compute_struct_eq_name generates a deterministic name for a structural type's eq function.
// For records: record_{field1}_{field2}_eq
// For tag unions: tagunion_{tag1}_{tag2}_eq
// For tuples: tuple_{count}_eq
compute_struct_eq_name :: proc(
    store: ^semantics.Type_Store,
    type_var: base.Type_Var_ID,
) -> base.Intern_ID {
    resolved := semantics.resolve_var(store, type_var)
    v := &store.vars[int(resolved)]
    
    if inf, is_inf := v.link.(semantics.Inferred_Type); is_inf {
        switch concrete in inf {
        case semantics.Inferred_Record_Row:
            parts := make([dynamic]string, 0, len(concrete.record_fields) + 2)
            append(&parts, "struct_eq_record")
            for f in concrete.record_fields {
                name_str := base.intern_get(store.interner, f.name)
                append(&parts, name_str)
            }
            str := strings.join(parts[:], "_")
            defer delete(str)
            return base.intern(store.interner, str)
            
        case semantics.Inferred_Tag_Union_Row:
            parts := make([dynamic]string, 0, len(concrete.tag_entries) + 2)
            append(&parts, "struct_eq_tagunion")
            for t in concrete.tag_entries {
                name_str := base.intern_get(store.interner, t.name)
                append(&parts, name_str)
            }
            str := strings.join(parts[:], "_")
            defer delete(str)
            return base.intern(store.interner, str)
            
        case semantics.Inferred_Tuple:
            name_str := fmt.tprintf("struct_eq_tuple_{}", concrete.element_count)
            return base.intern(store.interner, name_str)
        }
    }
    
    return base.NO_NAME
}
```

---

## Phase 5: Stdlib type implementations

### 5.1: Primitive Eq declarations

Each primitive stdlib module needs an `is Eq` block. The body uses `crash "intrinsic"`.

#### File: `stdlib/Num/I64.camp`

```camp
I64 is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: I64_eq" }
}
```

#### File: `stdlib/Num/U64.camp`

```camp
U64 is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: U64_eq" }
}
```

Same pattern for I8, I16, I32, U8, U16, U32, F32, F64.

#### File: `stdlib/Bool.camp`

```camp
Bool is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: Bool_eq" }
}
```

#### File: `stdlib/Str.camp`

```camp
Str is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: Str_eq" }
}
```

#### File: `stdlib/Bytes.camp`

| Name | Definition |
|------|-----------|
| Char | `crash "intrinsic: Char_eq"` |
| Unit | `crash "intrinsic: Unit_eq"` |

NOTE: the compiler MUST recognize the pattern `crash "intrinsic: {Type}_eq"` in lowering and emit WASM comparison instead of a function call.

### 5.2: Structural type auto-derive

For stdlib types that are type aliases around structural types (List, Result, Order, Option):

- `List(T)` is `[Cons(T, List(T)) | Nil]` → tag union → auto-derive Eq
- `Result(T, E)` is `[Ok(T) | Err(E)]` → tag union → auto-derive Eq
- `Order` is `[Less | Equal | Greater]` → tag union → auto-derive Eq
- `Option(T)` would be `[Some(T) | None]` → tag union → auto-derive Eq

These should just work once Phase 3 is complete. No manual source changes needed for these.

### 5.3: Manual `is Eq` for opaque types

Types whose internals are compiler-managed (Map, Set, Json) need manual `is Eq` blocks with intrinsic function calls.

#### File: `stdlib/Map.camp`

```camp
Map is Eq {
    eq = |a: Self, b: Self| -> Bool {
        crash "intrinsic: Map_eq"
    }
}
```

#### File: `stdlib/Set.camp`

Same pattern: `crash "intrinsic: Set_eq"`

#### File: `stdlib/Json.camp`

```camp
Json is Eq {
    eq = |a: Self, b: Self| -> Bool {
        crash "intrinsic: Json_eq"
    }
}
```

### 5.4: Delegating types

Types that are newtypes or wrappers delegating to other types:

#### File: `stdlib/Path.camp`

```camp
Path is Eq {
    eq = |a: Self, b: Self| -> Bool { a.inner == b.inner }
}
```

#### File: `stdlib/Duration.camp`

Duration is component-wise numeric comparison (likely intrinsic).

```camp
Duration is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: Duration_eq" }
}
```

#### File: `stdlib/Uri.camp`, `stdlib/Uuid.camp`, `stdlib/Regex.camp`, `stdlib/Base64.camp`

All use intrinsic comparison:

```camp
Uri is Eq {
    eq = |a: Self, b: Self| -> Bool { crash "intrinsic: Uri_eq" }
}
```

---

## Phase 6: Fix nominal `derives Eq`

### File: `src/semantics/canonicalize.odin`

#### Step 6.1: Fix `generate_derive_stubs` for Eq

Current code generates `x.inner.eq(y.inner)` which works for newtypes wrapping primitives. This is already correct — no change needed for the body expression.

**But:** The generated lambda has empty `where_clauses` and empty `type_params`. For generic nominal types like `@Result(a, e) : [Ok(a) | Err(e)] derives Eq`, the generated eq function needs:

1. Type params `a`, `e` propagated from the nominal type's `type_params`
2. `where a: Eq, e: Eq` constraints on those type params

**Change:** In `generate_derive_stubs`, case `"Eq"`:

At line ~1542-1549, after calling `make_derive_method_decl`, add:

```odin
case "Eq":
    stub_name := fmt.tprintf("{}_eq", type_name_str)
    if !generated[stub_name] {
        generated[stub_name] = true
        eq_decl := make_derive_method_decl(d, "eq", 2, false, scope, interner, collector)
        
        // Propagate type params and Eq constraints for generic nominal types
        if len(d.type_params) > 0 {
            if const_decl, ok := eq_decl.(^CDecl_Const); ok {
                if lambda, ok := const_decl.body.(^CExpr_Lambda); ok {
                    // Build type params with Eq constraints
                    eq_name_id := base.intern(interner, "Eq")
                    new_type_params := make(
                        [dynamic]frontend.Type_Param,
                        0,
                        len(d.type_params),
                    )
                    for tp in d.type_params {
                        constraints := make([dynamic]base.Intern_ID, 0, 1)
                        append(&constraints, eq_name_id)
                        append(
                            &new_type_params,
                            frontend.Type_Param{
                                name = tp,
                                constraints = constraints[:],
                            },
                        )
                    }
                    lambda.type_params = new_type_params
                }
            }
        }
        
        append(&result, eq_decl)
    }
```

#### Step 6.2: Ensure `derives Eq` generates structural comparison for tag-unioned nominals

The current body `x.inner.eq(y.inner)` works IF the inner type (tag union or record) has auto-derived Eq. Since Phase 3 adds auto-derive for structural types, this should Just Work.

However, the current body calls `.inner.eq(y.inner)` as a METHOD CALL — this requires `eq` to be findable via dot-dispatch on the inner type. For structural types, `eq` is auto-generated as a free function, not a method. So `x.inner.eq(y.inner)` won't work for structural inners.

**Fix:** For nominal types wrapping tag unions/records, generate INLINE structural comparison instead of `.inner.eq()`:

```odin
case "Eq":
    // Check if inner type is structural (tag union or record)
    inner_is_structural := false
    if d.inner_type != nil {
        #partial switch inner in d.inner_type {
        case ^CType_Tag_Union, ^CType_Record:
            inner_is_structural = true
        }
    }
    
    if inner_is_structural {
        // Generate inline structural eq using tag-by-tag or field-by-field
        // Use the same approach as generate_struct_eq but referencing .inner
        // Actually, just generate a structural comparison directly
        // that accesses fields of the unwrapped nominal
        eq_decl := make_nominal_struct_eq_decl(d, scope, interner, collector)
        append(&result, eq_decl)
    } else {
        // Use existing .inner.eq() for primitive/newtype inners
        eq_decl := make_derive_method_decl(d, "eq", 2, false, scope, interner, collector)
        // ... add type param constraints as above ...
        append(&result, eq_decl)
    }
```

Add `make_nominal_struct_eq_decl` — similar to `generate_struct_eq` but wraps in `.inner` field access:

```odin
make_nominal_struct_eq_decl :: proc(
    d: ^CDecl_Newtype,
    scope: ^Canonicalize_Scope,
    interner: ^base.Intern_Table,
    collector: ^diagnostics.Diagnostic_Collector,
) -> CDecl {
    type_name_str := base.intern_get(interner, d.name.name)
    
    // Extract fields/tags from inner type for structural comparison
    elements := extract_struct_elements(d.inner_type, interner)
    
    return generate_struct_eq(
        type_name_str,
        elements[:],
        /*is_tag_union=*/ determine_if_tag_union(d.inner_type),
        scope, interner, collector, d.span,
    )
}

// extract_struct_elements pulls field or tag names+types from a CType
extract_struct_elements :: proc(
    t: ^CType,
    interner: ^base.Intern_Table,
) -> [dynamic]struct{name: base.Intern_ID, type_ref: ^CType} {
    result := make([dynamic]struct{name: base.Intern_ID, type_ref: ^CType}, 0, 8)
    
    #partial switch ty in t {
    case ^CType_Record:
        for f in ty.fields {
            append(&result, struct{name: f.name, type_ref: f.type})
        }
    case ^CType_Tag_Union:
        for tg in ty.tags {
            append(&result, struct{name: tg.name, type_ref: tg.type})
        }
    }
    
    return result
}

// determine_if_tag_union checks if a CType is a tag union
determine_if_tag_union :: proc(t: ^CType) -> bool {
    #partial switch ty in t {
    case ^CType_Tag_Union:
        return true
    }
    return false
}
```

---

## Phase 7: Testing

### 7.1: Primitive Eq tests

In `tests/e2e/language/kitchen-sink/Main.camp`, add:

```camp
test "I64 eq" {
    expect 42 == 42
    expect not (42 == 0)
}
test "F64 eq NaN" {
    expect not (nan() == nan())
}
```

### 7.2: Structural auto-derive tests

```camp
test "record eq" {
    r1 = { a: 1, b: "hello" }
    r2 = { a: 1, b: "hello" }
    r3 = { a: 2, b: "hello" }
    expect r1 == r2
    expect not (r1 == r3)
}
test "tag union eq" {
    // Assumes Result is in scope
    expect Result.Ok(42) == Result.Ok(42)
    expect not (Result.Ok(42) == Result.Ok(0))
    expect not (Result.Ok(42) == Result.Err("x"))
}
```

### 7.3: Nominal derive tests

```camp
@UserId : U64 derives Eq
test "nominal eq via derive" {
    a = @UserId(42)
    b = @UserId(42)
    c = @UserId(0)
    expect a == b
    expect not (a == c)
}
```

### 7.4: Error case tests

```camp
// Should produce type error:
//   handler_a == handler_b  // Error: function type does not implement Eq
```

---

## Summary of file changes

| File | Change |
|------|--------|
| `src/semantics/prelude.odin` | Register Eq trait + primitive impls |
| `src/semantics/check_expr.odin` | Typecheck Eq conformance on `==`/`!=` |
| `src/semantics/types.odin` | Add `resolve_type_name_for_eq_check` |
| `src/semantics/canonicalize.odin` | Auto-derive Eq for structurals, fix nominal derive |
| `src/ir/lower.odin` | Dispatch `==` to eq trait for structurals |
| `src/diagnostics/constructors.odin` | Add `diag_type_does_not_implement_trait` |
| `stdlib/Num/I64.camp` | Add `is Eq` |
| `stdlib/Num/U64.camp` | Add `is Eq` |
| `stdlib/Num/I32.camp` | Add `is Eq` |
| `stdlib/Num/U32.camp` | Add `is Eq` |
| `stdlib/Num/I16.camp` | Add `is Eq` |
| `stdlib/Num/U16.camp` | Add `is Eq` |
| `stdlib/Num/I8.camp` | Add `is Eq` |
| `stdlib/Num/U8.camp` | Add `is Eq` |
| `stdlib/Num/F64.camp` | Add `is Eq` |
| `stdlib/Num/F32.camp` | Add `is Eq` |
| `stdlib/Bool.camp` | Add `is Eq` |
| `stdlib/Str.camp` | Add `is Eq` |
| `stdlib/Char.camp` | Add `is Eq` (or inline in existing) |
| `stdlib/Bytes.camp` | Add `is Eq` (or inline) |
| `stdlib/Map.camp` | Add `is Eq` intrinsic |
| `stdlib/Set.camp` | Add `is Eq` intrinsic |
| `stdlib/Json.camp` | Add `is Eq` intrinsic |
| `stdlib/Path.camp` | Add `is Eq` via inner |
| `stdlib/Duration.camp` | Add `is Eq` intrinsic |
| `stdlib/Uri.camp` | Add `is Eq` intrinsic |
| `stdlib/Uuid.camp` | Add `is Eq` intrinsic |
| `stdlib/Regex.camp` | Add `is Eq` intrinsic |
| `stdlib/Base64.camp` | Add `is Eq` intrinsic |

Total: ~30 files modified, ~400 lines added.
