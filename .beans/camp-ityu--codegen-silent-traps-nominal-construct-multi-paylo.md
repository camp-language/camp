---
# camp-ityu
title: 'Codegen silent traps: Nominal_Construct multi-payload, binop Exp, IR_Method_Call, crash message discarded'
status: completed
type: bug
priority: high
tags:
    - codegen
created_at: 2026-06-24T04:27:11Z
updated_at: 2026-06-27T02:57:36Z
---

Source: error-path sweep. Several codegen paths emit Wasm_Unreachable / camp_exit silently with no diagnostic context:
- src/codegen/emit_expr.odin:3273-3278 — IR_Expr_Nominal_Construct for qualified variants or multi-payload newtypes emits Wasm_Unreachable ("not yet implemented") — should be a compile error, not runtime trap.
- src/codegen/emit_expr.odin:3330-3331 — binop .Exp emits Wasm_Unreachable; exponentiation unsupported at codegen (silent trap).
- src/codegen/emit_expr.odin:2551-2556 — IR_Method_Call reaching codegen traps via camp_exit(1) ("compiler bug"); should be diag_internal (C9000) with context.
- src/codegen/emit_expr.odin:3054,3057,2857 — Wasm_Unreachable fallbacks in par-for-each / write! op handling.
- src/codegen/emit_expr.odin:3216-3223 — IR_Crash: the crash message is computed then dropped (Wasm_Drop) before camp_exit(1); runtime crashes carry no diagnostic.

Done: each path either emits a proper compile-time diagnostic or, for IR_Method_Call, diag_internal with span. Nominal_Construct multi-payload and .Exp become real features or emit a "not yet implemented" error. Crash message reaches runtime. E2E tests cover each.


## Verification (2026-06-27)

afc901e ("fix(codegen): replace silent traps with diagnostics", PR #132) implements this bean in full; its `Refs: camp-k7n5` is a typo for camp-ityu. Verified against Done criteria:

- All 5 flagged paths in src/codegen/emit_expr.odin emit C9000 via `codegen_internal_error` (or, for IR_Crash, print the message Str to stderr via Print_Err before camp_exit):
  - IR_Method_Call (emit_expr.odin:2553-2562) — diag_internal with span.
  - Console!/File! unknown op fallback (emit_expr.odin:2862-2870).
  - Parallel! unknown op fallback (emit_expr.odin:3066-3073).
  - Scheduler effect unknown op fallback (emit_expr.odin:3075-3083).
  - IR_Expr_Nominal_Construct multi-payload/qualified-variant (emit_expr.odin:3329-3337).
  - binop .Exp / bitwise XOR (emit_expr.odin:3395-3400).
  - IR_Crash message reaches runtime (emit_expr.odin:3242-3266) instead of Wasm_Drop.
- codegen.odin:252 `codegen_internal_error` helper emits C9000; Codegen_Env carries `collector` (codegen.odin:116); `codegen()` threads `^Diagnostic_Collector` (codegen.odin:261, 301).
- build/build.odin (run_build_single, ~line 336) and build/project.odin (run_build_project, ~line 248) check `diag_collector_has_errors` after codegen and render+fail.

## e2e coverage (this PR)

- errors/codegen-exp-unimplemented (Exp / XOR) — pre-existing from afc901e.
- execution/crash-message (IR_Crash stderr message) — pre-existing from afc901e.
- errors/codegen-nominal-construct-multi-payload — NEW; `@Pair: pub [Pair(I64, I64)]` then `@Pair(1, 2)` triggers the C9000.
- errors/codegen-nominal-construct-qualified-variant — NEW; `@Result(a, e): pub [Ok(a) | Err(e)]` then `@Result.Ok(42)` triggers the C9000.
- IR_Method_Call and the scheduler-effect fallbacks (Console!/Parallel!/scheduler unknown op) are NOT e2e-coverable: they are defensive paths reachable only via a compiler bug in an earlier stage (monomorphization / effect routing), not from valid Camp source. Covered instead by unit tests of the `codegen_internal_error` helper contract (src/test_codegen.odin: test_codegen_internal_error_records_c9000, test_codegen_internal_error_nil_collector_is_noop).

## `just check` gate

Green on CI (PR #132 was green). Locally `just check` is blocked by `test-doc-tests` only: `os.make_directory_all` returns `Permission_Denied` for every path on Odin dev-2026-05 on this machine (verified with a standalone Odin probe — `make_all("/tmp")` fails too), while `os.make_directory` works. `./camp test <file>` (used by the doc-tests recipe) calls `make_directory_all` for `/tmp/camp-test-<pid>-<name>` and the dir doesn't pre-exist, so the wasm write fails. The e2e runner ignores `make_directory_all` errors because `/tmp/camp-e2e/...` dirs pre-exist. This is an Odin-runtime toolchain bug on the local machine, NOT a Camp code issue and NOT in scope for camp-ityu. format-check / build / build-e2e / test-unit (505) / test-e2e (197) / lint-tree-sitter all green locally.

## Minor doc note (not blocking)

docs/diagnostics-catalog.md §14.1 (C9000) lists illustrative cases that "should become proper user-facing errors" (perform-without-handler, etc.) but does not mention the codegen "not yet implemented" C9000s (XOR, nominal construct) added by afc901e. The catalog says C9000 use is illustrative, not exhaustive, so no spec drift — but the catalog could be enriched in a separate docs pass.
