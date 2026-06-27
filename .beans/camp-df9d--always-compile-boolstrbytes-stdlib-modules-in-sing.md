---
# camp-df9d
title: Always-compile Bool/Str/Bytes stdlib modules in single-file builds
status: in-progress
type: task
priority: high
tags:
    - codegen
    - traits
    - stdlib
created_at: 2026-06-21T05:09:00Z
updated_at: 2026-06-27T23:21:00Z
---

Decision A (camp-24mj). Expand ALWAYS_COMPILE in build.odin to include all
primitive trait-impl modules so their trait methods compile to real WASM
functions even without explicit user import.

## Status
- **Char**: done (always-compiled since camp-24mj)
- **Bool**: done (always-compiled, all 492 unit + 179 e2e pass)
- **Str**: blocked — `Str is From { from = |val: Str| -> Bytes { Str.to_bytes(val) } }`
  body gets re-typechecked into a Construct_Tag + Call flat pattern during
  `combine_module_irs` that wasm validates as "type mismatch". Root cause is
  in how the re-typecheck resolves `Str.to_bytes` — the lambda body produces
  a different IR tree than the first typecheck.
- **Bytes**: blocked on Str (Bytes depends on Str for many operations)

## Blocker detail
When Str is added to ALWAYS_COMPILE, `Str_from_Bytes` (wasm func 168, params=1,
result=I32 after Bytes lower_type fix) has a body that allocates a Construct_Tag
(8-byte 0-field cell) followed by a Call, in a flat function body without block
wrapping. The source body `{ Str.to_bytes(val) }` should be a single function
call. The re-typecheck in combine_module_irs produces different IR. Also: the
`Bytes` primitive was missing from `lower_type.odin` (fixed: now `I32; is_heap=true`).

## Investigation plan for the Str re-typecheck blocker
1. Add a debug dump to `combine_module_irs` (project.odin ~line 336) that
   prints the TFile's `TDecl_Is_Impl` method bodies BEFORE and AFTER
   `typecheck_file`. Compare the first typecheck's TFile (saved in
   `ctx.module_stores`) with the re-typecheck TFile for Str.camp.
2. Specifically: dump `Str is From { from = ... }` method body as a TExpr tree.
   The first typecheck should produce `TExpr_Call(Str.to_bytes, [val])`. The
   re-typecheck produces something with `TExpr_Construct_Tag` — find out what.
3. Check whether `Str.to_bytes` is in scope during re-typecheck. The function
   is `pub to_bytes = |s: Str| -> Bytes { crash "intrinsic: Str.to_bytes" }`
   defined in Str.camp. During re-typecheck, `current_module = str_mod_id`
   (after the mod_id fix), so `Str.to_bytes` should resolve. If it doesn't,
   the body may be inferred as a different expression.
4. Also check: does the From trait's `from : (source) -> target` method
   signature interact with the lambda body during re-typecheck? The
   `verify_trait_conformance` for From now succeeds (From is registered in
   prelude), so the conformance check pins Self=Str and unifies the return
   type with `target`. If `target` gets constrained to something unexpected
   during re-typecheck, the body may be re-inferred.
5. Test with ONLY Str in ALWAYS_COMPILE (no Bool) to isolate whether Bool's
   From impls interact.
6. If the root cause is that `combine_module_irs` re-typecheck is fundamentally
   different from the first typecheck (different store state), consider
   skipping re-typecheck for `TDecl_Is_Impl` nodes — use the first
   typecheck's TFile for trait impl bodies instead.

## Once all primitives are always-compiled
- Remove prelude competing instances (`camp-d3k1`)
- Remove hand-written intrinsics (`camp-d3k2`)
- Display stdlib impls (`camp-d3k3`)
- Unit.camp + Debug impl (`camp-d3k4`)
- Kitchen-sink tests (`camp-a6je`)
- Update specs
