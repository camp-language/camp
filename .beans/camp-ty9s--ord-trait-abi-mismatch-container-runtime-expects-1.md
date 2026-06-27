---
# camp-ty9s
title: 'Ord trait ABI mismatch: container runtime expects -1/0/1 i32 callbacks but stdlib Ord.compare lambdas return Order heap tags'
status: in_progress
type: bug
priority: high
created_at: 2026-06-20T07:13:03Z
updated_at: 2026-06-20T07:45:00Z
blocked_by:
    - camp-24mj
---

## Progress (2026-06-20): Design B container-compare ABI layer DONE

The container runtime compare intrinsics have been rewritten to Design B:
callbacks are treated as returning `Order` heap tag cells. Verified end-to-end:
`List.compare([True,False],[True,False])` returns `Equal` (exit 1) and all 9
ordering variants are correct + deterministic. 468/468 unit tests pass,
176/176 e2e tests pass (incl. new `tests/e2e/traits/list-compare-method`).

### Changed files
- `src/codegen/container_hash.odin`: added `consume_order_to_trinary` (read
  Order tag → trinary, `camp_drop` the intermediate) and
  `emit_order_cell_from_trinary` (build Order cell from trinary) shared helpers;
  rewrote `emit_list_compare_body` and `emit_result_compare_body` to consume
  Order callbacks + return Order cells. Fixed a pre-existing off-by-two `br`
  label bug in `List_Compare`'s both-Nil path (was masked because List.compare
  always trapped before).
- `src/codegen/runtime.odin`: added `drop_func_idx` param to
  `emit_map_{insert,get,contains,remove}_body`; map compare callbacks now
  consumed via `consume_order_to_trinary`. `emit_i64_trampoline_body` now wraps
  `I64_compare`'s raw -1/0/1 into an Order cell (I64-keyed maps flow through
  the same map runtime bodies). Added `emit_bool_compare_body` interim
  intrinsic. `I64_compare` itself unchanged.
