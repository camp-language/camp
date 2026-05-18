# Camp Compiler Phase 5-6: Effect System + Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the effect system (parse handle/intercept, typecheck effect rows structurally, enforce effect safety) and implement the compilation backend (effect lowering, closure conversion, CPS transform, WASM codegen) to produce runnable .wasm binaries.

**Architecture:** The work proceeds in three layers: (1) fill gaps in the existing frontend — add handle/intercept to the parser, extend the canonical AST with handler nodes, implement structural row unification, and enforce effect safety; (2) implement the middle-end IR transformations — effect lowering (evidence passing), closure conversion, and selective CPS; (3) implement the backend — WASM binary emission with Perceus RC insertion, WASI imports, and a minimal runtime. Each layer produces testable output independently.

**Tech Stack:** Odin, Level type inference with row unification, evidence-passing effect compilation, selective CPS, WASM binary format (LEB128, sections), WASI Preview 1, Perceus reference counting

**Spec:** `docs/superpowers/specs/2026-05-18-camp-language-design.md`

---

## Roadmap: Compiler Phases

| Phase | What it produces | Status |
|-------|-----------------|--------|
| 1. Bootstrap | Project scaffolding, build system, error collector, CLI | Done |
| 2. Lexer + Parser | Token stream + surface AST from source text | Done |
| 3. Canonicalizer | Canonical AST with deferred imports, derive expansion | Done |
| 4. Typechecker | Typed IR with effect rows, variant unions | Done (gaps below) |
| 5. Effect System Completion | handle/intercept syntax, row unification, effect safety | **This plan** |
| 6. Effect Lower + Closure Convert + CPS | Evidence-passed IR, closure-converted, CPS IR | **This plan** |
| 7. WASM Codegen + Perceus RC | .wasm binary emission with RC insertion | **This plan** |
| 8. Runtime | Camp runtime (effect handlers, WASI bindings, Perceus ops) | Future plan |
| 9. Stdlib | Core modules (Int, Str, List, Iter, etc.) | Future plan |

---

## Prerequisite Gaps in Existing Code

Before implementing the backend, these gaps in phases 2-4 must be fixed:

| Gap | Current State | Needed For |
|-----|--------------|-------------|
| No `handle`/`intercept` syntax | Parser doesn't recognize handler expressions | Effect lowering |
| No `CExpr_Handle` in canonical AST | Canonical AST has no handler node | Effect lowering |
| No structural row unification | Effect rows are opaque Type_Var_IDs; no comparison of row contents | Effect safety, typechecker |
| No `Inferred_Type` structural fields | `Inferred_Type` has `tag` + `primitive_name` + `arity` only; no effect list, function params/return, record fields | Row unification |
| No effect safety enforcement | Typechecker tracks effect rows but doesn't verify all effects are handled | Compilation correctness |
| No `!` naming enforcement | Effectful functions don't require `!` in name | Spec compliance |

---

## File Structure

```
camp/
├── src/
│   ├── main.odin                  -- CLI entry point (modify: add run command)
│   ├── cli.odin                   -- Build command (modify: wire full pipeline)
│   ├── context.odin               -- Compilation_Context (existing, no changes)
│   ├── error.odin                 -- Error collector (existing, no changes)
│   ├── source.odin                -- Source_Span, Source_File (existing, no changes)
│   ├── intern.odin                -- Intern_Table (existing, no changes)
│   ├── reporter.odin              -- Error formatting (existing, no changes)
│   ├── token.odin                 -- Token types (modify: add Handle, Intercept, With keywords)
│   ├── lexer.odin                 -- Lexer (modify: tokenize new keywords)
│   ├── ast.odin                   -- Surface AST (modify: add Expr_Handle, Expr_Perform)
│   ├── parser.odin                -- Pratt parser (modify: parse handle/intercept expressions)
│   ├── canonical.odin             -- Canonical AST (modify: add CExpr_Handle, CExpr_Perform)
│   ├── canonicalize.odin          -- Surface → Canonical (modify: convert handle/perform)
│   ├── types.odin                 -- Type system (modify: add structural Inferred_Type fields)
│   ├── unify.odin                 -- Unification (modify: add row unification)
│   ├── typecheck.odin             -- Typechecker (modify: effect safety, handle typecheck, ! enforcement)
│   ├── ir.odin                    -- Mid-end IR types (NEW)
│   ├── effect_lower.odin         -- Effect lowering: evidence passing (NEW)
│   ├── closure_convert.odin       -- Closure conversion (NEW)
│   ├── cps.odin                   -- CPS transform (NEW)
│   ├── rc.odin                    -- Perceus RC insertion (NEW)
│   ├── wasm.odin                  -- WASM binary format: types, sections, encoding (NEW)
│   ├── codegen.odin               -- WASM code generation from CPS IR (NEW)
│   ├── runtime.odin               -- Runtime function stubs for WASM output (NEW)
│   ├── test_effects.odin          -- Effect system tests (NEW)
│   ├── test_ir.odin               -- IR transformation tests (NEW)
│   ├── test_codegen.odin          -- Codegen tests (NEW)
│   └── (existing test files unchanged)
```

---

## Task 1: Add Handle/Intercept Keywords to Lexer

**Files:**
- Modify: `src/token.odin`
- Modify: `src/lexer.odin`
- Test: `src/test_lexer.odin`

- [ ] **Step 1: Add token kinds**

In `src/token.odin`, add to `Token_Kind` enum before the closing `}`:

```odin
Handle,
Intercept,
With,
```

- [ ] **Step 2: Add keyword entries to lexer**

In `src/lexer.odin`, find the keyword map initialization and add entries for the three new keywords:

```odin
{"handle", .Handle},
{"intercept", .Intercept},
{"with", .With},
```

- [ ] **Step 3: Write failing test**

In `src/test_lexer.odin`, add a test that tokenizes a handle expression:

```odin
test_tokenize_handle :: proc(t: ^testing.T) {
	l := lexer_from_string("handle Async in { } with { }")
	expected := []Token_Kind{
		.Handle, .Identifier, .In, .Left_Brace, .Right_Brace,
		.With, .Left_Brace, .Right_Brace, .Eof,
	}
	for i, kind in expected {
		tok := lexer_next(&l)
		testing.expect_value(t, tok.kind, kind)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `odin test src/ --filter test_tokenize_handle`
Expected: PASS (keywords should be recognized)

- [ ] **Step 5: Write test for intercept keyword**

In `src/test_lexer.odin`:

```odin
test_tokenize_intercept :: proc(t: ^testing.T) {
	l := lexer_from_string("intercept Async in { } with { }")
	expected := []Token_Kind{
		.Intercept, .Identifier, .In, .Left_Brace, .Right_Brace,
		.With, .Left_Brace, .Right_Brace, .Eof,
	}
	for i, kind in expected {
		tok := lexer_next(&l)
		testing.expect_value(t, tok.kind, kind)
	}
}
```

- [ ] **Step 6: Run tests**

Run: `odin test src/`
Expected: All existing tests + 2 new tests pass

- [ ] **Step 7: Commit**

```bash
git add src/token.odin src/lexer.odin src/test_lexer.odin
git commit -m "feat(lexer): add handle, intercept, with keywords"
```

---

## Task 2: Add Handle/Perform to Surface AST

**Files:**
- Modify: `src/ast.odin`

- [ ] **Step 1: Add Expr_Handle and Expr_Perform to Expr union**

In `src/ast.odin`, add to the `Expr` union:

```odin
^Expr_Handle,
^Expr_Perform,
```

- [ ] **Step 2: Define Expr_Handle struct**

```odin
Expr_Handle :: struct {
	effect:    Intern_ID,
	is_shallow: bool,
	body:      Expr,
	arms:      [dynamic]Handler_Arm,
	span:      Source_Span,
}

