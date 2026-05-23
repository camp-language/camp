## Context

The Camp compiler front-end (lexer → parser → canonicalizer → typechecker → unused analysis) is substantially complete per `openspec/specs/compiler/design.md`. However, ~90 of 120 e2e snapshot tests fail, almost all due to parser-level issues that cascade into syntax errors before reaching semantic analysis. The root causes fall into three categories:

1. **Lexer gap**: `!` is never appended to identifier tokens. `main!` lexes as `Identifier("main")` + `Bang`, producing cascading parse errors across ~30 tests.
2. **Test syntax mismatch**: ~20 e2e tests use `(params) { body }` paren-style lambda syntax, but the spec mandates `|params| body` as the sole function form (§Function Syntax).
3. **Typechecker gaps**: `True`/`False` resolve to tag unions instead of `Bool`; trait method name resolution doesn't follow the `TypeName_methodname` convention; match guards and or-patterns aren't parsed.

Current state: 28 e2e tests pass (effects, scheduler, pattern-matching basics, strings, tag-union matching). 117 unit tests pass.

## Goals / Non-Goals

**Goals:**
- All e2e tests produce the exact output in their `expected.toml`
- Lexer emits `!` as part of identifier text (up to 2 trailing `!`)
- Parser correctly handles `!` suffix embedded in tokens, inferred generic type parameters, match guards, or-patterns, unary `+`, inline type annotations in blocks
- Typechecker resolves `True`/`False` to `Bool` primitive type
- Trait method matching uses `TypeName_methodname` convention
- E2e test `.camp` files use spec-compliant `|params|` lambda syntax

**Non-Goals:**
- No changes to the language spec — all fixes align the implementation WITH the spec
- No codegen/WASM improvements (existing IR/codegen bugs tracked separately in compiler/design.md)
- No new e2e tests (only fixing existing ones)
- No changes to the effect lowering, closure conversion, CPS, or RC passes
- No module system or import resolution fixes

## Decisions

### Decision 1: Lexer absorbs `!` into identifier tokens

**Choice**: Append trailing `!` (up to 2) to identifier text in `lexer_lex_identifier`.

**Rationale**: The `!` suffix is part of the identifier name in Camp (e.g., `main!`, `println!`, `Async!`). Treating it as a separate token forces every consumer to manually concatenate, which is error-prone and produces cascading parse failures.

**Alternative considered**: Keep `!` as a separate token and fix every parser site. Rejected because there are 10+ parser locations that check for `Bang` after identifiers, each needing the same concatenation logic. Centralizing in the lexer eliminates an entire class of bugs.

**Constraint**: `!` is only absorbed when preceded by an identifier character. Standalone `!` (e.g., in `!=`) is handled by the main `lexer_next` dispatch before reaching `lexer_lex_identifier`.

### Decision 2: Fix e2e test `.camp` files, not add paren-lambda syntax to parser

**Choice**: Convert all `(params) { body }` test code to `|params| { body }`.

**Rationale**: The spec says `|args| body` is the sole function form. Adding an alternative syntax would violate the spec and create ambiguity with parenthesized expressions.

**Alternative considered**: Support both syntaxes. Rejected because the spec explicitly forbids it: "No `fn` or `def` keyword" and "all functions SHALL use `|args| body` syntax."

### Decision 3: Inferred type parameters from lowercase type variables

**Choice**: Lowercase type variables in function annotations (parameter types, return types) are auto-generalized. No explicit `<a>` syntax, no speculative parsing needed.

**Rationale**: The spec now uses `add = |x: a, y: a| -> a { x + y }` — type params are inferred from the `a` in annotations. This eliminates the ambiguous `<` vs less-than parsing problem entirely and matches standard Hindley-Milner inference.

**Alternative considered**: Speculative `<a>|` parsing. Rejected because it requires look-ahead, backtracking, and introduces ambiguity with comparison expressions. The inferred approach is simpler and more principled.

### Decision 4: Match guard as optional `if` after pattern

**Choice**: In `parser_parse_match_arm`, after parsing a pattern, if the next token is `Kw_If`, parse a guard expression before `Fat_Arrow`.

**Rationale**: Matches the spec's `pattern if guard =>` syntax directly.

### Decision 5: Or-pattern via `|` between pattern alternatives

**Choice**: In match arm parsing, when a pattern is followed by `|` (before `Fat_Arrow`), parse additional patterns and wrap in `Pattern_Or`.

**Rationale**: The spec shows `Get | Head | Options => True` syntax. The `|` already serves double duty (match arm separator), so context determines meaning: `|` before `=>` is an arm separator; `|` between patterns (no `=>` after the left pattern) is an or-pattern.

### Decision 6: `True`/`False` as `Bool` primitive, not tag union

**Choice**: In `typecheck_synth` for `CExpr_Bool`, resolve the type variable to the prelude `Bool` primitive type.

**Rationale**: `if True 1 else 0` currently errors with "tag union does not match Bool" because `True` is inferred as a tag union value. The prelude already injects `Bool` as a primitive type with `True`/`False` as its only inhabitants.

### Decision 7: Trait method resolution by `TypeName_methodname` convention

**Choice**: When checking trait conformance for `@UserId is Eq : U64`, look for a binding named `UserId_eq` in the same module.

**Rationale**: The spec says "it SHALL look for a standalone function `eq` in the same module whose type matches `|UserId, UserId| -> Bool`". The naming convention `TypeName_method` is the established pattern for avoiding namespace collisions when multiple types implement the same trait.

## Risks / Trade-offs

**[Risk] `!` absorption breaks effect declaration parsing** → In `parser_parse_const_decl`, the `Bang` check after `Upper_Id` becomes a no-op since `!` is already in the token. The `is_effectful` flag must be set by checking `strings.has_suffix(name.text, "!")` instead. Same for `parser_parse_method_chain`.

**[Risk] Lowercase type variables could shadow existing names** → A type variable `a` in an annotation could conflict with a concrete type named `a`. Mitigation: Concrete types use `Upper_Camel_Case` naming (per spec), so lowercase identifiers are always available for type variables. This is checked during name resolution.

**[Risk] Or-pattern `|` ambiguous with arm separator** → In `1 | 2 | 3 => body`, the `|` after `1` could be an arm separator. Mitigation: After parsing a pattern, check if `=>` follows. If `|` follows instead, treat it as an or-pattern continuation. If `=>` follows a `|`, it's an arm separator.

**[Risk] Snapshot regeneration changes error messages for currently-failing tests** → Many tests expect specific error text that will change. Mitigation: `just update-snapshots` regenerates all `expected.toml` files. Manual review of diff to ensure errors remain semantically correct.

**[Risk] Changing `.camp` files in tests could break the test intent** → Some tests intentionally test error messages. Mitigation: Only change syntax, not semantics. Error tests remain error tests; they just produce different (correct) errors.
