## 1. Lexer: `!` in Identifier Names

- [ ] 1.1 Modify `lexer_lex_identifier` in `src/lexer.odin` to consume trailing `!` characters (up to 2) and append them to the identifier token text
- [ ] 1.2 Verify `!=` still produces `Bang_Eq`, standalone `!` produces `Bang`, and `Kw_True`/`Kw_False` are unaffected
- [ ] 1.3 Run `odin test src` to confirm all 117 unit tests pass

## 2. Parser: `!` Suffix Detection in Token Text

- [ ] 2.1 Update `parser_parse_const_decl` to set `is_effectful` by checking `strings.has_suffix(name.text, "!")` instead of `p.current.kind == .Bang`
- [ ] 2.2 Update `parser_parse_tag_or_call` to check token text suffix for `!` instead of consuming a separate `Bang` token
- [ ] 2.3 Update `parser_parse_method_chain` to detect `!` in method token text and set `is_effectful` accordingly
- [ ] 2.4 Remove dead `Bang`-consumption code that is now handled by the lexer (or make it idempotent with a suffix check)
- [ ] 2.5 Run `odin test src` to confirm unit tests pass

## 3. E2E Test File Fixes: Paren-Style Lambdas → Pipe-Form

- [ ] 3.1 Fix `tests/e2e/generics/identity-function/Main.camp`: `(x) { x }` → `|x| { x }`
- [ ] 3.2 Fix `tests/e2e/generics/generic-pair/Main.camp`: `(a, b) { ... }` → `|a, b| { ... }`
- [ ] 3.3 Fix `tests/e2e/generics/generic-with-constraint/Main.camp`: `(x) { x + 1 }` → `|x| { x + 1 }`
- [ ] 3.4 Fix `tests/e2e/generics/generic-function-compose/Main.camp`: `(f, g, x) { ... }` → `|f, g, x| { ... }`
- [ ] 3.5 Fix `tests/e2e/typechecking/lambda-inference/Main.camp`: `(x) { x }` → `|x| { x }`
- [ ] 3.6 Fix `tests/e2e/typechecking/function-param-inference/Main.camp`: `(x) { x + 1 }` → `|x| { x + 1 }`
- [ ] 3.7 Fix `tests/e2e/typechecking/higher-order-function/Main.camp`: `(f, x) { f(x) }` → `|f, x| { f(x) }`
- [ ] 3.8 Fix `tests/e2e/typechecking/let-polymorphism/Main.camp`: `(x) { x }` → `|x| { x }`
- [ ] 3.9 Fix `tests/e2e/typechecking/function-type-annotation/Main.camp`: `(x: I64) -> I64 { ... }` → `|x: I64| -> I64 { ... }`
- [ ] 3.10 Fix `tests/e2e/typechecking/return-type-annotation/Main.camp`: `(x) -> I64 { x }` → `|x| -> I64 { x }`
- [ ] 3.11 Fix `tests/e2e/typechecking/effectful-function/Main.camp`: `(name) -> -[IO]-> String { name }` → `|name| -> -[IO]-> String { name }`
- [ ] 3.12 Fix `tests/e2e/closures/higher-order-map/Main.camp`: `(f, xs) { ... }` → `|f, xs| { ... }`
- [ ] 3.13 Fix `tests/e2e/closures/higher-order-filter/Main.camp`: `(pred, xs) { ... }` → `|pred, xs| { ... }`
- [ ] 3.14 Fix `tests/e2e/closures/partial-application/Main.camp`: `(a, b) -> I64 { ... }` → `|a, b| -> I64 { ... }`
- [ ] 3.15 Fix `tests/e2e/closures/function-composition/Main.camp`: `(f, g) -> (I64) -> I64 { ... }` → `|f, g| -> (I64) -> I64 { ... }`
- [ ] 3.16 Fix `tests/e2e/closures/recursive-closure/Main.camp`: `() -> I64 { ... }` → `|| -> I64 { ... }`
- [ ] 3.17 Fix `tests/e2e/closures/closure-free-var/Main.camp`: `() -> I64 { x }` → `|| -> I64 { x }`
- [ ] 3.18 Fix `tests/e2e/closures/closure-nested/Main.camp`: `() -> I64 { ... }` → `|| -> I64 { ... }`
- [ ] 3.19 Fix `tests/e2e/closures/closure-mutation-simulated/Main.camp`: `() -> I64 { x.val }` → `|| -> I64 { x.val }`
- [ ] 3.20 Fix `tests/e2e/records/record-as-function-return/Main.camp`: `(a) -> { x: I64 } { ... }` → `|a| -> { x: I64 } { ... }`

## 4. Parser: Inferred Generic Type Parameters

- [ ] 4.1 Treat lowercase type variables (e.g., `a`, `b`, `e`) in annotations as auto-generalized type parameters — no explicit `<a>` syntax needed
- [ ] 4.2 When a lowercase type variable appears in a function's parameter or return type annotation, introduce it as a named type parameter during canonicalization
- [ ] 4.3 Verify `generics/basic/Main.camp` (`id = |x: a| -> a { x }`) parses correctly
- [ ] 4.4 Run `odin test src` to confirm unit tests pass

