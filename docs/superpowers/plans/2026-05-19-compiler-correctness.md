# Compiler Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 8 deferred compiler correctness bugs discovered during audit: IR_Crash, non-name callee lowering, handler evidence, match pattern typechecking + exhaustiveness, closure body, Perceus RC rewriting, CPS continuation generation, and generalization level soundness.

**Architecture:** Each bug touches a specific set of compiler phases. Fixes are applied in dependency order — infrastructure bugs (IR nodes, type system) first, then passes that depend on them. Each task is self-contained and committed independently.

**Tech Stack:** Odin compiler, WASM/WASI target, existing `camp` test infrastructure (`odin test src` for unit tests, `camp-e2e` for e2e snapshot tests).

---

## File Map

| File | Role | Touched by |
|------|------|------------|
| `src/ir.odin` | IR types (IR_Expr, IR_Decl, IR_Type, IR_Pattern unions and structs) | Task 1, 5, 6 |
| `src/lower.odin` | AST → IR lowering | Task 1, 5, 6 |
| `src/effect_lower.odin` | Evidence-passing effect lowering | Task 2 |
| `src/types.odin` | Type variable store, Inferred_Type, generalization | Task 3 |
| `src/typecheck.odin` | Type inference and checking | Task 4 |
| `src/closure_convert.odin` | Closure conversion | Task 5, 6 |
| `src/rc.odin` | Perceus reference counting | Task 1, 5, 6, 7 |
| `src/cps.odin` | Selective CPS transform | Task 1, 5, 6, 8 |
| `src/codegen.odin` | IR → WASM code generation | Task 1, 6 |
| `src/wasm.odin` | WASM binary format and serialization | Task 6 |
| `src/diag_constructors.odin` | Diagnostic message constructors | Task 2, 4 |
| `tests/e2e/` | E2e snapshot tests | All tasks |
| `src/test_ir.odin` | IR pass unit tests | Task 1, 5 |
| `src/test_typecheck.odin` | Typecheck unit tests | Task 4 |

---

### Task 1: IR_Crash Node (H2)

**Files:**
- Modify: `src/ir.odin` (add struct + union variant)
- Modify: `src/lower.odin:292-293` (rewrite crash lowering)
- Modify: `src/codegen.odin` (add emit_expr case)
- Modify: `src/rc.odin` (add traversal case)
- Modify: `src/closure_convert.odin` (add pass-through case)
- Modify: `src/cps.odin` (add pass-through case)
- Modify: `src/effect_lower.odin` (add pass-through case)

- [ ] **Step 1: Add IR_Crash struct and union variant**

In `src/ir.odin`, after `IR_Expr :: union {` closing brace, add before `}`:
```odin
	^IR_Crash,
}
```

Add the struct definition after existing IR structs (e.g., after IR_Alloc_At):
```odin
IR_Crash :: struct {
	message: IR_Expr,
	span:    Source_Span,
}
```

- [ ] **Step 2: Lower CExpr_Crash to IR_Crash**

In `src/lower.odin`, replace lines 292-293:
```odin
	case ^CExpr_Crash:
		msg_expr := lower_expr(e.message, env)
		crash := new(IR_Crash)
		crash^ = IR_Crash{message = msg_expr, span = e.span}
		return IR_Expr(crash)
```

- [ ] **Step 3: Add emit_expr case in codegen**

In `src/codegen.odin`, in `emit_expr`, add before the final `case:`:
```odin
	case ^IR_Crash:
		emit_expr(e.message, buf, env, runtime_indices)
		emit_instruction(Wasm_Drop{}, buf)
		emit_instruction(Wasm_Unreachable{}, buf)
```

- [ ] **Step 4: Add collect_locals case**

In `src/codegen.odin`, in `collect_locals`, add after `IR_Closure` case:
```odin
	case ^IR_Crash:
		collect_locals(e.message, locals)
```

- [ ] **Step 5: Add traversal cases in mid-end passes**

In `src/rc.odin`, `rc_collect_uses` proc, add after the last case:
```odin
	case ^IR_Crash:
		rc_collect_uses(e.message, uses)
```

In `src/rc.odin`, `rc_insert_expr_inner` proc, add after `IR_Alloc_At` case:
```odin
	case ^IR_Crash:
		new_msg := rc_insert_expr_inner(e.message, remaining, interner)
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = new_msg, span = e.span}
		return IR_Expr(new_crash)
```

In `src/closure_convert.odin`, `cc_convert_expr` proc, add after last case:
```odin
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = cc_convert_expr(e.message, env), span = e.span}
		return IR_Expr(new_crash)
```

