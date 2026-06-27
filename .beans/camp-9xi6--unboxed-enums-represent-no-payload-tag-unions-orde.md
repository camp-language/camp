---
# camp-9xi6
title: 'Unboxed enums: represent no-payload tag unions (Order, Bool, Result tag) as immediate values, eliminating per-element alloc in compare/hash loops'
status: in_progress
type: task
priority: high
created_at: 2026-06-20T07:30:00Z
updated_at: 2026-06-20T07:30:00Z
related:
    - camp-ty9s
    - camp-24mj
---

## Problem

Camp represents *every* tag union value — including no-payload enums like
`Order = [Less | Equal | Greater]` — as a heap-allocated cell with a tag byte
(`src/semantics/lower_type.odin:39-40` `Inferred_Tag_Union_Row` → `i32, is_heap=true`;
`src/codegen/emit_expr.odin:2261-2360` `IR_Construct_Tag` always allocs, even for
zero-payload tags). `Bool` is the lone exception (immediate `i32 0/1`,
`lower_type.odin:26-27`).

This makes `Order` heap-allocated, so every element compare in a `List.compare` /
`Map.insert` walk allocates a one-use `Less`/` Equal`/`Greater` cell and drops it
inside the loop. That allocation is pure overhead and an RC hazard, and it is the
underlying reason the A-vs-B `camp-ty9s` debate was awkward.

## Goal

Tag unions with **no payload across all variants** (e.g. `Order`, user-defined
`[Red | Green | Blue]`, `Result` *tag* but not its payloads) should lower to an
**immediate scalar** (small `i32` tag value), not a heap cell. Matching reads the
scalar directly (`i32.eq` / `br_table` on the value) instead of `load8u` at a tag
offset. Construction is a constant. No alloc, no RC, no drop.

This is the long-run destination of `camp-ty9s` Design C: with unboxed `Order`,
container `compare`/`eq`/`hash` can be written as plain Camp generics calling the
element trait methods, monomorphized per type — `call_indirect` + `func_map`
bridging + runtime intrinsics all deleted. `Order` (and any user enum) flows by
value through every layer with one representation.

## Scope (design TBD)

- Type-system/lowering: how to detect an "all-variants-no-payload" tag union and
  mark it `is_heap=false`, scalar `i32`.
- Codegen: `IR_Construct_Tag` picks immediate-const path for these; match
  dispatch reads the scalar; drop is a no-op.
- Interaction with polymorphism: an enum-typed value of statically-unknown
  variant set (e.g. an open row) must still be boxed — only *closed* no-payload
  tag unions qualify.
- Interaction with RC/reuse analysis (Perceus): immediate values are
  non-reference-counted; reuse nodes must not target them.
- Migration: `Bool`'s existing immediate path is the prior art to generalize.

## Not blocking

`camp-ty9s` Design B (container intrinsics return `Order`) proceeds without this;
it just carries the per-element-alloc cost until unboxed enums land. Filing this
so the cost is recorded rather than rediscovered as a "performance bug" later.

---

## Phase 1 Investigation — findings (2026-06-21)

Scope of read: `src/semantics/{lower_type,check_expr,check_control,check_decl,typecheck,types,unify,prelude}.odin`,
`src/ir/{ir,lower,rc,reuse,wasm_type}.odin`, `src/mono/mono.odin`,
`src/codegen/{codegen,emit_expr}.odin`, `src/codegen/container_hash.odin`,
`src/base/ir_type.odin`, `stdlib/{Bool,Ord}.camp`. No code changed (read-only).

### A. Type representation (the locus)

- `src/semantics/lower_type.odin:39-40` — `case Inferred_Tag_Union_Row: wasm_type=.I32; is_heap=true`. **This is the single line to change for the representation.** No per-variant inspection here today.
- `src/base/ir_type.odin:15-19` — `IR_Type{wasm_type, type_id, is_heap}`. No room for a new "immediate enum" flag without extending the struct. `is_heap=false` + `wasm_type=.I32` is the same shape Bool already uses.
- `src/semantics/types.odin:95-98` — `Inferred_Tag_Union_Row{tag_entries: []Type_Tag_Entry, tag_rest: Type_Var_ID}`. **No `closed` field** (unlike `Inferred_Record_Row` `closed: bool` at :92 and `Inferred_Tuple` `closed: bool` at :1242).
- `Type_Tag_Entry` = `{name: Intern_ID, payload: []Type_Var_ID}` (`types.odin:57`). No-payload tag = empty `payload` slice.

### B. Construction sites of `Inferred_Tag_Union_Row` (where rows are born open)

