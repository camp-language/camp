# Design: Implement Test Blocks & Stdlib Test Coverage

## Architecture Decisions

### AD1: First-Class `Expr_Expect` Instead of Call Desugaring

**Decision**: Replace the current `expect(cond)` call-expression desugaring with a first-class `Expr_Expect` AST node that flows through the entire pipeline as an intrinsic.

**Rationale**: The current desugaring to `expect(condition)` requires a phantom `expect` function that doesn't exist. Making `expect` a first-class expression means:
- No stdlib dependency for the most basic assertion
- The condition's source text is preserved for default failure messages
- Type checking is explicit (condition must be `Bool`)
- Codegen can emit conditional crash inline (like `IR_Crash`)

**AST changes**:
```odin
Expr_Expect :: struct {
    condition: Expr,
    message:   Expr,    // optional: String_Literal or doc comment text; nil = use condition source
    span:      Source_Span,
}
```

**Pipeline flow**:
```
Expr_Expect (AST)
  → CExpr_Expect (Canonical)
  → TExpr_Expect (Typed)  [condition: TExpr, message: TExpr; condition unified with Bool]
  → IR_Expr_Expect (IR)    [condition: IR_Expr, message: IR_Expr]
  → WASM conditional crash (Codegen)
```

**IR node**:
```odin
IR_Expr_Expect :: struct {
    condition: IR_Expr,
    message:   IR_Expr,    // string to display on failure
    span:      Source_Span,
}
```

**Codegen** (following `IR_Crash` pattern):
```
IR_Expr_Expect:
  evaluate condition → [i32]
  if [i32] != 0: continue (assertion passed)
  if [i32] == 0:
    push message string
    drop string
    push exit_code = 1
    call Exit
```

**Impact**: Inline `expect` works in any expression/statement context. No phantom function needed. Failure messages are always available.

### AD2: Fix Parser Double-`}` Bug

**Decision**: Remove the `parser_expect(p, .RBrace)` call after `parser_parse_block_or_record` in `parser_parse_test_decl`.

**Rationale**: `parser_parse_block_or_record` → `parser_parse_block` already consumes the closing `}`. The extra `parser_expect` consumes the *next* token after the block (the start of the next declaration or EOF), causing the syntax error observed in the existing e2e test.

**Change**: One line removal in `src/frontend/parser.odin`.

### AD3: Top-Level `expect` as Synthetic Test

**Decision**: In `run_test`, treat each top-level `Decl_Expect` as a synthetic `test "expect at line N" { expect condition }` entry.

**Rationale**: The spec allows `expect` at top level. The existing `run_test` function already walks the AST for `Decl_Test` and `Decl_Expect`. Currently it counts `Decl_Expect` but doesn't compile them. Instead, each `Decl_Expect` should be compiled as its own test entry with:
- Test name: `"expect at line {line_number}"` (or `"expect at line {line_number}: {doc_comment}"` if a doc comment is attached)
- Test body: the expect condition, wrapped in the `Expr_Expect` expression
- Compiled and run identically to named test blocks

**Impact**: Top-level `expect` works without special IR lowering. `Decl_Expect` remains skipped at IR lowering for production builds; it's only meaningful during `camp test`.

### AD4: Doc Comment Attachment for `expect` Messages

**Decision**: Add a `pending_doc: string` field to `Parser` that accumulates consecutive `.Doc_Comment` tokens. Before parsing any declaration or `expect` expression, consume and clear `pending_doc`. Attach to `Decl_Expect.message`, `Expr_Expect.message`, and all other declaration types.

**Rationale**: The syntax recipe says "/// doc comment on line before shown on failure". The lexer already produces `.Doc_Comment` tokens. The parser just doesn't consume them. Accumulating and attaching is the standard approach.

**Parser changes**:
```odin
Parser :: struct {
    // ... existing fields ...
    pending_doc: string,   // accumulated /// doc comment text
}
```

In `parser_parse_decl`, before dispatching to the specific declaration parser:
1. While `p.current.kind == .Doc_Comment`: append text to `pending_doc`, advance
2. Pass `pending_doc` to the declaration constructor
3. Clear `pending_doc`