In `src/cps.odin`, `cps_transform_expr` proc, add after last case:
```odin
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = cps_transform_expr(e.message, k_name, env), span = e.span}
		return IR_Expr(new_crash)
```

In `src/effect_lower.odin`, `el_lower_expr` proc, add after last case:
```odin
	case ^IR_Crash:
		new_crash := new(IR_Crash)
		new_crash^ = IR_Crash{message = el_lower_expr(e.message, env), span = e.span}
		return IR_Expr(new_crash)
```

Also add to `cc_free_vars` in `src/closure_convert.odin` after last case:
```odin
	case ^IR_Crash:
		inner := cc_free_vars(e.message, bound)
		for v in inner { append(&result, v) }
		delete(inner)
```

- [ ] **Step 6: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 7: Commit**

```bash
git add src/ir.odin src/lower.odin src/codegen.odin src/rc.odin src/closure_convert.odin src/cps.odin src/effect_lower.odin
git commit -m "feat(ir): add IR_Crash node with lowering and codegen"
git push
```

---

### Task 2: Missing Handler Evidence (M4)

**Files:**
- Modify: `src/effect_lower.odin:131-163` (handle NO_NAME evidence)

- [ ] **Step 1: Add diagnostic collector to Effect_Lower_Env**

In `src/effect_lower.odin`, add to `Effect_Lower_Env` struct:
```odin
Effect_Lower_Env :: struct {
	module:         ^IR_Module,
	interner:       ^Intern_Table,
	collector:      ^Diagnostic_Collector,   // NEW
	fresh:          int,
	evidence_stack: [dynamic]Effect_Evidence,
}
```

- [ ] **Step 2: Pass collector when creating env**

In `src/effect_lower.odin`, in `effect_lower` proc, add after `env.evidence_stack = ` line:
```odin
	env.collector = &ctx.collector
```

- [ ] **Step 3: Add diagnostic for no-handler case**

In `src/effect_lower.odin`, replace lines 139-163 in `el_lower_expr` (`IR_Perform` case):
```odin
	case ^IR_Perform:
		ev_var: Intern_ID = NO_NAME
		for i := len(env.evidence_stack) - 1; i >= 0; i -= 1 {
			if env.evidence_stack[i].effect == e.effect {
				ev_var = env.evidence_stack[i].ev_var
				break
			}
		}

		if ev_var == NO_NAME {
			collector_add_diag(env.collector, diag_internal(
				fmt.tprintf("perform without handler evidence for `{}`", intern_get(env.interner, e.op)),
				e.span))
			lit := new(IR_Literal_Int)
			lit^ = IR_Literal_Int{value = 0, type = e.type, span = e.span}
			return IR_Expr(lit)
		}

		args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
		ev_ref := new(IR_Var)
		ev_ref^ = IR_Var{name = ev_var, type = IR_Type{.I64, Type_Var_ID(0)}, span = e.span}
		append(&args, IR_Expr(ev_ref))
		for arg in e.args {
			append(&args, el_lower_expr(arg, env))
		}

		handler_callee := Canonical_Name{
			module = e.effect.module,
			name = e.op,
			is_local = false,
		}

		call := new(IR_Call)
		call^ = IR_Call{
			callee = handler_callee,
			args = args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(call)
```

- [ ] **Step 4: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 5: Commit**

```bash
git add src/effect_lower.odin
git commit -m "fix(effect_lower): emit diagnostic for perform without handler evidence"
git push
```

---

### Task 3: Generalization Level Soundness (M9)

**Files:**
- Modify: `src/types.odin:132-138` (rewrite generalize_at_level)

- [ ] **Step 1: Add child level checking helper**

In `src/types.odin`, add before `generalize_at_level`:
```odin
all_children_at_or_below :: proc(store: ^Type_Store, link: Type_Link, max_level: int) -> bool {
	_, is_unlinked := link.(Type_Unlinked)
	if is_unlinked do return true

	inf, is_inferred := link.(Inferred_Type)
	if !is_inferred do return true

	#partial switch inf.tag {
	case .Function:
		for pid in inf.param_ids {
			child := get_var(store, resolve_var(store, pid))
			if child.level > max_level do return false
		}
		child_ret := get_var(store, resolve_var(store, inf.return_id))
		if child_ret.level > max_level do return false
		child_eff := get_var(store, resolve_var(store, inf.effect_id))
		if child_eff.level > max_level do return false

	case .Record_Row:
		for f in inf.record_fields {
			child := get_var(store, resolve_var(store, f.var))
			if child.level > max_level do return false
		}
		child_rest := get_var(store, resolve_var(store, inf.record_rest))
		if child_rest.level > max_level do return false

	case .Tag_Union_Row:
		for te in inf.tag_entries {
			for pid in te.payload {
				child := get_var(store, resolve_var(store, pid))
				if child.level > max_level do return false
			}
		}
		child_rest := get_var(store, resolve_var(store, inf.rest_id))
		if child_rest.level > max_level do return false

	case .Effect_Row:
		child_rest := get_var(store, resolve_var(store, inf.rest_id))
		if child_rest.level > max_level do return false

	case .Primitive, .Constructor:
	}
	return true
}
```

