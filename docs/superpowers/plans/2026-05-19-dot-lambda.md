# Dot Lambda Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dot lambdas (`.foo(x)` → `|a| a.foo(x)`) to Camp with full pipeline support.

**Architecture:** Add `Expr_Dot_Lambda` to the surface AST. Parser produces it when `.` appears in prefix position. Canonicalizer desugars it to `CExpr_Lambda` by replacing a sentinel placeholder with a fresh parameter. Downstream stages (typecheck, lower, etc.) need zero changes. Tree-sitter grammar, corpus tests, and formatter all get updates.

**Tech Stack:** Odin (compiler), tree-sitter (grammar.js), tree-sitter corpus tests

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/ast.odin` | Modify | Add `Expr_Dot_Lambda` to `Expr` union + struct definition |
| `src/parser.odin` | Modify | Add dot lambda parsing in `parser_parse_prefix`, add `parser_parse_dot_lambda` |
| `src/canonicalize.odin` | Modify | Add `Expr_Dot_Lambda` case that desugars to `CExpr_Lambda` |
| `src/test_parser.odin` | Modify | Add parser tests for dot lambdas |
| `src/test_canonicalize.odin` | Modify | Add canonicalization tests for dot lambda desugaring |
| `tree-sitter/grammar.js` | Modify | Add `anonymous_method_expression` rule |
| `tree-sitter/test/corpus/expressions.txt` | Modify | Add dot lambda corpus tests |
| `tree-sitter/queries/highlights.scm` | Modify | Add `anonymous_method_expression` highlight |

---

### Task 1: Add `Expr_Dot_Lambda` to the Surface AST

**Files:**
- Modify: `src/ast.odin:79-104` (Expr union), `src/ast.odin:316-337` (after Expr_Handle)

- [ ] **Step 1: Add `^Expr_Dot_Lambda` to the `Expr` union**

In `src/ast.odin`, add `^Expr_Dot_Lambda,` after `^Expr_Handle,` in the `Expr` union (line 103):

```odin
Expr :: union {
	^Expr_Int,
	^Expr_Float,
	^Expr_String,
	^Expr_Bool,
	^Expr_Tag,
	^Expr_Record,
	^Expr_List,
	^Expr_Identifier,
	^Expr_Dollar_Identifier,
	^Expr_Call,
	^Expr_Method_Call,
	^Expr_Lambda,
	^Expr_Block,
	^Expr_If,
	^Expr_Match,
	^Expr_BinOp,
	^Expr_PrefixOp,
	^Expr_Field_Access,
	^Expr_Record_Update,
	^Expr_Assign,
	^Expr_Return,
	^Expr_Crash,
	^Expr_Interpolate,
	^Expr_Handle,
	^Expr_Dot_Lambda,
}
```

- [ ] **Step 2: Add the `Expr_Dot_Lambda` struct definition**

Add after the `Expr_Handle` struct (after line 329):

```odin
Expr_Dot_Lambda :: struct {
	body: Expr,
	span: Source_Span,
}
```

- [ ] **Step 3: Add `Expr_Dot_Lambda` case to `expr_span_start` in `src/parser.odin`**

Add before the `case:` default in `expr_span_start` (around line 84):

```odin
	case ^Expr_Dot_Lambda:        return e.span.start
```

- [ ] **Step 4: Add `Expr_Dot_Lambda` case to `right_span_end` in `src/parser.odin`**

Add before the `case:` default in `right_span_end` (around line 114):

```odin
	case ^Expr_Dot_Lambda:        return e.span.end
```

- [ ] **Step 5: Build and verify no compile errors**

Run: `just build`
Expected: Build succeeds. Nothing references `Expr_Dot_Lambda` yet, so it's a no-op addition.

- [ ] **Step 6: Commit**

```bash
git add src/ast.odin src/parser.odin
git commit -m "feat(ast): add Expr_Dot_Lambda to surface AST"
```

---

### Task 2: Parse Dot Lambdas

**Files:**
- Modify: `src/parser.odin:227-312` (parser_parse_prefix)

- [ ] **Step 1: Add `DOT_RECEIVER_SENTINEL` constant**

Add near the top of `src/parser.odin` (after the `INFIX_BP` map, around line 29):

```odin
DOT_RECEIVER_SENTINEL :: "__dot_receiver__"
```

- [ ] **Step 2: Add dot lambda case to `parser_parse_prefix`**

In `parser_parse_prefix`, add a new case for `.Dot` before the `case:` default (around line 305):

```odin
	case .Dot:
		return parser_parse_dot_lambda(p)
