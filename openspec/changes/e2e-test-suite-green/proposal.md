## Why

~90 of 120 e2e tests currently fail, most due to the lexer not supporting `!` in identifier names (blocking `main!`/`main!!` entry points), the parser not supporting alternative lambda syntaxes used in tests, and several typechecker/unused-analysis gaps. The compiler's front-end is substantially complete (per `openspec/specs/compiler/design.md`) but the gap between "parses" and "e2e tests pass" is large enough that real feature validation is impossible. Fixing these gaps unblocks the entire test suite and enables confident iteration on the compiler.

## What Changes

- **Lexer**: Append trailing `!` (up to 2) to identifier tokens, so `main!`, `main!!`, `IO!`, `println!` lex as single tokens instead of identifier + bang
- **Parser**: Update `parser_parse_const_decl`, `parser_parse_tag_or_call`, and `parser_parse_method_chain` to detect `!` suffix already embedded in token text (instead of expecting a separate `Bang` token)
- **Parser**: Add speculative parsing for `<a>|params|` generic lambda syntax (type params outside pipes, matching the spec example `add = <a>|x: a, y: a| -> a { x + y }`)
- **Parser**: Add match guard support (`pattern if guard =>`) in `parser_parse_match_arm`
- **Parser**: Add or-pattern support (`A | B =>`) via `Pattern_Or` in match arms
- **Parser**: Add unary `+` prefix operator for float literals
- **Parser**: Handle inline type annotations (`name: Type = value`) inside block scope
- **Typechecker**: Ensure `CExpr_Bool` (`True`/`False`) resolves to the prelude `Bool` primitive type, not a tag union
- **Typechecker**: Implement trait method name resolution using `TypeName_methodname` convention
- **Test files**: Convert `(params) { body }` paren-style lambdas to `|params| { body }` pipe-form in all e2e `.camp` files (the spec mandates pipe-form as the sole function syntax)
- **Test files**: Fix kitchen-sink bare top-level expressions (wrap in bindings), fix `=>` vs `->` in match arms
- **Snapshots**: Regenerate all `expected.toml` files after fixes via `just update-snapshots`

## Capabilities

### New Capabilities
- `match-extensions`: Or-patterns and guards in match expressions (new syntax in pattern-matching)
- `generic-lambda-syntax`: `<a>|params|` type-parameter syntax before pipe-delimited parameter lists

### Modified Capabilities
- `language`: `True`/`False` must resolve to `Bool` primitive (not tag union); inline type annotations `name: Type = value` in block scope
- `compiler`: Lexer must emit `!` as part of identifier tokens; parser must handle embedded `!` suffix; trait method name resolution by convention
- `diagnostics`: Unused-binding error messages must not suggest `_` prefix for top-level bindings that already start with `_`

## Impact

- **Lexer** (`src/lexer.odin`): `lexer_lex_identifier` appends trailing `!` to identifier text
- **Parser** (`src/parser.odin`): `parser_parse_const_decl`, `parser_parse_tag_or_call`, `parser_parse_method_chain`, `parser_parse_match_arm`, `parser_parse_prefix` all updated
- **Typechecker** (`src/typecheck.odin`): `CExpr_Bool` type resolution; trait method matching
- **Unused analysis** (`src/unused_analysis.odin`): No changes needed (behavior is spec-compliant; snapshots will update)
- **E2E tests** (`tests/e2e/**/*.camp`, `tests/e2e/**/*.toml`): ~40 `.camp` files updated to pipe-form lambdas; all `.toml` snapshots regenerated
- **No breaking changes to the language spec** — all changes align the implementation WITH the spec
