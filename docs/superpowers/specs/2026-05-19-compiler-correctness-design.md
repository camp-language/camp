# Compiler Correctness: Deferred Bug Fixes Design

## Overview

This document covers the design for 8 deferred bugs discovered during a
comprehensive correctness audit of the Camp compiler. Each bug represents a
missing or broken compiler feature that is blocking correct compilation of
non-trivial programs. The bugs span five compiler phases: IR lowering,
typechecking, effect lowering, closure conversion, CPS transformation, and
reference counting.

---

## Bug 1 (H2): IR_Crash Node

**Current state:** `CExpr_Crash` lowers to `lower_expr(e.message, env)` — the
crash semantics are discarded. No `IR_Crash` variant exists in the IR union.

### Design

Add a minimal `IR_Crash` variant to `IR_Expr` union and `ir.odin` structs:

```odin
IR_Crash :: struct {
    message: IR_Expr,  // the message expression (string)
    span:    Source_Span,
}
```

**Lowering** (`lower.odin`):
Lower `CExpr_Crash` to `IR_Crash{message = lower_expr(e.message, env)}`.

**Codegen** (`codegen.odin`):
Add `case ^IR_Crash: emit_instruction(Wasm_Unreachable{}, buf)` to
`emit_expr`. If we later want the message to appear before crashing, emit the
message expression first, then unreachable.

**RC** (`rc.odin`): Add case to `rc_collect_uses` and `rc_insert_expr_inner`
to traverse `e.message`.

**Closure convert / CPS / Effect lower**: Add pass-through cases.

**Estimated scope:** ~15 lines across 4 files.

---

## Bug 2 (C7): Non-Name Callee Lowering

**Current state:** `lower_call` checks if the callee is `CExpr_Name`; if not,
it creates a fresh dummy `Canonical_Name` and connects nothing. Higher-order
calls like `(f x) y` call non-existent functions.

### Design

**Option A — Diagnostic and stub:**
Emit a compiler diagnostic ("higher-order calls are not yet supported") and
lower the call to an unreachable. This is correct for error reporting but
doesn't implement the feature.

**Option B — Function references:**
Add `IR_Funcref` to the IR union representing a closable function reference.
Lower the callee expression normally, then use `call_indirect` in WASM
codegen. This requires:
- A `Funcref` IR type variant (exists as `IR_Wasm_Type.Funcref`)
- A WASM table for indirect calls
- `call_indirect` instruction support

**Option C — Lambda lifting (recommended):**
For `lam = (x) -> x + 1; lam(5)`, lift the lambda to a named top-level
function during lowering. `lam(5)` becomes a direct call to the lifted
function. This avoids function pointers entirely for statically-known calls.

For unknown callees (function parameters), combine with Option B.

**Socratic questions:**
1. What Camp programs require higher-order calls today?
2. Is it better to error clearly or silently produce wrong code?
3. Should we implement this incrementally (Option A now, Option C later)?

**Recommendation:** Option A as immediate fix (clear error instead of silent
wrong behavior). Option C deferred as a full feature.

**Estimated scope (Option A):** ~8 lines in `lower.odin` (add diagnostic
collector to `Lower_Env` and emit diagnostic).

---

## Bug 3 (M4): Missing Handler Evidence Parameter

**Current state** (`effect_lower.odin:131-163`): When `IR_Perform` finds no
matching handler on the evidence stack (`ev_var == NO_NAME`), the evidence
argument is simply not prepended to the call arguments. The handler function
expects an evidence parameter but the call site doesn't provide one — causing
a calling convention mismatch.

### Design

When `ev_var == NO_NAME`, emit a diagnostic and skip the perform (lower to
`IR_Literal_Int{0}` or unreachable). The evidence argument should always be
present for handled performs; for unhandled performs, the typechecker should
have caught this before effect_lower runs.

More robustly: add an evidence parameter to the handler function call at the
perform site unconditionally. When no evidence exists, pass a null/zero
literal with a diagnostic.

**Estimated scope:** ~5 lines in `effect_lower.odin`.

