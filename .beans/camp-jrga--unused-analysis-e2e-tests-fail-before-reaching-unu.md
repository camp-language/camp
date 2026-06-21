---
# camp-jrga
title: Unused analysis e2e tests fail before reaching unused pass — 12/14 tests caught by name resolution/shadowing first
status: completed
type: bug
priority: normal
created_at: 2026-06-19T23:41:34Z
updated_at: 2026-06-21T03:30:00Z
---

## Original symptom (bean as filed)

14 e2e tests in `tests/e2e/unused-analysis/` all expect `exit=1`, but only 2 of them actually reach the unused-analysis pass:

| Test | Expected error | Actual first error |
|------|---------------|-------------------|
| `contradictory-prefix` | C1000 (contrary prefix) | C0200 (UNDEFINED NAME) |
| `immutable-unused` | C0900 (unused binding) | C0200 (UNDEFINED NAME) |
| `record-escape` | (field escape tracking) | C0200 (UNDEFINED NAME) |
| `record-unused-field` | C0901 (unused field) | C0200 (UNDEFINED NAME) |
| `self-assignment` | C1001 (no-op assign) | C0200 (UNDEFINED NAME) |
| `shadowing-priority` | (shadowing > unused) | C0201 (SHADOWING) |
| `underscore-exempt` | (exempt from unused) | C0200 (UNDEFINED NAME) |
| `unused-import` | C0902 (unused import) | C0200 (UNDEFINED NAME) |
| `unused-pattern-binder` | (pattern binder unused) | C0200 (UNDEFINED NAME) |
| `var-loop-exempt` | (loop var exempt) | C0200 + C0201 |
| `var-loop-pure-unused` | (pure var unused) | C0200 + C0201 |
| `var-overwrite-before-read` | (overwrite warning) | C0201 (SHADOWING) |

**Original root-cause claim:** tests reference undefined names; name resolution runs before unused analysis.

## Investigation outcome (2026-06-21) — original diagnosis was PARTIALLY WRONG

The tests are currently GREEN (all 14 pass), but only because each `expected.toml` was snapshotted against the wrong/blocked error (C0200/C0201/C0300), NOT against the intended unused-analysis diagnostic. So the e2e suite is green-but-testing-the-wrong-thing. Triage revealed **5 pre-existing compiler gaps**; only some of the 12 tests are genuine test-authoring bugs.

### KEY STRUCTURAL FINDING (missed by the bean)

The e2e harness for single-module tests runs `camp build <file>` (single-file build). On a **successful** build, the unused-analysis pass runs (`src/build/build.odin:289`) but its C09xx diagnostics are **categorized `.Warning`** and are **never rendered** — `render_all` is only called at error gates (`build.odin:280-283`, `:291-295`) and in JSON mode (`:322`); the success path (`:324`) just prints "compiled …" and returns. So:

- The 2 "passing" reference tests (`pointless-eval`, `record-discard-not-use`) do **NOT** actually exercise C0903 — they exit 0 with the warning discarded. `pointless-eval/expected.toml` confirms: clean `canonicalized/typecheck passed/compiled`, exit=0, no C0903.
- **Any unused-analysis test whose intended diagnostic is a C09xx Warning (C0900/C0901/C0902/C0903/C0904) cannot be observed via the `build` e2e path.** Only hard errors (C02xx, C1000, C1001) surface.

The `args = "check"` e2e special command invokes **project-mode** `check` (`run_check_project`), NOT single-file `run_check`. Project-mode `check` ALSO swallowed warnings (only rendered on `diag_collector_has_errors`) until I patched `src/build/project_check.odin` to mirror single-file `run_check`'s warning rendering.

## Compiler changes made in this bean (Phase C, authorized by project owner)

