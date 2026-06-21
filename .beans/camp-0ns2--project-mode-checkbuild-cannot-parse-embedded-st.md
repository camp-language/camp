---
# camp-0ns2
title: project-mode check/build cannot parse embedded stdlib sources (C0800/C0100 for every stdlib import)
status: todo
type: bug
priority: high
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-21T03:00:00Z
---

## Symptom

`camp check` (project mode, `run_check_project`) and `camp build` (project mode, `run_build_project`) emit C0800 MODULE NOT FOUND for EVERY stdlib import (List, Result, Iter, Str, Map, Set, Bool, Fmt — all fail). Single-file `camp build <file>` / `camp check <file>` resolve the same imports fine.

## Root cause

`register_stdlib_modules` (src/build/discovery.odin:286) registers ALL embedded stdlib modules into `project.modules`. `parse_and_canonicalize` (src/build/project.odin:253) parses each and returns `Build_Error` on parse failure (its parse-error gate). The embedded stdlib sources (stdlib/*.camp) are AHEAD of the current parser — they use syntax the parser cannot yet handle (e.g. `pub abs : I16 -> I16` type signatures, `~a` bitwise-not, effect rows in signatures). So every stdlib module fails to parse → project build/check aborts with a flood of C0100/C0101 syntax errors.

The single-file build path (src/build/build.odin:130-175) avoids this by registering stdlib modules TRANSITIVELY (only imports the user used) and calling `parse_stdlib_module` + `demote_recent_errors` to tolerate parse failures, DROPPING unparseable modules so their names fall through to codegen runtime intercepts.

## Why this matters (surfaced by camp-jrga)

The e2e `args = "check"` special command invokes project-mode `check`. Any e2e test needing a stdlib import via project check cannot use it. camp-jrga worked around this by adding an e2e `args = "check-file"` special command (src/e2e/runner.odin) that invokes single-file `camp check <file>` (resolves stdlib + renders C09xx warnings). Project-mode `check` warning rendering was also fixed (src/build/project_check.odin) but is unusable for stdlib-importing programs until this bean is resolved.

## Fix direction (needs design — do NOT attempt without discussion)

1. Backport the single-file `demote_recent_errors` tolerance into `run_check_project` and `run_build_project` (parse stdlib, demote parse errors, drop unparseable modules) — mirrors src/build/build.odin:157-170. Smaller interim fix.
2. OR sync the embedded stdlib sources to the current parser (camp-24mj effort) — then project paths parse them cleanly. The real fix.

Recommend option 1 as an interim so project-mode check/build become usable.

## Files

- src/build/project_check.odin (run_check_project — missing stdlib tolerance)
- src/build/project.odin (run_build_project — same)
- src/build/build.odin:130-175 (single-file path WITH tolerance — reference)
- src/build/stdlib.odin (STDLIB_MODULES embedded sources)
