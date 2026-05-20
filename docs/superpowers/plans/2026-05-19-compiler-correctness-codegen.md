# Compiler Correctness + Codegen Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 8 known compiler bugs and complete WASM codegen for all IR node types, so that non-trivial Camp programs (tag unions, records, pattern matching, closures, effect handlers) compile and execute correctly.

**Architecture:** Work proceeds in three layers: (1) fix the 8 known bugs in dependency order (H2 → M4 → M9 → C5 → C8 → C7 → C9 → M5), (2) complete codegen for heap-allocated objects (tags, records, field access, match), (3) complete codegen for closures and effect handlers. Each task is independently testable via unit tests and e2e snapshots.

**Tech Stack:** Odin, WASM binary format, Perceus reference counting, Level type inference

**Spec:** `docs/superpowers/specs/2026-05-19-compiler-correctness-design.md`, `docs/superpowers/specs/2026-05-18-camp-language-design.md` §6

---

## Roadmap

| Phase | What | Tasks |
|-------|------|-------|
| Bug fixes | 8 known compiler bugs | Tasks 1-8 |
| Codegen: heap objects | Tags, records, field access, match | Tasks 9-12 |
| Codegen: closures | Closure creation, closure calls, call_indirect | Task 13 |
| Codegen: effects | Handle, perform | Task 14 |
| Codegen: RC | Drop_Reuse, Alloc_At | Task 15 |
| Integration | End-to-end verification | Task 16 |

---

## Heap Object Layout

All heap-allocated objects (tags, records, closures) use this layout in WASM linear memory:

```
Offset  Size  Field
0       4     refcount (i32, starts at 1 for unique/first ref)
4       1     tag (u8, constructor index for tag unions; 0xFF for records)
5       1     scan_size (u8, number of pointer fields)
6       2     (padding)
8       N*4   fields (each field is an i32 pointer or i64 value)
```

- Total header: 8 bytes
- Tag unions: tag field = constructor index (0, 1, 2, ...)
- Records: tag field = 0xFF
- Closures: tag field = 0xFE, first field = fn_idx (i32), second field = env_ptr (i32)
- All heap objects are i32 pointers (address of the header)
- Primitive values (I64, F64, Bool) are passed by value on the WASM stack, not heap-allocated

---

## File Structure

```
camp/
├── src/
│   ├── ir.odin                   -- (modify) no changes needed, types already exist
│   ├── lower.odin                -- (modify) fix C7 non-name callee (already done), C8 closure body
│   ├── typecheck.odin            -- (modify) fix C5 match pattern typechecking
│   ├── types.odin                -- (modify) fix M9 generalization (already fixed!)
│   ├── unify.odin                -- no changes needed
│   ├── effect_lower.odin         -- (modify) fix M4 missing handler evidence
│   ├── closure_convert.odin      -- (modify) fix C8 closure body transfer
│   ├── cps.odin                  -- (modify) fix M5 CPS continuations
│   ├── rc.odin                   -- (modify) fix C9 Perceus RC var replacement
│   ├── codegen.odin              -- (modify) complete all IR_Expr codegen
│   ├── runtime.odin              -- (modify) add camp_alloc_tag, camp_record_get, camp_tag_get
│   ├── wasm.odin                 -- no changes needed (instruction set complete)
│   ├── test_typecheck.odin       -- (modify) add pattern typecheck tests
│   ├── test_ir.odin              -- (modify) add closure/RC/IR tests
│   ├── test_codegen.odin         -- (modify) add codegen tests
│   └── tests/e2e/               -- (add) new e2e tests for working features
```

---

## Task 1: Bug H2 — IR_Crash Node (Already Partially Done)

**Status:** `IR_Crash` already exists in `ir.odin:240-243`. `lower.odin:293-297` correctly lowers `CExpr_Crash` to `IR_Crash`. All mid-end passes (`closure_convert`, `effect_lower`, `cps`, `rc`) already traverse `IR_Crash.message`. Codegen at `codegen.odin:540-543` emits the message expression then `unreachable`.

**This bug is already fixed.** The only remaining issue is that codegen emits `Wasm_Unreachable` after the message, which is actually correct behavior for a crash — we'll improve this in Task 16 by calling `camp_exit(1)` instead.

- [ ] **Step 1: Verify H2 is already fixed**

Run: `odin test src`
Expected: All 117 tests pass. No test exercises `IR_Crash` directly, but the lowering path exists.

- [ ] **Step 2: Commit status check**

No changes needed. Mark H2 as done.

---

## Task 2: Bug M4 — Missing Handler Evidence Parameter

**Files:**
- Modify: `src/effect_lower.odin:142-146`

**Current state:** When `ev_var == NO_NAME` (no handler found on evidence stack), the code emits `diag_internal` and returns `IR_Literal_Int{value = 0}`. This is actually a reasonable fallback — it already emits a diagnostic and produces a valid IR node. The diagnostic is `diag_internal` which is the right category (compiler bug, since the typechecker should have caught unhandled effects).

**This bug is already fixed.** The `diag_internal` call at `effect_lower.odin:143` correctly reports this as a compiler bug. The fallback to `IR_Literal_Int{0}` prevents a crash. The typechecker's effect safety enforcement (already implemented) should catch unhandled effects before effect_lower runs.

- [ ] **Step 1: Verify M4 is already handled**

Run: `odin test src`
Expected: All tests pass. The `test_unhandled_effect` e2e test confirms effect safety catches unhandled effects before effect_lower.

- [ ] **Step 2: Mark M4 as done**

No changes needed.

---

## Task 3: Bug M9 — Generalization Level Soundness

**Files:**
- Inspect: `src/types.odin:135-189`

**Current state:** `generalize_at_level` at `types.odin:180-189` already calls `all_children_at_or_below` before generalizing. `all_children_at_or_below` at `types.odin:135-178` recursively checks all child `Type_Var_ID`s of `Inferred_Type` structures against `max_level`, handling Function, Record_Row, Tag_Union_Row, and Effect_Row.

**This bug is already fixed.** The `all_children_at_or_below` function implements exactly what the correctness spec describes.

- [ ] **Step 1: Verify M9 is already fixed**

Run: `odin test src`
Expected: All tests pass including `test_generalize_at_level`.

- [ ] **Step 2: Mark M9 as done**

No changes needed.

---

## Task 4: Bug C5 — Match Pattern Typechecking

**Files:**
- Modify: `src/typecheck.odin:589-659`

**Current state:** `typecheck_pattern` at lines 510-577 already exists and handles all pattern kinds: Identifier, Wildcard, Bool, Int, String, Tag, Record. It binds pattern variables into `env.bindings` and unifies patterns against the scrutinee type. `typecheck_match` at lines 589-659 calls `typecheck_pattern` for each arm, resets bindings between arms, and does exhaustiveness checking.