### C-FIX-1: `check_shadow` false C0201 on `$`-reassignment — FIXED
- **File:** `src/semantics/typecheck.odin:46-72` (was `:46-62`)
- **Root cause:** `check_shadow` exempted only `_`-prefixed names from the shadowing check (line 53). `$`-prefixed (reassignable) names were NOT exempted, so every `$x = …` reassignment to an existing in-scope `$x` emitted a false **C0201 SHADOWING**. Fired at `typecheck.odin:494` (the `^CExpr_Name` assignment case, which `^CExpr_Dollar_Identifier` canonicalizes into).
- **Contradicts:** `docs/syntax-recipe.md:394` "`$x = expr` — mutable binding … `$x = 1` then `$x = 2`".
- **Fix:** added a `$`-prefix early-return in `check_shadow`, mirroring the existing `_`-prefix exemption.
- **Verification:** `$x = 1; $x = 2; $x` now compiles clean (was C0201). `$x = 1; $x = $x` now cleanly reaches **C1001** (was C0201+C1001 via check, C0201-only via build). `just test-unit` → 468/468 pass (leaks are pre-existing, present on baseline too).
- **Affects tests:** self-assignment, var-loop-exempt, var-loop-pure-unused, var-overwrite-before-read.

### C-FIX-2: project-mode `check` swallows C09xx warnings — FIXED (enables `args="check"` e2e for warning-intended tests)
- **File:** `src/build/project_check.odin:164-179`
- **Root cause:** `run_check_project` only called `render_all` when `diag_collector_has_errors` (errors only). C09xx warnings were added to the collector by `run_unused_analysis` (`:161`) but never rendered → silently dropped, "check passed for all modules" with exit=0 and no warning shown.
- **Fix:** mirror single-file `run_check` (`build.odin:484-501`) — render warnings when `warning_count > 0` (non-JSON). Hard errors already returned above; exit stays 0 for pure warnings.
- **Verification:** `check-project` e2e test (clean `Main.camp`) still exits 0 with "check passed for all modules" (no warnings). `count = 1 + 2` (unused) in project check now renders C0900 + "1 warning(s) found" + "check passed for all modules", exit=0.
- **Note:** this does NOT affect single-file `build`'s success path — `build` still swallows warnings (by design, see structural finding). To observe warnings in e2e, tests must use `args = "check"` (project mode).

## NEW compiler bugs surfaced (NOT fixed — split into separate beans)

### BUG-1: `_$x` (underscore-first) contradictory prefix never reaches C1000 — parser split
- **Where:** lexer/parser. `$` is a separate `Dollar` token (`src/frontend/lexer.odin:274`), not part of identifier lexeme. `_$x` lexes as `_` (identifier) + `$` (dollar) + `x` (identifier). The `_$x`-underscore-first form is parsed as a wildcard-target `_` assignment, so the binding name is never the literal `_$x` → `classify_name` (`src/analysis/unused.odin:17-25`) never returns `.Contradictory` for it → `register_binding` (`unused.odin:143-148`) never emits **C1000**.
- **Asymmetry:** `$_x` (dollar-first) IS handled correctly — `parser.odin:1593` `if p.current.kind == .Dollar` branch interns `$_x` as one name → C1000 fires (verified).
- **Diagnosis per catalog:** `docs/diagnostics-catalog.md` §11.1 says C1000 should fire for any name combining `_` and `$`. Both `_$x` and `$_x` should reach it. Currently only `$_x` does.
- **New bean:** see `BUG-1` bean file (contradictory-prefix-parser-split).

### BUG-2: C0901 UNUSED RECORD FIELD is completely unimplemented
- **Where:** `src/analysis/unused.odin:214` `register_record_field` is defined but has **ZERO callers**. `check_unused_record_fields` (`:1049`) iterates `analysis.record_fields`, which is always empty (only `make`/`delete`, never appended to outside the dead `register_record_field`). `mark_field_accessed` (`:231`) is called once (`:605`) but operates on never-populated data → no-op.
- **Effect:** C0901 (catalog §10.2, marked "✅ Implemented") is **unreachable** from any program. The "✅ Implemented" status in `docs/diagnostics-catalog.md:838` is inaccurate.
- **New bean:** see `BUG-2` bean file (c0901-record-field-unimplemented).

