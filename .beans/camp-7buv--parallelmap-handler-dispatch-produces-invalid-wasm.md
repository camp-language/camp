---
# camp-7buv
title: Parallel.map! handler dispatch produces invalid WASM — type mismatch in resume path
status: todo
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

`tests/e2e/scheduler/parallel-map/Main.camp` compiles but the generated WASM fails wasmtime validation:

```
Error: failed to compile: wasm[0]::function[86]
Invalid input WebAssembly code at offset 9748: type mismatch: expected i64, found i32
```

## Test

```camp
main! = || -[Parallel!]-> I64 {
  handle Parallel! in {
    Parallel!.map!(|x| x, [1, 2, 3])
  } with {
    .map!(resume, _f, _xs) => resume(0)
  }
}
```

Should return 0 (from `resume(0)`), currently wasm_exit=1 with invalid WASM.

## Root Cause (suspected)

Same class of bug as the async handler — the Parallel! effect lowering in `src/codegen/scheduler.odin` has a type mismatch in the resume continuation. The `map!` operation returns a `List(b)` but the handler tries to resume with `0` (I64), which may cause the type mismatch.
