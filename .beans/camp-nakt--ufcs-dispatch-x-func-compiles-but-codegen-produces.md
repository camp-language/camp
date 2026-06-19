---
# camp-nakt
title: UFCS dispatch (x->func()) compiles but codegen produces invalid WASM — type mismatch
status: todo
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

`tests/e2e/language/ufcs-lexical/Main.camp` now parses and typechecks (after the parser fix), but the generated WASM fails wasmtime validation:

```
Error: failed to compile: wasm[0]::function[86]
Invalid input WebAssembly code at offset 9403: type mismatch: expected i32, found i64
```

## Test

```camp
inc = |x: I64| -> I64 { x + 1 }
pub main! = || -[Console! | Throw!([..])]-> I64 {
  x: I64 = 41
  x->inc()
}
```

Should return 42, currently skip_wasm=true because WASM is invalid.

## Root Cause

The `Expr_Method_Call` with `dispatch = .Lexical` (UFCS via `->`) generates a call where the receiver is passed as an argument, but the codegen places the receiver at the wrong position or with the wrong type. The `Expr_Method_Call` codegen in `src/codegen/codegen.odin` may not handle `.Lexical` dispatch correctly — it might be treating it like `.Nominal` dispatch which has a different calling convention.

## Key files

- `src/codegen/codegen.odin` — method call emission for `.Lexical` dispatch
- `src/ir/effect_lower.odin` — if UFCS interacts with effect lowering