### BUG-3: project-mode `check` cannot resolve ANY stdlib import (C0800)
- **Where:** `src/build/project_check.odin` → `resolve_imports` (`src/build/import_resolve.odin:102`, `src/build/module_graph.odin:59`). `register_stdlib_modules` (`src/build/discovery.odin:286`) is called during project discovery, but every `import <StdlibModule> { … }` still emits **C0800 MODULE NOT FOUND** in project-mode `check`. Verified: `import List/Result/Iter/Str/Map/Set/Bool/Fmt` ALL fail C0800 via project check, while single-file `build` resolves the same imports fine (`stdlib_lookup` at `src/build/build.odin:143`).
- **Effect:** the `args = "check"` e2e path can use NO stdlib imports. Blocks `unused-import` from exercising C0902 via `args="check"`.
- **New bean:** see `BUG-3` bean file (project-check-stdlib-unresolved).

### BUG-4: design question — should `$x = $x` (undeclared LHS) reach C1001 before C0200?
- **Where:** `src/analysis/unused.odin:478-495` `collect_uses_assign`. `is_self_assignment` (`:536-544`) runs only inside the `if _, exists := analysis.bindings[name]; exists` branch (existing binding = reassignment). If `$x` is undeclared, the path takes the `else` branch (first-assignment = declaration) and never calls `is_self_assignment` → **C1001 never fires** for bare `$x = $x`; instead name resolution emits **C0200** (`$x` undefined on RHS) at `typecheck.odin:381-384`.
- **Design question:** is `$x = $x` (self-referential with undeclared LHS) supposed to lint as C1001 (no-op assignment) or C0200 (undefined name)? Reaching C1001 requires a prior `$x = 1`. The current behavior (C0200) is defensible, but the catalog §11.2 implies `$x = $x` is "always a mistake" → C1001.
- **Decision (from project owner):** rewrite the `self-assignment` test to `$x = 1; $x = $x` to exercise C1001 (see Phase B). Do NOT add a fake prior decl unless it's the minimal form reaching C1001 — and it IS minimal here.
- **New bean:** see `BUG-4` bean file (self-assign-undefined-vs-noop) — records the design question for separate resolution.

### BUG-5: `diag_unused_assignment` renders name as `$$x` (double `$`)
- **Where:** `src/analysis/unused.odin:965, 983` calls `diagnostics.diag_unused_assignment(name_str, …)` where `name_str` is already `"$x"` (with `$`), and the constructor `src/diagnostics/constructors.odin` formats `"Assignment #{n} to `${name}`…"` — but the actual output shows ``$$x`` (e.g. "Assignment #1 to `$$x` is unused"). The leading `$` is being doubled somewhere in rendering.
- **Effect:** cosmetic only, but visible in `var-overwrite-before-read` output via `args="check"`.
- **New bean:** see `BUG-5` bean file (unused-assignment-double-dollar).

## Phase B — test rewrites

Strategy (resolved with project owner):
- A new e2e special command `args = "check-file"` was added (src/e2e/runner.odin) invoking single-file `camp check <file>`. This renders C09xx warnings (unlike `build`, which swallows warnings on the success path) AND resolves stdlib imports via the single-file transitive-registration path (unlike project-mode `check`, which cannot parse the stale embedded stdlib sources — see camp-0ns2 / BUG-3). All warning-intended tests use `args = "check-file"` + `skip_wasm = true` (so the runner does not attempt wasm execution for a check-only test).
- Hard-error tests (C1000/C1001/C0201) use the default `build` path (exit=1, error rendered).

## Phase B status — COMPLETE. All 14 unused-analysis e2e tests pass (177/177 e2e total, 468/468 unit). Tests fail meaningfully when the intended warning is absent (verified by mutating immutable-unused to use its binding → C0900 disappears → test fails).