- `src/codegen/codegen.odin`: registered `Bool_Compare` `Runtime_Func` +
  `func_map["Bool_compare"]` (matches prelude's `Bool is Ord` canonical name);
  threaded `drop_func_idx`/`alloc_func_idx` through body emitters.
- `src/codegen/emit_expr.odin`: added `Bool_Compare` to `Runtime_Func` enum.
- 5 e2e snapshot files updated (pure wasm-func-index/offset shifts from adding
  one runtime function; trap types unchanged) — these test not-yet-implemented
  effect/scheduler features with hardcoded backtraces.
- `tests/e2e/traits/list-compare-method/` (new): acceptance e2e test.

### What's NOT done (still under camp-24mj / camp-stdlib-compile-single)
1. **Only `Bool` has a real element compare** (`Bool_compare`, hand-written
   intrinsic). `Char_compare`, `Str_compare`, `I32_compare`, `F64_compare`,
   `U8_compare`... remain names-only in `store.trait_impls` with no WASM body —
   `cmp_fn_idx` stays 0 for those element types → still traps. Need the
   stdlib-compile-single path (or more hand-written intrinsics) to provide them.
   Bean acceptance test currently must use Bool elements, not Char (`['a','b']`).
2. **stdlib-compile-single not resolved**: embedded `STDLIB_MODULES` sources in
   `src/build/stdlib.odin` are stale (pre-trait-impl); `run_build_single` doesn't
   route through `combine_module_irs`. So real stdlib `Bool.compare`/
   `Char.compare` lambdas don't reach lowering in single-file builds — the
   hand-written `Bool_compare` intrinsic stands in for now.
3. **`Result.compare` path unverified end-to-end** (needs a real
   `Result_compare` element callback; `Bool` works but no test yet). The codegen
   was rewritten to Design B consistently with List.compare.
4. Per-element alloc/drop of `Order` in compare loops (perf cliff) — tracked in
   `camp-9xi6` (unboxed enums).

### Original problem statement (kept for context)

## Problem

Discovered while investigating `camp-24mj`. The container runtime compare/eq/hash
functions (`List_Compare`, `Result_Compare`, `Map_Insert`, etc.) invoke element
trait-method callbacks via `call_indirect` with type signature `(i32, i32) -> i32`
and treat the return value as a **raw signed tri-state integer** `-1/0/1`
(`src/codegen/container_hash.odin:246-260` `List_Compare` does double-`Eqz` on
the callback result; `:98-115` `Result_Compare` `Return`s it verbatim). The only
real callback that satisfies this convention today is the hand-written runtime
intrinsic `I64_compare` (`src/codegen/runtime.odin:3866-3897`, returns -1/0/1).

The prelude registers the *names* `Bool_compare`, `Char_compare`, `Str_compare`,
`I8_compare`, ... in `store.trait_impls` (`src/semantics/prelude.odin:537-574`),
matched by `resolve_trait_method` (`src/ir/lower.odin:3428-3456`) and looked up
in `func_map` at the codegen dispatch sites (`emit_expr.odin:571-592` etc.).

**But the stdlib lambda bodies behind those names return `Order`, not `i32`.**
E.g. `stdlib/Bool.camp:74-78`:

```
Bool is Ord {
    compare = |a: Self, b: Self| -> Order {
        if a < b { Less } else if a == b { Equal } else { Greater }
    }
}
```

`Order` is a tag union `[Less | Equal | Greater]` (`prelude.odin:84-88`) whose
runtime representation is a **heap-allocated cell with a tag byte 0/1/2**
(`lower_type.odin:39-40`: `Inferred_Tag_Union_Row` → `i32, is_heap=true`;
`emit_expr.odin:2261-2360` `IR_Construct_Tag` always allocates a cell, even for
no-payload tags). A compiled `Bool_compare` lambda would therefore return a
**non-zero heap pointer** for ALL three variants, which the runtime's `!= 0`
check reads as "not equal" — i.e. `Less`, `Equal`, and `Greater` all compare
unequal. ABI-incompatible.

## Bidirectional mismatch

1. **Element callback side**: a compiled stdlib `Ord.compare` lambda returns an
   `Order` heap pointer, but `List_Compare`/`Result_Compare`/`Map_Insert`
   interpret the callback return as `-1/0/1`. Even after `camp-24mj` is fixed
   and the lambdas compile, passing them as `cmp_fn` is wrong.
2. **Container result side**: `List.compare`/`Result.compare` codegen
   (`emit_expr.odin:588-591`, `:1288-1291`) pushes the runtime's raw `i32`
   result directly as the source-level return — but the type system says these
   return `Order` (a heap tag). A source-level `match List.compare(...) { Equal => 1 }`
   compiles to `.Tag_Union` match (`codegen.odin:50-54` `determine_match_kind`)
   which does `Wasm_I32_Load8U{offset=CAMP_TAG_TAG_OFFSET}` on the scrutinee
   (`emit_expr.odin:1784`) — a wild read when the scrutinee is a raw `-1/0/1`
   integer.

## Eq is NOT affected

`Eq.eq` lambdas return `Bool`, which is an **immediate i32 0/1**
(`lower_type.odin:26-27`: `is_heap=false`; `emit_expr.odin:399-404,3291`). The
container runtimes `Result_Eq`/`Map_Eq`/`Set_Eq` return raw `1/0` and push it
as the source-level `Bool` result. Both directions ABI-compatible. So
`Result.eq`/`Map.eq`/`Set.eq` will work once `camp-24mj` compiles the eq lambdas;
only `Ord` paths (`List.compare`, `Result.compare`, Map/Set keyed compare,
`Set.from_list`) are broken on the ABI level.

## No adapter exists today

Grep of `src/codegen/` finds zero conversion between raw `i32` and `Order`
heap tags. The `Order`/`Less`/`Greater`/`Equal` strings appear only in
comments (`emit_expr.odin:567,1251`, `container_hash.odin:70`).

## Fix direction (DECIDED 2026-06-20: Design B)

**Chosen: Design B.** The principled fix: container runtime intrinsics honor
their declared return type (`Order`), and element `Ord.compare` callbacks return
`Order`. One convention at every layer, source-compatible, signature-honoring.
Design A was rejected — it would ratify the runtime/signature divergence with
permanent `i32 ↔ Order` adapter layers whose only purpose is bridging a gap
that shouldn't exist.

### B implementation shape

1. Element callback side: a compiled stdlib `Ord.compare` lambda returns an
   `Order` heap cell and is passed directly as the `cmp_fn` (no `-1/0/1`
   conversion). `resolve_container_trait_fn` (`lower.odin:3592`) returns the
   lambda's name unchanged for `compare` (it already does). No thunks.
2. Container runtime side — rewrite the compare intrinsics to treat the
   callback return as an `Order` heap cell and read its tag byte:
   - `List_Compare` (`container_hash.odin:193-288`): after the element
     `call_indirect`, `load8u CAMP_TAG_TAG_OFFSET` → map `0 (Less)→-1`,
     `1 (Equal)→0`, `2 (Greater)→+1` for the walker's `!= 0` / loop logic; AND
     `Drop` the intermediate `Order` (it has refcount 1) before continuing.
   - `Result_Compare` (`container_hash.odin:71-140`): same read+drop for the
     `Ok`/`Err` payload comparison results.
   - `Map_Insert`/`Map_Get`/`Map_Contains`/`Map_Remove`/`Map_Singleton`/
     `Set.from_list` (`runtime.odin:3929+`): callback returns `Order` tag; map
     `Less→negative`, `Equal→0`, `Greater→positive` for `< 0` / `== 0` /
     `> 0` tests; drop intermediate.
   - `Map_Eq`/`Set_Eq`/`Result_Eq`/`Result_Hash`/`List_Hash` use `Eq.eq`/
     `Hash.hash` callbacks (ABI-compatible — `Bool`/`Hasher` are pass-through
     i32) — **no change needed**; only the `Ord`-consuming intrinsics change.
3. Container result side — `List.compare`/`Result.compare` codegen
   (`emit_expr.odin:588-591`, `:1288-1291`) already pushes the runtime's result;
   under B the runtime returns an `Order` heap cell directly, so no `i32→Order`
   wrap is needed at the dispatch sites. The runtime *owns* constructing the
   result `Order` (e.g. `List_Compare` allocs the final `Less`/`Equal`/`Greater`
   before returning) — match-on-result works without adapters.
4. `I64_compare`: stays a hand-written intrinsic (`runtime.odin:3866`) returning
   `-1/0/1` for the *internal* I64-keyed Map/Set path (it never flows into
   `List.compare`); OR gains an `Order`-returning sibling if I64 should also
   flow through container compare. TBD: keep the I64 trampoline
   (`runtime.odin:3828`) for Map keys; route `List([I64])`'s element compare
   through a thunk that calls `I64_compare` and constructs `Order`. (Smaller
   scope: leave I64 as-is for now; I64-through-List.compare is a rare case.)

### RC hazard (acknowledged, acceptable, symmetric with A)

Every element compare in a walk allocates a one-use `Order` and the runtime
drops it before continuing. This overhead is the *same* in Design A (the thunk
also allocs-and-drops). The real fix is **unboxed enums** (`camp-9xi6`): no-payload
tag unions like `Order` lower to immediate scalars, zero alloc. Until unboxed
enums land, B carries the per-element alloc cost — recorded, not a reason to
choose A. A's ratifying-the-divergence cost is permanent; B's alloc cost is
retired when `camp-9xi6` ships.

### Non-goals under B (deferred)
- Writing `List.compare`/`Map.insert` as pure-Camp generics (Design C). Blocked
  on generics monomorphization reaching those call patterns. `stdlib/List.camp:74`
  `crash "intrinsic: List_compare"` stays as the intrinsic stub.
- Unboxed enums (`camp-9xi6`).
- The `camp-yxts` unboxed-I64-payload `i32.load` bug stays as-is; B does not
  touch Map/Set I64 storage layout.

## Test (acceptance, from camp-24mj)

```
import List { compare }
import Order { [Less, Equal, Greater] }
main! = || -> I64 {
  match List.compare(['a','b','c'], ['a','b','c']) {
    Less => 0
    Equal => 1
    Greater => 2
  }
}
```

Note: the version in `camp-24mj` and `camp-yxts` uses `;` arm separators
(`{ Equal => 1; _ => 0 }`), which the parser rejects (`;` is not a match arm
separator per `docs/language-spec.md:326-334`). Use newlines.

## Related

- `camp-24mj` — trait method impls never compiled to standalone fns (this bean's
  parent; resolving it alone does NOT fix Ord dispatch due to this ABI gap).
- `camp-yxts` — container eq/compare/hash do `i32.load` on unboxed I64
  payloads (overlaps Design B).
- `a5fab26` (merged) — introduced pure-Camp `Ord.compare` for scalars returning
  `Order`; that's the source of the lambda bodies that are now ABI-incompatible
  with the runtime convention.