For `Expr_Expect` inside blocks, `parser_parse_expr_or_decl` does the same check before the `expect` keyword.

**Propagation**:
- `Decl_Expect.message: Expr` — string literal or nil
- `Expr_Expect.message: Expr` — string literal or nil
- All pipeline layers carry the `message` field
- At codegen: if `message` is present, use it; otherwise, use the condition's source text

### AD5: Default Failure Messages from Source Text

**Decision**: When `Expr_Expect.message` is nil, the codegen emits the condition's source text as the failure string.

**Rationale**: The syntax recipe says non-equality expects show "evaluated to False". The condition source text provides much more useful context. For `expect a == b`, the source text is `a == b`. For `expect list.is_empty()`, it's `list.is_empty()`.

**Implementation**: The `span` field on `Expr_Expect` captures the condition's location. At codegen time, extract the source text from the original source using the span's byte offsets. This requires passing the source text through to codegen or embedding it as a string literal during lowering.

**Preferred approach**: During IR lowering, if `TExpr_Expect.message` is nil, create an `IR_Expr_String` from the condition's source text (looked up from the source file by span). This embeds the string at compile time and avoids needing source text at codegen.

### AD6: Compilation Modes (Debug/Test/Production)

**Decision**: Add `Build_Mode :: enum { Debug, Test, Production }` to `Compilation_Context`. CLI flags: `camp build` → Production, `camp test` → Test, `camp build --debug` → Debug, `camp check` → Debug.

**Rationale**: The spec requires `expect` to be a no-op in production and `todo` to be a compile error in production. Without modes, there's no way to implement this.

**Mode behavior**:

| Feature | Debug | Test | Production |
|---------|-------|------|------------|
| `expect` | Runtime check + crash on false | Runtime check + crash on false | No-op (condition not evaluated) |
| `todo` | Runtime panic with message | Runtime panic with message | Compile error |
| `test` blocks | Skipped (no IR) | Skipped (no IR) | Skipped (no IR) |
| Effect row of `expect` | Includes sub-expression effects | Includes sub-expression effects | No effects (removed) |

**IR lowering by mode**:
- Debug/Test: `TExpr_Expect` → `IR_Expr_Expect` (full check)
- Production: `TExpr_Expect` → nothing (skipped, condition expression dropped)

**CLI changes** (`src/cli.odin`):
```odin
CLI_Command :: enum { Build, Test, Fmt, Check, Lsp }
// build sub-flags: --debug
```

**Impact**: Minimal — `Compilation_Context` gets one new field. IR lowering gets a mode parameter. `expect` and `todo` behavior varies by mode.

### AD7: Stdlib Test Organization — Same File

**Decision**: Test blocks live in the same `.camp` file as the implementation. They are always excluded from production builds (already the case — `TDecl_Test` is skipped at IR lowering).

