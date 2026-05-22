# Camp Compiler — Implementation Plan

Complete technical plan for all unimplemented and broken features, verified against
source code as of 2026-05-22. Organized into 8 dependency-ordered tracks.

**Total estimated scope**: ~8,800 lines of Odin + ~1,500 lines of Camp + ~500 lines of JS/SCM

---

## Dependency Graph

```
Track 1: Bug Fixes ──────────────────────────────────────┐
  H2 → M4 → M9 → C5 → C8 → C7 → C9 → M5               │
                                                          ├──► Track 3: Stdlib
Track 2: User Effect Codegen ────────────────────────────┤    (needs working closures + RC)
  depends on C8, C7, M5 from Track 1                     │
                                                          ├──► Track 5: Language Features
Track 4: Traits/Generics ────────────────────────────────┤    (needs IR_Method_Call codegen)
  independent of Tracks 1-3                              │
                                                          ├──► Track 6: Infrastructure
Track 7: Parallelism ────────────────────────────────────┤    (needs stdlib, traits)
  depends on Tracks 1-4                                  │
                                                          └──► Track 8: Future Work
```

---

## Track 1: Bug Fixes (8 bugs, ~445 lines)

**Priority**: Critical — everything else depends on these being correct.
**Order**: H2 → M4 → M9 → C5 → C8 → C7 → C9 → M5 (per compiler design doc)

### Bug 1 — H2: IR_Crash Node Missing (~15 lines)

**Problem**: `CExpr_Crash` lowers to `lower_expr(e.message)` — the crash semantics
are discarded. No `IR_Crash` variant exists in the IR union.

**Files to change**:

| File | Change |
|------|--------|
| `src/ir.odin` | Add `IR_Crash :: struct { message: IR_Expr, span: Source_Span }` to `IR_Expr` union |
| `src/lower.odin` | `CExpr_Crash` case: return `IR_Crash{message = lower_expr(e.message, env)}` instead of just lowering the message |
| `src/effect_lower.odin` | Add traversal case: recurse into `.message` |
| `src/closure_convert.odin` | Add traversal case: recurse into `.message` |
| `src/cps.odin` | Add traversal case: recurse into `.message` |
| `src/rc.odin` | Add traversal case: recurse into `.message` |

**Codegen** (`src/codegen.odin`): Already has `IR_Crash` case at line 1818-1822 — emits
message expression then `camp_exit(1)` + `Wasm_Unreachable`. No codegen change needed.

**Verification**: `odin test src` passes; add e2e test `tests/e2e/execution/crash.camp`
that verifies `crash "msg"` produces exit code 1.

---

### Bug 2 — M4: Missing Handler Evidence Parameter (~5 lines)

**Problem**: When `IR_Perform` finds no matching handler on the evidence stack
(`ev_var == NO_NAME`), the evidence argument is silently omitted. The handler function
expects an evidence parameter but the call site doesn't provide one — calling convention
mismatch.

**File to change**: `src/effect_lower.odin`

**Change** (around line 131-163 in `el_lower_let_perform`):
```odin
if ev_var == NO_NAME {
    // Compiler bug — unhandled perform should be caught by typechecker
    collector_add_diag(env.collector, diag_internal(
        "effect_lower: no handler for perform of {effect}", e.span
    ))
    // Return a zero literal with the perform's type so downstream doesn't crash
    return IR_Expr(IR_Literal_Int{value = 0, type = perform_type, span = e.span})
}
```

**Prerequisite**: Add `collector: ^Diagnostic_Collector` field to `Effect_Lower_Env`.

**Verification**: Unit test: perform without handler emits diagnostic instead of
producing invalid IR.

---

### Bug 3 — M9: Generalization at Level — Unsound Child Levels (~45 lines)

**Problem**: `generalize_at_level` in `types.odin:132-138` marks all variables at
level L as `LEVEL_GENERIC` without checking that children of `Inferred_Type` structures
are also at level ≤ L. This can generalize type variables that reference non-generalizable
children, producing unsound types.

**File to change**: `src/types.odin`

**Add helper**:
```odin
all_children_at_or_below_level :: proc(store: ^Type_Store, link: Type_Link, max_level: int) -> bool {
    switch link in {
    case Type_Unlinked:
        return true
    case Type_Var_ID:
        child := get_var(store, link)
        return child.level <= max_level
    case Inferred_Type:
        // Extract and check all child Type_Var_IDs
        switch inf := link.inferred {
        case .Function:
            for id in inf.param_ids { if get_var(store, id).level > max_level { return false } }
            if get_var(store, inf.return_id).level > max_level { return false }
            if get_var(store, inf.effect_id).level > max_level { return false }
        case .Record_Row:
            for f in inf.record_fields { if get_var(store, f.var).level > max_level { return false } }
            if inf.record_rest != NO_TYPE_VAR && get_var(store, inf.record_rest).level > max_level { return false }
        case .Tag_Union_Row:
            for t in inf.tag_entries {
                for p in t.payload { if get_var(store, p).level > max_level { return false } }
            }
            if inf.rest_id != NO_TYPE_VAR && get_var(store, inf.rest_id).level > max_level { return false }
        case .Effect_Row:
            // Effect names are Intern_IDs, not type vars — skip
            if inf.rest_id != NO_TYPE_VAR && get_var(store, inf.rest_id).level > max_level { return false }
        }
        return true
    }
}
```

**Modify `generalize_at_level`**: Before setting `var.level = LEVEL_GENERIC`,
call `all_children_at_or_below_level(store, var.link, level)`. Only generalize if it
returns true.

**Verification**: Add unit test where a function captures a type variable from an
outer scope — verify it is NOT incorrectly generalized.

---

### Bug 4 — C5: Match Pattern Typechecking (~90 lines)

**Problem**: `typecheck_match` in `typecheck.odin:485-506` typechecks the scrutinee
and arm bodies but never processes patterns. Pattern variables are never bound into
the environment. Pattern structure is never checked against the scrutinee type.

**File to change**: `src/typecheck.odin`