- [ ] **Step 2: Update generalize_at_level to use the check**

Replace:
```odin
generalize_at_level :: proc(store: ^Type_Store, level: int) {
	for i := 0; i < len(store.vars); i += 1 {
		if store.vars[i].level == level && store.vars[i].level != LEVEL_GENERIC {
			store.vars[i].level = LEVEL_GENERIC
		}
	}
}
```

With:
```odin
generalize_at_level :: proc(store: ^Type_Store, level: int) {
	for i := 0; i < len(store.vars); i += 1 {
		v := &store.vars[i]
		if v.level == level && v.level != LEVEL_GENERIC {
			if all_children_at_or_below(store, v.link, level) {
				v.level = LEVEL_GENERIC
			}
		}
	}
}
```

- [ ] **Step 3: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 4: Commit**

```bash
git add src/types.odin
git commit -m "fix(types): check child levels before generalizing type variables"
git push
```

---

### Task 4: Match Pattern Typechecking + Exhaustiveness (C5)

**Files:**
- Modify: `src/typecheck.odin:485-506` (rewrite typecheck_match)
- Create: new `typecheck_pattern` proc in `src/typecheck.odin`

- [ ] **Step 1: Add typecheck_pattern function**

In `src/typecheck.odin`, add before `typecheck_match`:
```odin
typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	eff := fresh_effect_row(store, Source_Span_ZERO)

	#partial switch p in pattern {
	case ^CPat_Var:
		env.bindings[p.name.name] = scrutinee_var
		return Type_Result{var_id = scrutinee_var, effects = eff}

	case ^CPat_Wildcard:
		return Type_Result{var_id = scrutinee_var, effects = eff}

	case ^CPat_Bool:
		bool_name := intern(store.interner, "Bool")
		bool_var := make_primitive_type(store, bool_name, p.span)
		unify(store, scrutinee_var, bool_var)
		return Type_Result{var_id = bool_var, effects = eff}

	case ^CPat_Int:
		i64_name := intern(store.interner, "I64")
		i64_var := make_primitive_type(store, i64_name, p.span)
		unify(store, scrutinee_var, i64_var)
		return Type_Result{var_id = i64_var, effects = eff}

	case ^CPat_String:
		str_name := intern(store.interner, "Str")
		str_var := make_primitive_type(store, str_name, p.span)
		unify(store, scrutinee_var, str_var)
		return Type_Result{var_id = str_var, effects = eff}

	case ^CPat_Tag:
		payload_ids := store_alloc(store, Type_Var_ID, len(p.payload))
		for sp, i in p.payload {
			payload_ids[i] = fresh_value_var(store, p.span)
			pat_result := typecheck_pattern(sp, payload_ids[i], env, store)
			unify(store, eff, pat_result.effects)
		}
		rest_var := fresh_value_var(store, p.span)
		tag_entries := store_alloc(store, Type_Tag_Entry, 1)
		tag_entries[0] = Type_Tag_Entry{name = p.name.name, payload = payload_ids}
		tag_var := fresh_value_var(store, p.span)
		link_var(store, tag_var, Inferred_Type{
			tag = .Tag_Union_Row,
			tag_entries = tag_entries,
			rest_id = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, tag_var)
		return Type_Result{var_id = tag_var, effects = eff}

	case ^CPat_Record:
		field_entries := store_alloc(store, Type_Field_Entry, len(p.fields))
		for sf, i in p.fields {
			field_entries[i].name = sf.name
			field_entries[i].var = fresh_value_var(store, p.span)
			pat_result := typecheck_pattern(sf.pattern, field_entries[i].var, env, store)
			unify(store, eff, pat_result.effects)
		}
		rest_var := fresh_record_row(store, p.span)
		rec_var := fresh_value_var(store, p.span)
		link_var(store, rec_var, Inferred_Type{
			tag = .Record_Row,
			record_fields = field_entries,
			record_rest = resolve_var(store, rest_var),
		})
		unify(store, scrutinee_var, rec_var)
		return Type_Result{var_id = rec_var, effects = eff}

	case ^CPat_Or:
		for sub_pat in p.patterns {
			pat_result := typecheck_pattern(sub_pat, scrutinee_var, env, store)
			unify(store, eff, pat_result.effects)
		}
		return Type_Result{var_id = scrutinee_var, effects = eff}
	}

	return Type_Result{var_id = scrutinee_var, effects = eff}
}
```

