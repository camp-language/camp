# Compiler Correctness: Deferred Bug Fixes Design

## Overview

This document covers the design for 8 deferred bugs discovered during a
comprehensive correctness audit of the Camp compiler. Each bug represents a
missing or broken compiler feature that is blocking correct compilation of
non-trivial programs. The bugs span six compiler phases: IR lowering,
typechecking, effect lowering, closure conversion, CPS transformation,
reference counting, and types.

All designs follow a "most correct" approach — no shortcuts, proper compiler
engineering.

---

## Bug 1 (H2): IR_Crash Node

**Current state:** `CExpr_Crash` lowers to `lower_expr(e.message, env)` — the
crash semantics are discarded. No `IR_Crash` variant exists in the IR union.

### Design

Add `IR_Crash` to the IR_Expr union:

```odin
IR_Crash :: struct {
    message: IR_Expr,
    span:    Source_Span,
}
```

**Lowering:** Lower `CExpr_Crash` to `IR_Crash{message = lower_expr(e.message, env)}`.

**Codegen:** Emit `Wasm_Unreachable` (after optionally emitting the message
expression). Add case to `emit_expr`.

**All mid-end passes:** Add traversal cases (closure_convert, effect_lower,
cps, rc) to recurse into the message expression.

**Estimated scope:** ~15 lines across 6 files.

---

## Bug 2 (C7): Non-Name Callee Lowering

**Current state:** `lower_call` checks if the callee is `CExpr_Name`; if not,
it creates a fresh dummy `Canonical_Name` and connects nothing. Higher-order
calls like `(f x) y` call non-existent functions.

### Design

Use closure records and WASM `call_indirect` — the proper fix.

**New IR node:**
```odin
IR_Closure_Call :: struct {
    callee: IR_Expr,
    args:   [dynamic]IR_Expr,
    type:   IR_Type,
    span:   Source_Span,
}
```

**Lowering:** When `CExpr_Call` has a non-name callee, lower the callee
expression normally. Create
`IR_Closure_Call{callee = lowered_callee, args = lowered_args}`.

**Closure convert:** The callee expression passes through closure conversion.
If it's a lambda, it becomes a closure record with `fn_idx` and `env_ptr`.
Add traversal case for `IR_Closure_Call`.

**Codegen:** Lower the callee (closure record), extract `fn_idx` and
`env_ptr`, push args, emit `call_indirect`. Each closed function gets an
element entry in the WASM table. Add `Wasm_Call_Indirect` instruction.

**All mid-end passes:** Add passthrough traversal for `IR_Closure_Call`.

**Estimated scope:** ~30 lines in `lower.odin`, ~10 lines in
`closure_convert.odin`, ~15 lines for struct, ~20 lines in `rc.odin`, ~35
lines codegen (table + call_indirect), ~1 line in `wasm.odin`.

---

## Bug 3 (M4): Missing Handler Evidence Parameter

**Current state** (`effect_lower.odin:131-163`): When `IR_Perform` finds no
matching handler on the evidence stack (`ev_var == NO_NAME`), the evidence
argument is silently omitted. The handler function expects an evidence
parameter but the call site doesn't provide one — calling convention mismatch.

### Design

When `ev_var == NO_NAME`, emit a diagnostic and lower the perform to
`IR_Literal_Int{0}` with the perform's type. The evidence argument should
always be present for handled performs. Unhandled performs are caught by the
typechecker before effect_lower runs, so this case indicates a compiler bug.

**Estimated scope:** ~5 lines in `effect_lower.odin`. Requires adding
`collector` to `Effect_Lower_Env`.

---

## Bug 4 (C5): Match Pattern Typechecking

**Current state** (`typecheck.odin:485-506`): `typecheck_match` typechecks
the scrutinee and arm bodies but never processes patterns. Pattern variables
are never bound into the environment. Pattern structure is never checked
against the scrutinee type.

### Design

Add `typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID,
env: ^Type_Env, store: ^Type_Store) -> Type_Result`.

**Pattern dispatch:**