**Add function**:
```odin
typecheck_pattern :: proc(pattern: CPattern, scrutinee_var: Type_Var_ID, env: ^Type_Env, store: ^Type_Store) -> Type_Result {
    switch p := pattern.(type) {
    case ^CPat_Var:
        env.bindings[p.name] = scrutinee_var
        return Type_Result{var_id = scrutinee_var}
    case ^CPat_Wildcard:
        return Type_Result{var_id = scrutinee_var}
    case ^CPat_Bool:
        bool_id := get_or_create_bool_type(store)
        unify(scrutinee_var, bool_id, store, p.span)
        return Type_Result{var_id = scrutinee_var}
    case ^CPat_Int:
        i64_id := get_or_create_i64_type(store)
        unify(scrutinee_var, i64_id, store, p.span)
        return Type_Result{var_id = scrutinee_var}
    case ^CPat_String:
        str_id := get_or_create_str_type(store)
        unify(scrutinee_var, str_id, store, p.span)
        return Type_Result{var_id = scrutinee_var}
    case ^CPat_Tag:
        // Create tag union row {Tag_Entry{name, payload_vars}, rest}
        // Unify scrutinee with it
        // Recurse into payload patterns
    case ^CPat_Record:
        // Create record row {field_entries, rest}
        // Unify scrutinee with it
        // Recurse into field patterns
    case ^CPat_Or:
        // Typecheck each sub-pattern against same scrutinee_var
    }
}
```

**Modify `typecheck_match`**: For each arm:
1. Save `env.bindings` state
2. Call `typecheck_pattern(arm.pattern, scrutinee_result.var_id, arm_env, store)`
3. Typecheck arm body with `arm_env`
4. Restore `env.bindings` (patterns scoped per arm)

**Exhaustiveness**: Already implemented in `typecheck.odin:1119-1187` —
`collect_covered_tags` + missing branch diagnostics. Pattern typechecking will
feed it correct data.

**Verification**: E2e tests for:
- Tag pattern matching with payload destructuring
- Record pattern matching with field access
- Type error for pattern type mismatch with scrutinee
- Pattern variables usable in arm body

---

### Bug 5 — C8: Closure Body Nil (~90 lines)

**Problem**: `closure_convert.odin:241` creates an `IR_Decl_Fn` with `body = IR_Expr(nil)`.
The original lambda body is never transferred. `lower_lambda` sets `env = nil`,
so `cc_free_vars` returns zero free variables. The fn_idx and env_ptr in the closure
record are literal 0.

**Files to change**:

| File | Change |
|------|--------|
| `src/ir.odin` | Add `body: IR_Expr` field to `IR_Closure` struct |
| `src/lower.odin` | In `lower_lambda` (~line 403): set `IR_Closure.body = lowered_body` instead of discarding |
| `src/effect_lower.odin` | Add traversal case for `IR_Closure.body` |
| `src/cps.odin` | Add traversal case for `IR_Closure.body` |
| `src/rc.odin` | Add traversal case for `IR_Closure.body` |
| `src/closure_convert.odin` | Major rewrite of `IR_Closure` handling (see below) |

**closure_convert.odin changes**:

1. `cc_free_vars` should compute from `e.body` (the IR_Closure body), not from a nil env
2. Transfer body:
   ```odin
   case ^IR_Closure:
       // Compute free vars from e.body
       free_vars := cc_free_vars(e.body, bound_set)
       // Create closed function with env param
       closed_fn.body = cc_convert_expr(e.body, env)
       // Generate env allocation + field stores for each free var
       // Create closure record with fn_idx and env_ptr
   ```
3. Track function index: after adding `closed_fn` to `env.module.decls`, store its
   index in a `map[Canonical_Name]int` for `fn_idx` generation
4. Generate env allocation: `let _cenv = alloc(N * 4); _cenv[0] = free_var_1; ...`

**Verification**: E2e test where a lambda captures a free variable and the captured
value is actually used at runtime. Current test `closure-captures` likely passes only
because the value happens to be 0.

---

### Bug 6 — C7: Non-Name Callee / Higher-Order Calls (~110 lines)

**Problem**: `lower_call` checks if callee is `CExpr_Name`; if not, creates a fresh
dummy `Canonical_Name` and connects nothing. Higher-order calls like `(f x) y` call
non-existent functions.

**Depends on**: C8 (closure body fix) — need correct closure records first.

**Files to change**:

| File | Change |
|------|--------|
| `src/ir.odin` | `IR_Closure_Call` already exists (lines 1740+). Verify it has all needed fields. |
| `src/lower.odin` | When `CExpr_Call` has non-name callee, lower callee expression and create `IR_Closure_Call` instead of `IR_Call` |
| `src/effect_lower.odin` | Add traversal case for `IR_Closure_Call` (if not already present) |
| `src/closure_convert.odin` | Ensure `IR_Closure_Call` handling transforms callee through conversion |
| `src/rc.odin` | Add traversal for `IR_Closure_Call` callee |
| `src/codegen.odin` | `IR_Closure_Call` already has codegen at lines 1781-1808 — uses `call_indirect`. Verify it works with correct fn_idx from C8 fix. |

**lower.odin change** (in `lower_call`):
```odin
// If callee is not CExpr_Name:
callee_expr := lower_expr(e.callee, env)
ir_args := lower_exprs(e.args, env)
return IR_Expr(IR_Closure_Call{
    callee = callee_expr,
    args = ir_args,
    type = lower_type(env.store, type_var),
    span = e.span,
})
```

**Verification**: E2e test: `(|| 42)()` returns 42; higher-order `apply(f, x) = f(x)` works.

---

### Bug 7 — C9: Perceus RC — Var Replaced by Dup/Drop (~90 lines)

**Problem**: `rc.odin:124-139` replaces every `IR_Var` with `IR_Dup` (if uses remain)
or `IR_Drop` (if last use). The original `IR_Var` is never preserved. No variable is
ever actually read.

**Depends on**: C8 (correct closure records before fixing RC).

**File to change**: `src/rc.odin`

