# Dot Lambda Design Specification

## 1. Overview

Dot lambdas are anonymous method/field access expressions. A leading `.` creates a lambda that takes one argument and applies the chain to it.

| Syntax | Desugars to |
|--------|-------------|
| `.foo(x)` | `\|a\| a.foo(x)` |
| `.name` | `\|a\| a.name` |
| `.foo().bar(x)` | `\|a\| a.foo().bar(x)` |
| `.record.field.method(x).name` | `\|a\| a.record.field.method(x).name` |
| `.read!()` | `\|a\| a.read!()` |

Dot lambdas are valid in any expression position. Effect rows propagate naturally from the desugared body.

## 2. Syntax & Semantics

### 2.1 Syntax

A dot lambda is a `.` followed by an identifier, optionally followed by parenthesized arguments, then any further `.identifier(args?)` chain. The leading `.` is the syntactic marker — it signals "insert a lambda parameter as the receiver."

### 2.2 Rules

- The chain after `.` can mix method calls (`.foo(x)`), field access (`.name`), and any combination
- Effect rows propagate naturally — `.read!()` desugars to an effectful lambda
- The `!` suffix on method names follows the same rules as regular method calls
- Dot lambdas are valid in any expression position: `map(.name)`, `x == .foo(y)`, etc.

### 2.3 Disambiguation

- `.` in prefix position (start of expression) is a dot lambda
- `.` after an expression (infix) is a method call or field access
- `..` is the spread operator (record update, open types) — not two dots. No ambiguity with dot lambdas.

## 3. Architecture

### 3.1 Approach: Surface AST Node, Desugar at Canonicalization

Three approaches were considered:

| Approach | Description | Verdict |
|----------|-------------|---------|
| Desugar at parse time | No new AST node, parse directly to `Expr_Lambda` | Rejected — loses source info for formatter, LSP, error messages |
| **Surface AST node, desugar at canonicalization** | `Expr_Dot_Lambda` in surface AST, canonicalizer produces `CExpr_Lambda` | **Chosen** |
| Carry through entire pipeline | Distinct node at every stage | Rejected — high blast radius, every stage needs a new case for semantically identical construct |

Canonicalization is already the "resolve sugar" phase — it handles name resolution and other normalization. Adding dot lambda desugaring here follows the existing pattern.

### 3.2 Surface AST

Add `Expr_Dot_Lambda` to the `Expr` union in `ast.odin`:

```
Expr_Dot_Lambda :: struct {
    body:  Expr,
    span:  Source_Span,
}
```

The `body` is the receiver-less chain. For `.foo(x).bar`, the body is an `Expr_Method_Call` whose receiver is another `Expr_Method_Call` with a synthetic placeholder receiver.

### 3.3 Placeholder Receiver

The parser creates a special `Expr_Identifier` with the reserved name `__dot_receiver__`. This name is never valid in user code. The canonicalizer recognizes it and replaces it with the fresh lambda parameter.

### 3.4 Canonicalization

Desugar `Expr_Dot_Lambda` to `CExpr_Lambda`:

1. Generate a fresh parameter name (e.g., `_dot_0`, `_dot_1` per desugaring, using the intern table)
2. Walk the body tree, finding the leftmost deepest `Expr_Identifier` whose name is `__dot_receiver__` — this is the placeholder inserted by the parser at the innermost receiver position. Replace it with an `Expr_Identifier` for the fresh parameter.
3. Canonicalize the desugared body normally
4. Construct a `CExpr_Lambda` with that single parameter and the canonicalized body
5. No `CExpr_Dot_Lambda` in the canonical AST — it's gone after this phase

### 3.5 Downstream Stages

Zero changes to typechecker, lowerer, effect_lower, closure_convert, cps, rc, and codegen. They all see a plain `CExpr_Lambda`, which they already handle correctly.

## 4. Parser Changes

### 4.1 Detection