## 5. Parser: Match Guard Syntax

- [ ] 5.1 In `parser_parse_match_arm`, after parsing the pattern, check if `p.current.kind == .Kw_If`; if so, parse guard expression before `Fat_Arrow`
- [ ] 5.2 Add `guard` field to `Match_Arm` AST node (or use existing field if present)
- [ ] 5.3 Update canonicalizer to carry guard through to `CMatch_Arm`
- [ ] 5.4 Update typechecker to typecheck guard as `Bool`
- [ ] 5.5 Verify `pattern-matching/match-with-guard` parses and typechecks

## 6. Parser: Or-Pattern Syntax

- [ ] 6.1 Add `Pattern_Or` variant to the pattern AST in `src/ast.odin`
- [ ] 6.2 In match arm pattern parsing, when `|` appears between patterns (before `=>`), collect alternatives into `Pattern_Or`
- [ ] 6.3 Update canonicalizer for `CPattern_Or`
- [ ] 6.4 Update typechecker for `CPattern_Or`: each alternative must bind the same names with the same types
- [ ] 6.5 Update unused analysis for `CPattern_Or` pattern traversal
- [ ] 6.6 Fix `pattern-matching/match-or-pattern/Main.camp` to use `=>` instead of `->` for arm separator
- [ ] 6.7 Verify `pattern-matching/match-or-pattern` parses correctly

## 7. Parser: Unary `+` Prefix Operator

- [ ] 7.1 Add `.Plus = 7` to `PREFIX_BP` map in `src/parser.odin`
- [ ] 7.2 Add `.Plus` case in `parser_parse_prefix` alongside `.Minus` and `.Kw_Not`
- [ ] 7.3 Verify `typechecking/float-type/Main.camp` (`f = +3.14`) parses correctly

## 8. Parser: Inline Type Annotations in Block Scope

- [ ] 8.1 In `parser_parse_expr_or_decl`, after parsing an `Expr_Identifier` followed by `Colon`, parse type annotation then `Eq` then value expression
- [ ] 8.2 Return a `CExpr_Name`-style node with type annotation attached (or appropriate AST node for typed binding in block scope)
- [ ] 8.3 Verify kitchen-sink `primitives_demo` parses (`i8_val: I8 = 127` etc.)

## 9. Typechecker: `True`/`False` as `Bool` Primitive

- [ ] 9.1 In `typecheck_synth` for `CExpr_Bool`, create a type variable and unify it with the prelude `Bool` primitive type (not a tag union)
- [ ] 9.2 Verify `if True 1 else 0` typechecks without "tag union does not match Bool" error
- [ ] 9.3 Verify `typechecking/if-both-branches-same-type` and `typechecking/if-branch-mismatch` produce their intended errors (branch mismatch, not condition type error)
- [ ] 9.4 Run `odin test src` to confirm unit tests pass

## 10. Typechecker: Trait Method Name Resolution

- [ ] 10.1 In trait conformance checking, when looking for method implementations for nominal type `T` and trait method `m`, look for a binding named `T_m` (concatenation of type name, underscore, method name) in the current module's environment
- [ ] 10.2 Verify the method's type signature matches the trait's expected signature (with `Self` replaced by `T`)
- [ ] 10.3 Verify `traits/basic`, `traits/signature-mismatch`, `traits/overlapping-instance`, `traits/orphan-rule` produce their intended error messages

## 11. Unused Analysis: Fix `_` Prefix Hint for Top-Level

- [ ] 11.1 In `diag_unused_binding` (or its caller), when the binding is top-level and already starts with `_`, do NOT include the "Prefix with `_`" hint in `d.hints`
- [ ] 11.2 Verify `typechecking/bool-type`, `typechecking/tag-construction` etc. produce error messages without contradictory "Prefix with `_`" suggestion

## 12. Kitchen-Sink Test Fixes

- [ ] 12.1 Wrap bare top-level tag expressions (`Ok(42)`, `Err("fail")`, `None`, `True`) in bindings (e.g., `_ = Ok(42)`) or comment them out
- [ ] 12.2 Fix `add` function syntax to use pipe-form params
- [ ] 12.3 Fix `logic_demo` function syntax
- [ ] 12.4 Fix `main!` entry point syntax (should work after Phase 1)
- [ ] 12.5 Fix match arm separators to use `=>` not `->`

## 13. Snapshot Regeneration and Final Validation

- [ ] 13.1 Run `just build && just build-e2e`
- [ ] 13.2 Run `just update-snapshots` to regenerate all `expected.toml` files
- [ ] 13.3 Run `just test-e2e` and verify all tests pass
- [ ] 13.4 Run `odin test src` and verify all unit tests pass
- [ ] 13.5 Run `just test` (full suite: unit + e2e + tree-sitter) and verify exit code 0
