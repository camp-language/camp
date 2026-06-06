# Eq Trait Implementation - Complete Debug and Merge

## Original Context

**PR:** https://github.com/camp-language/camp/pull/80
**Status:** 80% complete, syntax issues remaining
**Branch:** `smores/eq-trait-implementation`

## Working Parts (DO NOT TOUCH)

These are complete and tested. Only modify if you discover a bug.

1. **Prelude Registration** (`src/semantics/prelude.odin`)
   - Eq trait registered with `eq: (Self, Self) -> Bool`
   - Primitive impls for: I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Bool, Char, Str, Bytes, Unit
   - DO NOT modify these

2. **Typechecker Enforcement** (`src/semantics/check_expr.odin`)
   - Eq conformance checked in `typecheck_binop` for `.Eq_Eq, .Bang_Eq`
   - Diagnostic `diag_type_does_not_implement_trait` added
   - DO NOT modify these

3. **Stdlib Eq Impls** (`stdlib/*.camp`)
   - All primitive types have `is Eq` blocks with intrinsic impls
   - DO NOT modify these

4. **Tests**
   - All 464 unit tests pass
   - DO NOT break existing tests

## Remaining Work (THE PROBLEM)

### 1. Auto-Derive Eq for Structural Types (`src/semantics/canonicalize.odin`)

**File:** `src/semantics/canonicalize.odin`

**Insert after line 1917** (after `infer_type_params`):