**Rationale**: `camp test` works on a single file. Putting tests in the same file as the implementation means:
- No import needed (test block shares the file's scope)
- No separate test directory structure required
- Tests are stripped at IR lowering anyway, so they don't bloat production builds
- Matches the design intent: `test` blocks are part of the module

**Usage**: `camp test stdlib/Result.camp` runs all test blocks in Result.camp.

### AD8: Stdlib Test Strategy by Module Kind

**Decision**: Different test strategies for pure vs intrinsic vs declaration-only modules.

**Pure Camp modules** (Result, Bool, Iter, Num types):
- Test blocks with `expect` assertions
- Run via `camp test <file>.camp`
- Each public function gets at least one `expect` covering the happy path and one for each error/boundary case

**Intrinsic modules** (Str, Map, Set, Bytes, Path, Duration, Fmt):
- E2E execution tests that compile a program using the function and check `wasm_stdout`
- OR: test blocks that call intrinsic functions and use `Console.println!` to output results, with `camp test` checking exit code 0 for correct behavior
- Preferred: test blocks with `expect` where possible (some intrinsics like `Str.length` may be testable once WASM runtime supports them); E2E tests for the rest

**Declaration-only modules** (traits: Eq, Ord, Hash, Debug, Default, IntoIter, FromIter, From, TryFrom; effects: Console!, Throw!, File!, Env!, Time!, Random!, Log!):
- E2E typechecking tests: programs that use the trait/effect should compile (or fail to compile if misused)
- No runtime tests needed

### AD9: `expect` Effect Row Semantics

**Decision**: In Debug/Test mode, `expect condition` has the same effect row as its sub-expression. In Production mode, `expect` is removed entirely and contributes no effects.

**Rationale**: If `expect Console.println!("hi") == ()` is written, the `Console!` effect must be in scope. The `expect` itself doesn't add effects — it inherits them from its sub-expression.

**Typecheck rule**:
```odin
// Debug/Test mode:
typecheck(Expr_Expect{condition, ...}) →
  cond_type = typecheck_synth(condition)
  unify(cond_type, Bool)
  effect_row = cond_effect_row  // inherit from sub-expression

// Production mode:
// expect is not typechecked at all (removed before typechecking)
// OR: typechecked but not lowered (safer — catches bugs even in production builds)
```

**Preferred**: Typecheck `expect` in all modes (catches type errors even in production), but only lower it in Debug/Test. In Production, IR lowering skips it.

## File Structure

```
src/frontend/ast.odin            — MODIFY: Add Expr_Expect to Expr union
src/frontend/parser.odin         — MODIFY: Fix double-}}, add pending_doc, change expect desugaring to Expr_Expect
src/semantics/canonical.odin     — MODIFY: Add CExpr_Expect
src/semantics/canonicalize.odin  — MODIFY: Canonicalize Expr_Expect
src/semantics/typed.odin         — MODIFY: Add TExpr_Expect
src/semantics/check_expr.odin    — MODIFY: Typecheck CExpr_Expect
src/ir/ir.odin                   — MODIFY: Add IR_Expr_Expect
src/ir/lower.odin                — MODIFY: Lower TExpr_Expect/TDecl_Expect by mode
src/codegen/emit_expr.odin       — MODIFY: Codegen IR_Expr_Expect
src/codegen/runtime.odin         — MODIFY: (possibly) Exit runtime function
src/build/build.odin             — MODIFY: Synthetic test entries for Decl_Expect, Build_Mode
src/build/context.odin           — MODIFY: Add Build_Mode to Compilation_Context
src/cli.odin                     — MODIFY: Parse --debug flag
src/main.odin                    — MODIFY: Pass Build_Mode to build functions

stdlib/Result.camp               — MODIFY: Add test blocks
stdlib/Bool.camp                 — MODIFY: Add test blocks
stdlib/Iter.camp                 — MODIFY: Add test blocks
stdlib/List.camp                 — MODIFY: Add test blocks
stdlib/Num.I64.camp              — MODIFY: Add test blocks
stdlib/Num.I32.camp              — MODIFY: Add test blocks
stdlib/Num.I16.camp              — MODIFY: Add test blocks
stdlib/Num.I8.camp               — MODIFY: Add test blocks
stdlib/Num.U64.camp              — MODIFY: Add test blocks
stdlib/Num.U32.camp              — MODIFY: Add test blocks
stdlib/Num.U16.camp              — MODIFY: Add test blocks
stdlib/Num.U8.camp               — MODIFY: Add test blocks
stdlib/Num.F64.camp              — MODIFY: Add test blocks
stdlib/Num.F32.camp              — MODIFY: Add test blocks
stdlib/Str.camp                  — MODIFY: Add test blocks
stdlib/Map.camp                  — MODIFY: Add test blocks
stdlib/Set.camp                  — MODIFY: Add test blocks
stdlib/Duration.camp             — MODIFY: Add test blocks

tests/e2e/language/test-block-syntax/expected.toml — MODIFY: Expect success instead of error
tests/e2e/stdlib/                 — NEW: E2E tests for intrinsic stdlib modules
```

## What Does NOT Change

- Token types (`.Kw_Test`, `.Kw_Expect` already exist)
- E2E snapshot test runner
- `test` block syntax (`test "name" { body }`)
- The overall `camp test` approach (discover → compile each → run via wasmtime)
- `todo` placeholder behavior (deferred to compilation modes change)
