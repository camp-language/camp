---
# camp-plwn
title: Nested tag matching (Ok(Ok(v))) codegen produces invalid WASM — type mismatch in tag field extraction
status: todo
type: task
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

`tests/e2e/tag-unions/tag-match-nested/Main.camp` compiles but the generated WASM fails wasmtime validation:

```
Error: failed to compile: wasm[0]::function[85]
Invalid input WebAssembly code at offset 9493: type mismatch: expected i64, found i32
```

## Root Cause

When matching `Ok(Ok(42))` against `Ok(Ok(v)) => v`, the inner tag field extraction during codegen produces an i32 value where an i64 is expected. The tag discriminant extraction (which returns an i32) is being passed directly to the value path without a widening conversion.

## Test

`tests/e2e/tag-unions/tag-match-nested/Main.camp` — should return 42, currently wasm_exit=1 with invalid WASM error.

## Fix

In `src/codegen/codegen.odin`, the nested tag match lowering needs to ensure inner tag payloads are correctly typed. Likely in the match arm codegen for `Expr_Method_Call` with dispatch `.Nominal` on tag extraction — the inner `Expr_Field_Access` for the tag payload value needs an i32→i64 widening when the payload type is I64.