```odin
// Auto-derive Eq for structural types

generate_struct_eq :: proc(
	type_name_hint: string,
	element_types: []struct{name: base.Intern_ID, type_ref: ^CType},
	is_tag_union: bool,
	scope: ^Canonicalize_Scope,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
	span: base.Source_Span,
) -> CDecl {
	type_name_id := base.intern(interner, type_name_hint)
	
	param_name_strs := [2]string{"x", "y"}
	params := make([dynamic]CFunc_Param, 0, 2)
	param_ids := make([dynamic]base.Intern_ID, 0, 2)
	for i in 0 ..< 2 {
		p_id := base.intern(interner, param_name_strs[i])
		append(&param_ids, p_id)
		append(&params, CFunc_Param{name = p_id, span = span})
	}
	
	x_name := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = param_ids[0],
		is_local = true,
	}
	x_expr := new(CExpr_Name)
	x_expr^ = CExpr_Name {
		name = x_name,
		span = span,
	}
	
	y_name := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = param_ids[1],
		is_local = true,
	}
	y_expr := new(CExpr_Name)
	y_expr^ = CExpr_Name {
		name = y_name,
		span = span,
	}
	
	body_expr: CExpr
	if is_tag_union {
		body_expr = generate_tag_union_eq_body(element_types[:], x_expr, y_expr, interner, span)
	} else {
		body_expr = generate_record_eq_body(element_types[:], param_ids[0], param_ids[1], interner, span)
	}
	
	lambda := new(CExpr_Lambda)
	lambda^ = CExpr_Lambda {
		type_params   = make([dynamic]frontend.Type_Param, 0),
		params        = params,
		return_type   = nil,
		effects       = nil,
		where_clauses = make([dynamic]frontend.Where_Clause, 0),
		body          = body_expr,
		span          = span,
	}
	
	cdecl := new(CDecl_Const)
	cdecl^ = CDecl_Const {
		name           = base.Canonical_Name{module = base.NO_NAME, name = type_name_id, is_local = true},
		is_pub         = true,
		is_effectful   = false,
		body           = lambda,
		derive_targets = make([dynamic]base.Intern_ID, 0, 4),
		span           = span,
	}
	
	return cdecl
}

generate_record_eq_body :: proc(
	elements: []struct{name: base.Intern_ID, type_ref: ^CType},
	x_id, y_id: base.Intern_ID,
	interner: ^base.Intern_Table,
	span: base.Source_Span,
) -> CExpr {
	if len(elements) == 0 {
		true_lit := new(CExpr_Literal_Bool)
		true_lit^ = CExpr_Literal_Bool{value = true, span = span}
		return CExpr(true_lit^)
	}
	
	// Start with first field comparison
	field_id_1 := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = x_id,
		is_local = true,
	}
	field_id_2 := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = y_id,
		is_local = true,
	}
	
	x_field := new(CExpr_Field_Access)
	x_field^ = CExpr_Field_Access {
		receiver = new(CExpr_Name),
		name     = x_id,
		span     = span,
	}
	y_field := new(CExpr_Field_Access)
	y_field^ = CExpr_Field_Access {
		receiver = new(CExpr_Name),
		name     = y_id,
		span     = span,
	}
	
	field_eq := new(CExpr_BinOp)
	field_eq^ = CExpr_BinOp {
		op    = .Eq_Eq,
		left  = new(CExpr{x_field^}),
		right = new(CExpr{y_field^}),
		span  = span,
	}
	
	and_result := new(CExpr_BinOp)
	and_result^ = CExpr_BinOp {
		op    = .And,
		left  = new(CExpr{field_eq^}),
		right = nil,
		span  = span,
	}
	
	// Chain remaining fields with and
	for i in 1 ..< len(elements) {
		x_field_i := new(CExpr_Field_Access)
		x_field_i^ = CExpr_Field_Access {
			receiver = new(CExpr_Name),
			name     = x_id,
			span     = span,
		}
		y_field_i := new(CExpr_Field_Access)
		y_field_i^ = CExpr_Field_Access {
			receiver = new(CExpr_Name),
			name     = y_id,
			span     = span,
		}
		
		field_eq_i := new(CExpr_BinOp)
		field_eq_i^ = CExpr_BinOp {
			op    = .Eq_Eq,
			left  = new(CExpr{x_field_i^}),
			right = new(CExpr{y_field_i^}),
			span  = span,
		}
		
		new_and := new(CExpr_BinOp)
		new_and^ = CExpr_BinOp {
			op    = .And,
			left  = new(CExpr{and_result^}),
			right = new(CExpr{field_eq_i^}),
			span  = span,
		}
		and_result = new_and
	}
	
	return CExpr(and_result^)
}

generate_tag_union_eq_body :: proc(
	tags: []struct{name: base.Intern_ID, type_ref: ^CType},
	x_expr, y_expr: CExpr,
	interner: ^base.Intern_Table,
	span: base.Source_Span,
) -> CExpr {
	// Tag-match comparison: compare tags first
	tag_id_1 := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = base.intern(interner, "tag"),
		is_local = true,
	}
	tag_id_2 := base.Canonical_Name {
		module   = base.NO_NAME,
		name     = base.intern(interner, "tag"),
		is_local = true,
	}
	
	x_tag := new(CExpr_Field_Access)
	x_tag^ = CExpr_Field_Access {
		receiver = x_expr,
		name     = tag_id_1,
		span     = span,
	}
	y_tag := new(CExpr_Field_Access)
	y_tag^ = CExpr_Field_Access {
		receiver = y_expr,
		name     = tag_id_2,
		span     = span,
	}
	
	tag_eq := new(CExpr_BinOp)
	tag_eq^ = CExpr_BinOp {
		op    = .Eq_Eq,
		left  = new(CExpr{x_tag^}),
		right = new(CExpr{y_tag^}),
		span  = span,
	}
	
	not_tag_eq := new(CExpr_PrefixOp)
	not_tag_eq^ = CExpr_PrefixOp {
		op      = .Kw_Not,
		operand = new(CExpr{tag_eq^}),
		span    = span,
	}
	
	return CExpr(not_tag_eq^)
}
```

**Insert Eq generation hooks after structural type cases** in `canonicalize_type`:

```odin
// After CType_Record case (after line ~1433):
		// Auto-derive Eq for records
		if len(c.fields) > 0 {
			element_types := make([]struct{name: base.Intern_ID, type_ref: ^CType}, len(c.fields))
			for i in 0 ..< len(c.fields) {
				f := c.fields[i]
				et := struct{name = f.name, type_ref = f.type}
				element_types[i] = et
			}
			gen_eq := generate_struct_eq("struct_eq_record", element_types[:], false, scope, interner, collector, c.span)
			append(&scope.generated_decl, gen_eq)
		}

// After CType_Tuple case (after line ~1445):
		// Auto-derive Eq for tuples
		if len(c.elements) > 0 {
			element_types := make([]struct{name: base.Intern_ID, type_ref: ^CType}, len(c.elements))
			for i in 0 ..< len(c.elements) {
				el := c.elements[i]
				et := struct{name = base.intern(interner, fmt.tprintf("_{}", i + 1)), type_ref = el}
				element_types[i] = et
			}
			gen_eq := generate_struct_eq("struct_eq_tuple", element_types[:], false, scope, interner, collector, c.span)
			append(&scope.generated_decl, gen_eq)
		}

// After CType_Tag_Union case (after line ~1464):
		// Auto-derive Eq for tag unions
		if len(c.tags) > 0 {
			tag_elements := make([]struct{name: base.Intern_ID, type_ref: ^CType}, len(c.tags))
			for i in 0 ..< len(c.tags) {
				tg := c.tags[i]
				tet := struct{name = tg.name, type_ref = tg.type}
				tag_elements[i] = tet
			}
			gen_eq := generate_struct_eq("struct_eq_tagunion", tag_elements[:], true, scope, interner, collector, c.span)
			append(&scope.generated_decl, gen_eq)
		}
```