**Rewrite `IR_Let` handling** in `rc_insert_expr_inner`:
```odin
case ^IR_Let:
    let_uses := count_uses_in_expr(e.binding_name, e.body)
    
    if let_uses == 0 {
        // Drop value, evaluate body
        drop := IR_Drop{value = e.value, span = e.span}
        return IR_Expr(IR_Block{
            statements = [IR_Expr(drop), rc_insert_expr_inner(e.body, remaining, interner)],
            type = e.type, span = e.span,
        })
    }
    
    // Insert dup before non-last uses of the variable
    transformed_body := insert_dups_and_drop(e.body, e.binding_name, let_uses, interner)
    
    return IR_Expr(IR_Let{
        binding_name = e.binding_name,
        value = rc_insert_expr_inner(e.value, remaining, interner),
        body = rc_insert_expr_inner(transformed_body, remaining, interner),
        type = e.type, span = e.span,
    })
```

**Add helper `insert_dups_and_drop`**: Walks the expression tree. When it finds
`IR_Var{name == binding_name}`, if not the last use, inserts `IR_Dup` before it.
At scope end (for owned references), appends `IR_Drop`.

**Verification**: E2e test where a variable is used twice — both uses should read
the correct value, not a dup/drop artifact.

---

### Bug 8 — M5: CPS Transformation — No Continuations Generated (~60 lines)

**Problem**: `cps.odin` threads `k_name` through the tree but never creates new
continuation functions. Only `IR_Return` becomes a tail-call to `k`.

**Depends on**: C8 (closure records), C7 (closure calls), C9 (correct RC).

**File to change**: `src/cps.odin`

**For `IR_Let` with effectful value** (the key case):
```odin
case ^IR_Let:
    if is_effectful_value(e.value, env) {
        // Create continuation for "the rest of the computation"
        kc_name := cps_fresh(env, "_kc")
        kc_fn := IR_Decl_Fn{
            name = Canonical_Name{name = kc_name, is_local = true},
            params = [e.binding_name],
            body = cps_transform_expr(e.body, k_name, env),
            is_effectful = false,
        }
        append(&env.module.decls, IR_Decl(kc_fn))
        
        // Create closure record for the continuation
        cont_closure := IR_Closure{fn_name = kc_fn.name, type = ...}
        
        // Transform value call to append continuation as extra arg
        transformed_value := cps_transform_expr(e.value, kc_name, env)
        // The call to the effectful function now receives the continuation
        return transformed_value
    } else {
        // Pure let — no continuation needed
        // ...
    }
```

**For `IR_If`**: Both branches must tail-call the same continuation:
```odin
case ^IR_If:
    return IR_If{
        cond = cps_transform_expr(e.cond, k_name, env),
        then_branch = cps_transform_expr(e.then_branch, k_name, env),
        else_branch = cps_transform_expr(e.else_branch, k_name, env),
    }
```

**Verification**: E2e test: `handle Console! in Console.println!("hi") with { ... }`
actually prints "hi" and continues execution after resume.

---

## Track 2: User-Defined Effect Codegen (~450 lines)

**Priority**: High — without this, only 6 built-in scheduler effects work at runtime.
All user-defined effects hit `unreachable` in codegen.

**Depends on**: Track 1 bugs C8, C7, M5 (correct closures + CPS + RC).

### Current State

| Component | Status |
|-----------|--------|
| Effect lowering (evidence passing) | ✅ Working — `effect_lower.odin:670-858` allocates evidence records, creates handler arm functions, stores closures |
| CPS continuation capture | ⚠️ Depends on Bug M5 fix |
| `IR_Handle` codegen | ⚠️ Only scheduler effects; user effects fall to `unreachable` at line 1474 |
| `IR_Perform` codegen | ⚠️ Only scheduler effects; user effects fall to `unreachable` at line 1680 |

### What Needs to Happen

The evidence passing infrastructure in `effect_lower.odin` already works correctly.
It allocates evidence records, stores handler arm closures at computed offsets, and
transforms perform calls into handler dispatch. The gap is purely in codegen —
`emit_expr` for `IR_Handle` and `IR_Perform` only handles scheduler effects.

### Step 2.1: `IR_Handle` Codegen for User Effects (~150 lines)

**File**: `src/codegen.odin`

**Current** (lines 1406-1475):
```odin
case ^IR_Handle:
    if cg_is_scheduler_effect(e.effect, env) {
        // ... scheduler handling (works)
    }
    // else: falls through to unreachable
```

**Change**: Add `else` branch for user-defined effects:
```odin
    else {
        // User-defined effect handler
        // 1. Emit body (which contains IR_Perform nodes that use the evidence variable)
        //    The evidence record was already allocated in effect_lower
        //    The evidence variable is in env.local_map
        emit_expr(e.body, buf, env, runtime_indices)
    }
```

The key insight: by the time we reach codegen, `effect_lower` has already:
- Allocated the evidence record via `camp_alloc`
- Stored handler arm closures into the evidence record
- Pushed the evidence variable into the environment
- Transformed `IR_Perform` into handler arm calls via the evidence record
- Popped the evidence and deallocated on handler exit

So `IR_Handle` for user effects just needs to emit the body — the evidence
infrastructure is already in place.

### Step 2.2: `IR_Perform` Codegen for User Effects (~200 lines)

**File**: `src/codegen.odin`

**Current** (lines 1476-1684): Only handles scheduler effects.