- [ ] **Step 2: Add exhaustiveness helper**

In `src/typecheck.odin`, add after `typecheck_pattern`:
```odin
collect_covered_tags :: proc(pattern: CPattern, tags: ^map[Intern_ID]bool, saturated: ^bool) {
	#partial switch p in pattern {
	case ^CPat_Wildcard:
		saturated^ = true
	case ^CPat_Tag:
		tags^[p.name.name] = true
	case ^CPat_Or:
		for sub in p.patterns {
			collect_covered_tags(sub, tags, saturated)
		}
	case:
	}
}
```

- [ ] **Step 3: Rewrite typecheck_match**

Replace `typecheck_match` (lines 485-506):
```odin
typecheck_match :: proc(e: ^CExpr_Match, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
	scrutinee_result := typecheck_synth(e.scrutinee, env, store)

	if len(e.arms) == 0 {
		var_id := fresh_value_var(store, e.span)
		return Type_Result{var_id = var_id, effects = scrutinee_result.effects}
	}

	saved_bindings := make(map[Intern_ID]Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	first_result := typecheck_synth(e.arms[0].body, env, store)
	result_var := first_result.var_id
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)
	unify(store, effect_row, first_result.effects)

	covered_tags: map[Intern_ID]bool
	covered_tags = make(map[Intern_ID]bool, len(e.arms))
	defer delete(covered_tags)
	saturated := false

	for i := 0; i < len(e.arms); i += 1 {
		arm := e.arms[i]

		for k in env.bindings {
			delete(env.bindings, k)
		}
		for k, v in saved_bindings {
			env.bindings[k] = v
		}

		pat_result := typecheck_pattern(arm.pattern, scrutinee_result.var_id, env, store)
		unify(store, effect_row, pat_result.effects)
		collect_covered_tags(arm.pattern, &covered_tags, &saturated)

		arm_result := typecheck_synth(arm.body, env, store)
		unify(store, result_var, arm_result.var_id)
		unify(store, effect_row, arm_result.effects)
	}

	resolved_scrut := get_var(store, resolve_var(store, scrutinee_result.var_id))
	#partial switch inf in resolved_scrut.link {
	case Inferred_Type:
		if inf.tag == .Tag_Union_Row && len(inf.tag_entries) > 0 && !saturated {
			uncovered_tags: [dynamic]string
			uncovered_tags = make([dynamic]string, 0, 8)
			for te in inf.tag_entries {
				if !covered_tags[te.name] {
					append(&uncovered_tags, intern_get(store.interner, te.name))
				}
			}
			if len(uncovered_tags) > 0 {
				missing := fmt.tprintf("{}", uncovered_tags[0])
				for j := 1; j < len(uncovered_tags); j += 1 {
					missing = fmt.tprintf("{}, {}", missing, uncovered_tags[j])
				}
				collector_add_diag(store.collector, diag_internal(
					fmt.tprintf("non-exhaustive match: missing branch for {}", missing),
					e.span))
			}
			delete(uncovered_tags)
		}
	case:
	}

	return Type_Result{var_id = result_var, effects = effect_row}
}
```

- [ ] **Step 4: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 5: Update e2e snapshots**

Run: `odin build src/e2e -out:camp-e2e && ./camp-e2e --update 2>&1 | tail -3`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

Run: `./camp-e2e 2>&1 | tail -1`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

- [ ] **Step 6: Commit**

```bash
git add src/typecheck.odin tests/
git commit -m "feat(typecheck): match pattern typechecking and exhaustiveness checking"
git push
```

---

### Task 5: Closure Body Transfer + Free Variable Capture (C8)

**Files:**
- Modify: `src/ir.odin` (add body field to IR_Closure)
- Modify: `src/lower.odin` (store body in closure)
- Modify: `src/closure_convert.odin` (transfer body to closed fn, capture free vars, track fn_idx)
- Modify: `src/codegen.odin` (add collect_locals for closure body)
- Modify: `src/rc.odin` (add traversal for closure body)
- Modify: `src/cps.odin` (add traversal for closure body)

- [ ] **Step 1: Add body field to IR_Closure**

In `src/ir.odin`, find `IR_Closure :: struct` and add `body` field:
```odin
IR_Closure :: struct {
	env:  IR_Expr,
	body: IR_Expr,    // NEW: the lambda body to transfer
	type: IR_Type,
	span: Source_Span,
}
```

- [ ] **Step 2: Store body in lower_lambda**