---

## Bug 4 (C5): Match Pattern Typechecking

**Current state** (`typecheck.odin:485-506`): `typecheck_match` typechecks
the scrutinee and arm bodies but never processes patterns. Pattern variables
are never bound into the environment, so arm bodies can't use bindings.
Pattern structure is never checked against the scrutinee type.

### Design

Add `typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Type_Result`.

This function dispatches on pattern kind and:

```
CPat_Var(name):
    env.bindings[name] = scrutinee_var
    return {var_id = scrutinee_var, effects = fresh_effect_row}

CPat_Wildcard:
    return {var_id = scrutinee_var, effects = fresh_effect_row}

CPat_Bool(value):
    bool_var = make_primitive_type("Bool")
    unify(store, scrutinee_var, bool_var)
    return {var_id = bool_var, effects = fresh_effect_row}

CPat_Int(value):
    int_var = make_primitive_type("I64")
    unify(store, scrutinee_var, int_var)
    return {var_id = int_var, effects = fresh_effect_row}

CPat_Tag(name, payload_patterns):
    // Create a tag union type constraining the scrutinee
    payload_vars = [fresh_value_var() for each payload pattern]
    for each payload_pattern, payload_var:
        typecheck_pattern(payload_pattern, payload_var, env, store)
    rest_var = fresh_value_var()
    tag_var = fresh_value_var()
    link(tag_var, Tag_Union_Row{[Tag_Entry{name, payload_vars}], rest_var})
    unify(store, scrutinee_var, tag_var)
    return tag_var

CPat_Record(field_patterns, is_open):
    // Create a record row type constraining the scrutinee
    field_entries = [Field_Entry{field.name, fresh_value_var()} for each field]
    for each field pattern:
        typecheck_pattern(field.pattern, field_entries[i].var, env, store)
    rest = fresh_record_row()
    rec_var = fresh_value_var()
    link(rec_var, Record_Row{field_entries, rest})
    unify(store, scrutinee_var, rec_var)
    return rec_var
```

**Modifications to `typecheck_match`:**
For each arm:
1. Save the current `env.bindings`
2. Call `typecheck_pattern(arm.pattern, scrutinee_result.var_id, arm_env, store)`
3. The pattern typechecking adds bindings to `arm_env.bindings`
4. Typecheck the arm body with `arm_env`
5. Restore `env.bindings` (patterns are scoped to their arm)

**Estimated scope:** ~80 lines in `typecheck.odin`.

---

## Bug 5 (C8): Closure Body Nil

**Current state** (`closure_convert.odin:241`): The closure conversion creates
an `IR_Decl_Fn` with `body = IR_Expr(nil)`. The original lambda body is not
transferred. Additionally, `e.env` is always nil (set in `lower_lambda:403`),
so `cc_free_vars` returns zero free variables. The fn_idx and env_ptr in the
closure record are literal 0.

### Design

**Step 1 — Transfer the body:**
The `IR_Closure` node currently has `env: IR_Expr` (the body) and `type:
IR_Type`. The closure conversion must:
1. Extract the lambda body from `e.env` (currently nil — see Step 2)
2. Set `closed_fn.body = cc_convert_expr(extracted_body, env)`

**Step 2 — Fix `lower_lambda` to preserve the body:**
In `lower.odin`, `lower_lambda` sets `env = nil` and `body = the_lambda_body`.
We need to change this so the IR_Closure carries the lambda body. Two options:

*Option A — Dual-purpose `env` field:*
Change `lower_lambda` to store the body in the `env` field:
```odin
IR_Closure{env = lower_expr(lambda_body), type = ...}
```
Then in closure_convert, extract it: `closed_fn.body = cc_convert_expr(e.env, env)`.

*Option B — Add a `body` field to IR_Closure:*
```odin
IR_Closure :: struct {
    fn_idx: IR_Expr,
    env_ptr: IR_Expr,
    body:    IR_Expr,  // the lambda body
    type:    IR_Type,
    span:    Source_Span,
}
```
This is cleaner but requires adding the field to the IR struct and updating
all traversals (collect_locals, cc_free_vars, rc_collect_uses, etc.).