**Add branch** after scheduler effect checks:
```odin
    else {
        // User-defined effect perform
        // effect_lower has already transformed this into:
        //   load handler fn from evidence record
        //   call handler with (env, op_args..., resume, ev)
        //
        // But the IR still contains IR_Perform for user effects
        // because the transformation happens in effect_lower's
        // el_lower_let_perform (which creates IR_Closure_Call).
        //
        // If we reach here, the perform was NOT in let position
        // (rare but possible — standalone perform as expression).
        // Emit it as a call to the evidence-record handler.
        
        ev_var := env.local_map[e.evidence_var]
        
        // Load handler fn_idx: i32.load(ev + arm_index * 8)
        emit(Wasm_I32_Const, arm_index * 8, buf)
        emit(Wasm_I32_Add, buf)  // ev + offset
        emit(Wasm_I32_Load{align=2, offset=0}, buf)  // fn_idx
        local_set(fn_idx_local, buf)
        
        // Load handler env_ptr: i32.load(ev + arm_index * 8 + 4)
        emit(Wasm_I32_Const, arm_index * 8 + 4, buf)
        emit(Wasm_I32_Add, buf)
        emit(Wasm_I32_Load{align=2, offset=0}, buf)  // env_ptr
        local_set(env_local, buf)
        
        // Push args: env_ptr, op_args..., resume_closure, ev
        // Call indirect
        emit(Wasm_Call_Indirect, fn_idx_local, type_idx, buf)
    }
```

### Step 2.3: Effectful Main Codegen for User Effects (~100 lines)

**File**: `src/codegen.odin`

**Current** (lines 641-875): `_start` allocates evidence for Console!, Throw!, and
scheduler effects. Need to add support for any user-defined effect in `main!`'s
effect row.

**Change**: When `main!` has user-defined effects in its row, allocate evidence
records and install "unhandled effect" handlers (that call `camp_exit(1)`), then
call `main!` with all evidence arguments.

```odin
// For each effect in main!'s effect row that is NOT a scheduler effect:
for effect_name in main_effects {
    if !cg_is_scheduler_effect(effect_name, env) {
        // Allocate evidence record with 1 arm per operation
        num_ops := store.effect_ops[effect_name]
        emit_camp_alloc(num_ops * 8, buf, env)
        ev_local := fresh_local(env)
        local_set(ev_local, buf)
        
        // Store unhandled_effect_handler into each slot
        for i in 0..<num_ops {
            emit_handler_into_evidence(buf, env, UNHANDLED_EFFECT_FN_IDX, 0, ev_local, i * 8)
        }
        
        // Pass ev_local as evidence argument to main!
    }
}
```

**Verification**: E2e tests:
- `tests/e2e/effects/user-effect-handle.camp` — define `Ask! : { ask!: || -> I64 }`,
  handle it, perform it, verify resume returns correct value
- `tests/e2e/effects/unhandled-effect.camp` — perform without handler exits with code 1
- `tests/e2e/effects/deep-vs-shallow.camp` — deep handler reinstalled after resume

---

## Track 3: Stdlib Completion (~400 lines of Camp)

**Priority**: High — `Str.length`, `Str.concat`, `Str.eq` and 6 `List` functions
crash at runtime with "not yet implemented". `Iter` module is complete but inaccessible.

### Step 3.1: Implement Str Builtins (~80 lines of Camp, ~40 lines of Odin)

**Problem**: `Str.length`, `Str.concat`, `Str.eq` crash at runtime because there's
no WASM implementation behind them.

**Approach**: These require runtime support since strings are stored as pointer+length
in WASM linear memory. The runtime already has `RUNTIME_STR_LEN` (index 11) and
`RUNTIME_STR_EQ` (index 12).

**Files to change**:

| File | Change |
|------|--------|
| `stdlib/Str.camp` | Replace `crash "not yet implemented"` with FFI-style calls. But Camp has no FFI — these must be compiler intrinsics. |
| `src/codegen.odin` | When lowering `Str.length`, `Str.concat`, `Str.eq`, emit calls to runtime functions |
| `src/lower.odin` | Add intrinsic recognition for `Str.length`, `Str.concat`, `Str.eq` |

**Compiler intrinsic approach**: During lowering, recognize calls to `Str.length`,
`Str.concat`, `Str.eq` as intrinsics and emit direct runtime calls:

| Camp Function | Runtime Function | WASM Emission |
|---------------|-----------------|---------------|
| `Str.length(s)` | `RUNTIME_STR_LEN` | `local_get(s); call $camp_str_len` |
| `Str.eq(a, b)` | `RUNTIME_STR_EQ` | `local_get(a); local_get(b); call $camp_str_eq` |
| `Str.concat(a, b)` | New runtime: `camp_str_concat` | Alloc new string, copy both, return ptr |

**New runtime function needed**: `camp_str_concat(a_ptr, a_len, b_ptr, b_len) -> result_ptr`.
This allocates memory, copies both strings, and returns a pointer to the concatenated
result. Length is `a_len + b_len` and stored at `result_ptr - 4` (string length prefix).

**Add to codegen.odin**: `RUNTIME_STR_CONCAT :: 35` and bump `RUNTIME_FUNC_COUNT :: 36`.
Add `emit_camp_str_concat_body` that:
1. Calls `camp_alloc(a_len + b_len + 4)` (4 for length prefix)
2. Stores `a_len + b_len` at offset 0 (length)
3. Memory.copy from a_ptr to result+4, length a_len
4. Memory.copy from b_ptr to result+4+a_len, length b_len
5. Returns result+4 (pointer past length prefix)

### Step 3.2: Implement List Builtins (~100 lines of Camp, ~60 lines of Odin)

**Problem**: `List.length`, `List.map`, `List.filter`, `List.fold`, `List.append`,
`List.head` crash at runtime.

**Runtime already has**: `RUNTIME_LIST_ALLOC` (7), `RUNTIME_LIST_PUSH` (8),
`RUNTIME_LIST_LEN` (9), `RUNTIME_LIST_GET` (10).

**Strategy**: Some List operations can be implemented in Camp using the existing
runtime primitives. Others need new runtime support.

| Function | Implementation |
|----------|---------------|
| `List.length(xs)` | Use `RUNTIME_LIST_LEN` intrinsic |
| `List.head(xs)` | `List.get(xs, 0)` → use `RUNTIME_LIST_GET` intrinsic |
| `List.map(f, xs)` | New Camp code: alloc result list, iterate, push `f(x)` for each |
| `List.filter(pred, xs)` | New Camp code: alloc result list, iterate, push if `pred(x)` |
| `List.fold(f, init, xs)` | New Camp code: iterate with accumulator |
| `List.append(xs, ys)` | New Camp code: alloc result list, push all from xs then ys |