```

- [ ] **Step 3: Implement `parser_parse_dot_lambda`**

Add after `parser_parse_method_chain` (after line 411):

```odin
parser_parse_dot_lambda :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	placeholder_id := intern(p.intern, DOT_RECEIVER_SENTINEL)
	placeholder := new(Expr_Identifier)
	placeholder^ = Expr_Identifier{name = placeholder_id, span = start}

	method_tok := parser_expect(p, .Identifier)
	method_id := intern(p.intern, method_tok.text)

	mc := new(Expr_Method_Call)
	mc^ = Expr_Method_Call{
		receiver = placeholder,
		method = method_id,
		args = make([dynamic]Expr, 0, 4),
		span = method_tok.span,
	}

	if p.current.kind == .LParen {
		parser_advance(p)
		for p.current.kind != .RParen && p.current.kind != .Eof {
			arg := parser_parse_expr(p)
			append(&mc.args, arg)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RParen)
	}

	result_expr := Expr(mc)

	if p.current.kind == .Dot {
		result_expr = parser_parse_method_chain(p, result_expr)
	}

	if p.current.kind != .Dot {
		fa := new(Expr_Field_Access)
		fa^ = Expr_Field_Access{record = placeholder, field = method_id, span = method_tok.span}
		result_expr = Expr(fa)
		if p.current.kind == .Dot {
			result_expr = parser_parse_method_chain(p, result_expr)
		}
	}

	dl := new(Expr_Dot_Lambda)
	dl^ = Expr_Dot_Lambda{body = result_expr, span = start}
	return dl
}
```

Wait — the logic above has a flaw. If there are no parens, we need a field access, not a method call. And if there are parens, we need a method call. Let me write this correctly:

```odin
parser_parse_dot_lambda :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	placeholder_id := intern(p.intern, DOT_RECEIVER_SENTINEL)
	placeholder := new(Expr_Identifier)
	placeholder^ = Expr_Identifier{name = placeholder_id, span = start}

	name_tok := parser_expect(p, .Identifier)
	name_id := intern(p.intern, name_tok.text)

	initial: Expr

	if p.current.kind == .LParen {
		mc := new(Expr_Method_Call)
		mc^ = Expr_Method_Call{
			receiver = placeholder,
			method = name_id,
			args = make([dynamic]Expr, 0, 4),
			span = name_tok.span,
		}
		parser_advance(p)
		for p.current.kind != .RParen && p.current.kind != .Eof {
			arg := parser_parse_expr(p)
			append(&mc.args, arg)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RParen)
		initial = mc
	} else {
		fa := new(Expr_Field_Access)
		fa^ = Expr_Field_Access{record = placeholder, field = name_id, span = name_tok.span}
		initial = fa
	}

	result := initial
	if p.current.kind == .Dot {
		result = parser_parse_method_chain(p, result)
	}

	dl := new(Expr_Dot_Lambda)
	dl^ = Expr_Dot_Lambda{body = result, span = start}
	return dl
}
```

- [ ] **Step 4: Build and verify**

Run: `just build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add src/parser.odin
git commit -m "feat(parser): parse dot lambda expressions"
```

---

### Task 3: Add Parser Tests for Dot Lambdas

**Files:**
- Modify: `src/test_parser.odin:181-196` (after existing tests)

- [ ] **Step 1: Add test for simple dot lambda with method call**

Append to `src/test_parser.odin`:

```odin
@(test)
test_parser_dot_lambda_method :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".foo(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Method_Call:
			testing.expect(t, len(body.args) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `just test-unit`
Expected: All tests pass including the new one.

- [ ] **Step 3: Add test for dot lambda with field access**

```odin
@(test)
test_parser_dot_lambda_field :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".name", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Field_Access:
			testing.expect(t, true)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 4: Add test for chained dot lambda**

```odin
@(test)
test_parser_dot_lambda_chained :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".foo().bar(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		#partial switch body in e.body {
		case ^Expr_Method_Call:
			testing.expect(t, true)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 5: Add test for mixed dot lambda (field + method)**

```odin
@(test)
test_parser_dot_lambda_mixed :: proc(t: ^testing.T) {
	ctx: Compilation_Context
	context_init(&ctx)
	defer context_destroy(&ctx)

	expr := parse_expr(".record.field.method(x)", &ctx)
	testing.expect(t, !diag_collector_has_errors(&ctx.collector))
	#partial switch e in expr {
	case ^Expr_Dot_Lambda:
		testing.expect(t, true)
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 6: Run tests**

Run: `just test-unit`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/test_parser.odin
git commit -m "test(parser): add dot lambda parser tests"
```

---

### Task 4: Desugar Dot Lambdas in Canonicalization

**Files:**
- Modify: `src/canonicalize.odin:178-449` (canonicalize_expr)

- [ ] **Step 1: Add counter for fresh dot lambda parameter names**

Add a counter field or use a simple incrementing approach. In `canonicalize.odin`, add a helper near the top:

```odin
DOT_RECEIVER_NAME :: "__dot_receiver__"
```

- [ ] **Step 2: Add `replace_dot_receiver` helper**

Add after the `sort_type_fields_by_name` procedure (around line 630):

```odin
dot_lambda_counter : int = 0
DOT_RECEIVER_INTERN_ID : Intern_ID = 0

replace_dot_receiver :: proc(expr: Expr, replacement: Intern_ID) -> Expr {
	switch e in expr {
	case ^Expr_Identifier:
		if e.name == DOT_RECEIVER_INTERN_ID {
			c := new(Expr_Identifier)
			c^ = Expr_Identifier{name = replacement, span = e.span}
			return c
		}
		return expr

	case ^Expr_Method_Call:
		creceiver := replace_dot_receiver(e.receiver, replacement)
		args := make([dynamic]Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(Expr_Method_Call)
		c^ = Expr_Method_Call{receiver = creceiver, method = e.method, args = args, span = e.span}
		return c

	case ^Expr_Field_Access:
		crecord := replace_dot_receiver(e.record, replacement)
		c := new(Expr_Field_Access)
		c^ = Expr_Field_Access{record = crecord, field = e.field, span = e.span}
		return c

	case ^Expr_Call:
		ccallee := replace_dot_receiver(e.callee, replacement)
		args := make([dynamic]Expr, 0, len(e.args))
		for a in e.args {
			append(&args, replace_dot_receiver(a, replacement))
		}
		c := new(Expr_Call)
		c^ = Expr_Call{callee = ccallee, args = args, span = e.span}
		return c

	case:
		return expr
	}
}
```

Set `DOT_RECEIVER_INTERN_ID` once at canonicalization entry (in `canonicalize` proc, before the decl loop):

```odin
DOT_RECEIVER_INTERN_ID = intern(&ctx.interner, DOT_RECEIVER_NAME)
```

- [ ] **Step 3: Add `Expr_Dot_Lambda` case to `canonicalize_expr`**

In `canonicalize_expr`, add before the final fallback (before line 446 `case ^Expr_Handle:` and after the `case ^Expr_Interpolate:` block):

```odin
	case ^Expr_Dot_Lambda:
		dot_lambda_counter += 1
		param_name := fmt.tprintf("_dot_{}", dot_lambda_counter)
		param_id := intern(&ctx.interner, param_name)

		resolved_body := replace_dot_receiver(e.body, param_id)
		cbody := canonicalize_expr(resolved_body, scope, ctx)

		params := make([dynamic]CFunc_Param, 1)
		params[0] = CFunc_Param{name = param_id, span = e.span}

		c := new(CExpr_Lambda)
		c^ = CExpr_Lambda{
			params = params,
			body = cbody,
			span = e.span,
		}
		return c
```

Also add `import "core:fmt"` at the top of `canonicalize.odin` if not already present.

- [ ] **Step 4: Build and verify**

Run: `just build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add src/canonicalize.odin
git commit -m "feat(canonicalize): desugar dot lambdas to plain lambdas"
```

---

### Task 5: Add Canonicalization Tests for Dot Lambda Desugaring

**Files:**
- Modify: `src/test_canonicalize.odin:81-132` (after existing tests)

- [ ] **Step 1: Add test for dot lambda desugaring to lambda**

Append to `src/test_canonicalize.odin`:

```odin
@(test)
test_canonicalize_dot_lambda_method :: proc(t: ^testing.T) {
	file, ctx := canon_file("f = .foo(x)")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^CExpr_Method_Call:
				testing.expect(t, true)
			case:
				testing.expect(t, false)
			}
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 2: Add test for dot lambda field access desugaring**

```odin
@(test)
test_canonicalize_dot_lambda_field :: proc(t: ^testing.T) {
	file, ctx := canon_file("f = .name")
	defer context_destroy(ctx)
	defer free(ctx)

	testing.expect(t, len(file.decls) == 1)
	#partial switch decl in file.decls[0] {
	case ^CDecl_Const:
		#partial switch expr in decl.body {
		case ^CExpr_Lambda:
			testing.expect(t, len(expr.params) == 1)
			#partial switch body in expr.body {
			case ^CExpr_Field_Access:
				testing.expect(t, true)
			case:
				testing.expect(t, false)
			}
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}
```

- [ ] **Step 3: Run tests**

Run: `just test-unit`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/test_canonicalize.odin
git commit -m "test(canonicalize): add dot lambda desugaring tests"
```

