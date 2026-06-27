---
# camp-3ojo
title: Multi-param trait support for From/TryFrom/IntoIter/FromIter
status: complete
type: task
priority: normal
tags:
    - traits
    - type-system
created_at: 2026-06-21T05:09:30Z
updated_at: 2026-06-22T02:15:00Z
---

## Problem

From, TryFrom, IntoIter, and FromIter are multi-param traits (e.g. From(source, target)) whose stdlib impls are written as 'Source is From { from = ... }' which does not match the current conformance model (param[0] is Self). The prelude does not inject these trait declarations (only Eq and Default are injected). Their 74 stdlib impls across 16 files are silently skipped during conformance (camp-24mj fix). Properly supporting them requires: (1) a multi-param trait dispatch design with applied constraint parameters, (2) prelude injection for all four traits, (3) stdlib trait impl files.

## Progress

### Completed

1. **Trait_Info extended** (`src/semantics/types.odin`):
   - Added `self_in_return: bool` — true = Self is the return type (e.g. FromIter), false = Self is params[0]
   - Added `is_multi_param: bool` — true = same type can have multiple impls with different targets (From, TryFrom)

2. **Prelude injection** (`src/semantics/prelude.odin`):
   - `From`: `from : (Self) -> Target` — Self=params[0], target=fresh var. `is_multi_param=true`.
   - `TryFrom`: `try_from : (Self) -> Result(Target, Error)` — Self=params[0], return=Result tag-union row with fresh Target/Error. `is_multi_param=true`.
   - `IntoIter`: `to_iter : (Self) -> Iter(Item)` — Self=params[0], return=Iter constructor.
   - `FromIter`: `from_iter : (Iter(a)) -> Self` — params[0]=Iter constructor, Self=return. `self_in_return=true`.

3. **Conformance model** (`src/semantics/check_decl.odin`):
   - Multi-param traits skip the overlap check (allow multiple impls with same source type)
   - `self_in_return` support: when true, pins expected return to Self instead of params[0]
   - Updated stale comment about From/TryFrom not being injected

4. **Disambiguated naming for multi-param traits** (`src/semantics/check_decl.odin`):
   - Added `lookup_binding` helper to search store/env bindings
   - Added `extract_multi_param_target` helper to extract target type from return type (handles both Inferred_Primitive for From and Tag_Union_Row with Ok payload for TryFrom)
   - In `verify_trait_conformance`, multi-param trait impls now register disambiguated canonical names (e.g. `Bool_from_I8` instead of `Bool_from`)
   - Disambiguated bindings are registered in both store.bindings and env.bindings

5. **Trait_Impl extended** (`src/semantics/types.odin`):
   - Added `target_type_name: base.Intern_ID` field for multi-param traits
   - `find_trait_impl` accepts optional `target_type_name` parameter for return-type-aware lookup
   - `find_trait_impl_by_method` accepts optional `target_type_name` parameter

6. **Mono dispatch integrated** (`src/mono/mono.odin`):
   - `find_method_impl` accepts optional `target_type_name` parameter, passed through to `find_trait_impl_by_method`
   - Added `resolve_type_name` helper to extract type name from IR_Type
   - Both dispatch sites (`substitute_types_in_expr` and `rewrite_calls_in_expr`) now resolve the expected return type and pass it as `target_type_name` to `find_method_impl`
   - Multi-param dispatch works end-to-end: `b->from()` in an I8 context resolves to `Bool_from_I8`, in I16 context to `Bool_from_I16`, etc.

7. **Stdlib trait declaration files updated**: From.camp, TryFrom.camp, IntoIter.camp, FromIter.camp now match the prelude injection signatures.

8. **IntoIter/FromIter stdlib impls**:
   - `Set is IntoIter` and `Set is FromIter` — delegate to existing `Set.to_iter` and `Iter.fold`
   - `Map is IntoIter` and `Map is FromIter` — delegate to existing `Map.to_iter` and `Iter.fold`
   - `Iter is IntoIter` — identity conversion
   - List IntoIter/FromIter omitted due to WASM codegen i32/i64 mismatch bug with recursive list operations (same blocker as List.filter)

9. **E2e test for multi-param dispatch**: `tests/e2e/traits/multi-param-from/` verifies compilation succeeds when calling `from` with specific expected return types

10. **All tests pass**: 473 unit tests, 179 e2e tests (snapshots updated for wasm function index shifts)

### Known limitations

- These items now have their own beans:
  - WASM i32/i64 codegen bug blocking List operations → `camp-jqvd`
  - Encode/Decode design → `camp-lh35` (blocked on method generics)
  - Constructor type args not tracked → `camp-8e9u` (low priority)