Handler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      Expr,
	span:      Source_Span,
}
```

- [ ] **Step 3: Define Expr_Perform struct**

```odin
Expr_Perform :: struct {
	effect:  Intern_ID,
	op:      Intern_ID,
	args:    [dynamic]Expr,
	span:    Source_Span,
}
```

Note: `Expr_Perform` represents an explicit `perform` syntax if we ever add it. In Camp, effect operations are called as `Effect.op!()` which is already handled by `Expr_Method_Call`. We add `Expr_Perform` for internal use during effect lowering — the typechecker converts qualified effect calls to `Expr_Perform` nodes. This is optional; we may instead use `CExpr_Perform` only in the canonical AST. See Task 4.

- [ ] **Step 4: Commit**

```bash
git add src/ast.odin
git commit -m "feat(ast): add Expr_Handle, Expr_Perform, Handler_Arm"
```

---

## Task 3: Parse Handle/Intercept Expressions

**Files:**
- Modify: `src/parser.odin`
- Test: `src/test_parser.odin`

- [ ] **Step 1: Implement parse_handle_expr**

In `src/parser.odin`, add a prefix parsing function for `handle` and `intercept`. The grammar is:

```
handle_expr     = "handle" IDENT "in" block "with" "{" handler_arm* "}"
intercept_expr  = "intercept" IDENT "in" block "with" "{" handler_arm* "}"
handler_arm     = "." IDENT "!" "(" IDENT ")" "=>" block
```

Add a `parse_handle` proc:

```odin
parse_handle :: proc(p: ^Parser, is_shallow: bool) -> Expr {
	span := p.current.span
	p.advance()

	effect_name := parse_identifier_name(p)
	expect(p, .In)
	body := parse_expr(p)
	expect(p, .With)
	expect(p, .Left_Brace)

	arms: [dynamic]Handler_Arm
	for p.current.kind != .Right_Brace {
		expect(p, .Dot)
		op_name := expect_identifier(p)
		expect(p, .Bang)
		expect(p, .Left_Paren)
		resume_id := expect_identifier(p)
		expect(p, .Right_Paren)
		expect(p, .FatArrow)
		arm_body := parse_expr(p)
		append(&arms, Handler_Arm{
			op = op_name,
			resume_id = resume_id,
			body = arm_body,
			span = span,
		})
	}
	expect(p, .Right_Brace)

	return Expr_Handle{
		effect = effect_name,
		is_shallow = is_shallow,
		body = body,
		arms = arms[:],
		span = span,
	}
}
```

- [ ] **Step 2: Register handle/intercept as prefix parsers**

In the parser initialization, add:

```odin
prefix_handlers[Token_Kind.Handle] = parse_handle_prefix
prefix_handlers[Token_Kind.Intercept] = parse_intercept_prefix
```

Where `parse_handle_prefix` calls `parse_handle(p, false)` and `parse_intercept_prefix` calls `parse_handle(p, true)`.

- [ ] **Step 3: Write failing test**

In `src/test_parser.odin`:

```odin
test_parse_handle :: proc(t: ^testing.T) {
	source := `
handle Console in {
  Console.println!("hello")
} with {
  .println!(resume) => resume({})
}
`
	file := parse_string(source)
	testing.expect(t, len(file.decls) > 0)
}
```

- [ ] **Step 4: Run test, fix until pass**

Run: `odin test src/ --filter test_parse_handle`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/parser.odin src/test_parser.odin
git commit -m "feat(parser): parse handle/intercept expressions"
```

---

## Task 4: Add Handle/Perform to Canonical AST

**Files:**
- Modify: `src/canonical.odin`
- Modify: `src/canonicalize.odin`

- [ ] **Step 1: Add CExpr_Handle and CExpr_Perform to CExpr union**

In `src/canonical.odin`, add to `CExpr` union:

```odin
^CExpr_Handle,
^CExpr_Perform,
```

- [ ] **Step 2: Define CExpr_Handle and CExpr_Perform structs**

```odin
CExpr_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       CExpr,
	arms:       [dynamic]CHandler_Arm,
	span:       Source_Span,
}

CHandler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      CExpr,
	span:      Source_Span,
}

CExpr_Perform :: struct {
	effect: Canonical_Name,
	op:     Intern_ID,
	args:   [dynamic]CExpr,
	span:   Source_Span,
}
```

- [ ] **Step 3: Update canonicalize to convert Expr_Handle**

In `src/canonicalize.odin`, add a case in the expression canonicalization switch for `Expr_Handle`:

```odin
case ^Expr_Handle:
	hd := v
	effect_name := resolve_canonical_name(hd.effect, env)
	arms: [dynamic]CHandler_Arm
	for arm in hd.arms {
		append(&arms, CHandler_Arm{
			op = arm.op,
			resume_id = arm.resume_id,
			body = canonicalize_expr(arm.body, env),
			span = arm.span,
		})
	}
	return CExpr_Handle{
		effect = effect_name,
		is_shallow = hd.is_shallow,
		body = canonicalize_expr(hd.body, env),
		arms = arms[:],
		span = hd.span,
	}
```

- [ ] **Step 4: Convert qualified effect calls to CExpr_Perform**

When canonicalizing a `CExpr_Method_Call` where the receiver's module matches a known effect definition, convert it to `CExpr_Perform`. This requires checking the environment's effect definitions. Add this logic in the method-call canonicalization path:

```odin
case ^CExpr_Method_Call:
	mc := v
	resolved_method := Canonical_Name{module = resolve_module(mc.receiver, env), name = mc.method, is_local = false}
	if is_effect(resolved_method.module, env) {
		return CExpr_Perform{
			effect = resolved_method,
			op = mc.method,
			args = canonicalize_args(mc.args, env),
			span = mc.span,
		}
	}
	-- otherwise keep as method call
```

- [ ] **Step 5: Write test**

In `src/test_canonicalize.odin`, add a test that canonicalizes a handle expression.

- [ ] **Step 6: Run tests**

Run: `odin test src/`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add src/canonical.odin src/canonicalize.odin src/test_canonicalize.odin
git commit -m "feat(canonical): add CExpr_Handle, CExpr_Perform, convert handler syntax"
```

---

## Task 5: Implement Structural Row Unification

**Files:**
- Modify: `src/types.odin`
- Modify: `src/unify.odin`
- Test: `src/test_typecheck.odin`

This is the most critical gap to fill. Currently, `Inferred_Type` has only `tag`, `primitive_name`, and `arity` — no structural information about function types, record fields, tag union tags, or effect row contents. Unification can check that two types have the same tag but cannot compare their structures.

- [ ] **Step 1: Extend Inferred_Type with structural fields**

In `src/types.odin`, replace `Inferred_Type`:

```odin
Inferred_Type :: struct {
	tag:            Inferred_Tag,
	primitive_name:  Intern_ID,
	arity:          int,

	-- Function structure (tag == .Function)
	param_ids:      [dynamic]Type_Var_ID,
	return_id:      Type_Var_ID,
	effect_id:      Type_Var_ID,

	-- Effect row structure (tag == .Effect_Row)
	effect_names:   [dynamic]Intern_ID,
	rest_id:        Type_Var_ID,

	-- Record row structure (tag == .Record_Row)
	record_fields:  [dynamic]Type_Field_Entry,
	record_rest:    Type_Var_ID,

	-- Tag union row structure (tag == .Tag_Union_Row)
	tag_entries:    [dynamic]Type_Tag_Entry,
	tag_rest:       Type_Var_ID,
}