---

### Task 6: Update Tree-sitter Grammar

**Files:**
- Modify: `tree-sitter/grammar.js`

- [ ] **Step 1: Add `anonymous_method_expression` rule to `_primary_expression`**

In `tree-sitter/grammar.js`, add `$.anonymous_method_expression,` to the `_primary_expression` choice (around line 183, before `$.return_expression`):

```js
    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.dollar_identifier,
      $.identifier,
      $.type_identifier,
      $.tag_expression,
      $.list_expression,
      $.parenthesized_expression,
      $.lambda_expression,
      $.block,
      $.record_expression,
      $.if_expression,
      $.match_expression,
      $.handle_expression,
      $.anonymous_method_expression,
      $.return_expression,
      $.crash_expression,
    ),
```

- [ ] **Step 2: Add `anonymous_method_expression` rule definition**

Add after `crash_expression` (around line 372):

```js
    anonymous_method_expression: ($) => prec(9, seq(
      ".",
      field("name", $.identifier),
      optional(field("arguments", $.arguments)),
    )),
```

- [ ] **Step 3: Add potential conflict**

Add to the `conflicts` array (around line 19):

```js
    [$.anonymous_method_expression, $.field_access_expression],
```

- [ ] **Step 4: Regenerate and test**

Run: `just tree-sitter-test`
Expected: Tree-sitter generates parser and all existing corpus tests pass.