### 2. IR Lowering Eq Dispatch (`src/ir/lower.odin`)

**File:** `src/ir/lower.odin`

**Insert Eq helpers before `lower_tprefixop`** (around line 1441):

```odin
// lower_eq_via_trait emits a call to the eq method via trait dispatch.
// It looks up the trait_impls for the operand type's eq method.
lower_eq_via_trait :: proc(
	left, right: ^semantics.TExpr,
	result_type: base.IR_Type,
	span: base.Source_Span,
	env: ^Lower_Env,
) -> IR_Expr {
	left_ir := lower_texpr(left^, env)
	right_ir := lower_texpr(right^, env)
	
	type_var := semantics.resolve_var(env.store, texpr_type_id(left^))
	store_vars_ptr := &env.store.vars
	v_ptr := store_vars_ptr[int(type_var)]
	
	it := v_ptr.link
	if it, is_inf := it.(semantics.Inferred_Type); is_inf {
		switch concrete in it {
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
			type_name = compute_struct_eq_name(env.store, type_var)
		}
	}
	
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
					type_            = result_type,
					span             = span,
					ord_compare_func = base.Canonical_Name{},
				}
				return IR_Expr(call)
			}
		}
	}
	
	unreachable := new(IR_Crash)
	unreachable^ = IR_Crash{
		message = IR_Expr(new(IR_Literal_String)),
		type_    = result_type,
		span     = span,
	}
	return IR_Expr(unreachable)
}

// compute_struct_eq_name generates a deterministic name for a structural type's eq function.
// For records: struct_eq_record_{field1}_{field2}
// For tag unions: struct_eq_tagunion_{tag1}_{tag2}
// For tuples: struct_eq_tuple_{count}
compute_struct_eq_name :: proc(
	store: ^semantics.Type_Store,
	type_var: base.Type_Var_ID,
) -> base.Intern_ID {
	resolved := semantics.resolve_var(store, type_var)
	store_vars_ptr := &store.vars
	v_ptr := store_vars_ptr[int(resolved)]
	
	it := v_ptr.link
	if it, is_inf := it.(semantics.Inferred_Type); is_inf {
		switch concrete in it {
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

**Insert Eq dispatch in `lower_tbinop`** after the Str concat block (after line ~1380):

```odin
		// Handle == and != for structural types
		if e.op == .Eq_Eq || e.op == .Bang_Eq {
			operand_type_var := semantics.resolve_var(env.store, e.type_.type_id)
			store_vars_ptr := &env.store.vars
			v_ptr := store_vars_ptr[int(operand_type_var)]
			
			is_wasm_scalar := false
			type_name: base.Intern_ID = base.NO_NAME
			
			if it, is_inf := v_ptr.link.(semantics.Inferred_Type); is_inf {
				if prim, prim_ok := it.(semantics.Inferred_Primitive); prim_ok {
					prim := prim
					type_name = prim.primitive_name
					name_str := base.intern_get(env.interner, type_name)
					is_wasm_scalar = semantics.is_int_primitive_name(env.store, type_name) ||
						semantics.is_float_primitive_name(env.store, type_name) ||
						name_str == "Bool" || name_str == "Char" || name_str == "Unit"
				}
			}
			
			if is_wasm_scalar {
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
				eq_result: IR_Expr = lower_eq_via_trait(e.left, e.right, e.type_, e.span, env)
				if e.op == .Bang_Eq {
					// For !=, negate the eq result
					not_result := new(IR_BinOp)
					not_result^ = IR_BinOp{
						op    = .Bang_Eq,
						left  = nil,
						right = nil,
						type  = e.type_,
						span  = e.span,
					}
					return IR_Expr(not_result)
				}
				return eq_result
			}
		}