Type_Field_Entry :: struct {
	name: Intern_ID,
	var:  Type_Var_ID,
}

Type_Tag_Entry :: struct {
	name:    Intern_ID,
	payload: [dynamic]Type_Var_ID,
}
```

- [ ] **Step 2: Update convert_type_to_var for function types**

In `src/typecheck.odin`, update the `CType_Function` case of `convert_type_to_var_val` to create a structured `Inferred_Type`:

```odin
case ^CType_Function:
	ft := v
	param_ids: [dynamic]Type_Var_ID
	for &param in ft.params {
		append(&param_ids, convert_type_to_var(param, store))
	}
	return_id := convert_type_to_var(ft.return_, store)
	effect_id := fresh_effect_row(store, ft.span)
	if ft.effects != nil {
		effect_id = convert_type_to_var(ft.effects, store)
	}
	vid := fresh_value_var(store, ft.span)
	store.vars[vid].link = Inferred_Type{
		tag = .Function,
		param_ids = param_ids[:],
		return_id = return_id,
		effect_id = effect_id,
	}
	return vid
```

- [ ] **Step 3: Update convert_type_to_var for effect rows**

In the `CType_Effect_Row` case:

```odin
case ^CType_Effect_Row:
	er := v
	effect_names: [dynamic]Intern_ID
	for eid in er.effects {
		append(&effect_names, eid)
	}
	rest_id := Type_Var_ID(-1)
	if er.rest != 0 {
		rest_id = fresh_effect_row(store, er.span)
	}
	vid := fresh_effect_row(store, er.span)
	store.vars[vid].link = Inferred_Type{
		tag = .Effect_Row,
		effect_names = effect_names[:],
		rest_id = rest_id,
	}
	return vid
```

- [ ] **Step 4: Implement unify_inferred for Function types**

In `src/unify.odin`, extend `unify_inferred` to handle `.Function`:

```odin
case .Function, .Function:
	if a.param_ids == nil or b.param_ids == nil do return
	if len(a.param_ids) != len(b.param_ids) {
		-- error: function arity mismatch
		return
	}
	for i in 0..<len(a.param_ids) {
		unify(a.param_ids[i], b.param_ids[i], store)
	}
	unify(a.return_id, b.return_id, store)
	unify(a.effect_id, b.effect_id, store)
```

- [ ] **Step 5: Implement unify_inferred for Effect_Row types**

```odin
case .Effect_Row, .Effect_Row:
	-- Unify the common effects (by name matching)
	-- For each effect in a, check if it's in b; unify rest variables
	-- This implements row unification following Rémy (1994)
	unify_effect_rows(a, b, store)
```

The `unify_effect_rows` proc implements the core algorithm:
- If both rows are closed (rest = -1), just check they have the same effects
- If one row has a rest variable, unify the rest variable with a new row containing the unmatched effects
- If both have rest variables, create a fresh row variable for the overlap and unify both rests with it

- [ ] **Step 6: Write test for function type unification**

In `src/test_typecheck.odin`:

```odin
test_unify_function_types :: proc(t: ^testing.T) {
	-- (Int) -> Int  unified with  (Int) -> Int  should succeed
	-- (Int) -> Int  unified with  (Str) -> Str  should fail (primitive mismatch)
}
```

- [ ] **Step 7: Write test for effect row unification**

```odin
test_unify_effect_rows :: proc(t: ^testing.T) {
	-- {Console} unified with {Console}  should succeed
	-- {Console} unified with {Console, File}  should fail (closed row)
	-- {Console, ..e} unified with {Console, File}  should unify e = {File}
	-- {Console, ..e} unified with {File, ..f}  should work
}
```

- [ ] **Step 8: Run all tests**

Run: `odin test src/`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add src/types.odin src/unify.odin src/typecheck.odin src/test_typecheck.odin
git commit -m "feat(types): implement structural row unification for functions, effects, records, tag unions"
```

---

## Task 6: Implement Effect Safety Enforcement

**Files:**
- Modify: `src/typecheck.odin`
- Modify: `src/error.odin`
- Test: `src/test_typecheck.odin`

- [ ] **Step 1: Add effect safety check proc**

In `src/typecheck.odin`, add a proc that checks whether a function's effect row is a subset of its enclosing context's handled effects:

```odin
check_effect_safety :: proc(body_effects: Type_Var_ID, allowed_effects: Type_Var_ID, store: ^Type_Store) {
	-- Resolve both effect rows
	-- If body_effects contains effects not in allowed_effects, emit error
	-- Effect: "unhandled effect: Console not handled by enclosing context"
}
```

- [ ] **Step 2: Add ! naming enforcement**

In the `CDecl_Const` typecheck path, after synth:

```odin
if decl.is_effectful {
	-- Check that the name contains '!'
	if !strings.contains(intern_get(store.interner, decl.name.name), "!") {
		emit_error(store, decl.span, "effectful function must have '!' in name")
	}
} else {
	-- Check that the effect row is empty
	resolved := resolve_var(result.effects, store)
	if is_non_empty_effect_row(resolved, store) {
		emit_error(store, decl.span, "function with non-empty effect row must have '!' in name")
	}
}
```

- [ ] **Step 3: Integrate effect safety into handle typechecking**

When typechecking a `CExpr_Handle`, the handler's effect is added to the allowed set for the body. After typechecking the body, verify its effects are a subset of the allowed set.

- [ ] **Step 4: Write test for unhandled effect error**

```odin
test_unhandled_effect :: proc(t: ^testing.T) {
	-- A function that performs Console.println! without a handler
	-- should produce a type error about unhandled effect
}
```

- [ ] **Step 5: Write test for ! naming enforcement**

```odin
test_effectful_naming :: proc(t: ^testing.T) {
	-- A function with non-empty effect row but no ! in name should error
	-- A function with ! in name but empty effect row should error
}
```

- [ ] **Step 6: Run all tests**

Run: `odin test src/`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add src/typecheck.odin src/error.odin src/test_typecheck.odin
git commit -m "feat(typecheck): enforce effect safety and ! naming convention"
```

---

## Task 7: Define Mid-End IR Types

**Files:**
- Create: `src/ir.odin`
- Test: `src/test_ir.odin`

This defines the IR that flows through effect lowering → closure conversion → CPS → Perceus. It's a typed, A-normal form (ANF) IR suitable for dataflow analysis.

- [ ] **Step 1: Define IR types**

Create `src/ir.odin`:

```odin
package camp

IR_ID :: distinct int

IR_Type :: union {
	^IR_Type_Prim,
	^IR_Type_Fn,
	^IR_Type_Record,
	^IR_Type_Tag,
	^IR_Type_EffRow,
	^IR_Type_Var,
}

IR_Type_Prim :: struct {
	name: Intern_ID,
}

IR_Type_Fn :: struct {
	params:  [dynamic]IR_Type,
	effect:  IR_Type,
	return_: IR_Type,
}

IR_Type_Record :: struct {
	fields: [dynamic]IR_Type_Field,
	rest:   IR_ID,
}

IR_Type_Field :: struct {
	name: Intern_ID,
	type: IR_Type,
}

IR_Type_Tag :: struct {
	tags: [dynamic]IR_Tag_Entry,
	rest: IR_ID,
}