**Recommendation:** Option B. We're fixing closures properly, so we should
have the right data structures.

**Step 3 — Track function index:**
The `fn_idx_lit` is hardcoded to 0. After creating `closed_fn`, its index in
`env.module.decls` is known. Store this in a map from closure name to index,
and use it when generating the closure record.

Alternatively: store the name and let a later pass (codegen) resolve it.

**Step 4 — Handle free variables:**
The `cc_free_vars` function correctly finds free variables. The env parameter
(`_cenv`) is added to params. The env is captured as:
```odin
let _cenv = alloc(sizeof(free_vars))
_cenv[0] = free_var_1
_cenv[1] = free_var_2
...
```

**Step 5 — Closure calling convention:**
When a closure is called, extract `fn_idx` and `env_ptr`, then do an indirect
call with the env as the first argument:
```odin
// At the call site:
let fn_idx = closure_record.fn_idx
let env_ptr = closure_record.env_ptr
call_indirect(fn_idx, env_ptr, arg1, arg2, ...)
```

This requires WASM tables and `call_indirect` — significant codegen work
deferred to a future task.

**Minimum viable fix (recommended for now):**
1. Add `body` field to `IR_Closure`
2. Store the lambda body in `lower_lambda`
3. In closure_convert, set `closed_fn.body` from `e.body`
4. Leave fn_idx/env_ptr as literal 0 (closures still don't "capture" but
   at least the closed function has the right body)
5. Codegen for closure calls uses direct call (only works for non-capturing)

**Estimated scope:** ~50 lines across `ir.odin`, `lower.odin`,
`closure_convert.odin`.

---

## Bug 6 (C9): Perceus RC — Var Replaced by Dup/Drop

**Current state** (`rc.odin:124-139`): Every `IR_Var` is replaced by
`IR_Dup` (if uses remain > 0) or `IR_Drop` (if last use). The original
`IR_Var` is never preserved. Result: no variable is ever actually *used* —
it's only duplicated or dropped.

### Design

The correct Perceus semantics for a variable used N times:

| Use # | IR Node | Meaning |
|-------|---------|---------|
| 1st | `IR_Var(name)` | Read the variable (first use = borrowed, not consumed) |
| 2nd..N-1th | `Dup(Var(name))` | Increment refcount, read the variable |
| Nth (last) | `Var(name)` | Read the variable (last use = consumed, refcount stays) |

Wait — that's wrong. Let me reconsider the Perceus paper.

**Correct Perceus semantics:**

Perceus uses reference counting with guaranteed destructive-read semantics. A
variable binding is "consumed" at its last use. For a variable used N times:

| Use # | Action |
|-------|--------|
| 1 | Read normally (borrowed) |
| 2..N | Depends on whether context needs ownership |
| Last | Read normally (consumed), no drop needed |

Actually, the Koka/Perceus paper describes it differently. The key insight:

- **Borrowed (`Var`):** The use doesn't take ownership. Refcount unchanged.
- **Shared (`Dup`):** Increments refcount, returns a shared reference.
- **Unique (last use):** Doesn't change refcount, passes ownership.

For a variable used N times in sequence:
1. Uses 1..N-1: Share (`Dup`) — increment refcount, return copy
2. Use N (last): Consume (just `Var`) — pass ownership, decrement happens
   when the binding goes out of scope (via `Drop`)

But `Drop` is handled separately — every `let` binding gets a deferred drop.

What the current code does wrong:
1. It replaces EVERY `Var` with `Dup` or `Drop` — should KEEP the `Var` and
   ADD `Dup` before it (not replace it)
2. It doesn't handle ordering — `Dup` should come BEFORE the use
3. The `Drop` is inserted at the wrong place — it should be at the end of
   the binding's scope, not at the use site

**Correct algorithm:**