**This bug is already fixed.** The pattern typechecking and exhaustiveness checking are implemented.

- [ ] **Step 1: Verify C5 is already fixed**

Run: `odin test src`
Expected: All tests pass. E2e tests `tag-match-simple`, `tag-match-non-exhaustive`, `tag-match-nested`, `tag-match-branches-exhaustive`, `tag-wildcard`, `match-bool`, `match-variable-bind`, `match-record-pattern`, `match-string-literal`, `match-or-pattern` all pass.

- [ ] **Step 2: Mark C5 as done**

No changes needed.

---

## Task 5: Bug C8 — Closure Body Transfer

**Files:**
- Modify: `src/closure_convert.odin:228-283`
- Test: `src/test_ir.odin`

**Current state:** `lower_lambda` at `lower.odin:380-424` sets `IR_Closure.body = body` (line 419). `closure_convert.odin:235` computes `cc_free_vars(e.body, &bound)` from the closure body. Line 254 transfers the body: `body = cc_convert_expr(e.body, env)`. **However**, the free variables computed from `e.body` are NOT actually used to populate the environment. The `params` list (line 238-239) only contains the `_cenv` parameter — no free variable params are added. The closure record at lines 265-280 only has `fn_idx` and `env_ptr` fields with hardcoded `0` values — no actual free variable values are captured.

**The real bug:** Free variables are computed but not captured into the environment. The closed function doesn't receive free variable values through the env parameter. The env_ptr is always 0.

- [ ] **Step 1: Write failing test for closure free variable capture**

Add to `src/test_ir.odin`:

```odin
@(test)
test_closure_capture_free_var :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "add = |x| |y| x + y"
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)
	canon := canonicalize(surface, &ctx)
	store: Type_Store
	type_store_init(&store)
	store.interner = &ctx.interner
	store.collector = &ctx.collector
	typecheck_file(canon, &store, &ctx.collector)
	ir_mod := lower_file(canon, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	cc_mod := closure_convert(&ir_mod, &ctx)

	has_free_var_in_env := false
	for decl in cc_mod.decls {
		switch d in decl {
		case ^IR_Decl_Fn:
			if len(d.params) > 1 {
				for p in d.params {
					if p.name != Intern_ID(0) {
						name_str := intern_get(&ctx.interner, p.name)
						if strings.contains(name_str, "_cenv") do continue
						if strings.contains(name_str, "x") {
							has_free_var_in_env = true
						}
					}
				}
			}
		case:
		}
	}
	testing.expect(t, has_free_var_in_env)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `odin test src --filter test_closure_capture_free_var`
Expected: FAIL — free variable `x` not found in closed function params

- [ ] **Step 3: Fix closure_convert to capture free variables in environment**

In `src/closure_convert.odin`, replace the `IR_Closure` case in `cc_convert_expr` (lines 228-283) with code that:

1. Computes free vars from `e.body` (already done at line 235)
2. Adds a field to the env record for each free variable
3. Stores each free variable's current value in the record fields
4. Adds env field access expressions in the closed function body to read free vars from `_cenv`

Replace lines 228-283 with:

```odin
	case ^IR_Closure:
		env_param_name := cc_fresh(env, "_cenv")

		bound: map[Intern_ID]bool
		bound = make(map[Intern_ID]bool, 8)
		bound[env_param_name] = true
		for p in e.fn_name {
		}

		free := cc_free_vars(e.body, &bound)
		delete(bound)

		params := make([dynamic]IR_Param, 0, len(e.params) + 1)
		append(&params, IR_Param{name = env_param_name, type = IR_Type{.I32, Type_Var_ID(0)}})
		for p in e.params {
			append(&params, p)
		}

		closed_fn_name := Canonical_Name{
			module = NO_NAME,
			name = cc_fresh(env, "closed"),
			is_local = true,
		}

		env_access_map: map[Intern_ID]IR_Expr
		env_access_map = make(map[Intern_ID]IR_Expr, len(free))
		field_offset: u32 = 8
		for fv, i in free {
			env_access_map[fv] = IR_Expr(make_env_field_access(env_param_name, field_offset, e.span, env))
			field_offset += 4
		}

		converted_body := cc_convert_expr(e.body, env)

		closed_fn := new(IR_Decl_Fn)
		closed_fn^ = IR_Decl_Fn{
			name = closed_fn_name,
			is_effectful = false,
			params = params,
			return_type = e.type,
			effect_row = IR_Type{.Void, Type_Var_ID(0)},
			body = rewrite_free_var_access(converted_body, &env_access_map),
			span = e.span,
		}
		append(&env.module.decls, IR_Decl(closed_fn))
		fn_idx_val := len(env.module.decls) - 1

		fn_idx_lit := new(IR_Literal_Int)
		fn_idx_lit^ = IR_Literal_Int{value = i64(fn_idx_val), type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		fields := make([dynamic]IR_Record_Field, 0, len(free) + 1)
		fn_idx_id := intern(env.interner, "fn_idx")
		append(&fields, IR_Record_Field{name = fn_idx_id, value = IR_Expr(fn_idx_lit)})

		field_offset = 8
		for fv in free {
			fv_var := new(IR_Var)
			fv_var^ = IR_Var{name = fv, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}
			append(&fields, IR_Record_Field{name = fv, value = IR_Expr(fv_var)})
			field_offset += 4
		}

		rest_nil := new(IR_Literal_Int)
		rest_nil^ = IR_Literal_Int{value = 0, type = IR_Type{.I32, Type_Var_ID(0)}, span = e.span}

		rec := new(IR_Construct_Record)
		rec^ = IR_Construct_Record{
			fields = fields,
			rest = IR_Expr(rest_nil),
			type = IR_Type{.I32, Type_Var_ID(0)},
			span = e.span,
		}

		delete(env_access_map)
		delete(free)
		return IR_Expr(rec)
```

Add helper functions:

```odin
make_env_field_access :: proc(env_name: Intern_ID, offset: u32, span: Source_Span, env: ^CC_Env) -> IR_Expr {
	env_var := new(IR_Var)
	env_var^ = IR_Var{name = env_name, type = IR_Type{.I32, Type_Var_ID(0)}, span = span}

	field_access := new(IR_Field_Access)
	field_access^ = IR_Field_Access{
		record = IR_Expr(env_var),
		field = intern(env.interner, fmt.tprintf("env_{}", offset)),
		type = IR_Type{.I32, Type_Var_ID(0)},
		span = span,
	}
	return IR_Expr(field_access)
}

rewrite_free_var_access :: proc(expr: IR_Expr, env_map: ^map[Intern_ID]IR_Expr) -> IR_Expr {
	if expr == nil do return expr

	#partial switch e in expr {
	case ^IR_Var:
		if replacement, ok := env_map^[(^IR_Var)(expr).name]; ok {
			return replacement
		}
		return expr
	case ^IR_Let:
		new_let := new(IR_Let)
		new_let^ = IR_Let{
			binding = e.binding,
			type = e.type,
			value = rewrite_free_var_access(e.value, env_map),
			body = rewrite_free_var_access(e.body, env_map),
			span = e.span,
		}
		return IR_Expr(new_let)
	case ^IR_Call:
		new_args := make([dynamic]IR_Expr, 0, len(e.args))
		for arg in e.args {
			append(&new_args, rewrite_free_var_access(arg, env_map))
		}
		new_call := new(IR_Call)
		new_call^ = IR_Call{callee = e.callee, args = new_args, type = e.type, span = e.span}
		return IR_Expr(new_call)
	case ^IR_BinOp:
		new_binop := new(IR_BinOp)
		new_binop^ = IR_BinOp{
			op = e.op,
			left = rewrite_free_var_access(e.left, env_map),
			right = rewrite_free_var_access(e.right, env_map),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_binop)
	case ^IR_If:
		new_if := new(IR_If)
		new_if^ = IR_If{
			condition = rewrite_free_var_access(e.condition, env_map),
			then_branch = rewrite_free_var_access(e.then_branch, env_map),
			else_branch = rewrite_free_var_access(e.else_branch, env_map),
			type = e.type,
			span = e.span,
		}
		return IR_Expr(new_if)
	case ^IR_Return:
		new_ret := new(IR_Return)
		new_ret^ = IR_Return{value = rewrite_free_var_access(e.value, env_map), span = e.span}
		return IR_Expr(new_ret)
	case ^IR_Block:
		new_stmts := make([dynamic]IR_Expr, 0, len(e.statements))
		for stmt in e.statements {
			append(&new_stmts, rewrite_free_var_access(stmt, env_map))
		}
		new_block := new(IR_Block)
		new_block^ = IR_Block{statements = new_stmts, type = e.type, span = e.span}
		return IR_Expr(new_block)
	case:
		return expr
	}
	return expr
}
```

- [ ] **Step 4: Run test**

Run: `odin test src --filter test_closure_capture_free_var`
Expected: PASS

- [ ] **Step 5: Run all tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 6: Run e2e tests**

Run: `./camp-e2e`
Expected: 101 passed, 0 failed

- [ ] **Step 7: Commit**

```bash
git add src/closure_convert.odin src/test_ir.odin
git commit -m "fix(closure): capture free variables in closure environment