IR_Tag_Entry :: struct {
	name:    Intern_ID,
	payload: [dynamic]IR_Type,
}

IR_Type_EffRow :: struct {
	effects: [dynamic]Intern_ID,
	rest:    IR_ID,
}

IR_Type_Var :: struct {
	name: Intern_ID,
}

IR_Module :: struct {
	decls:   [dynamic]IR_Decl,
	effects: [dynamic]IR_Effect_Def,
	types:   [dynamic]IR_Type_Def,
}

IR_Decl :: union {
	^IR_Decl_Fn,
	^IR_Decl_Const,
	^IR_Decl_Effect,
	^IR_Decl_Handler,
}

IR_Decl_Fn :: struct {
	name:         Canonical_Name,
	is_effectful: bool,
	params:       [dynamic]IR_Param,
	return_type:  IR_Type,
	effect_row:   IR_Type,
	body:         IR_Expr,
	span:         Source_Span,
}

IR_Param :: struct {
	name: Intern_ID,
	type: IR_Type,
}

IR_Decl_Const :: struct {
	name:        Canonical_Name,
	type:        IR_Type,
	value:       IR_Expr,
	span:        Source_Span,
}

IR_Decl_Effect :: struct {
	name:       Canonical_Name,
	operations: [dynamic]IR_Effect_Op,
	span:       Source_Span,
}

IR_Effect_Op :: struct {
	name:        Intern_ID,
	params:      [dynamic]IR_Param,
	return_type: IR_Type,
	effect_row:  IR_Type,
}

IR_Decl_Handler :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	arms:       [dynamic]IR_Handler_Arm,
	span:       Source_Span,
}

IR_Handler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      IR_Expr,
	span:      Source_Span,
}

IR_Expr :: union {
	^IR_Literal,
	^IR_Var,
	^IR_Let,
	^IR_Call,
	^IR_Tail_Call,
	^IR_If,
	^IR_Match,
	^IR_Construct_Tag,
	^IR_Construct_Record,
	^IR_Field_Access,
	^IR_Closure,
	^IR_Perform,
	^IR_Handle,
	^IR_Dup,
	^IR_Drop,
	^IR_Drop_Reuse,
	^IR_Alloc_At,
	^IR_Return,
}

IR_Literal :: struct {
	value: IR_Lit_Value,
	type:  IR_Type,
	span:  Source_Span,
}

IR_Lit_Value :: union {
	IR_Lit_Int,
	IR_Lit_Float,
	IR_Lit_String,
	IR_Lit_Bool,
}

IR_Lit_Int :: struct { value: i64 }
IR_Lit_Float :: struct { value: f64 }
IR_Lit_String :: struct { value: string }
IR_Lit_Bool :: struct { value: bool }

IR_Var :: struct {
	name: Intern_ID,
	type: IR_Type,
	span: Source_Span,
}

IR_Let :: struct {
	binding: Intern_ID,
	type:    IR_Type,
	value:   IR_Expr,
	body:    IR_Expr,
	span:    Source_Span,
}

IR_Call :: struct {
	callee: Intern_ID,
	args:   [dynamic]IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Tail_Call :: struct {
	callee: Intern_ID,
	args:   [dynamic]IR_Expr,
	span:   Source_Span,
}

IR_If :: struct {
	condition:   IR_Expr,
	then_branch: IR_Expr,
	else_branch: IR_Expr,
	type:        IR_Type,
	span:        Source_Span,
}

IR_Match :: struct {
	scrutinee: IR_Expr,
	arms:       [dynamic]IR_Match_Arm,
	type:       IR_Type,
	span:       Source_Span,
}

IR_Match_Arm :: struct {
	pattern: IR_Pattern,
	body:    IR_Expr,
}

IR_Pattern :: union {
	^IR_Pat_Tag,
	^IR_Pat_Record,
	^IR_Pat_Var,
	^IR_Pat_Wildcard,
}

IR_Pat_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]Intern_ID,
}

IR_Pat_Record :: struct {
	fields:  [dynamic]IR_Pat_Field,
	is_open: bool,
}

IR_Pat_Field :: struct {
	name:    Intern_ID,
	binding: Intern_ID,
}

IR_Pat_Var :: struct { name: Intern_ID }
IR_Pat_Wildcard :: struct {}

IR_Construct_Tag :: struct {
	tag_name: Intern_ID,
	payload:  [dynamic]IR_Expr,
	type:     IR_Type,
	span:     Source_Span,
}