All sites set `tag_rest := fresh_tag_row(...)` — an **unresolved fresh `Row_Tag` var = open row by default**. There is NO site that produces a definitively-closed tag row:
- `src/semantics/check_expr.odin:441-443` (`typecheck_tag`, bare tag like `Less`)
- `src/semantics/check_expr.odin:704-720` (`typecheck_list_literal`, `Nil`/`Cons`)
- `src/semantics/check_control.odin:105-117` (tag pattern in match)
- `src/semantics/typecheck.odin:1029-1057` (prelude tag-union synthesis — `List`/`Result`/`Ordering`)
- `src/semantics/typecheck.odin:1247-1268` (`convert_type_to_var_val`, `CType_Tag_Union` — **user annotation `[Red | Green | Blue]`**). This is the closed-declaration site; it still creates an open `tag_rest` because the data type has no `closed` field.
- `src/semantics/typecheck.odin:1556-1580` (`instantiate_rec`, generic instantiation — deep-clones `tag_rest`)
- `src/semantics/typecheck.odin:1410-1427` (`deep_clone_type`-ish path)
- `src/semantics/check_decl.odin:331` (newtype `{tags}` body — copies `tag_entries` only)

**Detection rule implication:** "closed" cannot be read off `tag_rest` alone. A row built by `convert_type_to_var_val` from a syntactic `[A | B | C]` is *morally* closed (the source listed all variants), but structurally indistinguishable from a one-arm open row built by `typecheck_tag`. The pipeline needs an explicit marker. See Q1.

### C. Unification model (how rows settle)

- `src/semantics/unify.odin:695-802` `unify_tag_union_rows`. When two rows share entries, rests unify via `fresh_tag_row` (`:756`, `:759`). Even when both sides are "complete", the shared rest stays an unresolved `Row_Tag` var forever — **there is no "closed/empty" sentinel** and no generalization step that pins a row as closed. Only exhaustiveness-check (`check_control.odin:476-485`) inspects `tag_entries` count + `cov.saturated`, and only for missing-arm diagnostics, not for representation.

### D. Monomorphization & representation propagation (CRITICAL for Q5)

- `src/mono/mono.odin:903-939` `substitute_ir_type`. Two gaps:
  1. **Early return at :915-917**: if `type_id` already resolves to an `Inferred_Type` (linked), it returns `ir_type` unchanged. So a generic decl whose param `T` was already bound to a concrete tag union at typecheck keeps whatever `wasm_type`/`is_heap` it had then.
  2. **`:925-936`**: for the generic-param case, it derives `wasm_type` from the concrete type but ONLY handles `Inferred_Newtype` (`:930-932`). It does NOT handle `Inferred_Tag_Union_Row`. It returns `IR_Type{wasm_type, type_id=concrete_resolved}` with `is_heap` defaulted to `false` — accidentally "right" for our optimization, but for the wrong reason, and it would not set `is_heap=true` for a *payloaded* tag union monomorphized into a generic. This is a latent bug independent of this bean: a generic `T` monomorphized to a payloaded tag union (e.g. `List(Result(I64, Str))` element type) currently gets `is_heap=false` from this path. Worth flagging to owner.
- `specialize_decl`/`specialize_newtype` (`:448-491`) call `substitute_ir_type` on `decl.type_` and every `TExpr.type_`. So if a generic body constructs `Less` (a `TExpr_Tag`), the specialized decl's `TExpr_Tag.type_.is_heap` is whatever `substitute_ir_type` produced — per above, currently `false` for the param-resolved case. **Net: monomorphization does NOT robustly propagate `is_heap` today; Q5 needs the owner to decide whether to fix `substitute_ir_type` as part of 9xi6 or to scope 9xi6 to non-generic call sites only.**

### E. RC (Perceus) — fully gated on `is_heap`, Bool proves it

- `src/ir/rc.odin` — every drop/dup path checks `is_heap` before emitting `IR_Dup`/`IR_Drop`:
  - `emit_drops_for_branch` `:259-260` `if !type_info.is_heap do continue`
  - `emit_param_drops` `:308` `if !param.type.is_heap do continue`
  - `rc_insert_expr_inner` `:508-509` (dup on use) `if type_ok && type_info.is_heap`
  - `:549`, `:559` (let rebind drop) `if e.type.is_heap`
  - `:643` (match-arm drops) `if !type_info.is_heap do continue`