In `src/lower.odin`, find `lower_lambda`. Locate where `IR_Closure` is constructed and add the body:
```odin
	closure := new(IR_Closure)
	closure^ = IR_Closure{
		env = IR_Expr(nil),
		body = lower_expr(lambda.body),    // NEW: store the lambda body
		type = ir_type,
		span = e.span,
	}
```

- [ ] **Step 3: Transfer body in closure_convert (IR_Closure case)**

In `src/closure_convert.odin`, replace the `IR_Closure` case in `cc_convert_expr`:

```odin
	case ^IR_Closure:
		env_param_name := cc_fresh(env, "_cenv")

		bound: map[Intern_ID]bool
		bound = make(map[Intern_ID]bool, 8)
		bound[env_param_name] = true

		free := cc_free_vars(e.body, &bound)
		delete(bound)

		params := make([dynamic]IR_Param, 0, len(free) + 1)
		append(&params, IR_Param{name = env_param_name, type = IR_Type{.I32, Type_Var_ID(0)}})

		closed_fn_name := Canonical_Name{
			module = NO_NAME,
			name = cc_fresh(env, "closed"),
			is_local = true,
		}

		closed_fn := new(IR_Decl_Fn)
		closed_fn^ = IR_Decl_Fn{
			name = closed_fn_name,
			is_effectful = false,
			params = params,
			return_type = e.type,
			effect_row = IR_Type{.Void, Type_Var_ID(0)},
			body = cc_convert_expr(e.body, env),
			span = e.span,
		}
		append(&env.module.decls, IR_Decl(closed_fn))

		fn_idx := len(env.module.decls) - 1

		fn_idx_lit := new(IR_Literal_Int)
		fn_idx_lit^ = IR_Literal_Int{value = i64(fn_idx), type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		env_alloc := new(IR_Literal_Int)
		env_alloc^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		fields := make([dynamic]IR_Record_Field, 0, 2)
		fn_idx_id := intern(env.interner, "fn_idx")
		env_ptr_id := intern(env.interner, "env_ptr")
		append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_lit)})
		append(&fields, IR_Record_Field{name = env_ptr_id, value = IR_Expr(env_alloc)})

		rest_nil := new(IR_Literal_Int)
		rest_nil^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		rec := new(IR_Construct_Record)
		rec^ = IR_Construct_Record{
			fields = fields,
			rest = IR_Expr(rest_nil),
			type = IR_Type{.I32, Type_Var_ID(0)},
			span = e.span,
		}

		delete(free)
		return IR_Expr(rec)
```

- [ ] **Step 4: Update collect_locals for closure body**

In `src/codegen.odin`, in `collect_locals`, update `IR_Closure` case:
```odin
	case ^IR_Closure:
		collect_locals(e.env, locals)
		collect_locals(e.body, locals)
```

- [ ] **Step 5: Update cc_free_vars for closure body**

In `src/closure_convert.odin`, update `IR_Closure` case in `cc_free_vars`:
```odin
	case ^IR_Closure:
		inner := cc_free_vars(e.env, bound)
		for v in inner { append(&result, v) }
		delete(inner)
		body_inner := cc_free_vars(e.body, bound)
		for v in body_inner { append(&result, v) }
		delete(body_inner)
```

- [ ] **Step 6: Update cc_convert_expr recursive calls for IR_Closure at call sites**

Ensure `cc_convert_expr` also recurses into `e.body` for the `IR_Closure` case (already done in step 3).

- [ ] **Step 7: Update rc and cps traversal for closure body**

In `src/rc.odin`, `rc_collect_uses`, find `IR_Closure` case and add body traversal:
```odin
	case ^IR_Closure:
		rc_collect_uses(e.env, uses)
		rc_collect_uses(e.body, uses)
```

In `src/rc.odin`, `rc_insert_expr_inner`, find `IR_Closure` case and add body:
```odin
	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure{
			env = rc_insert_expr_inner(e.env, remaining, interner),
			body = rc_insert_expr_inner(e.body, remaining, interner),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_closure)
```

In `src/cps.odin`, `cps_transform_expr`, find `IR_Closure` case and add body:
```odin
	case ^IR_Closure:
		new_closure := new(IR_Closure)
		new_closure^ = IR_Closure{
			env = cps_transform_expr(e.env, k_name, env),
			body = cps_transform_expr(e.body, k_name, env),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_closure)
```

- [ ] **Step 8: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 9: Update e2e snapshots and verify**

Run: `odin build src/e2e -out:camp-e2e && ./camp-e2e --update 2>&1 | tail -3`
Run: `./camp-e2e 2>&1 | tail -1`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