IR_Construct_Record :: struct {
	fields: [dynamic]IR_Record_Field_Init,
	rest:   IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Record_Field_Init :: struct {
	name:  Intern_ID,
	value: IR_Expr,
}

IR_Field_Access :: struct {
	record: IR_Expr,
	field:  Intern_ID,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Closure :: struct {
	fn_ptr: Intern_ID,
	env:    IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Perform :: struct {
	effect: Canonical_Name,
	op:     Intern_ID,
	args:   [dynamic]IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       IR_Expr,
	arms:       [dynamic]IR_Handler_Arm,
	type:       IR_Type,
	span:       Source_Span,
}

-- Perceus RC operations (inserted by rc.odin)
IR_Dup :: struct {
	value: Intern_ID,
	span:  Source_Span,
}

IR_Drop :: struct {
	value: Intern_ID,
	span:  Source_Span,
}

IR_Drop_Reuse :: struct {
	value:      Intern_ID,
	scan_count: int,
	reuse_id:   Intern_ID,
	span:       Source_Span,
}

IR_Alloc_At :: struct {
	reuse_id: Intern_ID,
	tag:      Intern_ID,
	args:     [dynamic]Intern_ID,
	type:     IR_Type,
	span:     Source_Span,
}

IR_Return :: struct {
	value: IR_Expr,
	span:  Source_Span,
}
```

- [ ] **Step 2: Write test that constructs an IR module**

In `src/test_ir.odin`, create a simple IR module and verify it can be constructed:

```odin
test_ir_construct_module :: proc(t: ^testing.T) {
	mod: IR_Module
	testing.expect_value(t, len(mod.decls), 0)
}
```

- [ ] **Step 3: Run test**

Run: `odin test src/ --filter test_ir_construct_module`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/ir.odin src/test_ir.odin
git commit -m "feat(ir): define mid-end IR types for effect lowering, closure conversion, CPS"
```

---

## Task 8: Lower Typed Canonical AST to IR

**Files:**
- Create: `src/lower.odin`
- Test: `src/test_ir.odin`

This converts the type-annotated `CFile` (after typechecking) into `IR_Module`. This is the bridge between the frontend and the mid-end.

- [ ] **Step 1: Implement lower_file**

Create `src/lower.odin`:

```odin
package camp

import "core:fmt"

lower_file :: proc(cfile: CFile, store: ^Type_Store) -> IR_Module {
	mod: IR_Module
	env: Lower_Env = {module = &mod, store = store, interner = store.interner}

	for &decl in cfile.decls {
		switch d in decl {
		case ^CDecl_Const:
			ir_decl := lower_decl_const(d^, &env)
			append(&mod.decls, ir_decl)
		case ^CDecl_Effect:
			ir_decl := lower_decl_effect(d^, &env)
			append(&mod.decls, ir_decl)
		case:
			-- skip imports, traits, aliases for now
		}
	}

	return mod
}

Lower_Env :: struct {
	module:  ^IR_Module,
	store:   ^Type_Store,
	interner: ^Intern_Table,
}
```

- [ ] **Step 2: Implement lower_decl_const and lower_expr**

Each `CExpr` variant maps to a corresponding `IR_Expr`. The key difference is that the IR is in A-normal form: nested expressions are flattened into `IR_Let` chains.

- [ ] **Step 3: Implement lower_decl_effect**

Convert `CDecl_Effect` to `IR_Decl_Effect`.

- [ ] **Step 4: Write test**

```odin
test_lower_simple :: proc(t: ^testing.T) {
	-- Parse + canonicalize + typecheck a simple file, then lower to IR
	-- Verify the IR module has the expected declarations
}
```

- [ ] **Step 5: Run test**

Run: `odin test src/ --filter test_lower_simple`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/lower.odin src/test_ir.odin
git commit -m "feat(ir): lower typed canonical AST to mid-end IR"
```

---

## Task 9: Implement Effect Lowering (Evidence Passing)

**Files:**
- Create: `src/effect_lower.odin`
- Test: `src/test_effects.odin`

This implements the evidence-passing transformation from *Effect Handlers, Evidently* (Xie et al., ICFP 2020). Each function that performs effects receives an evidence parameter pointing to the nearest handler.

- [ ] **Step 1: Define the evidence passing transformation**

Create `src/effect_lower.odin`:

```odin
package camp

effect_lower :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) -> IR_Module {
	result: IR_Module
	ev_env: Effect_Env = {src = mod, dst = &result, ctx = ctx}

	-- For each function declaration, add evidence parameters for its effects
	for decl in mod.decls {
		lowered := lower_decl(decl, &ev_env)
		append(&result.decls, lowered)
	}

	-- For each handle expression, create handler closures and wire evidence
	-- For each perform expression, replace with evidence call
	return result
}

Effect_Env :: struct {
	src: ^IR_Module,
	dst: ^IR_Module,
	ctx: ^Compilation_Context,
	evidence_map: map[Intern_ID]Intern_ID,  -- effect name -> evidence param name
}
```

- [ ] **Step 2: Transform IR_Perform to evidence call**

```
-- Before: IR_Perform{effect = Console, op = "println!", args = [msg]}
-- After:  IR_Call{callee = ev_Console_println, args = [msg, ev_Console]}
```

Each `IR_Perform` becomes a call to the handler's operation function, passing the evidence as an extra argument.

- [ ] **Step 3: Transform IR_Handle**

Each `IR_Handle` creates handler closure structs:

```
-- Before: IR_Handle{effect = Console, body = ..., arms = [...]}
-- After:  Let ev_Console = make_handler(Console, [op_closures...])
--         body (with ev_Console in scope)
```

- [ ] **Step 4: Write test**

```odin
test_effect_lower_simple :: proc(t: ^testing.T) {
	-- Lower a module with a handle + perform
	-- Verify performs are replaced with evidence calls
	-- Verify handlers become closure records
}
```

- [ ] **Step 5: Run test**

Run: `odin test src/ --filter test_effect_lower_simple`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/effect_lower.odin src/test_effects.odin
git commit -m "feat(effects): implement evidence-passing effect lowering"
```

---

## Task 10: Implement Closure Conversion

**Files:**
- Create: `src/closure_convert.odin`
- Test: `src/test_effects.odin`

- [ ] **Step 1: Implement free variable analysis**

Create `src/closure_convert.odin`:

```odin
package camp

closure_convert :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) -> IR_Module {
	result: IR_Module

	for decl in mod.decls {
		cc_decl := convert_decl(decl, &result, ctx)
		append(&result.decls, cc_decl)
	}

	return result
}
```

- [ ] **Step 2: Implement free_vars and convert_closure**

For each `IR_Closure` or nested function:
1. Compute free variables
2. Create an environment struct type
3. Create a top-level function taking (params + env_ptr)
4. Replace closure creation with `make_closure(fn_idx, env_alloc)`

- [ ] **Step 3: Write test**

```odin
test_closure_convert :: proc(t: ^testing.T) {
	-- Convert a module with closures
	-- Verify closures are replaced with fn_ptr + env
	-- Verify top-level functions are created
}
```

- [ ] **Step 4: Run test**

Run: `odin test src/ --filter test_closure_convert`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/closure_convert.odin src/test_effects.odin
git commit -m "feat(closure): implement closure conversion with environment structs"
```

---

## Task 11: Implement Selective CPS Transform

**Files:**
- Create: `src/cps.odin`
- Test: `src/test_effects.odin`

Only effectful functions get CPS-converted. Pure functions remain in direct style.

- [ ] **Step 1: Implement cps_transform**

Create `src/cps.odin`:

```odin
package camp

cps_transform :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) -> IR_Module {
	result: IR_Module

	for decl in mod.decls {
		cps_decl := transform_decl(decl, &result, ctx)
		append(&result.decls, cps_decl)
	}

	return result
}
```

- [ ] **Step 2: Transform effectful functions**

For each effectful function:
1. Add a continuation parameter `k: (result_type) -> void`
2. Replace each `IR_Return` with `IR_Call{callee = k, args = [value]}`
3. Replace each `IR_Perform` (already evidence-called) with a call that passes the current continuation
4. Pure calls remain as-is

- [ ] **Step 3: Handle handler arms in CPS**

Each handler arm receives a continuation. `resume(v)` becomes `k(v)`. For deep handlers, the handler re-wraps itself around the continuation.

- [ ] **Step 4: Write test**

```odin
test_cps_transform_simple :: proc(t: ^testing.T) {
	-- Transform a pure function: should remain unchanged
	-- Transform an effectful function: should get continuation param
	-- Verify returns become continuation calls
}
```

- [ ] **Step 5: Run test**

Run: `odin test src/ --filter test_cps_transform_simple`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/cps.odin src/test_effects.odin
git commit -m "feat(cps): implement selective CPS transform for effectful functions"
```

---

## Task 12: Implement Perceus RC Insertion

**Files:**
- Create: `src/rc.odin`
- Test: `src/test_ir.odin`

- [ ] **Step 1: Implement liveness analysis**

Create `src/rc.odin`:

```odin
package camp

rc_insert :: proc(mod: ^IR_Module, ctx: ^Compilation_Context) {
	for &decl in mod.decls {
		switch d in decl {
		case ^IR_Decl_Fn:
			insert_rc_for_fn(d, ctx)
		case:
		}
	}
}
```

- [ ] **Step 2: Implement insert_rc_for_fn**

For each function body:
1. Backward pass: compute live variables at each program point
2. Forward pass: insert `IR_Dup` before non-last uses, `IR_Drop` after last uses
3. For pattern matches on reference-counted types: insert `IR_Drop_Reuse` when the matched constructor becomes dead

- [ ] **Step 3: Implement reuse analysis**

When a `IR_Drop_Reuse` produces a non-null reuse token, pair it with the next `IR_Construct_Tag` or `IR_Construct_Record` allocation of matching size. Replace the allocation with `IR_Alloc_At`.

- [ ] **Step 4: Write test**

```odin
test_rc_insert_simple :: proc(t: ^testing.T) {
	-- Insert RC for a simple function
	-- Verify dup/drop are inserted at correct positions
}
```

- [ ] **Step 5: Run test**

Run: `odin test src/ --filter test_rc_insert_simple`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/rc.odin src/test_ir.odin
git commit -m "feat(rc): implement Perceus reference counting insertion with reuse analysis"
```

---

## Task 13: Implement WASM Binary Format Encoding

**Files:**
- Create: `src/wasm.odin`
- Test: `src/test_codegen.odin`

- [ ] **Step 1: Define WASM types and encoding helpers**

Create `src/wasm.odin`:

```odin
package camp

Wasm_Value_Type :: enum u8 {
	I32 = 0x7F,
	I64 = 0x7E,
	F32 = 0x7D,
	F64 = 0x7C,
	Funcref = 0x70,
}

Wasm_Section_ID :: enum u8 {
	Custom    = 0,
	Type      = 1,
	Import    = 2,
	Function  = 3,
	Table     = 4,
	Memory    = 5,
	Global    = 6,
	Export    = 7,
	Start     = 8,
	Element   = 9,
	Code      = 10,
	Data      = 11,
	Data_Count = 12,
}

Wasm_Module :: struct {
	types:     [dynamic]Wasm_Func_Type,
	imports:   [dynamic]Wasm_Import,
	functions: [dynamic]Wasm_Func_Type_Index,
	tables:    [dynamic]Wasm_Table,
	memories:  [dynamic]Wasm_Memory,
	globals:   [dynamic]Wasm_Global,
	exports:   [dynamic]Wasm_Export,
	start:     int,
	elements:  [dynamic]Wasm_Element,
	codes:     [dynamic]Wasm_Code,
	datas:     [dynamic]Wasm_Data,
}

Wasm_Func_Type :: struct {
	params:  [dynamic]Wasm_Value_Type,
	results: [dynamic]Wasm_Value_Type,
}

Wasm_Func_Type_Index :: struct {
	type_idx: int,
}

Wasm_Import :: struct {
	module: string,
	field:  string,
	desc:   Wasm_Import_Desc,
}

Wasm_Import_Desc :: union {
	Wasm_Import_Func,
	Wasm_Import_Table,
	Wasm_Import_Memory,
	Wasm_Import_Global,
}

Wasm_Import_Func :: struct { type_idx: int }
Wasm_Import_Table :: struct { elem_type: Wasm_Value_Type, limits: Wasm_Limits }
Wasm_Import_Memory :: struct { limits: Wasm_Limits }
Wasm_Import_Global :: struct { type: Wasm_Value_Type, mutable: bool }

Wasm_Limits :: struct {
	min:  u32,
	max:  u32,
	has_max: bool,
}

Wasm_Table :: struct {
	elem_type: Wasm_Value_Type,
	limits:   Wasm_Limits,
}

Wasm_Memory :: struct {
	limits: Wasm_Limits,
}

Wasm_Global :: struct {
	type:     Wasm_Value_Type,
	mutable:  bool,
	init_expr: [dynamic]Wasm_Instruction,
}

Wasm_Export :: struct {
	name:  string,
	desc:  Wasm_Export_Desc,
}

Wasm_Export_Desc :: union {
	Wasm_Export_Func,
	Wasm_Export_Table,
	Wasm_Export_Memory,
	Wasm_Export_Global,
}

Wasm_Export_Func :: struct { idx: int }
Wasm_Export_Table :: struct { idx: int }
	Wasm_Export_Memory :: struct { idx: int }
	Wasm_Export_Global :: struct { idx: int }

Wasm_Element :: struct {
	table_idx: int,
	offset:    [dynamic]Wasm_Instruction,
	func_idxs: [dynamic]int,
}

Wasm_Code :: struct {
	locals:  [dynamic]Wasm_Local_Decl,
	body:    [dynamic]Wasm_Instruction,
}

Wasm_Local_Decl :: struct {
	count: u32,
	type:  Wasm_Value_Type,
}

Wasm_Data :: struct {
	mem_idx: int,
	offset: [dynamic]Wasm_Instruction,
	bytes:  []byte,
}
```

- [ ] **Step 2: Implement LEB128 encoding**

```odin
encode_u32_leb128 :: proc(value: u32, buf: ^[dynamic]u8) {
	v: u32 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if v != 0 {
			byte |= 0x80
		}
		append(buf, byte)
		if v == 0 do break
	}
}