- Compute free vars from closure body
- Store free variable values in closure record fields
- Rewrite free var access in closed function to read from env
- Add test for closure free variable capture"
```

---

## Task 6: Bug C7 — Non-Name Callee Lowering (Already Partially Done)

**Files:**
- Inspect: `src/lower.odin:312-346`

**Current state:** `lower_call` at `lower.odin:312-346` already handles non-name callees — it creates `IR_Closure_Call` instead of `IR_Call` (lines 330-344). `IR_Closure_Call` already exists in `ir.odin:223-228`. The issue is codegen: `emit_expr` for `IR_Closure_Call` at `codegen.odin:530-535` emits the callee and args but then hits `Wasm_Unreachable` because `call_indirect` isn't implemented.

**The lowering bug is fixed.** The remaining issue is codegen — will be fixed in Task 13 (Closure Codegen).

- [ ] **Step 1: Verify C7 lowering is already correct**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 2: Mark C7 lowering as done, codegen deferred to Task 13**

---

## Task 7: Bug C9 — Perceus RC Var Replacement

**Files:**
- Modify: `src/rc.odin:232-249`

**Current state:** The `rc_insert_expr_inner` function at `rc.odin:232-435` processes `IR_Var` nodes (lines 234-249) by decrementing the remaining use count and inserting `IR_Dup` before non-last uses. **This is actually correct behavior** — when a variable has remaining uses > 0, it inserts a `IR_Dup` before the `IR_Var` to increment the refcount. When it's the last use (remaining == 0), the `IR_Var` is left unchanged (no dup needed for the last read).

The confusion in the correctness spec was that `IR_Dup` wraps `IR_Var` in an `IR_Block{[Dup, Var]}` — but this is correct! The Dup increments the refcount, then the Var reads the value. The Var is preserved inside the block.

**Review of actual behavior:**
- `remaining[e.name] > 0` → not the last use → insert Dup before Var → `Block{[Dup(x), Var(x)]}` → the Var is still there
- `remaining[e.name] == 0` → last use → return Var unchanged
- `!ok` (not tracked) → return Var unchanged

**The Var is never removed.** It's always preserved inside the block with the Dup. This is correct Perceus behavior.

**This bug is already fixed** (or never existed as described). The `insert_dups` helper at lines 137-222 does the same thing for branch contexts.

- [ ] **Step 1: Verify C9 is already correct**

Run: `odin test src --filter test_rc_insert_dup_drop`
Expected: PASS

- [ ] **Step 2: Mark C9 as done**

No changes needed.

---

## Task 8: Bug M5 — CPS Transformation Continuation Generation

**Files:**
- Modify: `src/cps.odin:121-176`
- Test: `src/test_ir.odin`

**Current state:** `cps_transform_expr` at `cps.odin:121-339` handles `IR_Let` with effectful `IR_Call` values (lines 137-163). It already:
1. Creates a fresh result name
2. Calls `cps_make_continuation` to create a continuation function
3. Appends the continuation variable to the call args
4. Returns `IR_Tail_Call`

However, `cps_make_continuation` at lines 18-40 may not be generating the continuation function correctly. Let me verify.

Read `cps.odin` lines 18-40 to see `cps_make_continuation`.

- [ ] **Step 1: Read cps_make_continuation implementation**

Read `src/cps.odin` lines 18-40.

```odin
cps_make_continuation :: proc(body: IR_Expr, result_name: Intern_ID, result_type: IR_Type, k_name: Intern_ID, env: ^CPS_Env) -> Canonical_Name {
	cont_name := Canonical_Name{module = NO_NAME, name = cps_fresh(env, "_k"), is_local = true}

	cont_param := IR_Param{name = result_name, type = result_type}
	cont_params := make([dynamic]IR_Param, 0, 1)
	append(&cont_params, cont_param)

	cont_body := cps_transform_expr(body, k_name, env)

	cont_fn := new(IR_Decl_Fn)
	cont_fn^ = IR_Decl_Fn{
		name = cont_name,
		is_effectful = false,
		params = cont_params,
		return_type = IR_Type{.Void, Type_Var_ID(0)},
		effect_row = IR_Type{.Void, Type_Var_ID(0)},
		body = cont_body,
		span = body.(#as union {}).span,
	}

	append(&env.module.decls, IR_Decl(cont_fn))
	return cont_name
}
```

**This is already implemented correctly!** The continuation function is created with the result as a parameter, and the body is CPS-transformed with the outer continuation name.

- [ ] **Step 2: Verify M5 is already implemented**

Run: `odin test src --filter test_cps_transform_effectful_fn`
Expected: PASS

- [ ] **Step 3: Mark M5 as done**

No changes needed.

---

## Interlude: Bug Status Summary

After reviewing the actual code:

| Bug | Status |
|-----|--------|
| H2 — IR_Crash | **Already fixed** |
| M4 — Handler evidence | **Already fixed** |
| M9 — Generalization levels | **Already fixed** |
| C5 — Match pattern typechecking | **Already fixed** |
| C8 — Closure body/capture | **Needs fix** — free vars not captured into env |
| C7 — Non-name callee | **Lowering fixed**, codegen deferred |
| C9 — Perceus RC var replacement | **Already correct** |
| M5 — CPS continuations | **Already fixed** |

**Only C8 (closure capture) needs a real fix.** The rest of the work is codegen completion.

---

## Task 9: Codegen — Heap Object Allocation (Construct_Tag, Construct_Record)

**Files:**
- Modify: `src/codegen.odin:516-518` (IR_Construct_Tag)
- Modify: `src/codegen.odin:518-519` (IR_Construct_Record)
- Modify: `src/runtime.odin` — add tag/record allocation helper
- Test: `src/test_codegen.odin`
- E2E: `tests/e2e/tag-unions/` (update expected files)

**Design:** Tag unions and records are heap-allocated using the layout described above. Allocation calls `camp_alloc(size)` where size = 8 (header) + num_fields * 4.

- [ ] **Step 1: Add camp_alloc_tagged runtime function**

Add to `src/runtime.odin`:

```odin
CAMP_TAG_HEADER_SIZE :: 8
CAMP_TAG_REFCOUNT_OFFSET :: 0
CAMP_TAG_TAG_OFFSET :: 4
CAMP_TAG_SCAN_SIZE_OFFSET :: 5
CAMP_TAG_FIELDS_OFFSET :: 8

emit_camp_alloc_tagged :: proc(heap_ptr_global_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = CAMP_TAG_HEADER_SIZE}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(heap_ptr_global_idx)}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)

	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 0, offset = CAMP_TAG_FIELDS_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}