- [ ] **Step 10: Commit**

```bash
git add src/ir.odin src/lower.odin src/closure_convert.odin src/codegen.odin src/rc.odin src/cps.odin tests/
git commit -m "feat(closure): transfer lambda body to closed function, track fn_idx"
git push
```

---

### Task 6: Non-Name Callee Lowering with Closure Calls (C7)

**Files:**
- Modify: `src/ir.odin` (add IR_Closure_Call struct + union variant)
- Modify: `src/lower.odin:308-331` (rewrite lower_call)
- Modify: `src/closure_convert.odin` (add traversal)
- Modify: `src/rc.odin` (add traversal)
- Modify: `src/cps.odin` (add traversal)
- Modify: `src/codegen.odin` (add emit_expr + collect_locals)
- Modify: `src/wasm.odin` (add Call_Indirect instruction if needed)

- [ ] **Step 1: Add IR_Closure_Call to IR types**

In `src/ir.odin`, add to `IR_Expr` union:
```odin
	^IR_Closure_Call,
```

Add struct after IR_Closure:
```odin
IR_Closure_Call :: struct {
	callee: IR_Expr,
	args:   [dynamic]IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}
```

- [ ] **Step 2: Rewrite lower_call**

In `src/lower.odin`, replace `lower_call`:
```odin
lower_call :: proc(e: ^CExpr_Call, env: ^Lower_Env) -> IR_Expr {
	#partial switch c in e.callee {
	case ^CExpr_Name:
		callee_name := c.name
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_expr(arg, env))
		}
		type_var := fresh_value_var(env.store, e.span)
		call := new(IR_Call)
		call^ = IR_Call{
			callee = callee_name,
			args = ir_args,
			type = lower_type(env.store, type_var),
			span = e.span,
		}
		return IR_Expr(call)

	case:
		callee_expr := lower_expr(c, env)
		ir_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&ir_args, lower_expr(arg, env))
		}
		type_var := fresh_value_var(env.store, e.span)
		ccall := new(IR_Closure_Call)
		ccall^ = IR_Closure_Call{
			callee = callee_expr,
			args = ir_args,
			type = lower_type(env.store, type_var),
			span = e.span,
		}
		return IR_Expr(ccall)
	}
}
```

- [ ] **Step 3: Add traversal cases in mid-end passes**

In `src/closure_convert.odin`, `cc_free_vars`, add:
```odin
	case ^IR_Closure_Call:
		callee := cc_free_vars(e.callee, bound)
		for v in callee { append(&result, v) }
		delete(callee)
		for arg in e.args {
			inner := cc_free_vars(arg, bound)
			for v in inner { append(&result, v) }
			delete(inner)
		}
```

In `src/closure_convert.odin`, `cc_convert_expr`, add:
```odin
	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cc_convert_expr(arg, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = cc_convert_expr(e.callee, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)
```

In `src/rc.odin`, `rc_collect_uses`, add:
```odin
	case ^IR_Closure_Call:
		rc_collect_uses(e.callee, uses)
		for arg in e.args {
			rc_collect_uses(arg, uses)
		}
```

In `src/rc.odin`, `rc_insert_expr_inner`, add:
```odin
	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rc_insert_expr_inner(arg, remaining, interner))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = rc_insert_expr_inner(e.callee, remaining, interner),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)
```

In `src/cps.odin`, `cps_transform_expr`, add:
```odin
	case ^IR_Closure_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, cps_transform_expr(arg, k_name, env))
		}
		new_cc := new(IR_Closure_Call)
		new_cc^ = IR_Closure_Call{
			callee = cps_transform_expr(e.callee, k_name, env),
			args = new_args,
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_cc)
```

- [ ] **Step 4: Add codegen for IR_Closure_Call**

In `src/codegen.odin`, `collect_locals`, add:
```odin
	case ^IR_Closure_Call:
		collect_locals(e.callee, locals)
		for arg in e.args {
			collect_locals(arg, locals)
		}
```

In `src/codegen.odin`, `emit_expr`, add:
```odin
	case ^IR_Closure_Call:
		emit_expr(e.callee, buf, env, runtime_indices)
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		emit_instruction(Wasm_Unreachable{}, buf)
```

Note: `call_indirect` requires WASM table support. The above emits `unreachable` as a stub until tables are implemented. The closure record's `fn_idx` will need to be the table index when tables are added.

- [ ] **Step 5: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 6: Update e2e snapshots and verify**

Run: `odin build src/e2e -out:camp-e2e && ./camp-e2e --update 2>&1 | tail -3`
Run: `./camp-e2e 2>&1 | tail -1`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

- [ ] **Step 7: Commit**