```
For each let binding x = expr in body:
    uses = count uses of x in body
    if uses == 0:
        // x is never used, drop the expr result immediately
        replace with: { drop x0; body }
        // where x0 is a temp holding expr's result
    
    elif uses == 1:
        // single use, pass unique reference (no dup needed)
        // let x = expr in body[x]
        // unchanged — the single Var use is correct
    
    else: // uses >= 2
        // multiple uses, dup before each use except the last
        // let x = expr in body[dup(x), dup(x), ..., x]
        for each use of x except the last:
            insert Dup before the Var
```

**Implementation approach:**

Change `rc_insert_expr_inner` for `IR_Var`:
```odin
case ^IR_Var:
    count := remaining^[e.name]
    if count <= 0 { return expr }  // shouldn't happen
    remaining^[e.name] = count - 1
    
    if count == 1:
        // Last use — keep the Var, add Drop after this scope
        return expr  // the Var stays as-is
    
    else:
        // Non-last use — prepend Dup
        dup := new(IR_Dup)
        dup^ = IR_Dup{value = e.name, span = e.span}
        
        block := new(IR_Block)
        block^ = IR_Block{
            statements = [IR_Expr(dup), expr],
            type = e.type,
            span = e.span,
        }
        return IR_Expr(block)
```

Wait — the above changes `IR_Var` (which is just a leaf expression) into a
block expression containing `[Dup, Var]`. This changes the semantic meaning
of the expression tree and would break call argument lists, if conditions,
etc. A `Dup` + `Var` inside a block changes the value on the stack.

**Better approach — rewrite the LET node instead:**

Don't touch `IR_Var` at all. Instead, rewrite `IR_Let` nodes:

```
For a let x = value in body:
    1. Count uses of x in body
    2. If uses > 1, add Dup calls in body
    3. Add Drop at the end of x's scope
```

Koka's approach wraps the let-body with:
```
let x = value in
    dup(x);  // if needed
    ... body with Var(x) references unchanged ...
    drop(x)  // at scope end
```

The `IR_Block` already provides this framing. Rewrite:
```
let x = value in body
```
becomes:
```
let x = value in
    { dup(x); transform(body); drop(x) }
```

**Estimated scope:** ~30 lines rewriting `IR_Let` handling in
`rc_insert_expr_inner`, ~15 lines to handle final drop insertion.

---

## Bug 7 (M5): CPS Transformation — No Continuations Generated

**Current state** (`cps.odin`): The CPS transform threads `k_name` through
the tree but never creates new continuation functions for sub-expressions.
`IR_Return` becomes `IR_Tail_Call{k, val}`, but `IR_Call`, `IR_BinOp`,
`IR_If` just recursively transform sub-expressions without introducing
continuation-passing.

### Design

**What true CPS does for effectful functions:**

An effectful function like:
```
f(x) = let y = print(x) in g(y + 1)
```

In CPS, every effectful sub-expression gets its own continuation:

```
f(x, k) =
    let k1(y) = let r = y + 1 in g(r, k) in
    print(x, k1)
```

Each step after an effectful call becomes a new top-level function.

**Minimal working CPS (effects → tail calls only):**

The current approach — converting returns to tail-calls of the effect
continuation — is actually sufficient for basic effect handling. The missing
piece is generating continuation functions for:
1. Sub-calls: `let y = f(x) in body` → `f(x, fun(y) { body })`
2. If branches: both branches must call the same continuation
3. Binary ops with effectful operands

Step-by-step algorithm:

```
cps_transform_expr(expr, k_name, env):
    switch expr:
        IR_Return{value}:
            // Tail-call continuation with the value
            return IR_Tail_Call{k, [value]}
        
        IR_Call{callee, args}:
            if callee is effectful:
                // Create a new continuation for the call
                new_k = fresh("kc")
                let_name = fresh("_r")
                cont_body = cps_transform_expr(body_using_result, k_name, env)
                cont_fn = IR_Decl_Fn{name=new_k, body=cont_body, params=[let_name]}
                add cont_fn to module
                
                // Transform the call to pass new continuation
                return IR_Tail_Call{callee, args=[...args, new_k]}
            else:
                return IR_Call{callee, cps_transform_args(args)}
        
        IR_If{cond, then, else}:
            return IR_If{
                cond = cps_transform_expr(cond, k_name, env),
                then = cps_transform_expr(then, k_name, env),
                else = cps_transform_expr(else, k_name, env),
            }
        
        IR_Let{binding, value, body}:
            return IR_Let{
                binding = binding,
                value = cps_transform_expr(value, k_name, env),
                body = cps_transform_expr(body, k_name, env),
            }
```