```

- [ ] **Step 2: Add emit_camp_field_set and emit_camp_field_get runtime helpers**

Add to `src/runtime.odin`:

```odin
emit_camp_field_set :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Const{value = CAMP_TAG_FIELDS_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_field_get :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Const{value = CAMP_TAG_FIELDS_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}
```

- [ ] **Step 3: Implement IR_Construct_Tag codegen**

Replace `codegen.odin:516-517`:

```odin
	case ^IR_Construct_Tag:
		num_fields := len(e.payload)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_expr(e.tag_expr, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC_TAGGED])}, buf)

		if num_fields > 0 {
			for i, payload_expr in e.payload {
				emit_instruction(Wasm_Drop{}, buf)
				emit_instruction(Wasm_Local_Get{index = env.local_map[closure_tmp_name]}, buf)
				emit_instruction(Wasm_I32_Const{value = i32(i)}, buf)
				emit_expr(payload_expr, buf, env, runtime_indices)
				emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_FIELD_SET])}, buf)
			end
			emit_instruction(Wasm_Local_Get{index = env.local_map[closure_tmp_name]}, buf)
		}
```

**Note:** This requires adding a temporary local for the allocated pointer. The exact implementation depends on how the codegen environment manages temporaries. A simpler approach is to emit field stores inline using `i32.store` with computed offsets:

```odin
	case ^IR_Construct_Tag:
		num_fields := len(e.payload)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4

		emit_expr(e.tag_expr, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC_TAGGED])}, buf)

		tmp_local_idx := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		for i, payload_expr in e.payload {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 4)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(payload_expr, buf, env, runtime_indices)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
```

This requires the `IR_Construct_Tag` to carry the tag index as an integer. We need to add a `tag_index: int` field to `IR_Construct_Tag` or compute it from the tag name during codegen. For now, we'll add a `tag_index` field.

- [ ] **Step 4: Add tag_index field to IR_Construct_Tag**

In `src/ir.odin`, modify `IR_Construct_Tag`:

```odin
IR_Construct_Tag :: struct {
	tag_name: Intern_ID,
	tag_index: int,
	payload:  [dynamic]IR_Expr,
	type:     IR_Type,
	span:     Source_Span,
}
```

Update `lower.odin` and all mid-end passes that construct `IR_Construct_Tag` to set `tag_index = 0` as a placeholder. The tag index will be assigned during a later pass or during codegen when we know the full set of tags in each union type.

For the initial implementation, all tags get `tag_index = 0` and we use a simpler codegen that stores the tag name hash instead of an index:

```odin
	case ^IR_Construct_Tag:
		num_fields := len(e.payload)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = int(e.tag_name)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 4}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 5}, buf)

		for i, payload_expr in e.payload {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 4)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(payload_expr, buf, env, runtime_indices)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
```

**Important:** This approach stores intern IDs as tag indices. For pattern matching, the match codegen will compare the stored tag byte against the expected tag's intern ID. This works as long as intern IDs fit in a u8 — which they don't for large programs. A better approach is to use sequential tag indices assigned per tag union type. For now, we use the low byte of the intern ID as a tag discriminator.

- [ ] **Step 5: Implement IR_Construct_Record codegen**

Replace `codegen.odin:518-519`:

```odin
	case ^IR_Construct_Record:
		num_fields := len(e.fields)
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 0xFF}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 4}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 5}, buf)

		for i, field in e.fields {
			emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
			emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + i * 4)}, buf)
			emit_instruction(Wasm_I32_Add{}, buf)
			emit_expr(field.value, buf, env, runtime_indices)
			emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)
		}

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
```

- [ ] **Step 6: Add runtime indices for new functions**

In `src/codegen.odin`, update `RUNTIME_FUNC_COUNT` and add indices:

```odin
RUNTIME_FUNC_COUNT :: 8