| Pattern kind | Action |
|---|---|
| `CPat_Var(name)` | `env.bindings[name] = scrutinee_var`; return scrutinee |
| `CPat_Wildcard` | Return scrutinee (matches everything; covers all tags for exhaustiveness) |
| `CPat_Bool(v)` | Unify scrutinee with `Bool` |
| `CPat_Int(v)` | Unify scrutinee with `I64` |
| `CPat_String(v)` | Unify scrutinee with `String` |
| `CPat_Tag(name, payloads)` | Create tag union row `{Tag_Entry{name, payload_vars}, rest}`; unify scrutinee with it; recurse into payload patterns |
| `CPat_Record(fields, is_open)` | Create record row `{field_entries, rest}`; unify scrutinee with it; recurse into field patterns |
| `CPat_Or(patterns)` | Typecheck each sub-pattern against the same scrutinee_var |

**Modifications to `typecheck_match`:**
For each arm:
1. Save current `env.bindings` state
2. Call `typecheck_pattern(arm.pattern, scrutinee_result.var_id, arm_env, store)`
3. Typecheck the arm body with `arm_env`
4. Restore `env.bindings` (patterns are scoped per arm)

**Exhaustiveness checking:**
After all arms are typechecked, resolve the scrutinee type:
- If it's a closed tag union (`tag_entries` with no open rest):
  - Collect covered tags from arm patterns
  - `CPat_Wildcard` and `CPat_Or` containing `CPat_Wildcard` saturate coverage
  - Any uncovered tag produces a "non-exhaustive match" diagnostic
  - Include hints listing missing tags
- If the scrutinee type is not a closed tag union, skip exhaustiveness

**Estimated scope:** ~90 lines in `typecheck.odin`.

---

## Bug 5 (C8): Closure Body Nil

**Current state** (`closure_convert.odin:241`): The closure conversion creates
an `IR_Decl_Fn` with `body = IR_Expr(nil)`. The original lambda body is never
transferred. `lower_lambda:403` sets `env = nil`, so `cc_free_vars` returns
zero free variables. The fn_idx and env_ptr in the closure record are literal 0.

### Design

**Step 1 — Add `body` field to `IR_Closure`:**
```odin
IR_Closure :: struct {
    env:     IR_Expr,
    body:    IR_Expr,    // NEW: the lambda body
    type:    IR_Type,
    span:    Source_Span,
}
```
Update all mid-end traversals to recurse into `.body`.

**Step 2 — Fix `lower_lambda`:**
Store the lambda body in the `IR_Closure.body` field. The `env` field
remains nil (free variables are computed by closure_convert from the body).

**Step 3 — Transfer body in closure_convert:**
```odin
case ^IR_Closure:
    // ... compute free vars from e.body ...
    closed_fn.body = cc_convert_expr(e.body, env)
```

**Step 4 — Track function index:**
After adding `closed_fn` to `env.module.decls`, store its index in a
`map[Intern_ID]int` mapping closure name → function index. Use this when
generating the closure record's `fn_idx` literal instead of hardcoding 0.

**Step 5 — Capture free variables as env:**
Generate env allocation and field stores for each free variable. The env
becomes `let _cenv = alloc(N); _cenv[0] = free_var_1; ...`. The env_ptr in
the closure record references `_cenv`.

**Estimated scope:** ~10 lines in `ir.odin`, ~5 lines in `lower.odin`, ~45
lines in `closure_convert.odin`, ~30 lines across mid-end traversal updates.

---

## Bug 6 (C9): Perceus RC — Var Replaced by Dup/Drop

**Current state** (`rc.odin:124-139`): Every `IR_Var` is replaced by
`IR_Dup` (if uses remain) or `IR_Drop` (if last use). The original `IR_Var`
is never preserved. No variable is ever actually used.

### Design

Rewrite `IR_Let` nodes rather than `IR_Var` nodes. The `IR_Var` nodes stay
unchanged.

**Correct Perceus algorithm for `let x = value in body`:**

1. `rc_collect_uses` counts uses of `x` in `body`
2. For uses = 0: `drop(x); body` (x is never read)
3. For uses = 1: `body` unchanged (single use, unique reference)
4. For uses >= 2: wrap body with `dup(x)` before non-last uses and `drop(x)` at scope end

**Implementation in `rc_insert_expr_inner` for `IR_Let`:**

```odin
case ^IR_Let:
    let_uses := count_uses_in_body(e.binding, e.body)
    
    if let_uses == 0 {
        // Never used: drop immediately
        drop := new(IR_Drop){value = e.binding}
        return IR_Expr(IR_Block{
            statements = [IR_Expr(drop), e.body],
            type = e.type, span = e.span,
        })
    }
    
    // Process the body, inserting dup before each non-last Var
    transformed_body := insert_dups_and_drop(e.body, e.binding, let_uses)
    
    new_let := new(IR_Let){
        binding = e.binding,
        type = e.type,
        value = rc_insert_expr_inner(e.value, remaining, interner),
        body = transformed_body,
    }
    return IR_Expr(new_let)
```

