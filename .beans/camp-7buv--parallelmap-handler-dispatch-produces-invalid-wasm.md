---
# camp-7buv
title: Parallel.map! handler dispatch — scheduler-effect user-resume dispatch unimplemented
status: in_progress
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-20T00:00:00Z
---

## Symptom

`tests/e2e/scheduler/parallel-map/Main.camp` currently `skip_wasm = true` (compile-only):

```camp
main! = || -[Parallel!]-> I64 {
  handle Parallel! in {
    Parallel!.map!(|x| x, [1, 2, 3])
  } with {
    .map!(resume, _f, _xs) => resume(0)
  }
}
```

Expected: exit 0 (from `resume(0)`). Currently: compiles, but the generated wasm fails
validation: `type mismatch: expected i64, found i32` at the resume continuation's
`local.set 2` (local 2 is i64).

## Root cause (confirmed by wasm disassembly)

Same fundamental issue as `camp-iokq` (scheduler-effect user-resume dispatch is
unimplemented), with a signature-specific wrinkle:

- `src/ir/effect_lower.odin:918-928` `all_scheduler` shortcut passes `Parallel!`
  handles to codegen with arms untransformed.
- `src/codegen/emit_expr.odin:2522-2614` `^IR_Handle` `is_sched` branch emits ONLY
  the body + structured-concurrency cleanup, never the `.map!(resume, _f, _xs) => resume(0)`
  arm.

Because the resume arm is never emitted, the handle body's result
(`Parallel!.map!(...)` → `List(b)`, wasm `i32` heap ptr) flows directly into the resume
continuation's result local — which is typed `i64` (the handle's return type, from
`resume(0)` where `0 : I64`). i32 value → i64 local → wasm validation fails
(`expected i64, found i32`).

Compared to `camp-iokq` (async-yield), there is no stray-drop sub-bug here — the body's
`Parallel!.map!` perform type is a `fresh_value_var` that happens to default to `.I64`
at lower time, but the i64/i32 mismatch is on the *resume continuation local*, not a
statement drop. (Note: `Parallel!.map!`'s result_var should also eventually be unified
with `List` rather than left unbound, but that is masked by the missing-arm bug.)

## Required work

Same as `camp-iokq`: implement scheduler-effect user-resume dispatch (bridge
direct-runtime-call and CPS evidence models). Once the `.map!(resume, _f, _xs) => resume(0)`
arm is actually emitted and `resume(0)` produces the I64, the i64/i32 mismatch
disappears (the body's List no longer flows into the result local; the arm's resume
result does).

## Key files

- `src/codegen/emit_expr.odin:2522-2614` — `^IR_Handle` `is_sched` branch (emits body only)
- `src/ir/effect_lower.odin:905-928` — `^IR_Handle` `all_scheduler` shortcut
- `src/codegen/emit_expr.odin:2824-2888` — `Parallel!.map!` perform → `camp_parallel_map`
- `docs/syntax-recipe.md` §Handle (lines 373-384) — authoritative resume semantics

## Related

- `camp-iokq` — same root cause for `Async!.yield!`.