- `collect_heap_types` (`:397-491`) copies `IR_Type` from `IR_Let`/`IR_Var`/params into the map; reads back via `is_heap`. A no-payload immediate union with `is_heap=false` therefore produces **zero** `IR_Drop`/`IR_Dup`. **RC layer needs no change.**
- **Bool is the proof.** `Bool` = `Inferred_Primitive{primitive_name="Bool"}` → `lower_type` :26-27 → `is_heap=false`. `make_ir_lit_bool` (`src/ir/lower.odin:251-259`) produces `IR_Literal_Bool`, and `ir_expr_is_heap` (`src/ir/wasm_type.odin:82-83`) returns `false` for `^IR_Literal_Bool`. No RC nodes ever target a Bool. Same mechanism applies if a no-payload tag union gets `is_heap=false`.

### F. Reuse analysis — safe (no hazard)

- `src/ir/reuse.odin` matches `IR_Drop{y}` immediately followed by `IR_Construct_Tag{...}` and sets `reuse_addr=y` (`extract_reuse_from_body` `:338-374`; `optimize_block_drops` `:411-440`).
- **Reuse CANNOT fire on an immediate union**: the `IR_Drop{y}` it looks for is only emitted by rc when `y.is_heap==true`. An immediate union has `is_heap=false` → no drop → `extract_reuse_from_body` finds nothing → `reuse_addr=NO_REUSE_ADDR`. The `IR_Construct_Tag` codegen's `e.reuse_addr != NO_REUSE_ADDR` branch (`emit_expr.odin:2291`) is never taken for immediates. **No reuse-node retargeting hazard.**

### G. Codegen — construction (`IR_Construct_Tag`)

- Definition `src/ir/ir.odin:315-322`: `{tag_name, tag_index:int, payload:[dynamic]IR_Expr, reuse_addr, type:IR_Type, span}`. `tag_index` is the variant ordinal (0-based) from `resolve_tag_index` (`src/ir/lower.odin:2768-2781`, which flattens entries and returns the position). **Ordinal stability:** `resolve_tag_index` walks `flatten_tag_entries` (`:2741-2766`) which iterates `tag_entries` in declaration order, dedups by name, then recurses `tag_rest`. For a closed no-payload union the ordinal is stable across construction and matching as long as both sides flatten the same row. Already true today; the immediate path reuses `tag_index` as the immediate value.
- **The allocation site** `src/codegen/emit_expr.odin:2269-2367` (`case ^ir.IR_Construct_Tag`). It UNCONDITIONALLY: computes `scan_size`/`scalar_mask`, `tmp_local`, emits `Wasm_Call Alloc`, stores refcount/tag/scan_size/scalar_mask, stores each payload field. There is **no `if e.type.is_heap` gate**. This is the primary codegen change: branch on `!e.type.is_heap` (or a new node flag — see Q3) and emit just `Wasm_I32_Const{value = i32(e.tag_index)}` for the immediate case.
- `IR_Construct_Tag` clone sites that must preserve any new flag/field through transformation:
  - `src/ir/lower.odin:2851-2860` (`lower_ttag`, the producer), `:3046-3047` & `:3063-3064` (`lower_list_literal` Nil/Cons), and the `Inferred_Tag_Union_Row` case noted by the bean near `~3491` (verify exact line during impl).
  - `src/ir/closure_convert.odin:109, 256, 784, 1108` (verbatim copy fields today).
  - `src/ir/effect_lower.odin:498-509, 1596-1609` (verbatim copy fields today).
  - `src/ir/rc.odin:111, 373-384, 431-457, 747-755` (rc does NOT clone IR_Construct_Tag wholesale except at `:747` in a match-arm reuse path — verify).
  - `src/ir/reuse.odin:159-173, 384-394, 430-440` (reuse rebuilds IR_Construct_Tag).
  If we add a flag, ALL these `IR_Construct_Tag {...}` literal reconstructions must copy it. If we derive from `e.type.is_heap`, NO clone site changes (the `type` field is already copied everywhere).

### H. Codegen — matching (the `load8u` sites)