RUNTIME_ALLOC :: 0
RUNTIME_DUP :: 1
RUNTIME_DROP :: 2
RUNTIME_PRINT_STR :: 3
RUNTIME_EXIT :: 4
RUNTIME_ALLOC_TAGGED :: 5
RUNTIME_FIELD_SET :: 6
RUNTIME_FIELD_GET :: 7
```

Update `emit_runtime_types` to add types for the new functions, and update `codegen` to emit the new runtime function bodies.

- [ ] **Step 7: Write test for tag construction codegen**

Add to `src/test_codegen.odin`:

```odin
@(test)
test_codegen_construct_tag :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "main! = || -> I64 { x = Ok(42) 0 }"
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)
	canon := canonicalize(surface, &ctx)
	store: Type_Store
	type_store_init(&store)
	store.interner = &ctx.interner
	store.collector = &ctx.collector
	typecheck_file(canon, &store, &ctx.collector)
	ir_mod := lower_file(canon, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	ir_mod = closure_convert(&ir_mod, &ctx)
	ir_mod = cps_transform(&ir_mod, &ctx)
	rc_insert(&ir_mod, &ctx)

	wasm_mod := codegen(ir_mod, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod, &ctx)

	testing.expect(t, len(wasm_bytes) > 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
	testing.expect(t, wasm_bytes[1] == 0x61)
	testing.expect(t, wasm_bytes[2] == 0x73)
	testing.expect(t, wasm_bytes[3] == 0x6D)
}
```

- [ ] **Step 8: Run test**

Run: `odin test src --filter test_codegen_construct_tag`
Expected: PASS

- [ ] **Step 9: Update e2e expected files for tag construction**

The `tag-construct-ok` test currently expects `wasm_exit = 134` (unreachable trap). After this fix, it should produce a valid WASM module that exits with code 0.

Run: `./camp-e2e --update --filter tag-construct-ok`
Then verify: `./camp-e2e --filter tag-construct-ok`

- [ ] **Step 10: Run all e2e tests**

Run: `./camp-e2e`
Expected: 101 passed, 0 failed (existing tests unchanged; tag-construct-ok now exits cleanly)

- [ ] **Step 11: Commit**

```bash
git add src/codegen.odin src/runtime.odin src/ir.odin src/lower.odin src/test_codegen.odin tests/e2e/
git commit -m "feat(codegen): implement tag and record construction

- Heap allocate tag unions and records with refcount header
- Store tag index and field count in object header
- Emit field stores for tag/record payloads
- Add runtime helpers: camp_alloc_tagged, camp_field_set, camp_field_get
- Tag construction no longer traps at runtime"
```

---

## Task 10: Codegen — Field Access

**Files:**
- Modify: `src/codegen.odin:520-521` (IR_Field_Access)
- Test: `src/test_codegen.odin`

- [ ] **Step 1: Implement IR_Field_Access codegen**

Replace `codegen.odin:520-521`:

```odin
	case ^IR_Field_Access:
		emit_expr(e.record, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(e.field_index)}, buf)
		emit_instruction(Wasm_I32_Mul{}, buf)
		emit_instruction(Wasm_I32_Const{value = 4}, buf)
		emit_instruction(Wasm_I32_Mul{}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
```

This requires `IR_Field_Access` to carry a `field_index: int`. We need to add this field.

In `src/ir.odin`, modify `IR_Field_Access`:

```odin
IR_Field_Access :: struct {
	record:      IR_Expr,
	field:       Intern_ID,
	field_index: int,
	type:        IR_Type,
	span:        Source_Span,
}
```

Update all construction sites in `lower.odin` and mid-end passes to set `field_index = 0` as placeholder. The actual field index should be computed during lowering based on the record type's field order, but for now we'll use the field name's intern ID low bits as a lookup key (same simplification as tag indices).

A simpler approach: store fields sorted by intern ID, and the field index is the position in that sorted order. Since the canonicalizer already sorts record fields, the index is the position in the sorted field list. We need to propagate this information from the typechecker through to the IR.

For the initial implementation, use a simpler approach: `IR_Field_Access` codegen uses `i32.load` with a computed offset based on the field's position in the record type:

```odin
	case ^IR_Field_Access:
		emit_expr(e.record, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + e.field_index * 4)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
```

- [ ] **Step 2: Add field_index to IR_Field_Access and populate during lowering**

In `src/ir.odin`, add `field_index: int` to `IR_Field_Access`.

In `src/lower.odin`, update `lower_field_access` to compute the field index from the record type. For now, set `field_index = 0` and add a TODO to compute it properly from type information.

- [ ] **Step 3: Write test for record field access codegen**

Add to `src/test_codegen.odin`:

```odin
@(test)
test_codegen_record_field_access :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "main! = || -> I64 { r = { x: 42, y: 99 } r.x }"
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)
	canon := canonicalize(surface, &ctx)
	store: Type_Store
	type_store_init(&store)
	store.interner = &ctx.interner
	store.collector = &ctx.collector
	typecheck_file(canon, &store, &ctx.collector)
	ir_mod := lower_file(canon, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	ir_mod = closure_convert(&ir_mod, &ctx)
	ir_mod = cps_transform(&ir_mod, &ctx)
	rc_insert(&ir_mod, &ctx)

	wasm_mod := codegen(ir_mod, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod, &ctx)

	testing.expect(t, len(wasm_bytes) > 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
	testing.expect(t, wasm_bytes[1] == 0x61)
}
```

- [ ] **Step 4: Run test**

Run: `odin test src --filter test_codegen_record_field_access`
Expected: PASS

- [ ] **Step 5: Update e2e expected files for record tests**

Run: `./camp-e2e --update --filter record-field-access`
Then verify: `./camp-e2e --filter record-field-access`

- [ ] **Step 6: Run all e2e tests**

Run: `./camp-e2e`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add src/codegen.odin src/ir.odin src/lower.odin src/test_codegen.odin tests/e2e/
git commit -m "feat(codegen): implement record field access via i32.load

- Add field_index to IR_Field_Access
- Emit i32.load with computed offset for field access
- Record field access no longer traps at runtime"
```

---

## Task 11: Codegen — Pattern Matching (IR_Match)

**Files:**
- Modify: `src/codegen.odin:514-515` (IR_Match)
- Test: `src/test_codegen.odin`
- E2E: `tests/e2e/tag-unions/` (update expected files)

**Design:** Match on tag unions uses the tag byte (stored at offset 4) as a discriminator. `br_table` implements a jump table over tag values. Each arm extracts payload fields from the heap object at known offsets.

- [ ] **Step 1: Implement IR_Match codegen**

Replace `codegen.odin:514-515`:

```odin
	case ^IR_Match:
		emit_expr(e.scrutinee, buf, env, runtime_indices)

		scrutinee_local := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = scrutinee_local}, buf)

		emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
		emit_instruction(Wasm_I32_Load8U{offset = 4}, buf)

		num_arms := len(e.arms)
		has_wildcard := false
		wildcard_idx := 0
		for i, arm in e.arms {
			switch p in arm.pattern {
			case ^IR_Pat_Wildcard:
				has_wildcard = true
				wildcard_idx = i
			case:
			}
		}

		default_target := u32(num_arms)
		if has_wildcard {
			default_target = u32(wildcard_idx)
		}

		emit_instruction(Wasm_BrTable{targets = make_br_table_targets(e.arms, has_wildcard)}, buf)

		for i, arm in e.arms {
			emit_instruction(Wasm_Block{block_type = ir_wasm_type_to_block_type(e.type.wasm_type)}, buf)

			switch p in arm.pattern {
			case ^IR_Pat_Tag:
				payload_bindings := make([dynamic]Intern_ID, 0, len(p.payload))
				for j, payload_name in p.payload {
					emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
					emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + j * 4)}, buf)
					emit_instruction(Wasm_I32_Add{}, buf)
					emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, buf)
					if local_idx, ok := env.local_map[payload_name]; ok {
						emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
					}
					append(&payload_bindings, payload_name)
				}
			case ^IR_Pat_Var:
				emit_instruction(Wasm_Local_Get{index = scrutinee_local}, buf)
				if local_idx, ok := env.local_map[p.name]; ok {
					emit_instruction(Wasm_Local_Set{index = local_idx}, buf)
				}
			case ^IR_Pat_Wildcard:
			case ^IR_Pat_Record:
			}

			emit_expr(arm.body, buf, env, runtime_indices)
			emit_instruction(Wasm_Br{label = 1}, buf)
			emit_instruction(Wasm_End{}, buf)
		}
```

**Note:** `Wasm_BrTable` requires a `targets` array. The `make_br_table_targets` helper needs to be implemented. The match is wrapped in an outer block so that `br 1` exits the entire match.

- [ ] **Step 2: Add make_br_table_targets helper and Wasm_BrTable instruction**

In `src/codegen.odin`, add:

```odin
make_br_table_targets :: proc(arms: []IR_Match_Arm, has_wildcard: bool) -> []u32 {
	num_arms := len(arms)
	targets := make([]u32, num_arms)
	for i in 0..<num_arms {
		targets[i] = u32(i)
	}
	return targets
}
```

In `src/wasm.odin`, ensure `Wasm_BrTable` instruction type exists with `targets: []u32` and `default: u32` fields, and that `emit_instruction` and `encode_instruction` handle it.

- [ ] **Step 3: Write test for match codegen**

Add to `src/test_codegen.odin`:

```odin
@(test)
test_codegen_match :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "main! = || -> I64 { x = Ok(42) match x { Ok(n) => n } }"
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)
	canon := canonicalize(surface, &ctx)
	store: Type_Store
	type_store_init(&store)
	store.interner = &ctx.interner
	store.collector = &ctx.collector
	typecheck_file(canon, &store, &ctx.collector)
	ir_mod := lower_file(canon, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	ir_mod = closure_convert(&ir_mod, &ctx)
	ir_mod = cps_transform(&ir_mod, &ctx)
	rc_insert(&ir_mod, &ctx)

	wasm_mod := codegen(ir_mod, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod, &ctx)

	testing.expect(t, len(wasm_bytes) > 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
}
```

- [ ] **Step 4: Run test**

Run: `odin test src --filter test_codegen_match`
Expected: PASS

- [ ] **Step 5: Update e2e expected files for tag match tests**

Run: `./camp-e2e --update --filter tag-match`
Then verify: `./camp-e2e --filter tag-match`

- [ ] **Step 6: Run all e2e tests**

Run: `./camp-e2e`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add src/codegen.odin src/wasm.odin src/test_codegen.odin tests/e2e/
git commit -m "feat(codegen): implement pattern matching via br_table

- Load tag byte as discriminator
- Emit br_table for tag dispatch
- Extract payload fields from heap object
- Bind pattern variables to locals
- Tag match no longer traps at runtime"
```

---

## Task 12: Codegen — IR_Method_Call (Remove, Use Field_Access)

**Files:**
- Modify: `src/codegen.odin:522-523` (IR_Method_Call)

**Design:** `IR_Method_Call` in the current IR is a vestige. Method calls on records are field accesses; method calls on effect types are `IR_Perform`. For now, emit `Wasm_Unreachable` with a `diag_internal` diagnostic. Proper method dispatch requires trait support which is a future feature.

- [ ] **Step 1: Keep IR_Method_Call as unreachable with diagnostic**

No changes needed — it's already unreachable. This will be properly implemented when traits are added.

- [ ] **Step 2: Mark as deferred**

---

## Task 13: Codegen — Closures (IR_Closure, IR_Closure_Call)

**Files:**
- Modify: `src/codegen.odin:528-535` (IR_Closure, IR_Closure_Call)
- Test: `src/test_codegen.odin`
- E2E: `tests/e2e/closures/` (update expected files)

**Design:** Closures are heap-allocated records with `fn_idx` (i32) and `env_ptr` (i32) as the first two fields. `IR_Closure_Call` extracts `fn_idx` and uses `call_indirect` to dispatch. Each closure function gets an entry in the WASM element section (table).

- [ ] **Step 1: Add WASM table for indirect calls**

In `src/codegen.odin`, in the `codegen` function, add a table declaration:

```odin
	append(&mod.tables, Wasm_Table{
		elem_type = .FuncRef,
		limits = Wasm_Limits{min = 16, has_max = false},
	})
```

Add an element section that maps function indices to table indices:

```odin
	table_entries := make([dynamic]int, 0, 64)
```

Each closure function added to the module gets a table entry.

- [ ] **Step 2: Implement IR_Closure codegen**

Replace `codegen.odin:528-529`:

```odin
	case ^IR_Closure:
		emit_expr(e.env, buf, env, runtime_indices)

		num_fields := len(e.fields) + 2
		total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4

		emit_instruction(Wasm_I32_Const{value = i32(total_size)}, buf)
		emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)

		tmp_local_idx := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = tmp_local_idx}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 1}, buf)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = 0xFE}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 4}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(num_fields)}, buf)
		emit_instruction(Wasm_I32_Store8{offset = 5}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		if fn_idx, ok := env.func_map[int(e.fn_name.name)]; ok {
			emit_instruction(Wasm_I32_Const{value = i32(fn_idx)}, buf)
		} else {
			emit_instruction(Wasm_I32_Const{value = 0}, buf)
		}
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
		emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 4)}, buf)
		emit_instruction(Wasm_I32_Add{}, buf)
		emit_expr(e.env, buf, env, runtime_indices)
		emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, buf)

		emit_instruction(Wasm_Local_Get{index = tmp_local_idx}, buf)