When `parser_parse_prefix` encounters a `Dot` token at the start of an expression, it enters dot-lambda parsing mode.

### 4.2 Algorithm

1. Consume the leading `.`
2. Expect an identifier (the method/field name)
3. Check for `(` — if present, parse arguments → produces `Expr_Method_Call`
4. If no `(`, produces `Expr_Field_Access`
5. Continue consuming `.identifier(args?)` chain via the existing `parser_parse_method_chain` logic, passing the placeholder as the initial receiver
6. Wrap the result in `Expr_Dot_Lambda`

### 4.3 Edge Case: Chained Dot Lambdas

`..foo` is not a dot lambda followed by a field access. The `..` token is `Dot_Dot` (used for record spread), not two `.` tokens. No ambiguity.

## 5. Tree-sitter Grammar

### 5.1 Grammar Rule

Add an `anonymous_method_expression` rule to `_primary_expression`:

```js
anonymous_method_expression: ($) => prec(9, seq(
  ".",
  field("name", $.identifier),
  optional(field("arguments", $.arguments)),
)),
```

Precedence 9 matches method calls/field access.

### 5.2 Chaining

`.foo().bar(x)` — the `anonymous_method_expression` produces just the first `.foo()`, then the existing `method_call_expression` and `field_access_expression` rules chain the rest. The tree-sitter tree:

```
(method_call_expression
  receiver: (anonymous_method_expression
    name: "foo"
    arguments: (arguments))
  method: "bar"
  arguments: (arguments (identifier)))
```

### 5.3 Conflicts

May add a conflict with `field_access_expression` since both start with `.`. The difference is context — `anonymous_method_expression` appears in prefix position (no left operand), while `field_access_expression` appears in infix position (has a left operand). Tree-sitter's GLR should handle this, verified with corpus tests.

### 5.4 Corpus Tests

Add entries to `expressions.txt`:

- `.foo(x)` — simple method
- `.name` — field access
- `.foo().bar(x)` — chained method + method
- `.record.field.method(x).name` — mixed field access and method calls
- `.read!()` — effectful method

## 6. Formatter Changes

Dot lambdas follow the existing method chain formatting rules (first-operator rule).

### 6.1 Single-line

```camp
list.map(.name).filter(.is_valid)
```

### 6.2 Multi-line

Break at first `.` in the chain:

```camp
list
    .map(.name)
    .filter(.is_valid)
```

Dot lambda as chain start:

```camp
.foo(x)
.bar(y)
```

### 6.3 Backslash Split Points

Same as regular method chains — `\` before `.` forces a line break and creates independent sub-groups.

### 6.4 Key Point

The formatter operates on the surface AST, so it sees `Expr_Dot_Lambda` and emits `.foo(x)` rather than the desugared lambda form.

## 7. Documentation Updates

### 7.1 Language Design Spec

Add dot lambdas to Section 3 (Type System and Syntax):
- Syntax and desugaring rules
- Valid positions (any expression)
- Effect row propagation
- Interaction with `!` suffix convention
- Disambiguation from `..` spread syntax

Add to Appendix C (Syntax Reference Card): `.foo(x)` and `.name` in the expression syntax table.

### 7.2 Tree-sitter Grammar Spec

Add `anonymous_method_expression` to the grammar rules section and precedence table.

### 7.3 Formatter Spec

Add dot lambda formatting rules alongside the existing method chain section.

## 8. Error Cases

| Case | Diagnostic |
|------|-----------|
| `.42` (dot followed by non-identifier) | "expected identifier after '.'" |
| `.` at end of file | "expected identifier after '.'" |
| `__dot_receiver__` in user source | Treated as undefined name — unlikely to appear in practice |

### 8.1 Post-Canonicalization Errors

Type errors and other post-canonicalization diagnostics reference the desugared lambda parameter name (`_dot_0`). The span points back to the dot lambda's source location. Improving these messages to say "dot lambda" is a future enhancement.