**Helper `insert_dups_and_drop`:** traverses the expression tree. When it
finds `IR_Var{name == binding}`, if not the last use, wraps it in
`Block{[Dup(binding), Var(binding)]}`. At the end of the body, appends
`Drop(binding)`.

**Estimated scope:** ~50 lines rewriting the `IR_Let` case in
`rc_insert_expr_inner`, ~40 lines for `insert_dups_and_drop`.

---

## Bug 7 (M5): CPS Transformation — No Continuations Generated

**Current state** (`cps.odin`): The CPS transform threads `k_name` through
the tree but never creates new continuation functions. Only `IR_Return`
becomes a tail-call.

### Design

Generate continuation functions for each effectful sub-expression.

**Key CPS rule — effectful calls:**
```
Before: let y = f(x) in g(y + 1)    (where f is effectful)
After:  f(x, fun(y) { g(y + 1) })
```

**Implementation for `IR_Let` with effectful value:**
1. Create a fresh continuation name `kc`
2. Compute the continuation body: `cps_transform_expr(e.body, kc, env)`
3. If the value is an `IR_Call` to an effectful function:
   - Add `kc` as an extra parameter to the call's `args`
   - Create a continuation function `IR_Decl_Fn{name=kc, params=[y: result_type], body=cont_body}`
   - Add it to `env.module.decls`
   - Return the transformed call
4. If the value is pure, recurse normally

**Implementation for `IR_If`:**
Both branches must call the same continuation:
```
Before: if cond then a else b; k(result)
After:  if cond then { a; k(a_result) } else { b; k(b_result) }
```

**When to generate continuations:**
Only for effectful sub-expressions. Determine effectfulness from the function
type's `effect_row` field (non-void = effectful).

**Estimated scope:** ~60 lines in `cps.odin`.

---

## Bug 8 (M9): Generalization at Level — Unsound Child Levels

**Current state** (`types.odin:132-138`): `generalize_at_level` marks all
variables at level L as `LEVEL_GENERIC` without checking that children of
`Inferred_Type` structures are also at level <= L.

### Design

Add a recursive check before generalizing:

```
generalize_at_level(store, level):
    for each var in store.vars:
        if var.level == level and var.level != LEVEL_GENERIC:
            if all_children_at_or_below_level(store, var.link, level):
                var.level = LEVEL_GENERIC

all_children_at_or_below_level(store, link, max_level):
    switch link:
        Type_Unlinked: return true
        Inferred_Type:
            extract all child Type_Var_IDs from the inferred type
            for each child_id:
                child = get_var(store, child_id)
                if child.level > max_level: return false
            return true
        Type_Var_ID: (delegated variant)
            child = get_var(store, link)
            return child.level <= max_level
```

**Child extraction per Inferred_Tag:**
| Tag | Children to check |
|---|---|
| .Function | param_ids[], return_id, effect_id |
| .Record_Row | record_fields[].var, record_rest |
| .Tag_Union_Row | tag_entries[].payload[], rest_id |
| .Effect_Row | effect_names (names, not vars), rest_id |

**Estimated scope:** ~45 lines in `types.odin`.

---

## Implementation Order

1. **H2 (IR_Crash)** — standalone, simplest
2. **M4 (handler evidence)** — standalone, small
3. **M9 (generalization levels)** — standalone, types only
4. **C5 (match patterns + exhaustiveness)** — standalone, typecheck only
5. **C8 (closure body)** — adds IR field, affects lower + closure_convert
6. **C7 (non-name callee)** — depends on C8 for closure record structure
7. **C9 (Perceus RC)** — affects rc code; benefits from C8's closure IR
8. **M5 (CPS continuations)** — affects cps; last because it's the most
   complex; builds on correct closures and RC

---

## Testing Strategy

Each fix includes:
1. Unit tests in the existing test file for that compiler phase
2. One or more e2e snapshot tests exercising the fixed behavior
3. All 117 existing unit tests must continue to pass
4. All 101 existing e2e snapshot tests must continue to pass