- [ ] **Step 5: Commit**

```bash
git add tree-sitter/
git commit -m "feat(tree-sitter): add anonymous_method_expression grammar rule"
```

---

### Task 7: Add Tree-sitter Corpus Tests

**Files:**
- Modify: `tree-sitter/test/corpus/expressions.txt`

- [ ] **Step 1: Add dot lambda corpus test — method call**

Append to `tree-sitter/test/corpus/expressions.txt`:

```
========
Dot lambda method call
========
x = .foo(y)
---
(source_file
  (const_declaration
    (identifier)
    (anonymous_method_expression
      (identifier)
      (arguments
        (identifier)))))

========
Dot lambda field access
========
x = .name
---
(source_file
  (const_declaration
    (identifier)
    (anonymous_method_expression
      (identifier))))

========
Dot lambda chained method
========
x = .foo().bar(y)
---
(source_file
  (const_declaration
    (identifier)
    (method_call_expression
      (anonymous_method_expression
        (identifier)
        (arguments))
      (identifier)
      (arguments
        (identifier)))))

========
Dot lambda mixed field and method
========
x = .record.field.method(y).name
---
(source_file
  (const_declaration
    (identifier)
    (field_access_expression
      (method_call_expression
        (field_access_expression
          (anonymous_method_expression
            (identifier))
          (identifier))
        (identifier)
        (arguments
          (identifier)))
      (identifier))))
```

