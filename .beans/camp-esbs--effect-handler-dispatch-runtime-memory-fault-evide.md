---
# camp-esbs
title: Effect handler dispatch runtime memory fault — evidence stack or closure dispatch wrong
status: todo
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-19T23:41:34Z
---

## Symptom

Three e2e effect handler tests compile but crash at runtime with memory fault (wasm_exit=134):

1. `tests/e2e/effects/effect-declare-and-handle/` — custom `Ask!` effect, `handle Ask! in Ask!.read!() with { .read!(resume) => resume(42) }` — should return 42
2. `tests/e2e/effects/effect-perform-return-value/` — same structure, should return 42 from resume
3. `tests/e2e/effects/effect-handler-resume-twice/` — `resume(resume(1))` — should trap on double-resume, crashes before that

All three show:
```
memory fault at wasm address 0x706d6162 in linear memory of size 0x140000
```

## Root Cause (suspected)

The evidence stack layout during effect lowering (`src/ir/effect_lower.odin`) or the closure dispatch for the handler's resume continuation has an off-by-one or wrong index. The address `0x706d6162` is ASCII "pamb" which suggests a string pointer being dereferenced as a memory address, likely from the closure's `env_ptr` or `fn_idx` being corrupted.

## Key files

- `src/ir/effect_lower.odin` — evidence stack management
- `src/codegen/scheduler.odin` — handler dispatch runtime