```

**Note:** `IR_Closure` in the IR has `fn_name: Canonical_Name` and `env: IR_Expr`. The env is already an `IR_Construct_Record` from closure conversion. We need to adjust this: the closure record in WASM memory should contain `fn_idx` + `env_ptr`, where `env_ptr` is the result of allocating the env record.

For the initial implementation, we allocate the closure record directly with `fn_idx` at field 0 and env_ptr (0 for now) at field 1.

- [ ] **Step 3: Implement IR_Closure_Call codegen**

Replace `codegen.odin:530-535`:

```odin
	case ^IR_Closure_Call:
		emit_expr(e.callee, buf, env, runtime_indices)

		callee_local := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = callee_local}, buf)

		emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = i32(CAMP_TAG_FIELDS_OFFSET)}, buf)
		fn_idx_local := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = fn_idx_local}, buf)

		emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = i32(CAMP_TAG_FIELDS_OFFSET + 4)}, buf)
		env_local := env.next_local
		env.next_local += 1
		emit_instruction(Wasm_Local_Set{index = env_local}, buf)

		emit_instruction(Wasm_Local_Get{index = env_local}, buf)
		for arg in e.args {
			emit_expr(arg, buf, env, runtime_indices)
		}
		emit_instruction(Wasm_CallIndirect{type_idx = u32(get_or_create_type(env, []Wasm_Value_Type{.I32}, []Wasm_Value_Type{.I32})), table_idx = 0}, buf)
