---
# camp-d3k1
title: Remove prelude trait impl registrations for always-compiled types
status: blocked
type: task
priority: normal
tags:
    - codegen
    - traits
    - prelude
created_at: 2026-06-22T06:30:00Z
updated_at: 2026-06-22T06:30:00Z
blocked_by:
    - camp-df9d
---

The prelude (`src/semantics/prelude.odin`) registers trait impls for primitive
types (Ord, Hash, Debug, Display) with `type_module = NO_NAME`. These serve
double duty:
1. Trait conformance — so `find_trait_impl` finds them during typecheck
2. Canonical name registrations — so codegen `func_map` has `I64_compare`,
   `Bool_compare`, etc. for container runtime dispatch

Once all primitive types are always-compiled (camp-df9d), their stdlib `.camp`
impls produce real WASM functions via `lower_tdecl_is_impl`. At that point
the prelude impl registrations can be removed for types that have stdlib
modules. Types without stdlib modules (I64, I32, F64, etc.) keep their
prelude registrations.

Removing requires:
1. Trait_impls propagation from dependency modules so the entry module's
   `resolve_trait_method` can find e.g. `Char_compare` from Char.camp's
   store. Previous attempt: propagated in the FIRST typecheck pass
   (build.odin, project.odin, project_check.odin, project_test.odin) —
   caused 14 e2e failures from spurious C0603 errors (the propagated impls
   triggered conformance checks for types the user didn't import). Must be
   in `combine_module_irs` only, OR done differently:
   - Option A: propagate trait_impls in combine_module_irs alongside bindings
     (per-module, not in the first pass). The entry module's store would get
     impls from deps during IR lowering but not during typecheck.
   - Option B: keep prelude impls for NON-always-compiled types, only remove
     for always-compiled types (Bool, Char). The prelude impls for I64, I32,
     etc. stay until those modules are also always-compiled. This avoids
     needing trait_impls propagation at all for the initial step.
   Option B is lower risk — start there.
2. Ensure codegen func_map resolves canonical names from stdlib impls, not
   prelude fallbacks. Test: `List.compare` with each primitive element type.
3. Verify container dispatch (List.compare, Result.eq, Map.eq) still works
   for all element types — run e2e `list-compare-method` test.

Prelude impl registrations to remove (once type's module is always-compiled):
- Display: Str_to_str, I64_to_str, I32_to_str, F64_to_str, Bool_to_str
- Debug: I64_debug, I32_debug, F64_debug, F32_debug, Bool_debug, Str_debug,
  Char_debug, Bytes_debug, Unit_debug
- Ord: I64_compare, I32_compare, I16_compare, I8_compare, U64_compare,
  U32_compare, U16_compare, U8_compare, F64_compare, F32_compare,
  Bool_compare, Str_compare, Bytes_compare, Char_compare
- Hash: I64_hash, I32_hash, I16_hash, I8_hash, U64_hash, U32_hash, U16_hash,
  U8_hash, F64_hash, F32_hash, Bool_hash, Str_hash, Bytes_hash, Char_hash

Keep: Eq/Default trait DECLARATIONS (no impl registrations — already correct).