- `src/codegen/codegen.odin:42-48` `Match_Kind{Tag_Union, Bool, Int, String, Record}`. `determine_match_kind` (:50-75): returns `.Tag_Union` if any arm is `IR_Pat_Tag`; `.Bool` if any arm is `IR_Pat_Bool`. All-catch-all fallthrough picks `.Int`/`.Bool` on scrutinee wasm type (:68-73). **A no-payload closed union still uses `IR_Pat_Tag` arms (the pattern AST is identical to payloaded tag unions — see `src/ir/lower.odin:1537-1540, 1585-1588, 2177-2179, 2606-2608`). So `determine_match_kind` returns `.Tag_Union` for an immediate enum.** Q4: either sub-branch `.Tag_Union` on `scrutinee.is_heap`, or add a `Match_Kind.Immediate_Tag`. Note `IR_Pat_Tag` already carries `tag_index` (`ir.odin:277`), so the immediate match can compare `i32.eq(scrutinee, p.tag_index)` directly — same shape as `IR_Pat_Bool` (`emit_expr.odin:2000-2003`).
- `.Tag_Union` dispatch reads the tag via `Wasm_I32_Load8U{offset=CAMP_TAG_TAG_OFFSET}` on the scrutinee *pointer* in BOTH the guarded path (`emit_expr.odin:1792`) and the `br_table` path (`:1933`), then loads payload fields at `CAMP_TAG_FIELDS_OFFSET + j*8` (`:1813, :1949`). For an immediate: skip the load (value IS the tag), and there are no payload fields to load (no-payload union). Payload-load loop is a no-op because `len(p.payload)==0`.
- `CAMP_TAG_TAG_OFFSET=4`, `CAMP_TAG_FIELDS_OFFSET=8`, `CAMP_TAG_HEADER_SIZE=8`, `CAMP_TAG_REFCOUNT_OFFSET=0`, `CAMP_TAG_SCAN_SIZE_OFFSET=5`, `CAMP_TAG_SCALAR_MASK_OFFSET=6` (`src/codegen/codegen.odin:8-17`). Only referenced in `codegen.odin` and `container_hash.odin`.

### I. Codegen — the `ir_expr_is_heap` hazard (NOT flagged by bean — surfacing)

- `src/ir/wasm_type.odin:86-91` hardcodes `^IR_Construct_Tag => return true` (and `IR_Construct_Record`, `IR_Construct_Tuple`, `IR_Closure`, `IR_Expr_Nominal_Construct`). It does NOT consult `e.type.is_heap`.
- This is consumed at `src/codegen/emit_expr.odin:2278` (Construct_Tag `scalar_mask` for its OWN payload fields) and `:2377` (Construct_Record `scalar_mask` for its fields). Both compute `heap_ptr := ir.ir_expr_wasm_type(p) == .I32 && ir.ir_expr_is_heap(p)` for each child value to set the parent cell's `CAMP_TAG_SCALAR_MASK_OFFSET` bit (so `camp_drop` knows which fields NOT to recurse into).
- **Concrete hazard if Order (or any no-payload enum) becomes immediate and appears as a record/tuple field or a payloaded tag's field:** `ir_expr_is_heap(order_construct)` returns `true` (hardcoded) → parent's scalar_mask bit for that field is cleared → `camp_drop` on the parent treats the immediate `i32` ordinal as a heap pointer and dereferences it → **trap**.
  - This is a *new* hazard created by the optimization (today no tag union is immediate, so `IR_Construct_Tag` is genuinely always-heap and the hardcode is correct).
  - Fix: make `ir_expr_is_heap` consult `e.type.is_heap` for the `^IR_Construct_Tag`/`^IR_Construct_Record`/`^IR_Construct_Tuple`/`^IR_Expr_Nominal_Construct` cases instead of hardcoding `true`. This is in `src/ir/wasm_type.odin` — tiny change, but it's a behavior shift PAST the bean's flagged surface, so calling it out for owner signoff in Q2.
  - Note: a no-payload enum can appear as a record field (`{result: Order}`) or tuple element (`(I64, Order)`) or a payloaded-tag payload (`Ok(order)`) — all real cases (e.g. `List.compare` returning `Order` inside a result struct). The fix must land together with the immediate codegen, or container drops will trap.

### J. `container_hash.odin` — Design B interaction (Q7)

- `consume_order_to_trinary` (`container_hash.odin:26-46`): on entry the Order cell ptr is on the stack; it does `Wasm_I32_Load8U{offset=CAMP_TAG_TAG_OFFSET}` to read the trinary (0/1/2), then `camp_drop` on the pointer. With immediate `Order`, the stack already holds the trinary ordinal (0/1/2 — same values, since `Less`/`Equal`/`Greater` flatten to ordinals 0/1/2 via `resolve_tag_index`). So `consume_order_to_trinary` would need to (a) NOT load8u, and (b) NOT camp_drop. The scratch-local layout (`6=order_ptr, 7=ptr, 8=tag`) would drop a slot.
- `emit_order_cell_from_trinary` (`:48-96`): constructs an Order heap cell from a trinary. Under immediate Order the "construction" is a no-op (the trinary IS the value) — the caller already has the immediate on the stack.
- `container_compare_for_*` (`:122-126, 144-146, 157-159, 199-203, 217-219, 229-231, 274-294, 343-348, 452`): all read `load8u CAMP_TAG_TAG_OFFSET` off Order cells returned by element-compare callbacks. Each would become a direct use of the immediate.
- **Owner Q7 decision needed:** these are camp-ty9s Design B sites. `camp-ty9s` is in_progress in another worktree. Per the bean, 9xi6 must land so Design B's adaptation is *mechanical* afterward. That means 9xi6 should NOT touch `container_hash.odin` (leave Design B emitting load8u+drop on the Order ptr), and the moment `Order` becomes immediate, Design B's `consume_order_to_trinary` will MISBEHAVE (load8u off an immediate i32 ordinal interpreted as a pointer = trap). So either:
  - (a) 9xi6 lands the representation but keeps `Order` boxed for now (gated by a flag Design B can opt out of) — defeats the purpose; or
  - (b) 9xi6 and Design B land together (violates "don't touch the other worktree"); or
  - (c) 9xi6 lands the immediate path AND adapts `container_hash.odin` to read immediates (i.e. sneak the mechanical Design B change into 9xi6 since the file lives in THIS worktree, not the ty9s one — `container_hash.odin` is in `src/codegen/`, not blocked).
  - I'll recommend (c) and ask owner to confirm the boundary, since `container_hash.odin` is local to this worktree and the change is mechanical. This is the one place where 9xi6 cannot be purely representation-only.