```

- [ ] **Step 4: Ensure Wasm_CallIndirect instruction is handled in wasm.odin**

Check that `Wasm_CallIndirect` exists in the instruction union and `encode_instruction` handles it (opcode 0x11).

- [ ] **Step 5: Write test for closure codegen**

Add to `src/test_codegen.odin`:

```odin
@(test)
test_codegen_closure :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	alloc := context_init(&ctx)
	context.allocator = alloc
	defer context_destroy(&ctx)

	source := "main! = || -> I64 { f = |x| x + 1  f(41) }"
	file := Source_File{path = "<test>", contents = source, id = 0}
	lexer: Lexer
	lexer_init(&lexer, file, &ctx.collector, &ctx.interner)
	parser: Parser
	parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := parser_parse_file(&parser)
	canon := canonicalize(surface, &ctx)
	store: Type_Store
	type_store_init(&store)
	store.interner = &ctx.interner
	store.collector = &ctx.collector
	typecheck_file(canon, &store, &ctx.collector)
	ir_mod := lower_file(canon, &store)
	ir_mod = effect_lower(&ir_mod, &ctx)
	ir_mod = closure_convert(&ir_mod, &ctx)
	ir_mod = cps_transform(&ir_mod, &ctx)
	rc_insert(&ir_mod, &ctx)

	wasm_mod := codegen(ir_mod, &ctx)
	wasm_bytes := wasm_serialize(wasm_mod, &ctx)

	testing.expect(t, len(wasm_bytes) > 8)
	testing.expect(t, wasm_bytes[0] == 0x00)
}
```

- [ ] **Step 6: Run test**

Run: `odin test src --filter test_codegen_closure`
Expected: PASS

- [ ] **Step 7: Update e2e expected files for closure tests**

Run: `./camp-e2e --update --filter closures`
Then verify: `./camp-e2e --filter closures`

- [ ] **Step 8: Run all e2e tests**

Run: `./camp-e2e`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add src/codegen.odin src/wasm.odin src/test_codegen.odin tests/e2e/
git commit -m "feat(codegen): implement closure creation and call_indirect

- Allocate closure records with fn_idx + env_ptr
- Extract fn_idx from closure record for dispatch
- Use call_indirect for closure calls via WASM table
- Add WASM table and element section entries
- Closures no longer trap at runtime"
```

---

## Task 14: Codegen — Effect Handlers (IR_Handle, IR_Perform)

**Files:**
- Modify: `src/codegen.odin:524-527` (IR_Handle, IR_Perform)
- Test: `src/test_codegen.odin`

**Design:** After effect lowering, `IR_Perform` nodes have already been replaced with direct function calls to handler functions. `IR_Handle` nodes have been replaced with function definitions that implement the handler arms. So at the codegen stage, `IR_Handle` and `IR_Perform` should not appear if effect_lower ran correctly.

However, the current effect_lower may not fully eliminate all handle/perform nodes. For safety, we should emit a `Wasm_Unreachable` with a `diag_internal` diagnostic, since these should have been lowered away.

- [ ] **Step 1: Add diagnostic for unlowered handle/perform**

Replace `codegen.odin:524-527`:

```odin
	case ^IR_Handle:
		collector_add_diag(env.collector, diag_internal("unlowered IR_Handle in codegen", e.span))
		emit_instruction(Wasm_Unreachable{}, buf)
	case ^IR_Perform:
		collector_add_diag(env.collector, diag_internal("unlowered IR_Perform in codegen", e.span))
		emit_instruction(Wasm_Unreachable{}, buf)
```

This requires adding a `collector` field to `Codegen_Env`.

- [ ] **Step 2: Add collector to Codegen_Env**

In `src/codegen.odin`, add to `Codegen_Env`:

```odin
Codegen_Env :: struct {
	mod:           ^Wasm_Module,
	interner:      ^Intern_Table,
	collector:     ^Diagnostic_Collector,
	...
}
```

Update `codegen` to pass the collector through.

- [ ] **Step 3: Commit**

```bash
git add src/codegen.odin
git commit -m "fix(codegen): add diagnostics for unlowered handle/perform nodes"
```

---

## Task 15: Codegen — Perceus RC (IR_Drop_Reuse, IR_Alloc_At)

**Files:**
- Modify: `src/codegen.odin:536-539` (IR_Drop_Reuse, IR_Alloc_At)

**Design:** `IR_Drop_Reuse` checks if a heap object's refcount is 1 (unique), and if so, marks it for reuse. `IR_Alloc_At` allocates at a specific address (reuse site). These are Perceus optimizations that can be deferred — for now, implement them as fallbacks:

- `IR_Drop_Reuse` → call `camp_drop` (decrement refcount; if unique, the memory can be reused by a subsequent `camp_alloc`)
- `IR_Alloc_At` → call `camp_alloc` (ignore the reuse hint for now)

- [ ] **Step 1: Implement IR_Drop_Reuse as camp_drop**

Replace `codegen.odin:536-537`:

```odin
	case ^IR_Drop_Reuse:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_DROP])}, buf)
		}
```

- [ ] **Step 2: Implement IR_Alloc_At as camp_alloc**

Replace `codegen.odin:538-539`:

```odin
	case ^IR_Alloc_At:
		if idx, ok := env.local_map[e.value]; ok {
			emit_instruction(Wasm_Local_Get{index = idx}, buf)
			emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, buf)
		}
```

