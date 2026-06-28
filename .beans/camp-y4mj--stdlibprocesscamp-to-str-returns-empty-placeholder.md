---
# camp-y4mj
title: 'stdlib/Process.camp: to_str returns empty placeholder, module has zero tests'
status: todo
type: task
priority: low
tags:
    - stdlib
    - testing
created_at: 2026-06-28T02:16:59Z
updated_at: 2026-06-28T02:16:59Z
---

Source: stdlib coverage sweep (docs/discovering-gaps.md §3).

`stdlib/Process.camp` (198 lines) is PARTIAL and UNTESTED:
- `Process.to_str` (`Process.camp:77-79`) returns an empty placeholder: `// TODO: use actual UTF-8 decode when available` — returns `Str { ... }` with no body content. This is silent wrong behavior: any caller rendering a Process as a string gets empty output.
- Zero `test "..."` blocks despite real pure-Camp builder helpers (`from`, `arg`, `env`, `cwd`, `capture_stdout`, `capture_stderr`, `capture_merged`) that are testable without effect runtime.
- Effect operations (`spawn!`, `wait!`, `read!`, `write!`, `close!`, `run!`) require WASIX runtime; camp-dxqh (COMPLETED) covers codegen only, not behavioral tests.

Existing beans do NOT cover this: camp-dxqh is codegen-only (completed), camp-i1i5 is timeout support (different feature), camp-3q0j's module list omits Process.

## Work
1. Implement `Process.to_str` using a real UTF-8 decode path (cross-ref Str/Bytes intrinsics — may be blocked until those are real; if so, fold the TODO into the body and add a builder-state test that asserts the constructed fields instead of render output).
2. Add `test "..."` blocks following AGENTS.md Stdlib Testing principles: one concern per test, happy path -> empty -> singleton -> multi-element -> error/edge. Cover the pure builder helpers (from/arg/env/cwd/capture_*) since they are real Camp code with no runtime dependency.
3. Update kitchen-sink if Process construction is exercised there.

## Done looks like
`to_str` produces non-empty output (or the TODO is justified by a tracked Bytes/Str blocker and the test asserts builder fields instead). At least 4-5 test blocks covering builder helpers pass under `odin test src`.