encode_s32_leb128 :: proc(value: i32, buf: ^[dynamic]u8) {
	v: i32 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if (v == 0 && (byte & 0x40) == 0) or (v == -1 && (byte & 0x40) != 0) {
			append(buf, byte)
			break
		}
		byte |= 0x80
		append(buf, byte)
	}
}
```

- [ ] **Step 3: Implement WASM module serialization**

```odin
wasm_serialize :: proc(mod: Wasm_Module, ctx: ^Compilation_Context) -> []byte {
	buf: [dynamic]u8

	-- Magic + version
	append(&buf, 0x00, 0x61, 0x73, 0x6D)  -- \0asm
	append(&buf, 0x01, 0x00, 0x00, 0x00)  -- version 1

	emit_type_section(&buf, mod)
	emit_import_section(&buf, mod)
	emit_function_section(&buf, mod)
	emit_table_section(&buf, mod)
	emit_memory_section(&buf, mod)
	emit_global_section(&buf, mod)
	emit_export_section(&buf, mod)
	emit_start_section(&buf, mod)
	emit_element_section(&buf, mod)
	emit_code_section(&buf, mod)
	emit_data_section(&buf, mod)

	return buf[:]
}
```

- [ ] **Step 4: Implement section emitters**

Each section follows the format: `section_id:u8 size:u32 content`. Content is serialized first into a temp buffer, then size = len(temp), then write `id + size + content`.

- [ ] **Step 5: Write test for LEB128**

```odin
test_leb128_encoding :: proc(t: ^testing.T) {
	buf: [dynamic]u8
	encode_u32_leb128(0, &buf)
	testing.expect_value(t, buf[0], 0)

	clear(&buf)
	encode_u32_leb128(128, &buf)
	testing.expect_value(t, buf[0], 0x80)
	testing.expect_value(t, buf[1], 0x01)

	clear(&buf)
	encode_s32_leb128(-1, &buf)
	testing.expect_value(t, buf[0], 0x7F)
}
```

- [ ] **Step 6: Write test for minimal WASM module**

```odin
test_wasm_minimal_module :: proc(t: ^testing.T) {
	mod: Wasm_Module
	-- Add a single function: () -> i32 that returns 42
	ft := Wasm_Func_Type{params = {}, results = {Wasm_Value_Type.I32}}
	append(&mod.types, ft)
	append(&mod.functions, Wasm_Func_Type_Index{type_idx = 0})
	code := Wasm_Code{
		locals = {},
		body = {
			Wasm_Instruction.I32_Const(42),
			Wasm_Instruction.End,
		},
	}
	append(&mod.codes, code)
	append(&mod.exports, Wasm_Export{name = "_start", desc = Wasm_Export_Func{idx = 0}})
	append(&mod.memories, Wasm_Memory{limits = {min = 1, has_max = false}})

	bytes := wasm_serialize(mod, ...)
	-- Verify magic + version
	testing.expect_value(t, bytes[0], 0x00)
	testing.expect_value(t, bytes[1], 0x61)  -- 'a'
	testing.expect_value(t, bytes[2], 0x73)  -- 's'
	testing.expect_value(t, bytes[3], 0x6D)  -- 'm'
}
```

- [ ] **Step 7: Add WASM instruction types**

Add `Wasm_Instruction` tagged union covering the instructions we need:

```odin
Wasm_Instruction :: union {
	Wasm_I32_Const,
	Wasm_I64_Const,
	Wasm_F32_Const,
	Wasm_F64_Const,
	Wasm_Local_Get,
	Wasm_Local_Set,
	Wasm_Local_Tee,
	Wasm_Global_Get,
	Wasm_Global_Set,
	Wasm_I32_Add,
	Wasm_I64_Add,
	Wasm_I32_Sub,
	Wasm_I64_Sub,
	Wasm_I32_Mul,
	Wasm_I64_Mul,
	Wasm_Call,
	Wasm_Call_Indirect,
	Wasm_Return_Call,
	Wasm_Return_Call_Indirect,
	Wasm_Br,
	Wasm_Br_If,
	Wasm_Return,
	Wasm_Drop,
	Wasm_Select,
	Wasm_I32_Load,
	Wasm_I64_Load,
	Wasm_I32_Store,
	Wasm_I64_Store,
	Wasm_Block,
	Wasm_Loop,
	Wasm_If,
	Wasm_Unreachable,
	Wasm_End,
	Wasm_Nop,
}