```bash
git add src/ir.odin src/lower.odin src/closure_convert.odin src/rc.odin src/cps.odin src/codegen.odin tests/
git commit -m "feat(ir): add IR_Closure_Call for higher-order call lowering"
git push
```

---

### Task 7: Perceus RC — Correct Dup/Drop Insertion (C9)

**Files:**
- Modify: `src/rc.odin` (rewrite IR_Let case, add insert_dups_and_drop helper)

- [ ] **Step 1: Rewrite IR_Var case to preserve the Var**

In `src/rc.odin`, `rc_insert_expr_inner`, replace `IR_Var` case:
```odin
	case ^IR_Var:
		count, ok := (remaining^)[e.name]
		if !ok do return expr

		(remaining^)[e.name] = count - 1
		return expr
```

This keeps the `IR_Var` as-is (no more replacement with Dup/Drop at the Var site).

- [ ] **Step 2: Add insert_dups_and_drop helper**

In `src/rc.odin`, add before `rc_insert_expr_inner`:
```odin
insert_dups_and_drop :: proc(expr: IR_Expr, binding: Intern_ID, total_uses: int, interner: ^Intern_Table) -> IR_Expr {
	return insert_dups_and_drop_impl(expr, binding, total_uses, &total_uses, interner)
}

insert_dups_and_drop_impl :: proc(expr: IR_Expr, binding: Intern_ID, total_uses: int, remaining: ^int, interner: ^Intern_Table) -> IR_Expr {
	#partial switch e in expr {
	case ^IR_Var:
		if e.name != binding do return expr
		remaining^ -= 1
		if remaining^ > 0 {
			dup := new(IR_Dup)
			dup^ = IR_Dup{value = binding, span = e.span}
			block := new(IR_Block)
			block^ = IR_Block{
				statements = make_ir_stmt_list(IR_Expr(dup), expr),
				type = e.type,
				span = e.span,
			}
			return IR_Expr(block)
		}
		return expr

	case ^IR_Let:
		new_val := insert_dups_and_drop_impl(e.value, binding, total_uses, remaining, interner)
		new_body := insert_dups_and_drop_impl(e.body, binding, total_uses, remaining, interner)
		if remaining^ == 0 && e.binding != binding {
			drop := new(IR_Drop)
			drop^ = IR_Drop{value = binding, span = e.span}
			block := new(IR_Block)
			block^ = IR_Block{
				statements = make_ir_stmt_list(IR_Expr(drop), new_body),
				type = e.type,
				span = e.span,
			}
			return IR_Expr(IR_Let{
				binding = e.binding,
				type = e.type,
				value = new_val,
				body = IR_Expr(block),
				span = e.span,
			})
		}
		return IR_Expr(IR_Let{
			binding = e.binding,
			type = e.type,
			value = new_val,
			body = new_body,
			span = e.span,
		})

	case ^IR_Return:
		new_val := insert_dups_and_drop_impl(e.value, binding, total_uses, remaining, interner)
		return IR_Expr(IR_Return{value = new_val, span = e.span})

	case ^IR_If:
		then_rem := *remaining
		else_rem := *remaining
		new_then := insert_dups_and_drop_impl(e.then_branch, binding, total_uses, &then_rem, interner)
		new_else := insert_dups_and_drop_impl(e.else_branch, binding, total_uses, &else_rem, interner)
		return IR_Expr(IR_If{
			condition = e.condition,
			then_branch = new_then,
			else_branch = new_else,
			type = e.type,
			span = e.span,
		})

	case:
		return expr
	}
}

make_ir_stmt_list :: proc(a: IR_Expr, b: IR_Expr) -> [dynamic]IR_Expr {
	list := make([dynamic]IR_Expr, 0, 2)
	append(&list, a)
	append(&list, b)
	return list
}
```

- [ ] **Step 3: Rewrite IR_Let case in rc_insert_expr_inner**

Replace the `IR_Let` case:
```odin
	case ^IR_Let:
		let_uses := (remaining^)[e.binding]

		var new_let: ^IR_Let
		new_let = new(IR_Let)

		if let_uses == 0 {
			inner_new_let := new(IR_Let)
			inner_new_let^ = IR_Let{
				binding = e.binding,
				type = e.type,
				value = rc_insert_expr_inner(e.value, remaining, interner),
				body = e.body,
				span = e.span,
			}
			drop := new(IR_Drop)
			drop^ = IR_Drop{value = e.binding, span = e.span}
			block := new(IR_Block)
			block^ = IR_Block{
				statements = make_ir_stmt_list(IR_Expr(drop), rc_insert_expr_inner(e.body, remaining, interner)),
				type = e.type,
				span = e.span,
			}
			new_let^ = IR_Let{
				binding = e.binding,
				type = e.type,
				value = rc_insert_expr_inner(e.value, remaining, interner),
				body = IR_Expr(block),
				span = e.span,
			}
		} else {
			transformed_body := rc_insert_expr_inner(e.body, remaining, interner)
			if let_uses > 1 {
				transformed_body = insert_dups_and_drop(transformed_body, e.binding, let_uses, interner)
			}
			new_let^ = IR_Let{
				binding = e.binding,
				type = e.type,
				value = rc_insert_expr_inner(e.value, remaining, interner),
				body = transformed_body,
				span = e.span,
			}
		}

		return IR_Expr(new_let)
```

