---
# camp-hjve
title: Make expect a dedicated syntax concept (not a desugar)
status: open
type: task
priority: normal
created_at: 2026-05-30T00:00:00Z
updated_at: 2026-05-30T00:00:00Z
---

## Problem

`expect` looks like its own syntax (keyword `expect condition`, no parens), parsed as
`Decl_Expect`, threaded through canonicalization and typechecking as a first-class
declaration kind. But its treatment is inconsistent and broken:

1. **IR lowering skips it entirely** (`src/ir/lower.odin:55`). `TDecl_Expect` falls
   through with zero code emitted. Expect statements compile to nothing — no runtime
   check, no failure, nothing.

2. **Dead desugar path in canonicalize**. `canonicalize.odin:715-751` checks if an
   `Expr_Call`'s callee is named "expect" and desugars to `if !x { crash "expectation failed" }`.
   This path is a dead alternative to the proper `Decl_Expect` path (`canonicalize.odin:291`).
   It also hardcodes a generic message with no access to operand Debug representations.

3. **No Debug capture**. The syntax recipe says `expect a == b` should capture both
   operands + their Debug representations. With the desugar approach, there's no
   structured access to sub-expressions — you just get `"expectation failed"`.

4. **No conditional compilation**. Can't strip expects from prod builds because they
   vanish into nothing or crash unconditionally — no flag controls it.

5. **`///` doc comments on expect lines**. Documented but unused — the doc comment
   field exists on `Decl_Expect` and `CDecl_Expect` but is never rendered on failure.

## Scope of work

### Phase 1: IR representation & lowering

- Add `IR_Expect :: struct { condition: ^IR_Expr, message: string, span: base.Source_Span }`
  variant to `IR_Decl` in `src/ir/ir.odin`.
- In `src/ir/lower.odin`, handle `TDecl_Expect` by producing `IR_Expect` (with the
  condition lowered, plus the doc comment as failure message). Remove the skip.

### Phase 2: Codegen

- In codegen `emit_decl`, handle `IR_Expect`:
  - Emit condition as a Bool.
  - In `if false`, emit a WASM `unreachable` + a `message` string through the runtime's
    debug-print mechanism (or `throw` a dedicated error).
  - Alternatively, emit a `Call` to a runtime `__camp_expect_failed(message)` import.

### Phase 3: Conditional compilation

- Gate `IR_Expect` emission on a build flag (e.g. `-debug:expect` or the inverse
  `-release`). In release builds, skip emitting the check entirely — no runtime cost.
- Expose via `camp build --release` (strips expects) vs default (keeps expects).

### Phase 4: Rich failure messages

- Instead of desugaring, collect operand Debug info syntactically:
  - `expect a == b` → know operands are `a` and `b`, the operator is `==`, produce
    something like `"expected: 42, actual: 0"`.
  - `expect <expr>` → show `"expected true, got false"` + `expr` source snippet and
    its Debug representation.
- This requires walking the condition expression at codegen time rather than
  desugaring it away. Keep the expression intact in `IR_Expect` rather than
  decomposing it.

### Phase 5: Cleanup

- Remove the dead `Expr_Call` → `expect` desugar in `canonicalize.odin` (lines 715-751
  and the `Expr_Identifier{name="expect"}` hack in parser.odin:1580-1581).
- Wire the doc comment field in `Decl_Expect` into the failure message.

## Non-goals (for this bean)

- Effectful expects (e.g. `expect result` where result is a `Result`). Future work.
- Fancy assertion frameworks. Keep it simple: condition + message.

## Acceptance

- `expect true` compiles to a no-op (size zero or a nop) in release builds.
- `expect false` emits `unreachable` / traps with a message in debug builds.
- `expect x == y` fails with a message showing both operands' values.
- `/// "must be positive"\nexpect x > 0` includes the doc comment in the failure message.
- Dead desugar code in `canonicalize.odin` and parser is removed.
- All existing tests pass.
