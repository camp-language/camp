---
# camp-esbs
title: Effect handler dispatch runtime fault — IR_Resume evidence/env not threaded into handler
status: in_progress
type: bug
priority: high
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-21T00:30:00Z
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

### PARTIALLY FIXED — resume-call rewrite missed IR_Closure_Call form (`src/ir/effect_lower.odin:377`)

The prior diagnosis above (`local 5 = 0`, OOB table access in func 91) was a SYMPTOM.
Root cause confirmed via instrumented codegen (`emit_expr` IR_Resume debug prints):
the IR_Resume landing in the handler fn had `e.value = IR_Closure_Call{callee=IR_Var{name=5}}`
where name=5 is the source identifier for `resume` (the handler arm binding), NOT the
resume_param (134). `e.value` should have been `IR_Literal_Int{42}`.

Why: `el_replace_resume` (`src/ir/effect_lower.odin:301`) only matched `^IR_Call` for
`resume(args)` calls (`e.callee.name == resume_id`). But the lowerer routes a call to a
LOCAL name (resume is an arm-binding, not a module decl) through the closure path
(`src/ir/lower.odin:849` `if callee_name.is_local && !env.module_decl_names[...]`), producing
`IR_Closure_Call{callee=IR_Var{name=resume_id}, args=[...]}`. `el_replace_resume` had no
`^IR_Closure_Call` arm that recognized the resume callee, so it recursed and left the call
intact. Then the implicit-resume wrap (`effect_lower.odin:1044`) saw the body was not an
IR_Resume and wrapped the whole (un-rewritten) Closure_Call as `IR_Resume.value`.

FIX (committed fe7b185): added a `^IR_Closure_Call` arm in `el_replace_resume` that detects
`callee = ^IR_Var{name == resume_id}` and rewrites it to IR_Resume, mirroring the IR_Call
arm. After this fix the IR_Resume is well-formed: `resume_id=134 in_map=true`,
`value=Literal_Int 42`, `ev=Var name=135 in_map=true`. The 468/468 unit-test baseline is
preserved; `git diff --stat` shows only `src/ir/effect_lower.odin | 43 +++`.

### REMAINING — null-env drop fault in closure-converted continuation (`src/ir/closure_convert.odin`)

After the resume-rewrite fix, the trap moved to `memory fault at wasm address 0x706d6162`
(byte pattern "bamp" LE = low-linear-memory garbage, the same RC-bug signature). Traced via
`wasm2wat` disassembly of effect-declare-and-handle/Main.wasm:

  func 95 (_start) -> func 94 (main, the effect_lower Handle lowering) builds:
    - evidence record (`ev_var`) + handler closure {fn_idx=91, env=0} stored into evidence[0]
    - perform dispatch: Closure_Call loads handler closure from evidence[0], calls func 91
      with (env=0, resume=cont_closure, ev=evidence_record)
  func 91 (handler `.read!(resume) => resume(42)`): one-shot check OK, loads cont_closure
    env from `resume_local[+16]` (=0), pushes i64.const 42, pushes evidence, calls
    `call_indirect (type 22)` → func 93 with (env=0, value=42, ev=evidence).
  func 93 (the cont `_kc` continuation): `local.get 0; i32.const 0; call 11` — i.e. it
    calls `camp_drop(env=0, 0)`. `camp_drop` does `i32.load` at address 0 → reads the
    data-segment bytes "camp..." (0x706d6163-ish) as a refcount → underflows / faults.

Root cause: the continuation closure built in `el_lower_let_perform` (`effect_lower.odin:886`)
has `body = cont_fn_body` (non-nil) with NO captured free vars (the handle body is just the
perform). `closure_convert` (`src/ir/closure_convert.odin:378`, body!=nil path) therefore
creates a NEW `closed_fn` with an injected `_cenv` env param prepended, and — because free
is empty (line 628-636) — sets the closure's env field to `IR_Literal_Int{0}` (null). The
`closed_fn` receives env=0 as param0. `rc_insert` (`src/ir/rc.odin:299 emit_param_drops`)
sees the `_cenv` param is heap-typed and never used in the body, so it emits an `IR_Drop`
for it at function end. Dropping address 0 → `camp_drop(0)` → load from addr 0 → fault.

This is NOT effect-specific: a minimal `main! = || -> I64 { f = || -> I64 { 42 }; f() }`
(a no-capture lambda) reproduces the SAME `0x706d6162` fault. ANY closure-converted
function with zero free vars has env=0 and unconditionally drops it.

The handler-fn path avoids this because effect_lower declares the handler fn directly
(`IR_Decl_Fn` with params `env_param, resume_param, ev_param`, all `is_heap=false`) so
`emit_param_drops` skips them. The cont path goes through closure_convert's `closed_fn`
which marks `_cenv` as `is_heap=true`.

Candidate fixes (not yet implemented — needs a design decision on which is correct):
  (a) `camp_drop` (runtime, `src/codegen` emit for IR_Drop, or the drop builtin func 11)
      should treat ptr==0 as a no-op (null is not a heap object). Cheapest, fixes ALL
      no-capture closures, but the task framing says "fix at source, not symptom suppression".
  (b) `closure_convert` should NOT mark `_cenv` as `is_heap` when `free` is empty (no
      captured vars → env is a null literal, not a heap object), so `emit_param_drops` skips
      it. Targeted to the actual root (the env is a literal 0, not a heap allocation).
  (c) `closure_convert` should allocate a real (empty) heap env record instead of a null
      literal when free is empty, so the drop is a valid heap-object drop.
Recommended: (b) — the env is genuinely a null literal when there are no captures, so
treating it as non-heap is semantically correct and matches how the handler-fn path already
works (its env param is `is_heap=false`).

## Key files

- `src/codegen/emit_expr.odin:3035` — `^ir.IR_Resume` emit (loads env/value/ev, `call_indirect`)
- `src/ir/effect_lower.odin:951-1032` — handler fn construction + params (env, op, resume, ev)
- `src/ir/effect_lower.odin:1398-1426` — perform dispatch: loads handler closure from
  evidence at `arm_index*4`, calls it with `[perform_args..., cont_closure, ev_arg]`
- `src/codegen/emit_expr.odin:3143` — `^IR_Closure_Call` emit (closure env at `+16`, fn_idx at `+8`)
- `src/ir/rc.odin:538` — FIXED: RC double-free on fully-consumed heap let-binding

## Remaining work

Resume-rewrite fix is committed (fe7b185). The 3 effect tests STILL trap at runtime —
now on a DIFFERENT, more general bug: `closure_convert`'s `closed_fn` drops its null
(`is_heap=true`) `_cenv` env param when the closure has zero captured free vars.
See the "REMAINING — null-env drop fault" section above for the full wasm trace and
candidate fixes (a/b/c). Recommended: (b) mark `_cenv` non-heap when `free` is empty,
matching the handler-fn path. Reproduces with a plain no-capture lambda
(`f = || -> I64 { 42 }; f()`), so this fix unblocks lambdas too — but it is out of the
camp-esbs effect-handler scope and should be tracked separately if scoped narrowly.
Do NOT delete this bean until all 3 effect e2e tests pass with `skip_wasm=false`.