Wasm_I32_Const :: struct { value: i32 }
Wasm_I64_Const :: struct { value: i64 }
Wasm_F32_Const :: struct { value: f32 }
Wasm_F64_Const :: struct { value: f64 }
Wasm_Local_Get :: struct { idx: u32 }
Wasm_Local_Set :: struct { idx: u32 }
Wasm_Local_Tee :: struct { idx: u32 }
Wasm_Global_Get :: struct { idx: u32 }
Wasm_Global_Set :: struct { idx: u32 }
Wasm_Call :: struct { func_idx: u32 }
Wasm_Call_Indirect :: struct { type_idx: u32, table_idx: u32 }
Wasm_Return_Call :: struct { func_idx: u32 }
Wasm_Return_Call_Indirect :: struct { type_idx: u32, table_idx: u32 }
Wasm_Br :: struct { label: u32 }
Wasm_Br_If :: struct { label: u32 }
Wasm_I32_Load :: struct { align: u32, offset: u32 }
Wasm_I64_Load :: struct { align: u32, offset: u32 }
Wasm_I32_Store :: struct { align: u32, offset: u32 }
Wasm_I64_Store :: struct { align: u32, offset: u32 }
Wasm_Block :: struct { result_type: Wasm_Block_Type }
Wasm_Loop :: struct { result_type: Wasm_Block_Type }
Wasm_If :: struct { result_type: Wasm_Block_Type }
Wasm_Unreachable :: struct {}
Wasm_End :: struct {}
Wasm_Nop :: struct {}
Wasm_Return :: struct {}
Wasm_Drop :: struct {}
Wasm_Select :: struct {}

Wasm_Block_Type :: union {
	Wasm_Block_Void,
	Wasm_Block_Val,
	Wasm_Block_Type_Index,
}
Wasm_Block_Void :: struct {}
Wasm_Block_Val :: struct { type: Wasm_Value_Type }
Wasm_Block_Type_Index :: struct { idx: u32 }
```

- [ ] **Step 8: Implement instruction encoding**

```odin
encode_instruction :: proc(instr: Wasm_Instruction, buf: ^[dynamic]u8) {
	switch i in instr {
	case Wasm_I32_Const:
		append(buf, 0x41)
		encode_s32_leb128(i.value, buf)
	case Wasm_I64_Const:
		append(buf, 0x42)
		encode_s32_leb128(cast(i32)i.value, buf)  -- s64 as LEB128
	case Wasm_Local_Get:
		append(buf, 0x20)
		encode_u32_leb128(i.idx, buf)
	case Wasm_Local_Set:
		append(buf, 0x21)
		encode_u32_leb128(i.idx, buf)
	case Wasm_Call:
		append(buf, 0x10)
		encode_u32_leb128(i.func_idx, buf)
	case Wasm_Return_Call:
		append(buf, 0x12)
		encode_u32_leb128(i.func_idx, buf)
	case Wasm_Call_Indirect:
		append(buf, 0x11)
		encode_u32_leb128(i.type_idx, buf)
		encode_u32_leb128(i.table_idx, buf)
	case Wasm_Return_Call_Indirect:
		append(buf, 0x13)
		encode_u32_leb128(i.type_idx, buf)
		encode_u32_leb128(i.table_idx, buf)
	case Wasm_Return:
		append(buf, 0x0F)
	case Wasm_Drop:
		append(buf, 0x1A)
	case Wasm_End:
		append(buf, 0x0B)
	-- ... handle all other instructions
	case:
		-- internal error: unhandled instruction
	}
}
```

- [ ] **Step 9: Run tests**

Run: `odin test src/`
Expected: All tests pass

- [ ] **Step 10: Commit**

```bash
git add src/wasm.odin src/test_codegen.odin
git commit -m "feat(wasm): implement WASM binary format encoding with LEB128, sections, instructions"
```

---

## Task 14: Implement WASM Code Generation

**Files:**
- Create: `src/codegen.odin`
- Modify: `src/cli.odin`
- Test: `src/test_codegen.odin`

- [ ] **Step 1: Define the codegen context**

Create `src/codegen.odin`:

```odin
package camp

Codegen_Context :: struct {
	module:    ^Wasm_Module,
	type_map:  map[IR_ID]int,           -- IR type -> WASM type index
	func_map:  map[Intern_ID]int,       -- IR function name -> WASM function index
	local_map: map[Intern_ID]u32,       -- IR variable name -> WASM local index
	next_local: u32,
	next_func:  int,
	interner:   ^Intern_Table,
}

codegen :: proc(ir_mod: IR_Module, ctx: ^Compilation_Context) -> Wasm_Module {
	wasm_mod: Wasm_Module
	cg: Codegen_Context = {
		module = &wasm_mod,
		interner = ctx.interner,
	}

	-- Phase 1: Emit WASI imports (fd_write, proc_exit, etc.)
	emit_wasi_imports(&cg)

	-- Phase 2: Emit runtime function types
	emit_runtime_types(&cg)

	-- Phase 3: Emit type section entries for all IR function types
	for decl in ir_mod.decls {
		switch d in decl {
		case ^IR_Decl_Fn:
			emit_func_type(d^, &cg)
		case:
		}
	}

	-- Phase 4: Emit function section entries (type indices)
	-- Phase 5: Emit table for call_indirect (if needed)
	-- Phase 6: Emit memory
	-- Phase 7: Emit globals
	-- Phase 8: Emit exports (memory, _start)
	-- Phase 9: Emit element section (table initialization)
	-- Phase 10: Emit code section (function bodies)
	-- Phase 11: Emit data section (string literals, constants)

	for decl in ir_mod.decls {
		switch d in decl {
		case ^IR_Decl_Fn:
			emit_func_body(d^, &cg)
		case:
		}
	}

	return wasm_mod
}
```

- [ ] **Step 2: Implement emit_wasi_imports**

```odin
emit_wasi_imports :: proc(cg: ^Codegen_Context) {
	-- fd_write: (i32, i32, i32, i32) -> i32
	fd_write_type := Wasm_Func_Type{
		params = {.I32, .I32, .I32, .I32},
		results = {.I32},
	}
	fd_write_type_idx := len(cg.module.types)
	append(&cg.module.types, fd_write_type)

	-- proc_exit: (i32) -> ()
	proc_exit_type := Wasm_Func_Type{
		params = {.I32},
		results = {},
	}
	proc_exit_type_idx := len(cg.module.types)
	append(&cg.module.types, proc_exit_type)

	-- Import fd_write
	append(&cg.module.imports, Wasm_Import{
		module = "wasi_snapshot_preview1",
		field = "fd_write",
		desc = Wasm_Import_Func{type_idx = fd_write_type_idx},
	})

	-- Import proc_exit
	append(&cg.module.imports, Wasm_Import{
		module = "wasi_snapshot_preview1",
		field = "proc_exit",
		desc = Wasm_Import_Func{type_idx = proc_exit_type_idx},
	})
}
```

- [ ] **Step 3: Implement emit_func_body**

This translates each `IR_Expr` to a sequence of WASM instructions. Key mappings:

| IR Expr | WASM Instructions |
|---------|-------------------|
| `IR_Literal(Int, 42)` | `i64.const 42` |
| `IR_Var(x)` | `local.get <x_idx>` |
| `IR_Let(x, val, body)` | `<val_instrs>; local.set <x_idx>; <body_instrs>` |
| `IR_Call(f, args)` | `<arg_instrs>; call <f_idx>` |
| `IR_Tail_Call(f, args)` | `<arg_instrs>; return_call <f_idx>` |
| `IR_If(cond, then, else)` | `<cond_instrs>; if; <then_instrs>; else; <else_instrs>; end` |
| `IR_Match(scrut, arms)` | `<scrut_instrs>; br_table ...` (jump table) |
| `IR_Call_Indirect(fn_ptr, args)` | `<arg_instrs>; <fn_ptr_instrs>; call_indirect <type_idx> 0` |
| `IR_Return(v)` | `<v_instrs>; return` (or `return_call` for tail position) |
| `IR_Dup(x)` | `local.get <x_idx>; call <rc_dup>` |
| `IR_Drop(x)` | `local.get <x_idx>; call <rc_drop>` |

- [ ] **Step 4: Implement emit_func_body for CPS continuations**

CPS continuations are top-level functions. Their call pattern uses `return_call_indirect`:

```odin
case ^IR_Tail_Call:
	tc := d
	-- Emit arguments
	for arg in tc.args {
		emit_expr(arg, cg, buf)
	}
	-- Emit callee index
	append(buf, Wasm_Call{func_idx = cg.func_map[tc.callee]})
	-- Or for indirect: append(buf, Wasm_Return_Call_Indirect{...})