```

## Odin Syntax Rules (CRITICAL)

**DO NOT** use these patterns (they cause syntax errors):

❌ `..` elision in proc bodies
❌ `v.link.(T)` without proper type handling
❌ Implicit pointer dereferencing in function arguments
❌ Missing trailing commas in struct literals
❌ Using `type:` instead of `type_` for IR structs
❌ `IR_PrefixOp` doesn't exist - use `IR_BinOp` with `.Bang_Eq`

**ALWAYS** use these patterns:

✅ Explicit pointer dereferencing: `left^` for `^TExpr` arguments
✅ Type switch with proper handling: `it := v_ptr.link; it, is_inf := it.(T)`
✅ Field-by-field struct initialization with trailing commas
✅ IR struct field names: `type_` not `type`
✅ For negation: `IR_BinOp{op = .Bang_Eq, ...}` not `IR_PrefixOp`

## Validation and Testing

**Build and Test:**
```bash
odin build src -collection:camp=src -out:camp
odin test src -collection:camp=src
```

**Expected Results:**
- Compiler builds without errors
- All 464 unit tests pass
- No new leak warnings (arena allocator is expected)

**Add Tests to kitchen-sink:**
Insert after the existing test sections in `tests/e2e/language/kitchen-sink/Main.camp`:

```camp
// ============================================================
// SECTION: Eq Trait (Primitives)
// Demonstrates: Eq trait, == operator, != operator, NaN comparison
// ============================================================

test "I64 eq" {
    expect 42 == 42
    expect not (42 == 0)
    expect not (42 != 42)
    expect (42 != 0)
}

test "F64 eq - NaN" {
    expect not (nan() == nan())
    expect not (nan() == 0.0)
    expect (nan() != nan())
    // Note: NaN != NaN due to IEEE 754
}

test "Bool eq" {
    expect True == True
    expect False == False
    expect not (True == False)
    expect (True != False)
}

test "Str eq" {
    expect "hello" == "hello"
    expect not ("hello" == "world")
    expect ("hello" != "world")
}

test "Byte array eq" {
    b1 = { 0x01, 0x02, 0x03 }
    b2 = { 0x01, 0x02, 0x03 }
    b3 = { 0x01, 0x02, 0x04 }
    expect b1 == b2
    expect not (b1 == b3)
    expect (b1 != b3)
}
```

**Update expected snapshots:**
```bash
just update-snapshots
```

## Merging

**PR Requirements:**
1. All Odin syntax errors resolved
2. Compiler builds successfully
3. All tests pass
4. No new leak warnings
5. Kitchen-sink tests updated

**Merge Checklist:**
- [ ] All syntax errors fixed
- [ ] `odin build src` succeeds
- [ ] `odin test src` passes (464 tests)
- [ ] Kitchen-sink tests added and passing
- [ ] No new diagnostics or warnings introduced
- [ ] Documentation updated in `.beans/camp-fix-eq-trait-odn-syntax.md`

**Final PR Update:**
Update the PR description to reflect completion:
```markdown
## Summary
Complete Eq trait implementation for Camp programming language.

## Features
- ✅ Eq trait registration in prelude
- ✅ Primitive implementations (I64, F64, Bool, Str, Bytes, etc.)
- ✅ Typechecker enforcement on ==/!= operators
- ✅ Auto-derive for records, tag unions, and tuples
- ✅ IR lowering dispatch for structural types

## Testing
- All 464 unit tests pass
- Eq trait works for all primitive types
- Eq auto-derives correctly for structural types
- Typechecker rejects operations on non-Eq types
- Kitchen-sink tests updated and passing
```

## Dependencies

**No new dependencies** - All work is within existing codebase.

**Files to modify:**
1. `src/semantics/canonicalize.odin` - Add Eq code generation
2. `src/ir/lower.odin` - Add Eq dispatch and helpers
3. `tests/e2e/language/kitchen-sink/Main.camp` - Add Eq tests

**Files to preserve:**
1. `src/semantics/prelude.odin` - Eq trait registration (already done)
2. `src/semantics/check_expr.odin` - Typechecker enforcement (already done)
3. `stdlib/*.camp` - Stdlib Eq impls (already done)

## Success Criteria

- Eq trait fully functional for all types
- `==` and `!=` operators work correctly
- Typechecker enforces Eq conformance
- No syntax errors in Odin
- All tests pass
- No memory leaks introduced
- Code compiles cleanly

## Notes

- Odin's type system is strict - pay attention to pointer types and dereferencing
- Arena allocation is used throughout - respect ownership semantics
- Don't introduce GC or unsafe casts
- Maintain deterministic memory management
- Follow existing code patterns