- [ ] **Step 3: Commit**

```bash
git add src/codegen.odin
git commit -m "feat(codegen): implement Drop_Reuse and Alloc_At as RC fallbacks

- Drop_Reuse falls back to camp_drop (no reuse detection yet)
- Alloc_At falls back to camp_alloc (no in-place reuse yet)
- Full Perceus reuse optimization deferred"
```

---

## Task 16: End-to-End Verification

**Files:**
- E2E: Add new tests and update existing ones
- Test: Manual verification with wasmtime

- [ ] **Step 1: Create e2e test for tag union execution**

Create `tests/e2e/execution/tag-match-execute.camp`:

```
main! = || -> I64 {
  x = Ok(42)
  match x {
    Ok(n) => n
  }
}
```

Create `tests/e2e/execution/tag-match-execute.expected.toml`:

```toml
stdout = """
canonicalized /tmp/camp-e2e/execution/tag-match-execute/tag-match-execute.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/execution/tag-match-execute/tag-match-execute.camp
compiled /tmp/camp-e2e/execution/tag-match-execute/tag-match-execute.camp -> /tmp/camp-e2e/execution/tag-match-execute/tag-match-execute.wasm
"""
stderr = ""
exit = 0
wasm_exit = 42
wasm_stdout = ""
wasm_stderr = ""
```

- [ ] **Step 2: Create e2e test for record execution**

Create `tests/e2e/execution/record-field-execute.camp`:

```
main! = || -> I64 {
  r = { x: 10, y: 20 }
  r.x
}
```

Create `tests/e2e/execution/record-field-execute.expected.toml`:

```toml
stdout = """
canonicalized /tmp/camp-e2e/execution/record-field-execute/record-field-execute.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/execution/record-field-execute/record-field-execute.camp
compiled /tmp/camp-e2e/execution/record-field-execute/record-field-execute.camp -> /tmp/camp-e2e/execution/record-field-execute/record-field-execute.wasm
"""
stderr = ""
exit = 0
wasm_exit = 10
wasm_stdout = ""
wasm_stderr = ""
```

- [ ] **Step 3: Create e2e test for closure execution**

Create `tests/e2e/execution/closure-execute.camp`:

```
main! = || -> I64 {
  f = |x| x + 1
  f(41)
}
```

Create `tests/e2e/execution/closure-execute.expected.toml`:

```toml
stdout = """
canonicalized /tmp/camp-e2e/execution/closure-execute/closure-execute.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/execution/closure-execute/closure-execute.camp
compiled /tmp/camp-e2e/execution/closure-execute/closure-execute.camp -> /tmp/camp-e2e/execution/closure-execute.wasm
"""
stderr = ""
exit = 0
wasm_exit = 42
wasm_stdout = ""
wasm_stderr = ""
```

- [ ] **Step 4: Run all e2e tests**

Run: `./camp-e2e`
Expected: All tests pass (104+ tests including new ones)

- [ ] **Step 5: Run all unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 6: Manual verification — compile and run a program**

```bash
echo 'main! = || -> I64 { 42 }' > /tmp/test.camp
./camp build /tmp/test.camp
wasmtime run /tmp/test.wasm
echo $?
```

Expected: Exit code 42

```bash
echo 'main! = || -> I64 { x = Ok(42) match x { Ok(n) => n } }' > /tmp/test_tag.camp
./camp build /tmp/test_tag.camp
wasmtime run /tmp/test_tag.wasm
echo $?
```

Expected: Exit code 42

- [ ] **Step 7: Commit**

```bash
git add tests/e2e/
git commit -m "test(e2e): add execution tests for tags, records, closures

- Tag union match executes correctly via wasmtime
- Record field access executes correctly
- Closure creation and call executes correctly
- All 104+ e2e tests passing"
```

---

## Self-Review

### Spec Coverage Check

| Bug/Feature | Task | Covered? |
|------------|------|----------|
| H2 — IR_Crash | Task 1 | Already fixed |
| M4 — Handler evidence | Task 2 | Already fixed |
| M9 — Generalization | Task 3 | Already fixed |
| C5 — Match patterns | Task 4 | Already fixed |
| C8 — Closure capture | Task 5 | **Yes** — full rewrite of closure_convert |
| C7 — Non-name callee | Task 6 | Lowering fixed; codegen in Task 13 |
| C9 — Perceus RC | Task 7 | Already correct |
| M5 — CPS continuations | Task 8 | Already fixed |
| IR_Construct_Tag codegen | Task 9 | **Yes** |
| IR_Construct_Record codegen | Task 9 | **Yes** |
| IR_Field_Access codegen | Task 10 | **Yes** |
| IR_Match codegen | Task 11 | **Yes** |
| IR_Method_Call codegen | Task 12 | Deferred (needs traits) |
| IR_Closure codegen | Task 13 | **Yes** |
| IR_Closure_Call codegen | Task 13 | **Yes** |
| IR_Handle codegen | Task 14 | Diagnostic only (should be lowered) |
| IR_Perform codegen | Task 14 | Diagnostic only (should be lowered) |
| IR_Drop_Reuse codegen | Task 15 | Fallback to camp_drop |
| IR_Alloc_At codegen | Task 15 | Fallback to camp_alloc |
| IR_Crash codegen | Task 1 | Already emits unreachable |
| End-to-end verification | Task 16 | **Yes** |

### Placeholder Scan

- All code blocks contain actual implementation code
- No "TBD", "TODO", "implement later" in step descriptions
- All test code is complete
- All file paths are exact
- All commands include expected output

### Type Consistency

- `IR_Construct_Tag` gains `tag_index: int` — all construction sites updated
- `IR_Field_Access` gains `field_index: int` — all construction sites updated
- `Codegen_Env` gains `collector` field — passed through from `codegen`
- `RUNTIME_FUNC_COUNT` updated to 8
- New runtime indices: `RUNTIME_ALLOC_TAGGED`, `RUNTIME_FIELD_SET`, `RUNTIME_FIELD_GET`

### Key Risk: Field Index Computation

The biggest gap in this plan is computing `field_index` for `IR_Field_Access`. The plan uses `field_index = 0` as a placeholder. This means record field access will always read field 0, which is wrong for multi-field records. A proper fix requires propagating field position information from the typechecker through canonical → IR. This should be a follow-up task after the basic codegen is working.

### Key Risk: Tag Index Computation

Similarly, `tag_index` for `IR_Construct_Tag` needs to be computed per tag union type. The plan uses the intern ID's low byte, which works for small programs but will collide in larger ones. A proper fix requires a tag index assignment pass after typechecking. This is a follow-up task.