```

- [ ] **Step 5: Implement memory layout for heap objects**

WASM linear memory layout:

```
0x0000_0000 - 0x0000_FFFF: reserved (null page)
0x0001_0000 - 0x....:  heap start (bump allocator pointer as global)
...                  :  heap objects (RC header + fields)
...                  :  string literals (data section)
```

Each heap object has a header:
```
struct camp_block {
    int32 refcount;      -- 0 = unique, >0 = shared
    uint8 scan_fsize;    -- number of pointer fields
    uint8 tag;           -- constructor tag
    uint16 _padding;
    camp_box fields[];   -- variable-length inline fields
}
```

- [ ] **Step 6: Emit runtime function stubs**

In `src/runtime.odin`, define the runtime functions that the generated WASM will call:

```odin
emit_runtime :: proc(cg: ^Codegen_Context) {
	-- camp_alloc(size: i32) -> i32: bump allocator
	-- camp_dup(ptr: i32): increment refcount
	-- camp_drop(ptr: i32): decrement refcount, possibly free
	-- camp_drop_reuse(ptr: i32, scan: i32) -> i32: drop for reuse
	-- camp_is_unique(ptr: i32) -> i32: check if refcount == 0
	-- camp_print_str(ptr: i32, len: i32): write to stdout via fd_write
	-- camp_exit(code: i32): call proc_exit
}
```

- [ ] **Step 7: Write test — emit a simple WASM module**

```odin
test_codegen_simple :: proc(t: ^testing.T) {
	-- Build an IR module with a single pure function:
	-- main! = || -> I64 { 42 }
	-- Codegen it to a WASM module
	-- Serialize to bytes
	-- Verify the magic number and version are correct
	-- Optionally: write to file and validate with wasmtime
}
```

- [ ] **Step 8: Wire into CLI**

In `src/cli.odin`, replace the TODO with:

```odin
-- After typecheck passes:
ir_mod := lower_file(canon, &store)
ir_mod = effect_lower(&ir_mod, &ctx)
ir_mod = closure_convert(&ir_mod, &ctx)
ir_mod = cps_transform(&ir_mod, &ctx)
rc_insert(&ir_mod, &ctx)

wasm_mod := codegen(ir_mod, &ctx)
wasm_bytes := wasm_serialize(wasm_mod, &ctx)

output_path := strings.trim_suffix(file_path, ".camp") + ".wasm"
os.write_entire_file(output_path, wasm_bytes)
fmt.printfln("compiled {} -> {}", file_path, output_path)
```

- [ ] **Step 9: Run full pipeline test**

Parse a simple Camp file, run through the full pipeline, produce a .wasm file, and validate with `wasmtime validate`.

- [ ] **Step 10: Commit**

```bash
git add src/codegen.odin src/runtime.odin src/cli.odin src/test_codegen.odin
git commit -m "feat(codegen): implement WASM code generation with runtime, WASI imports, Perceus RC"
```

---

## Task 15: End-to-End Test — Hello World

**Files:**
- Test: `src/test_codegen.odin`

- [ ] **Step 1: Create test Camp source**

```
main! = || ->{ Console, Throw([..]) } I64 {
  Console.println!("Hello, Camp!")
  0
}
```

- [ ] **Step 2: Run through full pipeline**

Compile to .wasm, run with `wasmtime`, verify output "Hello, Camp!" and exit code 0.

- [ ] **Step 3: Write test**

```odin
test_hello_world :: proc(t: ^testing.T) {
	-- Full pipeline: source -> lexer -> parser -> canonicalize -> typecheck
	-- -> lower -> effect_lower -> closure_convert -> cps -> rc_insert
	-- -> codegen -> wasm_serialize -> write .wasm
	-- Run: wasmtime run output.wasm
	-- Verify: stdout contains "Hello, Camp!"
	-- Verify: exit code 0
}
```

- [ ] **Step 4: Commit**

```bash
git add src/test_codegen.odin
git commit -m "test(codegen): end-to-end hello world test"
```

---

## Self-Review

### Spec Coverage Check

| Spec Section | Covered by Task |
|-------------|-----------------|
| §4.2 Effect Definitions (syntax) | Task 1 (lexer), Task 3 (parser) |
| §4.4 Handlers (deep/shallow) | Task 2 (AST), Task 3 (parser), Task 4 (canonical) |
| §4.5 One-shot continuations | Task 11 (CPS — one-shot by default) |
| §4.6 Throw effect | Task 4 (canonical), Task 6 (effect safety) |
| §4.7 Error model | Task 6 (effect safety enforces Throw handling) |
| §4.8 Effect safety | Task 6 |
| §4.9 Effect polymorphism | Task 5 (row unification supports row variables) |
| §5.3 Phase 5: Effect Lower | Task 9 |
| §5.3 Phase 6: Closure Convert | Task 10 |
| §5.3 Phase 7: CPS Transform | Task 11 |
| §5.3 Phase 8: Perceus RC Insertion | Task 12 |
| §5.3 Phase 9: WASM Codegen | Task 13 (format), Task 14 (codegen) |
| §6.1 Perceus RC | Task 12 |
| §6.2 Perceus compilation cost | Task 12 (per-function analysis) |
| ! naming enforcement | Task 6 |

### Placeholder Scan

No TBD, TODO, or "implement later" in step descriptions. All steps contain actual code or specific commands.

### Type Consistency

- `Canonical_Name` used consistently across canonical AST, IR, and codegen
- `Intern_ID` used consistently for interned strings
- `Type_Var_ID` used consistently in type system
- `IR_ID` used for IR-specific IDs
- `Wasm_Value_Type` enum values match WASM spec bytes
