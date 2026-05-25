# Implement Test Blocks & Stdlib Test Coverage

## Problem

The `test` and `expect` keywords are plumbed through the entire compiler pipeline (lexer, parser, AST, canonical, typed, IR) but are broken in critical ways:

1. **Parser bug**: `parser_parse_test_decl` double-consumes `}` after the block body, making `test "name" { body }` always produce a syntax error
2. **No runtime `expect`**: Inside blocks, `expect cond` desugars to `expect(cond)` call expression, but no `expect` function exists in the runtime or stdlib — the program will fail at link time
3. **No failure reporting**: `expect` gives no diagnostic on failure — the test just crashes with exit code 1 and no message
4. **No doc comment attachment**: The syntax recipe says `///` before `expect` becomes the failure message, but the parser doesn't consume doc comment tokens at all
5. **No debug/production modes**: The spec says `expect` should be a no-op in production, but no compilation mode system exists
6. **Top-level `expect` is silently dropped**: It typechecks but produces no code at IR lowering

Without working test blocks, the 38 stdlib modules have no unit test coverage at all.

## Affected Spec Domains

- `testing-language` — `expect` expression behavior, `test` block compilation, failure messages
- `testing` — `camp test` runner behavior (test discovery, result reporting)
- `doc-comments` — doc comment attachment to declarations (prerequisite for `///` before `expect`)
- `compiler` — compilation mode system (debug/test/production)

## Current Implementation Status

- Lexer: `test` → `.Kw_Test`, `expect` → `.Kw_Expect` — working
- Parser: `parser_parse_test_decl` has double-`}` bug; `parser_parse_expect_decl` works; inline `expect` desugars to broken `expect(cond)` call
- AST: `Decl_Test`, `Decl_Expect` exist; no `Expr_Expect` for inline usage
- Canonical: `CDecl_Test`, `CDecl_Expect` exist; no `CExpr_Expect`
- Typed: `TDecl_Test`, `TDecl_Expect` exist; no `TExpr_Expect`
- IR: Both skipped at lowering (empty case bodies)
- Build: `camp test` discovers `Decl_Test`, compiles each as synthetic `main!`, runs via wasmtime — but only works if the parser bug is fixed and `expect` has a runtime
- Doc comments: Lexer produces `.Doc_Comment` tokens; parser never consumes them
- Compilation modes: None exist

## Goals

1. Fix the parser double-`}` bug so `test "name" { body }` parses correctly
2. Make `expect condition` work at runtime as a first-class intrinsic (not a call to a phantom function)
3. Add meaningful failure messages: condition source text as default, `///` doc comment as custom message
4. Support `expect` both inline (inside `test` blocks) and top-level (treated as named tests by `camp test`)
5. Add compilation modes (debug/test/production) so `expect` can be stripped in production
6. Implement comprehensive stdlib test coverage using `test` blocks

## Non-Goals

- Doctest extraction from `///` code blocks (depends on doc comment infrastructure, deferred to future change)
- `todo` production-mode compilation error (orthogonal, can be added with compilation modes)
- Changing the `camp test` CLI interface beyond what's needed for the above
- E2E snapshot test changes (that system works correctly already)
