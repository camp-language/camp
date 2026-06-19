---
# camp-iokq
title: Async.yield! handler dispatch produces invalid WASM — stack type error
status: todo
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

`tests/e2e/scheduler/async-yield/Main.camp` compiles but the generated WASM fails wasmtime validation:

```
Error: failed to compile: wasm[0]::function[85]
Invalid input WebAssembly code at offset 9375: type mismatch: expected a type but nothing on stack
```

## Test

```camp
main! = || -[Async!]-> I64 {
  handle Async! in {
    Async!.yield!()
    42
  } with {
    .yield!(resume) => resume(0)
  }
}
```

Should return 0 (the value passed to `resume(0)`), currently wasm_exit=1 with invalid WASM.

## Root Cause (suspected)

The Async! effect lowering in the scheduler codegen (`src/codegen/scheduler.odin`) expects a value on the WASM stack where none exists, or the `yield!` operation's return type (unit `{}` / void) is not handled correctly in the resume continuation codegen.