**New runtime needed**: `camp_list_iter` — returns next element and advances cursor.
Or: just implement all List operations in Camp with `List.get(xs, i)` and `List.length(xs)`.

**Files to change**:

| File | Change |
|------|--------|
| `stdlib/List.camp` | Replace crashes with real Camp implementations using intrinsics |
| `src/lower.odin` | Add intrinsic recognition for `List.length`, `List.get` |
| `src/codegen.odin` | Map `List.length` → `RUNTIME_LIST_LEN`, `List.get` → `RUNTIME_LIST_GET` |

### Step 3.3: Register Iter Module (~5 lines)

**Problem**: `Iter.camp` exists with all 16 functions implemented, but is not in
`STDLIB_MODULES` — inaccessible to user code.

**File**: `src/stdlib.odin`

**Change**: Add to `STDLIB_MODULES`:
```odin
{"Iter", ITER_CAMP, "stdlib/Iter.camp"},
```

And add `ITER_CAMP` string literal loaded from `#embed "stdlib/Iter.camp"` or as
a raw string constant (matching existing pattern).

**Verification**: Import `Iter` in a test file, use `Iter.map`, `Iter.collect`, etc.

---

## Track 4: Traits & Generics Completion (~600 lines)

**Priority**: High — trait system is substantially implemented but has critical gaps.

### Current State

| Feature | Status |
|---------|--------|
| Trait declaration parsing | ✅ Done |
| Trait typechecking (orphan rule, overlap, inheritance, structural verification) | ✅ Done |
| Constraint violation checking | ✅ Done |
| UFCS dispatch in monomorphization | ✅ Done |
| `IR_Method_Call` codegen | ❌ Emits `unreachable` — entirely unimplemented |
| `where` clause syntax | ❌ Not parsed |
| `@derive` expansion | ⚠️ Stubs generated, no actual implementations |
| Generic newtypes | ⚠️ Parsing works, no mono/lower |

### Step 4.1: `IR_Method_Call` Codegen (~80 lines)

**File**: `src/codegen.odin`

**Problem**: Line 1404-1405 — the only case that emits pure `unreachable`:
```odin
case ^IR_Method_Call:
    emit(Wasm_Unreachable, buf)
```

**Context**: By the time we reach codegen, most method calls should have been resolved
by monomorphization (UFCS dispatch rewrites `x.method(args)` → `Type_method(x, args)`).
So `IR_Method_Call` should rarely appear in practice. But it's needed for:
1. Dynamic dispatch when mono can't resolve (generic type variables)
2. Interim correctness before mono is fully wired

**Implementation**: Method calls on objects with known vtable layout can use
`call_indirect` via a vtable record. But Camp uses static-only dispatch (no vtables).
So the correct approach is: if `IR_Method_Call` reaches codegen, it's a compiler error
(the mono pass should have resolved it). Emit a diagnostic and `camp_exit(1)`.

```odin
case ^IR_Method_Call:
    // Method calls should be resolved by monomorphization.
    // If we reach here, mono failed to resolve the dispatch.
    // Emit runtime error.
    emit(Wasm_I32_Const{value = string_offset("unresolved method call")}, buf)
    emit(Wasm_Call{fn_idx = RUNTIME_PRINT_ERR}, buf)
    emit(Wasm_I32_Const{value = 1}, buf)
    emit(Wasm_Call{fn_idx = RUNTIME_EXIT}, buf)
    emit(Wasm_Unreachable, buf)
```

**Better long-term**: Add a `resolved` field to `IR_Method_Call` that mono fills
in, then lower it as `IR_Call` with the resolved target. For now, the runtime error
is safer than silent `unreachable`.

### Step 4.2: `where` Clause Syntax (~60 lines)

**File**: `src/parser.odin`

**Current**: Only `|x: a is Display|` syntax works for constraints. No `where` clause.

**Add `where` parsing** after type annotation in const declarations:
```
name = <a>|x: a| -> Str where a is Display { ... }
```

**Parser changes**:
1. After parsing return type in const declaration, check for `Kw_Where`
2. Parse constraint list: `a is Trait1, b is Trait2`
3. Store in `Decl_Const.where_clauses: [dynamic]Where_Clause`
4. During typecheck, transfer `where` constraints to `type_constraints` on the
   relevant type variables (same mechanism as inline `is Display`)

**New AST node**:
```odin
Where_Clause :: struct {
    type_param: Intern_ID,
    trait_name: Intern_ID,
    span:       Source_Span,
}
```

**Files to change**:

| File | Change |
|------|--------|
| `src/ast.odin` | Add `where_clauses` field to `Decl_Const` |
| `src/parser.odin` | Parse `where` clause after return type |
| `src/canonicalize.odin` | Transfer `where_clauses` to `type_constraints` |
| `src/typecheck.odin` | Process `where_clauses` into constraints on type variables |
| `src/format_decl.odin` | Format `where` clauses |

### Step 4.3: Generic Newtype Mono/Lower (~80 lines)

**Problem**: `TDecl_Newtype` has an empty case in `lower.odin:76`. Generic newtypes
like `@Pair(a, b)` are parsed and typechecked but never lowered to IR.

**File**: `src/lower.odin`

**Change**: Add newtype lowering:
```odin
case ^TDecl_Newtype:
    // Newtypes are erased at runtime — they're just their inner type
    // No IR decl needed. The type information is in Type_Store.
    // Monomorphization will create specialized versions.
    return
```

**File**: `src/mono.odin`

**Change**: Add newtype specialization. When mono encounters a call that uses a
generic newtype, create a specialized version with concrete type arguments. The
specialized newtype maps directly to its inner type.

### Step 4.4: @derive Expansion (~200 lines)

**Problem**: `canonicalize.odin:873-919` generates stub method declarations for
`@derive(Eq, Clone, Hash, Ord, Compare)`. The stubs have empty bodies.

**Approach**: Generate actual method implementations during canonicalization:

| Trait | Method | Implementation |
|-------|--------|---------------|
| `Eq` | `eq(self, other) -> Bool` | Compare each field: `self.field1 == other.field1 and self.field2 == ...` |
| `Clone` | `clone(self) -> Self` | Construct new record with each field cloned |
| `Hash` | `hash(self) -> U64` | XOR/combine hash of each field |
| `Ord` | `compare(self, other) -> Ordering` | Compare fields lexicographically |

**File**: `src/canonicalize.odin`

**Change**: Replace `make_derive_method_decl` stub generation with real implementations.
Generate Camp-like expressions in CExpr form:

```odin
// For @derive(Eq) on a newtype @UserId := U64:
// Generate: eq = |self, other| self.inner() == other.inner()

// For @derive(Eq) on a record { name: Str, age: I64 }:
// Generate: eq = |self, other| self.name == other.name and self.age == other.age
```

**Challenge**: This requires generating CExpr trees programmatically. The existing
`make_derive_method_decl` already does this for the stub (return type + params).
Extend it to also generate the body.

**Scope**: ~200 lines in `canonicalize.odin` for the 5 trait derivations.

### Step 4.5: Wiring Mono into the Pipeline (~15 lines)

**File**: `src/cli.odin`

**Ensure**: The mono pass runs between typecheck and lower in both
`run_build_single` and `run_build_project`. Check that the pipeline order is:
`typecheck → annotate → mono → lower → effect_lower → ...`

**Also**: Add `TFile`-based pipeline path (per G9/G10 in generics-traits design):
if `tfile.decls` is populated, call `lower_tfile` instead of `lower_file`.

---

## Track 5: Language Features (~500 lines)

### Step 5.1: Mutable `$` Variables (~120 lines)

**Problem**: `$` identifiers are parsed (`Expr_Dollar_Identifier`), `$var = expr`
syntax works in blocks, but there's no mutation store semantics.

**Approach**: Mutable variables are stack-local cells. In WASM, this means using
WASM locals with `local.set`/`local.get`.

**Files to change**:

| File | Change |
|------|--------|
| `src/typecheck.odin` | When `$var` appears in an assignment, mark it as mutable in the environment. Verify type compatibility. |
| `src/lower.odin` | `Expr_Assign` with `$` target: emit `IR_I32_Store` or `local.set` instead of `IR_Let` |
| `src/codegen.odin` | For mutable locals: use `local_set` instead of `local_tee`. For heap-allocated mutables: emit `i32.store` to update the cell. |

**Implementation strategy**:
1. `$var = expr` in a block creates a mutable cell on the stack
2. Reading `$var` loads from the cell
3. `$var = new_value` stores to the cell
4. The cell is a WASM local (for simple types) or heap-allocated (for complex types)

**Simplification**: Start with WASM locals only. All `$` variables become mutable
WASM locals. No heap allocation for mutable cells — that's only needed if the
variable's address is taken (which Camp's stack-local restriction prevents).

```odin
// In codegen, for $var assignment:
case ^IR_Assign:  // new IR node needed
    emit_expr(e.value, buf, env, runtime_indices)
    local_set(env.local_map[e.target], buf)
```

**New IR node**:
```odin
IR_Assign :: struct {
    target: Intern_ID,
    value:  IR_Expr,
    type:   IR_Type,
    span:   Source_Span,
}
```

### Step 5.2: `for` Loops (~100 lines)

**Problem**: `for` keyword only works in `par for`. Standalone `for` loops not
implemented.

**File**: `src/parser.odin`

**Add parsing**:
```
for x in xs { body }        — iterate over list
for i in 0..10 { body }     — range iteration
```

**Desugaring approach** (in `canonicalize.odin`): Transform `for x in xs { body }`
into a recursive function or a `List.fold`-like pattern:

```camp
// for x in xs { body }
// becomes:
_list_fold(|_, x| { body; {} }, {}, xs)
```

Or more directly, generate a loop in IR:
```odin
IR_Loop :: struct {
    var:      Intern_ID,
    iterable: IR_Expr,
    body:     IR_Expr,
    type:     IR_Type,
    span:     Source_Span,
}
```

**Codegen**: WASM has `loop`/`block`/`br` instructions for loops:
```wasm
(block $break
  (loop $continue
    ;; check condition
    ;; if done, br $break
    ;; emit body
    ;; br $continue
  )
)
```

### Step 5.3: String Methods (~50 lines)

**Problem**: `.len()`, `.slice()`, etc. not implemented.

**Approach**: Map to runtime intrinsics (same pattern as Str.length in Track 3):

| Method | Implementation |
|--------|---------------|
| `s.len()` | `RUNTIME_STR_LEN` intrinsic |
| `s.slice(start, end)` | New runtime: `camp_str_slice(ptr, len, start, end)` |
| `s.concat(other)` | `RUNTIME_STR_CONCAT` from Track 3 |

**File**: `src/lower.odin` — add intrinsic recognition for string method calls.
When `lower_method_call` sees a `Str` receiver with `len`/`slice`/`concat` method,
generate the corresponding runtime call instead of `IR_Method_Call`.

### Step 5.4: No-Shadowing Enforcement (~30 lines)

**File**: `src/typecheck.odin`

**Change**: When binding a variable name, check if it already exists in the current
scope (not parent scopes — shadowing parent scopes is allowed). If it does, emit
a `diag_shadowing` diagnostic.

```odin
if name in env.current_scope_bindings {
    collector_add_diag(store.collector, diag_shadowing(name, span, original_span))
}
```

### Step 5.5: `pub` Visibility Enforcement (~50 lines)

**File**: `src/import_resolve.odin`

**Current**: `pub_variants` field exists on newtypes. But general `pub` enforcement
during import resolution is not complete.

**Change**: When resolving `import Module exposing [name]`, verify that `name` is
marked `pub` in the exporting module. If not, emit a visibility diagnostic.

### Step 5.6: Backtick Raw Identifiers (~30 lines)

**Files**: `src/lexer.odin`, `src/token.odin`

**Change**: Add backtick-delimited identifiers to the lexer. `` `if` `` tokenizes as
an identifier with text "if" (not a keyword). Add `Token_Kind.Raw_Identifier`.