- [ ] **Step 4: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 5: Update e2e snapshots and verify**

Run: `odin build src/e2e -out:camp-e2e && ./camp-e2e --update 2>&1 | tail -3`
Run: `./camp-e2e 2>&1 | tail -1`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

- [ ] **Step 6: Commit**

```bash
git add src/rc.odin tests/
git commit -m "fix(rc): correct Perceus dup/drop insertion, preserve Var uses"
git push
```

---

### Task 8: CPS Continuation Generation (M5)

**Files:**
- Modify: `src/cps.odin` (rewrite cps_transform_expr for effectful calls)

- [ ] **Step 1: Add continuation-function generation helper**

In `src/cps.odin`, add after `cps_fresh`:
```odin
cps_make_continuation :: proc(body: IR_Expr, param_name: Intern_ID, return_type: IR_Type, k_name: Intern_ID, env: ^CPS_Env) -> Canonical_Name {
	cont_name := Canonical_Name{
		module = NO_NAME,
		name = cps_fresh(env, "_kc"),
		is_local = true,
	}

	cont_params := make([dynamic]IR_Param, 0, 1)
	append(&cont_params, IR_Param{name = param_name, type = return_type})

	cont_fn := new(IR_Decl_Fn)
	cont_fn^ = IR_Decl_Fn{
		name = cont_name,
		is_effectful = false,
		params = cont_params,
		return_type = return_type,
		effect_row = IR_Type{.Void, Type_Var_ID(0)},
		body = cps_transform_expr(body, k_name, env),
		span = Source_Span_ZERO,
	}
	append(&env.module.decls, IR_Decl(cont_fn))
	return cont_name
}
```

Wait — CPS_Env needs a `module` field. Add it:
```odin
CPS_Env :: struct {
	interner: ^Intern_Table,
	module:   ^IR_Module,   // NEW
	fresh:    int,
}
```

Update `cps_transform` to set `env.module = &result`.

- [ ] **Step 2: Rewrite IR_Let with effectful call value**

In `src/cps.odin`, `cps_transform_expr`, rewrite `IR_Let` case:
```odin
	case ^IR_Let:
		#partial switch v in e.value {
		case ^IR_Call:
			if v.type.effect_row.wasm_type != .Void {
				result_name := cps_fresh(env, "_r")
				result_type := v.type

				cont_name := cps_make_continuation(
					e.body,
					result_name,
					result_type,
					k_name,
					env,
				)

				new_args := make([dynamic]IR_Expr, 0, len(v.args) + 1)
				for arg in v.args {
					append(&new_args, cps_transform_expr(arg, k_name, env))
				}
				cont_var := new(IR_Var)
				cont_var^ = IR_Var{name = cont_name.name, type = IR_Type{.Funcref, Type_Var_ID(0)}, span = e.span}
				append(&new_args, IR_Expr(cont_var))

				tc := new(IR_Tail_Call)
				tc^ = IR_Tail_Call{callee = v.callee, args = new_args, span = e.span}
				return IR_Expr(tc)
			}
		case:

		}

		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = cps_transform_expr(e.value, k_name, env),
			body = cps_transform_expr(e.body, k_name, env),
			span = e.span,
		}
		return IR_Expr(new_let)
```

- [ ] **Step 3: Build and run tests**

Run: `odin build src -out:camp`
Expected: builds without errors

Run: `odin test src 2>&1 | grep "Finished"`
Expected: `Finished 117 tests in ...ms. All tests were successful.`

- [ ] **Step 4: Update e2e snapshots and verify**

Run: `odin build src/e2e -out:camp-e2e && ./camp-e2e --update 2>&1 | tail -3`
Run: `./camp-e2e 2>&1 | tail -1`
Expected: `101 passed, 0 failed, 0 skipped (101 total)`

- [ ] **Step 5: Commit**

```bash
git add src/cps.odin tests/
git commit -m "feat(cps): generate continuation functions for effectful call chains"
git push
```