| Test | Main.camp form | Path | Asserted diagnostic | Notes |
|------|----------------|------|---------------------|-------|
| contradictory-prefix | `_$x = 5` (unchanged src) | build | C1000 CONTRADICTORY PREFIX (exit 1) | BUG-1 fix made `_$x` reach C1000 |
| self-assignment | `$x = 1; $x = $x` (rewritten) | build | C1001 NO-OP ASSIGNMENT (exit 1) | check_shadow fix + minimal-prior-decl per BUG-4 decision |
| shadowing-priority | `x = 1; x = 2; x` (unchanged) | build | C0201 SHADOWING (exit 1) | unchanged — was already correct (category iii) |
| immutable-unused | `count = 1 + 2` (rewritten) | check-file | C0900 UNUSED BINDING | real expr instead of undefined `items.length` |
| underscore-exempt | `_count = 1 + 2` (rewritten) | check-file | (clean — C0900 suppressed by `_` prefix) | asserts suppression; `items.length` replaced |
| record-unused-field | `r = { x:1, y:2 }; r.x` (rewritten) | check-file | C0901 UNUSED RECORD FIELD | BUG-2 fix wired register_record_field |
| record-escape | `use_x = \|r\| r.x; r={x:1,y:2}; use_x(r)` (rewritten) | check-file | (clean — r escapes, fields not tracked) | asserts escape suppression; real fn |
| unused-import | `import List { length, map }` (rewritten) | check-file | C0902 UNUSED IMPORT (x3 w/ dup bug camp-7btb) | real stdlib module |
| unused-pattern-binder | `match Ok(1) { Ok(x) => 0 }` (rewritten) | check-file | C0900 on `x` | prelude `Ok`, real scrutinee |
| var-overwrite-before-read | `$x = 1; $x = 2; 42` (rewritten) | check-file | C0904 UNUSED ASSIGNMENT x2 | BUG-5 fix: `$$x`→`$x` |
| var-loop-exempt | `$count` loop + Console.println + return (rewritten) | check-file | C0900 on `item` (loop var) | check_shadow fix removed false C0201; loop-var-exempt design Q → camp-pf7r |
| var-loop-pure-unused | `$count=0; for{ $count=99 }; 42` (rewritten) | check-file | C0904 x2 + C0900 on `item` | uses non-self-ref form (self-ref gap → camp-g6h9) |
| pointless-eval | `_ = 42` (unchanged, reference) | build | (clean exit 0, wasm_exit=42) | reference — unchanged |
| record-discard-not-use | `r={x:1,y:2}; _=r.y; r.x` (unchanged, reference) | build | (clean exit 0, wasm_exit=1) | reference — unchanged |

## New beans created for surfaced issues (camp-jrga scope split out)

- **camp-0ns2** — project-mode check/build cannot parse embedded stdlib sources (BUG-3, full fix needs design).
- **camp-4613** — design Q: `$x = $x` (undeclared LHS) C1001 vs C0200 (BUG-4).
- **camp-7btb** — C0902 emits duplicate warnings for same unused import (BUG-6, cosmetic).
- **camp-g6h9** — `$count = $count + 1` self-ref reassignment not flagged C0904 (BUG-7).
- **camp-pf7r** — design Q: should `for` loop variables be exempt from C0900 (loop-var-exempt).
- **camp-vwcv** — e2e harness `/tmp/camp-e2e` make_directory_all Permission_Denied in sandbox (environment).

## Status

camp-jrga RESOLVED. Its scope (make the 14 unused-analysis e2e tests exercise their intended diagnostics instead of blocked name-resolution errors, and surface real compiler bugs) is complete. The 5 real compiler bugs found were either FIXED in this bean (C-FIX-1 check_shadow, BUG-1 `_$x` parser, BUG-2 C0901 wiring, BUG-5 `$$x` rendering, plus C-FIX-2 project-check warning rendering + the e2e `check-file` workaround for BUG-3) or split into the new beans above (camp-0ns2 full fix, camp-4613 design, camp-7btb dup, camp-g6h9 self-ref, camp-pf7r loop-var, camp-vwcv env).

Verification: 177/177 e2e pass, 468/468 unit pass, leaks pre-existing (present on baseline).
