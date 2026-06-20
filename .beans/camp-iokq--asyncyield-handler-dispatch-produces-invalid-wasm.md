---
# camp-iokq
title: Async.yield! handler dispatch — scheduler-effect user-resume dispatch unimplemented
status: in_progress
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-20T00:00:00Z
---

## Symptom

`tests/e2e/scheduler/async-yield/Main.camp` currently `skip_wasm = true` (compile-only):

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

Expected: exit 0 (from `resume(0)`). Currently: compiles, wasm validates, but runtime
hangs (scheduler yields with no resume to make progress; the worker loop never returns).

## Root cause (confirmed by wasm disassembly)

Two sub-bugs. One is FIXED; the feature is still unimplemented.

### FIXED — invalid wasm (stray `drop` after void scheduler call)

The wasm previously failed validation: `type mismatch: expected a type but nothing on
stack` at the `drop` following `call <Sched_Yield>`. Cause: `Async!.yield!()` is a
scheduler op whose result type was an **unbound fresh type var**, so
`lower_type` returned the default `wasm_type = .I64` (`src/semantics/lower_type.odin:9`).
`IR_Block` emission (`src/codegen/emit_expr.odin:1740-1754`) then dropped the (non-final)
statement result — but `Sched_Yield` is declared `() -> nil` (`src/codegen/codegen.odin:487`)
and pushes nothing, so the `drop` had nothing to consume → invalid wasm.

The typechecker's scheduler branch (`src/semantics/check_expr.odin:851-942`) handled
`spawn!`/`join!` but left `yield!`/`cancel!` to fall through to line 1058
(`return_var := fresh_value_var` → unbound `.I64`).

Fix: `src/semantics/check_expr.odin` now unifies the result of `yield!`/`cancel!`
with `Unit` (`.Void`), mirroring the existing `for_each!` handling for `Parallel!`.
Wasm now validates. 468/468 unit tests pass; no regressions in other scheduler/e2e tests.

### REMAINING — scheduler-effect user-resume dispatch not implemented

Per `docs/syntax-recipe.md` §Handle (lines 373-384), scheduler effects use the same
handler/resume model as user effects (the recipe's canonical example is `Console!` WITH
`resume`). BUT:

- `src/ir/effect_lower.odin:918-928` `^IR_Handle` `all_scheduler` shortcut passes
  scheduler handles to codegen UNCHANGED — arms "kept for scope_id tracking but not
  transformed".
- `src/codegen/emit_expr.odin:2522-2614` `^IR_Handle` `is_sched` branch emits ONLY
  `emit_expr(e.body)` + the structured-concurrency scope-cleanup loop. It NEVER emits
  the user handler arms and never lowers `IR_Resume`.

So the `.yield!(resume) => resume(0)` arm is dropped entirely. The body's `Async!.yield!()`
calls `camp_sched_yield`, which re-enqueues the current task and clears `current_task`;
the worker loop has no resume path to continue, so it loops / parks forever and `_start`
never reaches `proc_exit(0)`.

## Required work

Implement scheduler-effect user-resume dispatch: bridge the direct-runtime-call model
(scheduler ops → `camp_sched_*`) with the CPS evidence model (user effects → evidence
records + `call_indirect`). Either:
- Have the `is_sched` codegen branch emit the user arm and wire `resume` to re-enter the
  body continuation after the scheduler op completes; OR
- Remove the `all_scheduler` shortcut in `effect_lower` and lower scheduler handles
  through the same CPS path as user effects (requires scheduler performs to carry
  evidence).

Either way, the resume continuation must be allocated as a closure and `resume(val)`
must `call_indirect` into it with the body's state restored. This is a multi-file
feature, not a localized fix.

## Key files

- `src/codegen/emit_expr.odin:2522-2614` — `^IR_Handle` `is_sched` branch (emits body only)
- `src/ir/effect_lower.odin:905-928` — `^IR_Handle` `all_scheduler` shortcut
- `src/ir/effect_lower.odin:1310-1316` — `^IR_Perform` scheduler pass-through
- `src/codegen/emit_expr.odin:2680-2685` — `yield!` → `camp_sched_yield()`
- `src/codegen/runtime.odin:1994` — `emit_camp_sched_yield_body`
- `docs/syntax-recipe.md` §Handle (lines 373-384) — authoritative resume semantics

## Related

- `camp-7buv` — same root cause for `Parallel!.map!`.
- `camp-esbs` — unrelated (CPS evidence threading for non-scheduler `Ask!`).
