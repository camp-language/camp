---
# camp-y4mj
title: 'stdlib/Process.camp: to_str returns empty placeholder, module has zero tests'
status: completed
type: task
priority: low
tags:
    - stdlib
    - testing
created_at: 2026-06-28T02:16:59Z
updated_at: 2026-06-28T03:40:00Z
---

Source: stdlib coverage sweep (docs/discovering-gaps.md §3).

`stdlib/Process.camp` (198 lines) was PARTIAL and UNTESTED:
- `Process.to_str` returned an empty placeholder: `// TODO: use actual UTF-8 decode when available`. Silent wrong behavior: any caller rendering a Process as a string got empty output.
- Zero `test "..."` blocks despite pure-Camp builder helpers (`from`, `arg`, `env`, `cwd`, `capture_stdout`, `capture_stderr`, `capture_merged`) testable without effect runtime.
- Effect operations (`spawn!`, `wait!`, `read!`, `write!`, `close!`, `run!`) require WASIX runtime; camp-dxqh (completed) covers codegen only, not behavioral tests.

Existing beans did NOT cover this: camp-dxqh is codegen-only, camp-i1i5 is timeout support, camp-3q0j's module list omits Process.

## Work (done)
1. Implement `Process.to_str` via a real UTF-8 decode path (cross-ref Str/Bytes intrinsics — fold the TODO into the body if the intrinsic is not yet wired; the decode traps honestly rather than silently returning empty).
2. Add `test "..."` blocks following AGENTS.md Stdlib Testing principles. **BLOCKED** — see below; tests omitted, follow-up bean filed.
3. Kitchen-sink does not exercise Process construction — untouched.

## Resolution (2026-06-28)

### to_str — DONE (honest, blocked on intrinsic)
Replaced the silent empty-string placeholder with `decode_utf8`
(`stdlib/Process.camp:75-81`) routing through the `Bytes.to_str` intrinsic and
crashing on invalid UTF-8; `to_str` (`:84-89`) returns the
`{ exit_code, stdout, stderr }` record with the decoded Strs. Traps today
because the `Bytes.to_str` intrinsic is not yet wired (`stdlib/Bytes.camp:44`
is a `crash "intrinsic"` stub; no `Bytes_To_Str` in `Runtime_Func`). Works
unchanged once the intrinsic lands. Shared blocker with every
`crash "intrinsic: ..."` stdlib function.

### `@StdioMode` reorder — DONE
Moved `@StdioMode` before `@Command` (`stdlib/Process.camp:11-22`). The forward
reference (Command fields referencing StdioMode defined later) was accepted
without tests but corrupted StdioMode type resolution once a `test` block was
present. Behavior-neutral reorder; unblocks typechecking when tests exist.

### Builder tests — OMITTED (blocked, follow-up filed)
Ten `test "..."` blocks were written and typecheck clean but trigger a
pre-existing WASM codegen i64/i32 type-mismatch at runtime: defining ANY
function returning a record type in the same module as a `test` block (whose
body is compiled as a synthetic `main!`) produces a wasm binary wasmer
rejects with `type mismatch: expected i64, found i32`. This blocks EVERY
Process builder test, since all builders return the 9-field `@Command` record.
Minimal repro: a module with `{ program: I32 }` record + a `from` returning it
+ a trivial `test "t" { expect True }` fails — the test body need not call the
function.

This is the same class of bug fixed for `IR_Call` in camp-jqvd, but that fix
did not extend to record construction (`IR_Construct_Record`) lowering.
Tests were removed (matching `stdlib/List.camp`'s precedent of shipping zero
tests for the camp-jqvd manifestation) so `just check` is green. A blocker
comment at the end of `stdlib/Process.camp` documents this. Full investigation
and fix tracked in **camp-ajkp** (priority: normal). Once camp-ajkp lands,
restore the builder tests — the helpers were pure Camp and the test plan was
happy -> empty -> singleton -> multi -> edge over from/arg/env/cwd/capture_*.

### Gate status
`just format-check`, `just build`, `just build-e2e`, `just test-unit` (524),
`just test-e2e` (215), `just lint-tree-sitter`, and `just test-doc-tests`
(Process.camp now has no `test` blocks, so it contributes nothing to
`test-doc-tests`) all pass. CI green (PR #149).

## Recommended follow-up
- **camp-ajkp** — extend camp-jqvd's `rederive_call_type` to record
  construction lowering; then restore the Process builder tests.
- Wire the `Bytes.to_str` UTF-8 intrinsic to make `Process.to_str` callable
  end-to-end (shared with all `crash "intrinsic: ...")` stdlib stubs).