**When to create continuations:**

Only create continuations for effectful sub-expressions. Pure expressions
(arithmetic, constructor, field access) can stay direct-style. The
`effect_row` field on function types tells us whether a call is effectful.

**Socratic questions:**
1. Do we need true CPS, or is tail-call conversion sufficient?
2. What Camp programs today exercise the effect system?
3. How does Koka's selective CPS work? (Only effectful parts get CPS)

**Recommendation:** The current "mark tail-calls" approach works for the
single-function case. For multi-function effects with resumes, we need
continuation generation. Implement the `IR_Call` case (most common) and
defer `IR_If`/`IR_BinOp` continuation generation until needed.

**Estimated scope:** ~40 lines modifying `cps_transform_expr`, ~15 lines for
continuation function generation.

---

## Bug 8 (M9): Generalization at Level — Unsound Child Levels

**Current state** (`types.odin:132-138`): `generalize_at_level` sets all
variables at level L to `LEVEL_GENERIC` without verifying that children of
`Inferred_Type` structures are also at level ≤ L.

**Example of the bug:**
```
let f = (x) -> {             // level 1
    let g = (y) -> x + y     // level 2
    g
}
```
When generalizing at level 1, `f`'s return type `int -> int` is generalized.
But `x` inside `g` is at level 1 (it's bound in f's scope, at level 1). When
`f` is instantiated multiple times, `x` should be freshened each time. But if
`x`'s level wasn't properly tracked through `g`'s type, it might not get the
correct level for generalization.

### Design

The fix: when generalizing a variable at level L, recursively check that all
children of its `Inferred_Type` are at level ≤ L. If any child is at level >
L, produce the existing diagnostic or mark the variable as non-generalizable.

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
            for each child_var_id in the inferred type:
                child = get_var(store, child_var_id)
                if child.level > max_level:
                    return false
            return true
        Type_Var_ID:
            child = get_var(store, link)
            return child.level <= max_level
```

The `Inferred_Type` traversal extracts child `Type_Var_ID`s from:
- `.Function`: param_ids, return_id, effect_id
- `.Record_Row`: record_fields[*].var, record_rest
- `.Tag_Union_Row`: tag_entries[*].payload[*], rest_id
- `.Effect_Row`: effect_names (names, not vars), rest_id

**Estimated scope:** ~35 lines in `types.odin`.

---

## Implementation Order

The bugs are listed below in recommended implementation order, accounting for
dependencies:

1. **H2 (IR_Crash)** — simplest, standalone
2. **C7 (non-name callee)** — standalone diagnostic
3. **M4 (handler evidence)** — standalone, small
4. **C5 (match patterns)** — standalone, typecheck only
5. **M9 (generalization levels)** — standalone, types only
6. **C8 (closure body)** — affects ir/odin, lower, closure_convert
7. **C9 (Perceus RC)** — affects rc, codegen
8. **M5 (CPS continuations)** — affects cps, codegen; depends on C8

---

## Testing Strategy

Each fix should include:
1. A unit test in the existing test file for that compiler phase
2. One or more e2e snapshot tests exercising the fixed behavior
3. Verification that all 117 existing unit tests continue to pass
4. Verification that all 101 existing e2e tests continue to pass

## Success Criteria

After all fixes:
- The compiler compiles simple programs with closures
- Reference counting inserts correct dup/drop
- Effectful programs with handles produce working WASM
- Match expressions with patterns compile and run correctly
- CPS generates continuations for effectful call chains
- No type soundness regressions
- All existing tests pass
