---
# camp-esbs
title: Effect handler dispatch runtime fault — IR_Resume evidence/env not threaded into handler
status: in_progress
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-20T00:00:00Z
---

## Symptom

Three e2e effect handler tests compile cleanly but trap at runtime:

1. `tests/e2e/effects/effect-declare-and-handle/` — custom `Ask!` effect, `handle Ask! in Ask!.read!() with { .read!(resume) => resume(42) }` — should return 42
2. `tests/e2e/effects/effect-perform-return-value/` — same structure, should return 42 from resume
3. `tests/e2e/effects/effect-handler-resume-twice/` — `resume(resume(1))` — should trap on double-resume, crashes before that

All three are `skip_wasm = true` (compile-only assertions) until this is resolved.

## Root cause (with file:line refs)

This is TWO bugs. The first is FIXED; the second remains.

### FIXED — RC double-free (`src/ir/rc.odin:538`)

The original symptom was `memory fault at wasm address 0x706d6162` (ASCII "pamb"). Cause:
`rc_insert_expr_inner` for `IR_Let` emitted an `IR_Drop` for a heap binding whose
single use fully consumed it (`binding_used == true, binding_count == 0`). That is a
**move** (ownership transferred to the destination), not an unused binding. The spurious
DROP freed the handler-closure record (`_hcl_*`, built in `src/ir/effect_lower.odin` and
stored into the evidence record via `IR_I32_Store`) BEFORE its pointer was read back out
of the evidence slot by the `call_indirect` perform dispatch. The stale slot later
aliased other live allocations (byte pattern `62 61 6d 70` = "bmap" LE), so the loaded
closure pointer was garbage → out-of-bounds memory access.

Fix: `src/ir/rc.odin:538` changed `} else if !binding_used || binding_count <= 0 {` to
`} else if !binding_used {`. The genuinely-never-referenced case still drops (preserved by
`test_rc_insert_heap_drop`, `test_rc_drop_unused_heap_param`); the "fully consumed / moved
exactly once" case no longer double-frees. 468/468 unit tests pass.

This matches Perceus semantics: the last reference to a value (not preceded by an
inserted `IR_Dup`) is a consume/move; the binding no longer owns a reference, so no
drop is owed.

### REMAINING — IR_Resume evidence/env not threaded (`src/codegen/emit_expr.odin:3035`)

After the RC fix, the trap changes to `undefined element: out of bounds table access`
in the resume continuation (`func 91` of effect-declare-and-handle/Main.wasm, at the
`call_indirect` ~offset 0x28bf).

Trace of func 91 (handler arm `.read!(resume) => resume(42)`):
- `resume_local` ← param (resume closure ptr) — OK
- `fn_idx_local` ← `resume_local[+8]` (tee'd) — OK; one-shot check passes; fn_idx zeroed
- `resume_local[+16]` loaded as the env ptr — pushed onto the stack
- THEN a `local.set 5 = i32.const 0` and subsequent `local.get 5; i32.load {8,16}`
  load from **address 0+8 / 0+16** (low linear memory, garbage), and THAT garbage
  value is used as the `call_indirect` table index → out of bounds.

The `local 5 = 0` is `e.ev` (the evidence) mapped via `env.local_map[e.resume_id]` /
the resume param, but the evidence pointer is never actually threaded into the handler
function — the local is uninitialized (holds 0). The `emit_expr(^ir.IR_Resume)`
(`src/codegen/emit_expr.odin:3035-3094`) reads `e.ev` and emits it as a continuation
argument, but the handler fn (`IR_Decl_Fn` built in `src/ir/effect_lower.odin:951-1032`,
params `env_param, op_params..., resume_param, ev_param`) is invoked via the evidence
dispatch whose `ev_param` isn't wired to the caller's evidence.

## Key files

- `src/codegen/emit_expr.odin:3035` — `^ir.IR_Resume` emit (loads env/value/ev, `call_indirect`)
- `src/ir/effect_lower.odin:951-1032` — handler fn construction + params (env, op, resume, ev)
- `src/ir/effect_lower.odin:1398-1426` — perform dispatch: loads handler closure from
  evidence at `arm_index*4`, calls it with `[perform_args..., cont_closure, ev_arg]`
- `src/codegen/emit_expr.odin:3143` — `^IR_Closure_Call` emit (closure env at `+16`, fn_idx at `+8`)
- `src/ir/rc.odin:538` — FIXED: RC double-free on fully-consumed heap let-binding

## Remaining work

Verify how the `ev_param` of the handler function is meant to receive the caller's
evidence pointer, and wire the codegen so `e.ev` resolves to the live evidence record
(rather than local 0). Likely the handler closure's env field (offset `CAMP_TAG_FIELDS_OFFSET+8`)
should carry the evidence ptr, OR the dispatch should pass evidence as an explicit
argument that `local_map` resolves correctly. Requires care to not regress the
non-scheduler effect path (only the `Ask!`-style CPS path is exercised here).