---

## Track 6: Infrastructure (~600 lines)

### Step 6.1: `camp test` Command (~200 lines)

**File**: `src/main.odin`, `src/cli.odin`

**Implementation**:
1. Parse `test` and `expect` declarations from source files
2. Compile each `test "name" = { body }` to WASM
3. Execute each test, capture exit code
4. Report PASS/FAIL/SKIP per test
5. Support `--filter` and `--verbose` flags

**Pipeline**: Reuse existing build pipeline. Each `test` declaration becomes a
WASM function. `camp test` compiles and runs each one, checking for exit code 0
(success) vs non-zero (failure).

### Step 6.2: `camp check` Command (~50 lines)

**File**: `src/main.odin`, `src/cli.odin`

**Implementation**: Run the compilation pipeline through typecheck only (no lowering,
no codegen). Report any diagnostics. Exit 0 if clean, 1 if errors.

```odin
case .Check:
    // Parse + canonicalize + typecheck only
    // Report diagnostics
    // Exit 0 if no errors, 1 if errors
```

### Step 6.3: Tree-sitter Grammar Completion (~300 lines of JS)

**File**: `tree-sitter/grammar.js`

**Current**: 522 lines, missing:
- Newtype declarations (`@Name is Trait := Type`)
- `derives` clause
- `par` block and `par for`
- `crash` expression
- `test`/`expect` declarations
- Backtick raw identifiers

**Approach**: Add rules mirroring the Camp parser's grammar. Each missing construct
needs:
1. A named rule in `grammar.js`
2. Corpus test in `tree-sitter/test/corpus/`
3. Validation against e2e `.camp` files

### Step 6.4: Formatter `--check` and `--stdin` Modes (~50 lines)

**Files**: `src/main.odin`, `src/run_fmt.odin`

**Current**: `camp fmt` works for in-place formatting. Missing `--check` (diff mode)
and `--stdin` (pipe mode).

**Implementation**:
- `--check`: format to string, compare with source, print diff, exit 1 if different
- `--stdin`: read stdin, format, write to stdout

---

## Track 7: Parallelism Completion (~4,000 lines)

**Depends on**: Tracks 1-4 (bug fixes, user effect codegen, stdlib, traits).

The parallelism design document specifies 6 phases. Phase 1 (Async scheduler) has
substantial runtime code already in `runtime.odin` and `codegen.odin`, but is not
fully functional. Phases 2-6 are not started.

### Phase 1: I/O Concurrency via WASI Poll (~1,410 lines)

**Status**: ~60% complete — scheduler data structures and runtime functions exist
in codegen, but the scheduler loop body is incomplete and WASI poll bridge is missing.

**Remaining work**:

| Step | Description | Scope |
|------|-------------|-------|
| 1b | Complete scheduler loop body in runtime.odin | ~150 Odin |
| 1c | `camp_async_run` main loop: dequeue → resume → check blocked → poll → repeat | ~200 Odin |
| 1d | WASI poll bridge: `poll_oneoff` on blocked pollables, move ready to queue | ~150 Odin |
| 1e | Short read/write handling: buffer partial results, retry | ~100 Odin |
| 1f | `Time.sleep!` via poll timeout | ~50 Odin |
| 1g | `Async.yield!` — reschedule current coroutine | ~30 Odin |
| 1h | Structured concurrency: auto-cancel pending spawns on handler exit | ~80 Odin |
| 1i | Effect-to-WASI mapping for File!/Console! | ~200 Odin |
| 1j | E2E tests | ~150 Camp |

**Key implementation**: The `_start` function for effectful `main!` with `Async!`
needs to:
1. Initialize scheduler (`camp_sched_init`)
2. Enqueue main as first coroutine
3. Run scheduler loop
4. Return exit code

The scheduler loop (`camp_async_run` / `RUNTIME_ASYNC_RUN`):
```wasm
(block $done
  (loop $schedule
    ;; Try to dequeue next ready task
    (call $camp_async_dequeue)
    ;; If no task and no blocked → done
    ;; If no task but blocked → poll_oneoff, move ready to queue
    ;; If task → call_indirect to resume it
    ;; Resume may: complete, yield, block on I/O, spawn, join
    br $schedule
  )
)
```

**Exit criterion**: Concurrent file reads work with `wasi:io/poll`.

### Phase 2: Sequential Parallel! Effect (~520 lines)

| Step | Description | Scope |
|------|-------------|-------|
| 2a | `Parallel!` effect definition in prelude | ~40 Camp |
| 2b | Sequential handler implementation | ~80 Camp |
| 2c | Typechecker: effect row propagation through Parallel! ops | ~30 Odin |
| 2d | Collection method sugar (`list.par_map!(f)` → `Parallel!.map!(list, f)`) | ~60 Odin |
| 2e | `par { }` and `par for` block desugaring | ~80 Odin |
| 2f | E2E tests | ~200 Camp |
| 2g | Formatter support for `par` syntax | ~30 Odin |

**Exit criterion**: `Parallel!.map!` works with sequential handler.

### Phase 3: Multi-Instance Spawn (~1,560 lines)

| Step | Description | Scope |
|------|-------------|-------|
| 3a | `--threads=N` CLI flag + `CAMP_THREADS` env var | ~50 Odin |
| 3b | Thread pool manager (Odin host side) | ~250 Odin |
| 3c | Worker loop | ~100 Odin |
| 3d | Worker module generation (separate WASM for workers) | ~200 Odin |
| 3e | Closure serialization format | ~200 Odin |
| 3f | Closure deserialization in worker | ~100 Odin |
| 3g | Spawn handler (serialize, submit, wait, deserialize) | ~150 Odin |
| 3h | Parallel handler (chunk, spawn, join, concatenate) | ~150 Odin |
| 3i | String/list cross-instance handling | ~100 Odin |
| 3j | Error propagation across instances | ~80 Odin |
| 3k | Structured concurrency tracking | ~80 Odin |
| 3l | E2E tests + benchmarks | ~200 Camp |