### K. Bool prior art — end-to-end (Q8)

- Bool's immediate path uses a **parallel IR node**, NOT a generalized tag-union path:
  - Represent: `lower_type` :26-27 (`Inferred_Primitive{primitive_name="Bool"}` → `.I32, is_heap=false`).
  - Construct: `TExpr_Bool` → `make_ir_lit_bool` → `IR_Literal_Bool{value:bool}` (`ir.odin:190-194`). Codegen `emit_expr.odin:407-412` → `i32.const 1`/`0`.
  - Pattern: `IR_Pat_Bool{value:bool}` (`ir.odin:305-307`), distinct from `IR_Pat_Tag`.
  - Match: `Match_Kind.Bool` dispatch (`emit_expr.odin:1986-2046`) → `i32.eq` on `scrutinee_local` directly (no load).
- **Bool is NOT "a no-payload tag union" in the IR** — it never touches `Inferred_Tag_Union_Row` or `IR_Construct_Tag`. Unifying them (Q8 option "delete the special case, make Bool a regular no-payload closed tag union") is a LARGE change: it would re-route `True`/`False` through `TExpr_Tag`/`IR_Construct_Tag`, retire `IR_Literal_Bool`/`IR_Pat_Bool`/`Match_Kind.Bool`, and touch every `Bool` reference in `check_expr.odin` (conditions, `==`, `<`, `and`/`or`), `make_ir_lit_bool`'s ~25 call sites, and the `IR_Pat_Bool` match arms. High blast radius. The conservative option (keep Bool special, add a parallel immediate path for no-payload closed tag unions) duplicates mechanism but is far smaller and lower-risk. I'll recommend keeping Bool special in Q8.

### L. Other facts discovered