- [ ] **Step 2: Run tree-sitter tests**

Run: `just tree-sitter-test`
Expected: All corpus tests pass including new ones.

- [ ] **Step 3: Commit**

```bash
git add tree-sitter/test/corpus/expressions.txt
git commit -m "test(tree-sitter): add dot lambda corpus tests"
```

---

### Task 8: Update Tree-sitter Highlight Queries

**Files:**
- Modify: `tree-sitter/queries/highlights.scm`

- [ ] **Step 1: Add `anonymous_method_expression` to highlights**

The leading `.` is already highlighted as punctuation. The method name inside a dot lambda should be highlighted as a function/method. Add after the `(identifier) @variable` line (line 16):

```scm
;; Dot lambda method names
(anonymous_method_expression
  name: (identifier) @function.method)
```

- [ ] **Step 2: Run tree-sitter test to verify**

Run: `just tree-sitter-test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tree-sitter/queries/highlights.scm
git commit -m "feat(tree-sitter): highlight dot lambda method names"
```

---

### Task 9: Update Documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-05-18-camp-language-design.md`
- Modify: `docs/superpowers/specs/2026-05-19-tree-sitter-grammar-design.md`
- Modify: `docs/superpowers/specs/2026-05-19-formatter-design.md`

- [ ] **Step 1: Add dot lambda section to language design spec**

In `2026-05-18-camp-language-design.md`, add a new subsection after Section 3.9 (Var Syntax) and before Section 3.10 (Traits):

```markdown
### 3.10 Dot Lambdas

A dot lambda is a leading `.` followed by a method/field chain, creating an anonymous function that applies the chain to its argument.

| Syntax | Desugars to |
|--------|-------------|
| `.foo(x)` | `\|a\| a.foo(x)` |
| `.name` | `\|a\| a.name` |
| `.foo().bar(x)` | `\|a\| a.foo().bar(x)` |
| `.record.field.method(x)` | `\|a\| a.record.field.method(x)` |

**Rules**:
- Valid in any expression position
- Effect rows propagate naturally — `.read!()` desugars to an effectful lambda
- Mixes field access and method calls freely
- `..` is spread syntax, not a double dot lambda — no ambiguity

**Design decision**: Dot lambdas are desugared at canonicalization. The surface AST preserves the dot lambda structure for tooling (formatter, LSP, error messages), but the typechecker and later stages see a plain lambda.
```

Renumber subsequent sections (3.10 → 3.11, etc.).

- [ ] **Step 2: Add dot lambda to tree-sitter grammar design spec**

In `2026-05-19-tree-sitter-grammar-design.md`, add to the `_expression` → `_primary_expression` list:

```
    -> anonymous_method_expression  # .foo(x) or .name — dot lambda
```

And add to the precedence table:

```
anonymous_method_expression       prec.left(9)
```

- [ ] **Step 3: Add dot lambda to formatter design spec**

In `2026-05-19-formatter-design.md`, add a "Dot Lambdas" subsection in Section 7 (Expression Formatting), after "Method Chains":

```markdown
### Dot Lambdas

Follow the same first-operator rule as method chains.

Single-line:
```camp
list.map(.name).filter(.is_valid)
```

Multi-line (break at first `.` in the chain):
```camp
list
    .map(.name)
    .filter(.is_valid)
```

Dot lambda as chain start, multi-line:
```camp
.foo(x)
.bar(y)
```
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/
git commit -m "docs: add dot lambda to language, tree-sitter, and formatter specs"
```

---

### Task 10: End-to-End Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `just test-unit`
Expected: All unit tests pass.

- [ ] **Step 2: Run tree-sitter tests**

Run: `just tree-sitter-test`
Expected: All tree-sitter tests pass.

- [ ] **Step 3: Run e2e tests**

Run: `just test-e2e`
Expected: All e2e tests pass (dot lambdas don't break existing programs).

- [ ] **Step 4: Manually test dot lambda compilation**

Create a temporary test file:

```camp
foo = .name
bar = .toString()
baz = .record.field.method(x).name
```

Run: `./camp check <testfile>`
Expected: No crashes. Type errors are expected (undefined names), but no parse errors or internal compiler errors.