**Key insight**: This is the first phase that requires changes to the **Odin host**
(not just the WASM module). The thread pool manager runs in the Camp CLI process
(Odin), creating multiple wasmtime instances and managing work distribution.

**Exit criterion**: Two spawned tasks ~2x faster than sequential.

### Phase 4: Thread-Pool Parallel Handler (~490 lines)

| Step | Description | Scope |
|------|-------------|-------|
| 4a | `Parallel!` → `Spawn!` handler with chunk-based distribution | ~150 Camp |
| 4b | Auto-install thread-pool handler when `Parallel!` in `main!` row | ~80 Odin |
| 4c | Chunk size heuristics | ~60 Camp |
| 4d | E2E + benchmarks | ~200 Camp |

**Exit criterion**: Near-linear speedup on multi-core.

### Phase 5: WASM Threads (~1,540 lines)

| Step | Description | Scope |
|------|-------------|-------|
| 5a | Shared memory codegen (`shared=true`, `maximum` field) | ~80 Odin |
| 5b | `IR_Atomic_*` nodes already in IR/codegen — verify completeness | ~100 Odin |
| 5c | IR traversal for atomic nodes (already exists at lines 1834-1859) | ~0 (done) |
| 5d | Atomic instruction WASM emission (verify existing codegen) | ~0 (done) |
| 5e | Shared work queue data structure | ~150 Odin |
| 5f | Enqueue/dequeue using atomics | ~150 Odin |
| 5g | Worker entry function codegen | ~100 Odin |
| 5h | Per-thread heap regions (bump allocator) | ~100 Odin |
| 5i | `camp_alloc_region` bump allocator | ~50 Odin |
| 5j | Spawn handler migration (multi-instance → in-process) | ~100 Odin |
| 5k | Parallel handler migration | ~50 Odin |
| 5l | COOP/COEP browser warning | ~30 Odin |
| 5m | Runtime detection + fallback | ~80 Odin |
| 5n | E2E tests + benchmarks | ~200 Camp |

**Note**: IR nodes for atomics (`IR_Atomic_Load`, `IR_Atomic_Store`, `IR_Atomic_RMW`,
`IR_Atomic_Fence`, `IR_Wait`, `IR_Notify`) and their codegen already exist in
`codegen.odin:1834-1859`. This reduces Phase 5 scope significantly.

**Exit criterion**: `Spawn!.spawn!` and `Parallel!.map!` work within single WASM
module with shared memory.

### Phase 6: SIMD Optimization (Future, ~600 lines)

Deferred — requires WASM SIMD proposal support in wasmtime and browser runtimes.

---

## Track 8: Future Work

These features are designed in their spec documents but explicitly deferred due to
scope, dependency on other features, or requiring research.

### Comptime Evaluation (~2,000 lines, depends on full trait system + module system)

Not specified in detail yet. Requires:
- Constant expression evaluation at compile time
- `comptime` blocks that execute during compilation
- Integration with `@derive` for generating trait impls
- The compiler needs an interpreter for Camp values (or compiles and runs WASM
  snippets at compile time)

### Cycle Collector (~500 lines)

Perceus reference counting handles acyclic data. Cyclic structures leak.
A cycle collector (like Koka's) would periodically scan for reference cycles.
Deferred because:
- Most Camp code is functional and doesn't create cycles
- The collector adds runtime complexity
- Can be added later without language changes

### Package Manager (~1,000 lines)

`camp.toml` parsing, git-based dependency fetching, lockfile generation.
Explicitly deferred to a separate effort per modules design doc.

### WASM Component Model Async (~300 lines, depends on wasmtime support)

When WASI Preview 3 ships with `future<T>` and `stream<T>`, the `Async!` runtime
can migrate from CPS-compiled coroutines to host-managed async. User code doesn't
change — only the runtime.

---

## Implementation Priority Summary

| Priority | Track | Lines | Unblocks |
|----------|-------|-------|----------|
| **P0** | Track 1: Bug Fixes | ~445 | All other tracks |
| **P1** | Track 2: User Effect Codegen | ~450 | Real effect programs |
| **P1** | Track 3: Stdlib Completion | ~400 | Useful programs |
| **P1** | Track 4: Traits/Generics | ~600 | Reusable abstractions |
| **P2** | Track 5: Language Features | ~500 | Ergonomics |
| **P2** | Track 6: Infrastructure | ~600 | Developer experience |
| **P3** | Track 7: Parallelism | ~4,000 | Performance |
| **P4** | Track 8: Future Work | ~3,500+ | Ecosystem |

### Critical Path

```
Week 1-2:  Bug H2, M4, M9 (simple, independent)
Week 2-3:  Bug C5 (match patterns)
Week 3-5:  Bug C8, C7, C9 (closures + RC — most complex)
Week 5-6:  Bug M5 (CPS continuations)
Week 6-7:  Track 2: User effect codegen
Week 6-8:  Track 3: Stdlib (parallel with Track 2)
Week 7-9:  Track 4: Traits/Generics (parallel with Tracks 2-3)
Week 9+:   Tracks 5-8 (language features, infrastructure, parallelism)
```

### What You Can Do After Each Track

| After Track | What Works |
|-------------|-----------|
| **1** | All 8 bugs fixed; closures close over variables; higher-order calls work; RC preserves variable reads; CPS generates continuations |
| **1+2** | User-defined effects execute in WASM; `handle`/`perform`/`resume` all work; deep/shallow handlers functional |
| **1+2+3** | Str and List operations don't crash; Iter module accessible; can write real programs |
| **1-4** | Full trait system; `@derive` generates real impls; `where` clauses; method dispatch works end-to-end |
| **1-5** | Mutable variables; for loops; string methods; no-shadowing; pub enforcement; raw identifiers |
| **1-6** | `camp test` runs tests; `camp check` typechecks without building; tree-sitter parses all constructs; formatter check/stdin modes |
| **1-7** | Async I/O with WASI poll; sequential Parallel! effect; multi-instance Spawn; thread-pool parallelism; WASM threads |