- `docs/semantics-spec.md` does NOT exist (`docs/` has only `language-spec.md`, `diagnostics-catalog.md`, `stdlib-design-notes.md`, plus `docs/ideas/`). The bean's Phase 3 step "update `docs/semantics-spec.md`" cannot be literal — the representation rule should instead go into `docs/stdlib-design-notes.md` (which discusses `Order`/`Ord` at length) or a new short spec. Will ask owner in Q.
- `stdlib/Ord.camp:4` declares `@Order : pub [Less | Equal | Greater]` — a closed, all-no-payload, newtype-wrapped tag union. **This is the canonical 9xi6 target.** `Bool.compare` (`Bool.camp:74-78`) and `Char.compare` (`Char.camp:7`) are *Camp source* that constructs `Less`/`Equal`/`Greater` — with immediate `Order` these stop allocating too (free win).
- **Prelude naming wart (pre-existing, NOT 9xi6's to fix, flag only):** prelude registers a tag union named `Ordering` (`prelude.odin:47, 85`) but `Ord.compare`'s return type is `Order` (`prelude.odin:516`, `prelude_resolve_type_ref(store, "Order", ...)`). `Order` only resolves if `stdlib/Ord.camp` is loaded (it binds `@Order`). The prelude's own `Ordering` is effectively dead. The bean's title says `Order`; the live type is `@Order`; the prelude alias is `Ordering`. Naming is consistent *at the stdlib layer* (`Order` everywhere) — the prelude `Ordering` is just an unused registration. No action for 9xi6.
- Kitchen-sink (`tests/e2e/language/kitchen-sink/Main.camp`) does NOT exercise `Order`/`Less`/`Equal`/`Greater` in live code (only in comments at :240, :251-252). 9xi6 Phase 3 step 7 (add a user-defined no-payload enum to kitchen-sink) is warranted. `Color = [Red | Green | Blue]` is already sketched in kitchen-sink *comments* (:248-255, :266-274) — making one live is natural.

### M. Exact set of things that must change to make a NO-PAYLOAD CLOSED tag union immediate

1. **Detection + marking.** Add a `closed: bool` (or `is_immediate: bool` computed from closed+all-no-payload) to `Inferred_Tag_Union_Row` (`types.odin:95-98`), set it at `convert_type_to_var_val` (`typecheck.odin:1247-1268`) for syntactic `[A | B | ...]` declarations and at prelude synthesis (`typecheck.odin:1029-1057`) for `Ordering`; carry through `instantiate_rec`/`deep_clone_type`/`unify_tag_union_rows` (the clone sites at `typecheck.odin:1410-1427, 1556-1580` and `unify.odin:1423-1427, 1575-1580`). (See Q1 — owner may prefer a post-typecheck analysis pass instead of a row field.)
2. **Representation.** `lower_type.odin:39-40`: branch on `closed && all_payloads_empty` → `.I32, is_heap=false`; else today's `.I32, is_heap=true`.
3. **Codegen construct.** `emit_expr.odin:2269-2367`: gate on `!e.type.is_heap` → emit `Wasm_I32_Const{e.tag_index}` only.
4. **Codegen match.** `codegen.odin:50-75` + `emit_expr.odin:1772-1985`: `.Tag_Union` path sub-branches on scrutinee `is_heap`; immediate case uses `i32.eq`/`br_table` on the scalar, skips load8u and payload-load loop.
5. **`ir_expr_is_heap` fix.** `src/ir/wasm_type.odin:86-91`: consult `e.type.is_heap` for `IR_Construct_Tag`/`Record`/`Tuple`/`Expr_Nominal_Construct` instead of hardcoding `true`. (Section I hazard — must land with #3/#4 or containers trap.)
6. **Monomorphization.** `src/mono/mono.odin:925-936` `substitute_ir_type`: handle `Inferred_Tag_Union_Row` (and respect the new `closed`/no-payload flag) so a generic monomorphized to `Order` gets `is_heap=false` (and a payloaded union gets `is_heap=true`). (Section D — latent bug; Q5 scope decision.)
7. **`container_hash.odin` adaptation.** `consume_order_to_trinary` + `emit_order_cell_from_trinary` + the 9 `load8u` compare sites read/write immediates instead of cells. (Section J — Q7 boundary decision.)
8. **Spec.** Record the representation rule in `docs/stdlib-design-notes.md` (or a new short spec; `docs/semantics-spec.md` does not exist). (Section L.) Syntax recipe needs no change — this is representation only.
9. **Kitchen-sink + tests.** Add a live `[Red | Green | Blue]`-style enum to kitchen-sink; unit tests for detection (#1), immediate codegen (#3), is_heap gating (#5); e2e for construct/match correctness and `List.compare` over `Order` not trapping.

---

## Phase 2 Design — settled with owner (2026-06-21)

All 9 design questions grilled via `question` tool. Owner signoff recorded below.

- **Q1 Detection rule — ROW FLAG `closed`, set at typecheck.** Add `closed: bool` to `Inferred_Tag_Union_Row` (matching `Inferred_Record_Row.closed` at types.odin:92). Set `closed=true` ONLY at `convert_type_to_var_val` (typecheck.odin:1247-1268, syntactic `[A | B | ...]`) and prelude synthesis (typecheck.odin:1029-1057, `Ordering`). Carry through clone sites: `instantiate_rec` (1410-1427), deep_clone (1556-1580), `unify_tag_union_rows` (unify.odin:1423-1427? — verify: the unify clone sites build new rows, set `closed` from inputs). sites that build a one-arm open row (`typecheck_tag` check_expr.odin:441, `typecheck_list_literal` :704, match patterns check_control.odin:115) keep `closed=false`. At `lower_type`, compute all-payloads-empty by scanning `tag_entries[i].payload` AND require `closed`.
- **Q2 Representation — i32 variant ordinal only.** Reuse `resolve_tag_index` (lower.odin:2768) output as the immediate value (0/1/2 for Less/Equal/Greater). No type-id, no sentinel. Same shape as Bool's 0/1.
- **Q3 Construction — derive from `e.type.is_heap`.** No new IR field, no new node. `emit_expr.odin:2269-2367` gates on `!e.type.is_heap` → emits `Wasm_I32_Const{e.tag_index}`. Zero clone-site changes (all IR_Construct_Tag clones already copy `type`). REQUIRES the §I `ir_expr_is_heap` fix.
- **Q4 Matching — sub-branch `.Tag_Union` on scrutinee is_heap.** No new `Match_Kind`. In the `.Tag_Union` emit path (emit_expr.odin:1772-1985), check the scrutinee's is_heap (via `ir_expr_is_heap` after the §I fix); immediate case uses `scrutinee_local` directly with `i32.eq`/`br_table` on `p.tag_index`, skips `load8u` and the payload-load loop (no-op anyway for no-payload). Mirrors `IR_Pat_Bool` dispatch (emit_expr.odin:2000-2003).
- **Q5 Polymorphism — fix `substitute_ir_type` (src/mono/mono.odin:925-936) AS PART OF 9xi6.** Handle `Inferred_Tag_Union_Row` in the concrete-type derivation: when a generic param `T` monomorphizes to a concrete tag union, re-derive `wasm_type`/`is_heap` by calling `lower_type` on the concrete `type_var` (so it respects the new `closed`+no-payload flag). This ALSO closes the latent bug: payloaded unions monomorphized into generics currently get `is_heap=false` (Phase1 §D). Fix for BOTH no-payload AND payloaded cases folds into 9xi6 (owner chose option 1, the full fix, over option 3 the no-payload-only middle ground). The early-return at mono.odin:915-917 needs review — may need to re-derive even when type_id is already an Inferred_Type, if is_heap wasn't set correctly at first lowering.
- **Q6 RC/reuse — NO CHANGE; add RC-skip unit test.** Phase1 §E/§F confirmed `is_heap` gates everything and reuse can't target immediate slots. Add `src/test_rc.odin` (or extend existing) test: build a function that drops a no-payload closed union, assert zero `IR_Drop` nodes emitted for it (mirrors Bool's path).
- **Q7 Container runtime — 9xi6 ADAPTS `container_hash.odin` ATOMICALLY.** `container_hash.odin` lives in `src/codegen/` in THIS worktree — not blocked by camp-ty9s. If 9xi6 makes @Order immediate without adapting, Design B compares trap on landing (load8u off an immediate-as-pointer). The adaptation is mechanical: `consume_order_to_trinary` (container_hash.odin:26-46) drops the `load8u`+`camp_drop` (the immediate IS the trinary); `emit_order_cell_from_trinary` (:48-96) becomes a no-op passthrough (the trinary IS the value); the 9 compare-site `load8u`s (:122,126,144,146,157,159,199,203,217,219,229,231,274,282,294,343,348,452) become direct reads of the callback result. camp-ty9s-side work (I64_Trampoline adapter, func_map bridging) stays untouched.
- **Q8 Bool migration — KEEP Bool SPECIAL; add parallel path.** Bool keeps `IR_Literal_Bool`/`IR_Pat_Bool`/`Match_Kind.Bool`/`lower_type:26-27`. No-payload closed tag unions get a parallel immediate path via the `closed` flag + `.Tag_Union` sub-branch. Two immediate mechanisms coexist; unifying is high-risk for no gain (Bool is already immediate).
- **Q9 Design C scope — REPRESENTATION ONLY.** 9xi6 delivers: representation + codegen + mono fix + container_hash adaptation + tests + spec. NOT in 9xi6: pure-Camp container generics rewrite, call_indirect/func_map deletion, I64_Trampoline removal — those are camp-ty9s Design C, blocked on camp-24mj (trait method compilation, in_progress in another worktree, off-limits).

### Phase 2 — additional scope items owner implicitly accepted by the answers
- The §I `ir_expr_is_heap` hazard fix (src/ir/wasm_type.odin:86-91 consult `e.type.is_heap` for IR_Construct_Tag/Record/Tuple/Expr_Nominal_Construct) MUST land with Q3 — it's a stated prerequisite of Q3's chosen option.
- The latent payloaded-union mono bug fix folds into 9xi6 via Q5 option 1.

### Phase 2 — deferred / out of scope (recorded as TBDs, not blocking 9xi6)
- Design C container generics rewrite (camp-ty9s territory).
- Bool unification into a regular no-payload tag union (rejected, high blast radius).
- Prelude `Ordering` vs `@Order` naming wart (pre-existing, prelude's `Ordering` registration is effectively dead; not 9xi6's to fix). **Tracked as bean `camp-7ghe`.**
- Latent `substitute_ir_type` payloaded-union bug (Phase1 §D): folded INTO 9xi6 per Q5 option 1 (both no-payload and payloaded cases fixed). **Also tracked independently as bean `camp-zmni`** so the latent bug is discoverable even if 9xi6's mono fix is later descoped.

### Phase 2 — open implementation details (to resolve during Phase 3, NOT needing owner re-grill)
- Exact unify_tag_union_rows closedness propagation rule (does unifying two closed rows stay closed? does closed + open yield open? — answer: closed && closed => closed, else open, conservatively).
- Whether `emit_order_cell_from_trinary` can be fully deleted or must remain as a no-op for call-site stability — decide at impl time.
- Whether the early-return at mono.odin:915-917 needs to re-derive is_heap even for already-Inferred_Type type_ids — investigate during impl; if the first lowering already set is_heap correctly (post-Q1), the early return is fine.

### Phase 3 — design gap surfaced & resolved (2026-06-21, owner signoff via `question`)

**Gap:** Q1's "row flag `closed` set at typecheck" is INSUFFICIENT for bare-tag
construction. `typecheck_tag` (check_expr.odin:441) builds `Blue`'s row as OPEN
and snapshots `TExpr_Tag.type_ = lower_type(tag_var)` => `is_heap=true` (boxed)
BEFORE the call site unifies the tag with the closed `Color` type. And
`unify_tag_union_rows` (unify.odin:693) does NOT merge the row vars nor
propagate `closed` from the closed side to the open side. Result: `Blue`
constructs a heap cell, but `match c: Color` reads immediate via br_table =>
trap (reproduced in tests/e2e/execution/annotated-tag-union-param). This is
exactly the "silent assumption" the task brief warned about.

**Resolution (owner chose option 1 "Propagate `closed` through unify"):**
1. Make `unify_tag_union_rows` propagate closedness: when unifying an open row A
   with a closed row B where B is all-no-payload and B's entries are a
   superset of A's (the common bare-tag-into-closed-union case), set A's
   `closed=true`. Precise rule implemented below (closed && closed => closed;
   closed-all-no-payload superset absorbs an open subset).
2. In `lower_ttag` (lower.odin:2845), re-derive `result.type` by calling
   `lower_type(env.store, e.type_.type_id)` at IR-lowering time instead of
   copying the stale `e.type_` snapshot. Post-unification the var reflects the
   propagated `closed` flag, so the construct node picks up `is_heap=false`.

This keeps Q1's chosen "row flag" answer intact — unification does the work the
flag needs. The conservative closedness rules in the "open implementation
details" note above are UPDATED: the precise propagation is "open absorbed by a
closed all-no-payload superset becomes closed; closed + closed stays closed;
everything else stays open."

---

## Phase 3 Implementation — statuses

STARTED: 2026-06-21 (after Phase 2 signoff). ALL STEPS COMPLETE. 472 unit tests + 178 e2e tests pass.

| Step | Description | Status |
|------|-------------|--------|
| 3.1 | Add `closed: bool` to `Inferred_Tag_Union_Row`, set at 9 construction sites | DONE |
| 3.2 | `lower_type`: `tag_union_is_immediate` helper, `is_heap = !tag_union_is_immediate(...)` | DONE |
| 3.3 | `emit_expr`: `IR_Construct_Tag` immediate short-circuit (`i32.const <ordinal>`) | DONE |
| 3.4 | `emit_expr`: `.Tag_Union` match `scrutinee_immediate` sub-branch (skip load8u) | DONE |
| 3.5 | `wasm_type`: split construct cases, consult `e.type.is_heap` | DONE |
| 3.6 | `substitute_ir_type`: `lower_type(env.store, concrete_var_id)` for ALL concrete types (camp-zmni) | DONE |
| 3.7 | `container_hash.odin`: `consume_order_to_trinary` + `emit_order_cell_from_trinary` + `emit_i64_trampoline_body` immediates | DONE |
| 3.8 | Spec: D31 in `docs/stdlib-design-notes.md` | DONE |
| 3.9 | Kitchen-sink: already in comments; e2e test `tag-unboxed-enum` created | DONE |
| 3.10 | Unit tests: 4 new in `test_lower_type.odin`; e2e: `tag-unboxed-enum` (178th test) | DONE |

### Additional fixes discovered during Phase 3
- **Closedness propagation**: `unify_tag_union_rows` now propagates `closed` from closed all-no-payload superset to open subset. `row_all_entries_no_payload` + `mark_tag_row_closed` helpers added.
- **`lower_ttag` re-derive**: re-derives `resolved_type` at IR-lowering time instead of using stale `e.type_`.
- **Nested tag IR_Var.type**: `expand_nested_tag_pattern` sets `IR_Var.type = lower_type(store, inner_scrutinee_type_id)`.
- **Resnapshot pass**: replaced broad `lower_type` resnapshot with targeted `resnapshot_is_heap` — only updates `is_heap` for `Inferred_Tag_Union_Row` types. The broad version caused `parallel-map` handler regression (changed `resume` continuation type from I64→Funcref, altering wasm call_indirect signatures).
- **`resnapshot_decl_types`**: uses `resnapshot_is_heap` for decl-level types too.
