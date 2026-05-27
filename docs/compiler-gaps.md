# Camp Compiler: Unimplemented Behavior Audit

> Comprehensive inventory of compiler gaps — code paths that silently produce
> wrong results, accept invalid input without error, or define behavior that
> never executes. Found by systematic audit of all dispatch switches in the
> pipeline, cross-referenced with the syntax recipe.

## Severity Classification

| Level | Meaning |
|-------|---------|
| **P0 — Wrong Code** | Produces incorrect output silently at runtime; no diagnostic |
| **P1 — Missing Error** | Invalid input accepted without error; downstream behavior undefined |
| **P2 — Semantic Hole** | Feature partially implemented; some paths silently drop data |
| **P3 — Not Yet Parsed** | Syntax recipe defines feature; parser doesn't recognize it |

---

## 1. Typechecker (P0 / P1)

### GAP-1: `verify_trait_conformance` never called

**File:** `src/semantics/check_decl.odin:405-540`
**Severity:** P0 — Wrong Code

`verify_trait_conformance` is a ~135-line function that:
- Checks orphan rule violations (impl defined in wrong module)
- Detects overlapping/duplicate impls
- Verifies every required method exists and has correct signature
- Unifies impl method types against trait declarations
- Emits precise diagnostics for each failure

It is **never called** anywhere. The `CDecl_Is_Impl` handler (line 261) typechecks
method bodies individually but:
1. Does NOT invoke `verify_trait_conformance`
2. Does NOT register the impl in `store.trait_impls`
3. Fills `params = make([dynamic]TFunc_Param, 0)` — method parameter types from the
   trait declaration are never populated

**Effect:** Any `is` impl compiles regardless of correctness. Wrong method signatures,
missing methods, and orphan impls are all silently accepted.

**Fix:** Call `verify_trait_conformance` from the `CDecl_Is_Impl` handler after
typechecking all method bodies. Register successful impls in `store.trait_impls`.

---

### GAP-2: `CExpr_Perform` args never unified against effect signature

**File:** `src/semantics/typecheck.odin:757-775`
**Severity:** P1 — Missing Error

```odin
case ^CExpr_Perform:
    var_id, effects := fresh_with_effects(store, e.span)
    args_t := make([dynamic]TExpr, len(e.args))
    for arg, i in e.args {
        arg_result := typecheck_synth(arg, env, store)
        _ = arg_result                    // ← discarded
        args_t[i] = arg_result.texpr
    }
```

Each argument is typechecked (for internal consistency) but `arg_result` is
explicitly discarded. The argument types are **never unified** against the
effect operation's declared parameter types. The effect's return type is also
a fresh variable rather than resolved from the effect declaration.

**Effect:** `perform Console.println!(42)` where `println!` expects `Str` passes
without error. Wrong-arity performs pass silently.

**Fix:** Look up the effect operation in the type environment, extract its
parameter types and return type, unify each arg against them.

---

### GAP-3: `CExpr_Nominal_Construct` never resolves `type_name`

**File:** `src/semantics/typecheck.odin:398-414`
**Severity:** P1 — Missing Error

```odin
case ^CExpr_Nominal_Construct:
    type_var, eff := fresh_with_effects(store, e.span)
    // ... typechecks payload args ...
    t^ = TExpr_Nominal_Construct {
        type_name     = e.type_name,       // ← carried as intern ID
        resolved_type = type_var,          // ← fresh unification variable
        // ...
    }
```

The `type_name` is carried as an intern ID but **never resolved** against the
actual newtype/constructor declarations in `store.bindings`. The result type is
a fresh unification variable with no constraints.

**Effect:** `@NonexistentType.Foo(42)` compiles without error. The constructed
value has a completely unconstrained type.

**Fix:** Resolve `e.type_name` via `store.bindings` (or `env.bindings`). If not
found, emit an "undefined type" diagnostic. Unify the fresh type_var with the
resolved type.

---

### GAP-4: `typecheck_binop` default case accepts all operators

**File:** `src/semantics/check_expr.odin:~165`
**Severity:** P1 — Missing Error

The default `case:` in the binop switch passes `left_result.var_id` as the
result type for **any** unhandled binary operator. No check that the operator
is valid; no constraint on operand types.

**Effect:** A typo like `x ??? y` (if it reaches the typechecker) would be
accepted with type = left operand type.

**Fix:** The default case should emit a diagnostic ("unknown operator") and
return a fresh error type.

---

### GAP-5: `typecheck_prefixop` default case same pattern

**File:** `src/semantics/check_expr.odin:~200`
**Severity:** P1 — Missing Error

Same issue as GAP-4 for prefix operators.

**Fix:** Same as GAP-4 — emit diagnostic in default case.

---

### GAP-6: `typecheck_synth` fallthrough returns `TExpr_Int{span=ZERO}`

**File:** `src/semantics/typecheck.odin:884-893`
**Severity:** P1 — Missing Error

After the main `#partial switch` on `CExpr` variants, the code falls through to:

```odin
var_id, eff := fresh_with_effects(store, base.Source_Span_ZERO)
t := new(TExpr_Int)
t^ = TExpr_Int { type_ = type_ir, eff_ = eff_ir, span = base.Source_Span_ZERO }
return Synth_Result{var_id = var_id, effects = eff, texpr = TExpr(t)}
```

Any `CExpr` variant not explicitly handled silently becomes integer 0 with
`Source_Span_ZERO` — no diagnostic, and subsequent error messages will point to
nowhere.

**Effect:** If a new CExpr variant is added to the union but the typechecker
isn't updated, all instances of that variant silently become `0`.

**Fix:** Replace with a diagnostic-emitting default that returns a fresh error
type. Convert to total switch or add an explicit `case:` that errors.

---

### GAP-7: `typecheck_file` second-pass switch is all no-ops

**File:** `src/semantics/typecheck.odin:194-205`
**Severity:** P2 — Semantic Hole

After the first pass (typechecking all decls), the second pass iterates all
decls again but **every case body is empty**:

```odin
for decl in file.decls {
    #partial switch d in decl {
    case ^CDecl_Newtype:
    case ^CDecl_Const, ^CDecl_Effect, ^CDecl_Trait, ^CDecl_Alias,
         ^CDecl_Import, ^CDecl_Test, ^CDecl_Expect:
    }
}
```

`CDecl_Is_Impl` is notably **absent** from this switch. This second pass was
presumably intended for post-hoc verification (e.g., checking that newtypes are
well-formed after all bindings are resolved), but does nothing.

**Effect:** No functional impact currently (it's dead code), but the absence of
`CDecl_Is_Impl` from the switch means even if the pass were activated, trait
impls would be skipped.

**Fix:** Either remove the dead second pass or implement the intended
post-hoc checks. If kept, add `CDecl_Is_Impl` and call `verify_trait_conformance`.

---

### GAP-8: `check_effect_safety` only checks `main!`, stops at first offense

**File:** `src/semantics/typecheck.odin` (search for `check_effect_safety`)
**Severity:** P2 — Semantic Hole

The effect safety check:
1. Only validates `main!` — other entrypoints are not checked
2. Returns after finding the **first** non-prelude effect — no comprehensive
   list of unhandled effects is reported

**Effect:** A user with 5 unhandled effects in `main!` sees only 1 diagnostic.

**Fix:** Collect all unhandled effects before reporting. Extend to check all
declared entrypoints, not just `main!`.

---

## 2. Unification (P1)

### GAP-9: `Inferred_Constructor` unification ignores `primitive_name` and `arity`

**File:** `src/semantics/unify.odin:204-216`
**Severity:** P1 — Missing Error

```odin
case Inferred_Constructor:
    _, ok := b.(Inferred_Constructor)
    if !ok {
        // emit type_mismatch diagnostic
        return false
    }
    // ← falls through to success
```

The code checks that both sides are `Inferred_Constructor` but **never compares**
`primitive_name` or `arity` fields. Given that `Inferred_Constructor` has both
fields (defined at `types.odin:71-74`):

```odin
Inferred_Constructor :: struct {
    primitive_name: base.Intern_ID,
    arity:          int,
}
```

**Effect:** `List I32` unifies with `Map Str Str` — both are `Inferred_Constructor`,
so unification succeeds. This silently corrupts the type system.

**Fix:** After confirming both sides are `Inferred_Constructor`, check that
`a.primitive_name == b.primitive_name` and `a.arity == b.arity`. If either
differs, emit a diagnostic and return false.

---

### GAP-10: `Inferred_Effect_Row` occurs check skips `effects[].type_args`

**File:** `src/semantics/unify.odin:837-840`
**Severity:** P1 — Missing Error

```odin
case Inferred_Effect_Row:
    if occurs_check_impl(store, target, v.rest_id, visited) {
        return true
    }
    // ← does NOT check v.effects[].type_args
```

The occurs check for effect rows only traverses `rest_id` but not the type
arguments of the effects in the row. Parameterized effects like
`Effect![T]` can create infinite types through the type args.

**Effect:** A type variable appearing in an effect's type argument can be
unified with an effect row containing that same type variable, creating an
infinite type. No occurs check catches it.

**Fix:** Add traversal of each effect entry's type arguments in the
`Inferred_Effect_Row` case of `occurs_check_impl`.

---

## 3. Canonicalization (P1)

### GAP-11: `canonicalize_decl` fallthrough returns empty `CDecl_Const`

**File:** `src/semantics/canonicalize.odin:~285`
**Severity:** P1 — Missing Error

Unhandled `Decl` variants fall through to:

```odin
return CDecl(CDecl_Const{})  // empty const — no name, no body, no type
```

No diagnostic is emitted. The empty const is added to the canonical IR and
propagated downstream.

**Effect:** Adding a new declaration variant without updating canonicalization
silently produces a meaningless empty constant.

**Fix:** Emit a diagnostic in the default case. Convert to total switch or add
an explicit error case.

---

### GAP-12: `canonicalize_expr` fallthrough returns `CExpr_Int{span=ZERO}`

**File:** `src/semantics/canonicalize.odin:~980`
**Severity:** P1 — Missing Error

Same pattern as GAP-6 but in the canonicalizer. Unknown `Expr` variants become
integer 0 with `Source_Span_ZERO`.

**Fix:** Emit a diagnostic and return a sentinel error expression.

---

### GAP-13: `canonicalize_pattern` fallthrough returns `CPattern_Wildcard`

**File:** `src/semantics/canonicalize.odin`
**Severity:** P1 — Missing Error

Unknown pattern variants silently become wildcards. Any bindings the pattern
introduces are lost.

**Fix:** Emit a diagnostic in the default case.

---

### GAP-14: `generate_derive_stubs` silently skips unknown derive names

**File:** `src/semantics/canonicalize.odin`
**Severity:** P1 — Missing Error

The default `case:` in the derive switch produces no stub and no error. A
typo like `derives [Eqq]` is silently ignored — no `eq` method is generated,
and no diagnostic tells the user their derive was unrecognized.

**Fix:** Emit "unrecognized derive" diagnostic for unknown derive names.

---

## 4. Pattern Coverage / Exhaustiveness (P1)

### GAP-15: `collect_pattern_coverage` treats Record/List/Destructure/Tuple as non-matching

**File:** `src/semantics/check_control.odin:305-306`
**Severity:** P1 — Missing Error

```odin
case ^CPattern_Record, ^CPattern_List, ^CPattern_Destructure, ^CPattern_Tuple:
    // ← empty body
```

These pattern types contribute **nothing** to the coverage state. For
exhaustiveness checking, this means:
- A match where all arms use record patterns is reported as non-exhaustive
  (even though records are structurally exhaustive)
- Redundancy checking ignores these patterns entirely

**Effect:** False "non-exhaustive match" warnings on valid code. Missing
"redundant arm" warnings on invalid code.

**Fix:** Implement coverage tracking for each pattern type:
- **Record:** Mark saturated if the record type is closed (no rest field)
- **List:** Track length-based coverage
- **Destructure:** Recurse into sub-patterns
- **Tuple:** Recurse into each element's coverage

---

### GAP-16: `typecheck_pattern` fallthrough returns `TPattern_Wildcard{span=ZERO}`

**File:** `src/semantics/check_control.odin:~250`
**Severity:** P1 — Missing Error

Same pattern as GAP-6/12. Unknown pattern variants silently become wildcards,
losing all bindings.

**Fix:** Emit a diagnostic and return an error pattern.

---

## 5. Codegen (P0)

### GAP-17: `emit_binop` — Div/Mod/Exp emit wrong opcode

**File:** `src/codegen/emit_expr.odin:2331-2332`
**Severity:** P0 — Wrong Code

```odin
case .Div, .Mod, .Exp:
    emit_instruction(Wasm_I64_Add{}, buf)
```

Division, modulo, and exponentiation all emit `i64.add`. This produces
**silently wrong arithmetic** at runtime — `10 / 3 = 13` instead of `3`.

**Fix:** Emit `Wasm_I64_Div_S` for `.Div`, `Wasm_I64_Rem_S` for `.Mod`, and
implement exponentiation as a runtime call (WASM has no native exp instruction
for integers).

---

### GAP-18: `emit_binop` — no F64 arithmetic paths

**File:** `src/codegen/emit_expr.odin:2263-2333`
**Severity:** P0 — Wrong Code

All binop cases only handle I32 and I64. There are **no F64 paths**. F64
addition, subtraction, multiplication, and comparison all use integer opcodes.

**Effect:** `3.14 + 1.0` emits `i32.add` on bit-patterns — produces garbage.

**Fix:** Add F64 branches for each arithmetic/comparison operator:
`Wasm_F64_Add`, `Wasm_F64_Sub`, `Wasm_F64_Mul`, `Wasm_F64_Div`, `Wasm_F64_Eq`,
etc.

---

### GAP-19: `IR_Expr_Nominal_Construct` emits `Wasm_Unreachable`

**File:** `src/codegen/emit_expr.odin:~2257`
**Severity:** P0 — Wrong Code

Nominal type construction always traps at runtime. This means any code using
newtypes (which are core to Camp's type system) crashes immediately.

**Fix:** Nominal construction should emit the same code as the inner type
(constructing the payload), since newtypes are erased at runtime. Or, if
newtypes have a different representation, implement the correct construction
sequence.

---

### GAP-20: `IR_Method_Call` emits `exit(1)` + `Wasm_Unreachable`

**File:** `src/codegen/emit_expr.odin:~1498`
**Severity:** P0 — Wrong Code

Method calls (UFCS dispatch) crash the program. No compile-time error is
emitted — the trap only fires at runtime.

**Fix:** Method calls should be resolved during monomorphization/lowering to
direct function calls. If they reach codegen, that's a compiler bug — emit a
diagnostic instead of silently generating a trap.

---

### GAP-21: `IR_Decl_Const` non-literal initializers silently dropped

**File:** `src/codegen/codegen.odin:780-782`
**Severity:** P0 — Wrong Code

```odin
case:   // non-literal const value
    delete(init_buf)
    continue
```

Constants with non-literal initializers (e.g., `const x = someCall()`) are
silently skipped. The const name gets no global, and any reference to it in
later code will fail to resolve or use a stale value.

**Fix:** Non-literal consts need to be emitted as globals with a `_start`-time
initialization sequence, or lowered to `let` bindings in the init function.

---

### GAP-22: `collect_locals` misses `IR_Wait.timeout`

**File:** `src/codegen/emit_expr.odin:102-104`
**Severity:** P0 — Wrong Code

```odin
case ^ir.IR_Wait:
    collect_locals(e.base, locals)
    collect_locals(e.expected, locals)
    // ← e.timeout NOT traversed
```

`IR_Wait` has a `timeout: IR_Expr` field (defined at `ir.odin:114`). Any local
variables referenced inside the timeout expression won't get stack slots
allocated. At runtime, accessing these locals via the wrong offset corrupts
the stack.

**Fix:** Add `collect_locals(e.timeout, locals)` to the `IR_Wait` case.

---

## 6. IR / Lowering (P0 / P2)

### GAP-23: `TPattern_Destructure` loses all nested bindings

**File:** `src/ir/lower.odin:1289-1292`
**Severity:** P0 — Wrong Code

```odin
case ^semantics.TPattern_Destructure:
    result := new(IR_Pat_Var)
    result.name = base.Intern_ID(0)    // ← zero = effectively a wildcard
    return IR_Pattern(result)
```

Destructuring patterns (e.g., `Point(x, y)`) are lowered to a single variable
binding with name 0 — effectively a wildcard. **All inner bindings are lost.**

**Effect:** `let Point(x, y) = point` compiles but `x` and `y` are never bound.
References to them will fail or resolve to wrong values.

**Fix:** Lower destructure patterns to nested `IR_Pat_Var` nodes or a
destructuring IR node that extracts each field.

---

### GAP-24: `TPattern_Char` lowered to `IR_Pat_Int`

**File:** `src/ir/lower.odin:1264`
**Severity:** P2 — Semantic Hole

Char patterns are lowered as integer patterns, losing the distinction between
char and int. This is likely intentional (WASM has no native char type) but
means char-specific error messages and semantics are lost.

**Fix:** Consider adding `IR_Pat_Char` as a type alias for `IR_Pat_Int` with a
tag, or document this as an intentional erasure.

---

### GAP-25: `lower_texpr` fallthrough returns `make_ir_lit_int(0, ...)`

**File:** `src/ir/lower.odin` (end of `lower_texpr`)
**Severity:** P1 — Missing Error

Same pattern as GAP-6/11/12. Unknown `TExpr` variants silently become integer 0.

**Fix:** Emit a diagnostic and return an error expression node.

---

### GAP-26: `lower_tmethod_call` receiver fallthrough

**File:** `src/ir/lower.odin:~730, ~803`
**Severity:** P2 — Semantic Hole

Two `#partial switch` on the receiver expression extract `receiver_type_var` for
intrinsic method resolution. Unhandled receiver variants (e.g., tuple
expressions, block expressions) get `receiver_type_var = 0`, causing intrinsic
method resolution to fail silently.

**Effect:** `myTuple.len()` compiles but `.len()` is not resolved.

**Fix:** Either handle all receiver types or emit a diagnostic when the
receiver type cannot be determined.

---

### GAP-27: `IR_Construct_Tuple` not handled in effect lowering

**File:** `src/ir/effect_lower.odin`
**Severity:** P0 — Wrong Code

`IR_Construct_Tuple` is **absent** from:
1. The main `el_lower_expr` switch — falls through to `return expr` unchanged
2. The `el_replace_resume` switch — resume calls inside tuple elements are not
   rewritten

This means:
- A `perform` inside a tuple element won't get the evidence-passing transform,
  so the handler's continuation won't receive the right evidence
- A `resume` inside a tuple element won't be rewritten to pass the evidence,
  causing a stack mismatch at runtime

**Fix:** Add `IR_Construct_Tuple` case to both switches in effect_lower.odin.
For `el_lower_expr`, recursively lower each element. For `el_replace_resume`,
traverse into each element.

---

### GAP-28: `IR_Expr_Nominal_Construct` not handled in effect lowering

**File:** `src/ir/effect_lower.odin:1205`
**Severity:** P2 — Semantic Hole

`IR_Expr_Nominal_Construct` appears only in the `IR_Let` value fall-through
list (which runs the default "lower body" path). It has no explicit case in
`el_lower_expr`, so its children are never recursively lowered.

If a nominal construct's payload contains a `perform`, the evidence-passing
transform is skipped.

**Fix:** Add explicit case for `IR_Expr_Nominal_Construct` in `el_lower_expr`
that recursively lowers each payload element.

---

## 7. Parser — Syntax Recipe Features Not Yet Parsed (P3)

These features are defined in the syntax recipe but the parser doesn't
recognize them. They will produce parse errors if used.

| # | Feature | Recipe § | Notes |
|---|---------|----------|-------|
| 29 | As-patterns: `x @ Tag(y)` | §5 | No `@` in pattern position |
| 30 | String pattern interpolation | §5 | Pattern strings with `${expr}` |
| 31 | Lambda where-clauses: `\|x\| -> I64 where T: Eq` | §4 | No `where` in lambda |
| 32 | Effect aliases: `effect alias E = Row` | §3 | No `alias` in effect def |
| 33 | Newtype where-clauses & method blocks | §3 | `newtype Foo[T] where T: Ord { ... }` |
| 34 | Type alias type params: `type Alias[T] = ...` | §3 | `Decl_Alias` has no `type_params` |
| 35 | Bitwise shift operators: `<<`, `>>` | §1 | Not in operator precedence table |
| 36 | Type wildcard `_` in type position | §2 | `Type_Wildcard` AST node defined but never produced |

---

## 8. AST — Dead Nodes (P3)

| # | Node | File | Status |
|---|------|------|--------|
| 37 | `Expr_Record_Update` | `ast.odin:408` | Defined but **never produced** by parser |
| 38 | `Type_Wildcard` | `ast.odin:566` | Defined but **never produced** by parser |
| 39 | `Pattern_Record` `..rest` | — | Has no rest-name field; `..rest` syntax in records not supported |

Note: `CExpr_Record_Update` **is** handled by the typechecker (GAP reference:
`typecheck.odin:433`), but since the parser never produces `Expr_Record_Update`,
that code path is unreachable.

---

## 9. Summary by Severity

### P0 — Wrong Code (must fix before any correctness claim)

| ID | Area | Description |
|----|------|-------------|
| 1 | typecheck | `verify_trait_conformance` never called |
| 17 | codegen | Div/Mod/Exp emit `i64.add` |
| 18 | codegen | No F64 arithmetic opcodes |
| 19 | codegen | Nominal construct always traps |
| 20 | codegen | Method calls always crash |
| 21 | codegen | Non-literal consts silently dropped |
| 22 | codegen | `collect_locals` misses `IR_Wait.timeout` → stack corruption |
| 23 | lower | Destructure patterns lose all bindings |
| 27 | effect_lower | `IR_Construct_Tuple` not lowered for effects |

### P1 — Missing Error (accepts invalid input silently)

| ID | Area | Description |
|----|------|-------------|
| 2 | typecheck | Perform args not unified against effect signature |
| 3 | typecheck | Nominal construct type never resolved |
| 4 | typecheck | Unknown binop accepted |
| 5 | typecheck | Unknown prefix op accepted |
| 6 | typecheck | Unknown CExpr variant → `TExpr_Int{0}` |
| 9 | unify | Constructor unification ignores name/arity |
| 10 | unify | Effect row occurs check skips type args |
| 11 | canonicalize | Unknown Decl → empty `CDecl_Const` |
| 12 | canonicalize | Unknown Expr → `CExpr_Int{0}` |
| 13 | canonicalize | Unknown Pattern → wildcard |
| 14 | canonicalize | Unknown derive names silently skipped |
| 15 | check_control | Record/List/Destructure/Tuple patterns not tracked for exhaustiveness |
| 16 | check_control | Unknown pattern variant → wildcard |
| 25 | lower | Unknown TExpr → `IR_Literal_Int{0}` |

### P2 — Semantic Hole (partial implementation)

| ID | Area | Description |
|----|------|-------------|
| 7 | typecheck | Second-pass switch is all no-ops |
| 8 | typecheck | Effect safety only checks `main!`, stops at first |
| 24 | lower | Char patterns → int patterns (erasure) |
| 26 | lower | Method call receiver fallthrough for complex types |
| 28 | effect_lower | Nominal construct children not recursively lowered |

### P3 — Not Yet Parsed

| ID | Feature | Recipe § |
|----|---------|----------|
| 29-36 | See Section 7 | Various |
| 37-39 | Dead AST nodes | See Section 8 |

---

## 10. Recommended Fix Priority

1. **P0 codegen bugs first** — GAP-17/18 (wrong opcodes) and GAP-22 (stack
   corruption) produce silently wrong runtime behavior with no compile-time
   signal. These are the most dangerous because tests may pass by coincidence.

2. **P0 typechecker next** — GAP-1 (trait conformance) and GAP-23 (destructure
   bindings) mean core language features don't work. Programs using traits or
   destructuring patterns compile but produce wrong results.

3. **P1 missing errors** — Convert all `#partial switch` fallthroughs to
   explicit error-emitting defaults. This is the single highest-impact
   structural fix: it ensures future gaps are caught immediately rather than
   silently.

4. **P0 effect lowering** — GAP-27 (tuples in effect lowering) only affects
   code that uses both tuples and effects in combination. Important but less
   likely to be hit than the arithmetic bugs.

5. **P2 semantic holes** — Lower priority but should be addressed to prevent
   confusion.

6. **P3 parser gaps** — Implement as the language design stabilizes and test
   coverage demands them.

---

## 11. Structural Fix: Eliminate `#partial switch` Fallthroughs

The root cause of most P1 gaps is the use of `#partial switch` in dispatch
functions. In Odin, a `#partial switch` silently skips unhandled union tags
at runtime. This is safe when the set of variants is truly exhaustive in the
handler, but the compiler pipeline has **8 separate dispatch functions** that
use `#partial switch` fallthroughs as implicit "unreachable" paths — and they're
wrong every time a new variant is added.

**Proposed structural fix:**

For each dispatch function that processes a union type:
1. Convert `#partial switch` to total `switch`
2. Add an explicit `case:` that emits a diagnostic and returns a sentinel
   error value
3. Optionally, add a compile-time `@(require)` annotation to ensure the switch
   is exhaustive

This ensures that adding a new AST/IR variant immediately triggers a compiler
developer-visible error rather than silently producing wrong code.


---

# Part II: Detailed Fix Plans

Below is a concrete, file-and-line-level implementation plan for every gap
identified in Part I. Each plan specifies: the exact code change, any new
diagnostics needed, test strategy, and dependencies on other fixes.

---

## 12. GAP-1: `verify_trait_conformance` never called

**Files:** `src/semantics/check_decl.odin`
**Dependencies:** None

### Step 1: Call `verify_trait_conformance` from the `CDecl_Is_Impl` handler

In `typecheck_decl` at the `case ^CDecl_Is_Impl:` branch (line 261), after
typechecking all method bodies and constructing the `TDecl_Is_Impl`, add:

```odin
// After constructing methods, verify conformance
type_module := d.type_name.module
if type_module == base.NO_NAME {
    type_module = env.current_module
}
ok := verify_trait_conformance(d.type_name.name, type_module, d.trait_name.name, d.span, store, env)
if !ok {
    // Conformance check already emitted diagnostics.
    // Continue with the impl so downstream passes don't crash on nil.
}
```

### Step 2: Populate method params from trait declaration

Replace `params = make([dynamic]TFunc_Param, 0)` with actual parameter info
from the trait. After verifying the trait exists in `store.trait_registry`,
look up each method's param types and populate them:

```odin
trait_info, trait_found := store.trait_registry[d.trait_name.name]
for m, i in d.methods {
    body_result := typecheck_synth(m.body, env, store)
    params := make([dynamic]TFunc_Param, 0)
    if trait_found {
        for tmethod in trait_info.methods {
            if tmethod.name == m.name {
                for j, pid in tmethod.param_types {
                    append(&params, TFunc_Param{
                        name = /* generate param name from index */,
                        type_ = lower_type(store, pid),
                        span = m.span,
                    })
                }
                break
            }
        }
    }
    methods[i] = TIs_Method {
        name   = m.name,
        params = params,
        body   = body_result.texpr,
        type_  = lower_type(store, body_result.var_id),
        eff_   = lower_effect_type(store, body_result.effects),
        is_pub = false,
        span   = m.span,
    }
}
```

### Step 3: Remove the dead second-pass or activate it

In `typecheck_file` (line 194-205), either:
- **Option A (recommended):** Delete the dead second-pass loop entirely. The
  conformance check now happens inline during `typecheck_decl`.
- **Option B:** Add `case ^CDecl_Is_Impl:` to the second pass and call
  `verify_trait_conformance` there for post-hoc validation.

### New diagnostics needed

None -- `verify_trait_conformance` already uses `diag_orphan_rule_violation`,
`diag_overlapping_instance`, `diag_missing_trait_method`, and
`diag_trait_method_signature_mismatch`.

### Test strategy

1. **Negative test:** `is Eq for NonexistentType { ... }` should error
2. **Negative test:** `is Eq for MyType { eq = ... }` where `eq` has wrong
   signature should error with signature mismatch
3. **Negative test:** Orphan impl in different module should error
4. **Positive test:** Valid `is` impl with correct method signatures compiles
5. **Duplicate test:** Two `is` impls for same type+trait produces overlapping error

---

## 13. GAP-2: `CExpr_Perform` args never unified against effect signature

**Files:** `src/semantics/typecheck.odin`
**Dependencies:** None

### Step 1: Add effect operation signature table to Type_Store

In `src/semantics/types.odin`, add to `Type_Store`:

```odin
effect_op_signatures: map[base.Intern_ID]Effect_Op_Signature
```

where:

```odin
Effect_Op_Signature :: struct {
    param_types: []base.Type_Var_ID,
    return_type: base.Type_Var_ID,
}
```

### Step 2: Populate the table during `CDecl_Effect` typechecking

In `typecheck_decl`'s `case ^CDecl_Effect:` branch, after typechecking each
operation, store its signature indexed by the operation's intern ID.

### Step 3: Unify perform args against the signature

At `case ^CExpr_Perform:` (line 757), replace the `_ = arg_result` pattern:

```odin
op_sig, op_found := store.effect_op_signatures[e.op]
if op_found {
    if len(e.args) != len(op_sig.param_types) {
        diagnostics.collector_add_diag(
            store.collector,
            diagnostics.diag_arity_mismatch(
                /*expected=*/len(op_sig.param_types),
                /*actual=*/len(e.args),
                e.span,
            ),
        )
    }
    for arg, i in e.args {
        arg_result := typecheck_synth(arg, env, store)
        if i < len(op_sig.param_types) {
            unify(store, arg_result.var_id, op_sig.param_types[i])
        }
        args_t[i] = arg_result.texpr
    }
    // Unify the perform result with the declared return type
    instantiate_return := instantiate(store, op_sig.return_type)
    unify(store, var_id, instantiate_return)
} else {
    // Effect not found -- still typecheck args for cascading errors
    for arg, i in e.args {
        arg_result := typecheck_synth(arg, env, store)
        args_t[i] = arg_result.texpr
    }
}
```

### Step 4: Add effect to the effect row

Also add the performed effect to the `effects` row. Currently `var_id, effects`
is a fresh variable pair -- the effect should be recorded:

```odin
// Add the effect to the inferred effect row
effect_row_var := resolve_var(store, effects)
rv := store.vars[int(effect_row_var)]
if inf, ok := rv.link.(Inferred_Type); ok {
    if er, ok2 := inf.(Inferred_Effect_Row); ok2 {
        append(&er.effects, Effect_Row_Entry{name = e.effect.name, type_args = {}})
        rv.link = Inferred_Type(er)
    }
}
```

### New diagnostics needed

- `diag_undefined_effect` already exists (constructors.odin:1227)
- Arity mismatch: `diag_arity_mismatch` already exists
- Type mismatch from unification: already emitted by `unify`

### Test strategy

1. `perform Console.println!(42)` where `println!` expects `Str` -> type error
2. `perform Console.println!()` with wrong arity -> arity error
3. `perform UnknownEffect.op!()` -> undefined effect error
4. Valid perform with correct args -> compiles, effect appears in type

---

## 14. GAP-3: `CExpr_Nominal_Construct` never resolves `type_name`

**Files:** `src/semantics/typecheck.odin`, `src/semantics/check_expr.odin`
**Dependencies:** None

### Step 1: Resolve `type_name` against bindings

In both `typecheck_synth` (line 398) and `typecheck_nominal_construct`
(check_expr.odin:374), after creating the fresh type var, resolve the type name:

```odin
// Resolve the type name
resolved_var, found := env_lookup(env, e.type_name.name)
if !found {
    found = (e.type_name.name in store.bindings)
    if found {
        resolved_var = store.bindings[e.type_name.name]
    }
}
if found {
    unify(store, type_var, resolved_var)
} else {
    type_str := base.intern_get(store.interner, e.type_name.name)
    diagnostics.collector_add_diag(
        store.collector,
        diagnostics.diag_undefined_type(type_str, "newtype", e.span),
    )
}
```

### Step 2: Apply same fix to `typecheck_nominal_construct` helper

The same fix must be applied to the standalone `typecheck_nominal_construct`
function in `check_expr.odin` (line 374-396), which has the identical bug.

### New diagnostics needed

`diag_undefined_type` already exists (constructors.odin:1209).

### Test strategy

1. `@Nonexistent.Foo(42)` -> "undefined type" error
2. `@KnownType.Variant(value)` where `KnownType` exists -> compiles, type resolved
3. `@KnownType.WrongVariant(value)` where variant doesn't exist -> should error
   (this is a separate gap -- variant validation not yet implemented)

---

## 15. GAP-4 & GAP-5: Binop/Prefixop default cases accept all operators

**Files:** `src/semantics/check_expr.odin`
**Dependencies:** None

### Step 1: Emit diagnostic in `typecheck_binop` default case

At `check_expr.odin:230-232`:

```odin
case:
    // Unknown operator -- should never happen if the parser is correct.
    op_str := fmt.tprintf("{}", e.op)
    diagnostics.collector_add_diag(
        store.collector,
        diagnostics.diag_internal(
            fmt.tprintf("unhandled binary operator in typechecker: {}", op_str),
            e.span,
        ),
    )
    result_var = left_result.var_id
```

### Step 2: Same for `typecheck_prefixop` default case

At `check_expr.odin:266-269`:

```odin
case:
    op_str := fmt.tprintf("{}", e.op)
    diagnostics.collector_add_diag(
        store.collector,
        diagnostics.diag_internal(
            fmt.tprintf("unhandled prefix operator in typechecker: {}", op_str),
            e.span,
        ),
    )
    result_var = operand_result.var_id
    result_eff = operand_result.effects
```

### New diagnostics needed

`diag_internal` already exists. Alternatively, add a more specific
`diag_unknown_operator` for user-facing clarity if this path can be reached
from user code (it shouldn't be, but defensive programming).

### Test strategy

1. This is a compiler-internal safety net. No user-level test can reach this
   path currently since the parser only produces known operators.
2. Add a unit test that constructs a `CExpr_BinOp` with an invalid op and
   verifies the internal diagnostic is emitted.

---

## 16. GAP-6: `typecheck_synth` fallthrough returns `TExpr_Int{span=ZERO}`

**Files:** `src/semantics/typecheck.odin`
**Dependencies:** None

### Step 1: Add error-emitting default at the end of `typecheck_synth`

Replace lines 884-893:

```odin
// Unhandled CExpr variant -- compiler bug
var_id, eff := fresh_with_effects(store, base.Source_Span_ZERO)
diagnostics.collector_add_diag(
    store.collector,
    diagnostics.diag_internal(
        "unhandled CExpr variant in typecheck_synth",
        base.Source_Span_ZERO,
    ),
)
// Return a fresh error type so downstream doesn't crash
return Synth_Result{var_id = var_id, effects = eff, texpr = nil}
```

Note: returning `nil` for `texpr` requires verifying that all callers of
`typecheck_synth` handle nil. Alternatively, return a `TExpr_Crash` node that
will trap at runtime, ensuring the bug is visible rather than silent.

### Step 2: Convert to total switch (recommended)

Replace `#partial switch` with total `switch` on `CExpr`. This will cause a
compile-time error in Odin when a new variant is added, forcing the developer
to update the typechecker.

### New diagnostics needed

`diag_internal` already exists.

### Test strategy

Unit test: construct a CExpr union with only an unhandled variant tag and
verify the internal diagnostic fires.

---

## 17. GAP-7: `typecheck_file` second-pass switch is all no-ops

**Files:** `src/semantics/typecheck.odin`
**Dependencies:** GAP-1

### Step 1: Remove the dead second-pass loop

Delete lines 194-205. The conformance check is now done inline during
`typecheck_decl` (GAP-1 fix). This loop serves no purpose and is confusing.

### Alternative: Keep and activate

If post-hoc validation is desired (e.g., forward references), keep the loop
but add actual checks:
- `CDecl_Newtype`: verify all referenced types exist
- `CDecl_Is_Impl`: call `verify_trait_conformance`
- `CDecl_Trait`: verify parent traits exist

**Recommendation:** Remove. Post-hoc checks should be added to `typecheck_decl`
directly, not in a separate loop.

### Test strategy

Existing tests should pass unchanged (this is dead code removal).

---

## 18. GAP-8: `check_effect_safety` only checks `main!`, stops at first

**Files:** `src/semantics/typecheck.odin`
**Dependencies:** None

### Step 1: Collect all unhandled effects before reporting

Replace the early `return` at line 1549:

```odin
unhandled: [dynamic]string
for entry in it_effect.effects {
    if !is_prelude_effect_by_entry(entry.name, store.interner) {
        effect_str := base.intern_get(store.interner, entry.name)
        append(&unhandled, effect_str)
    }
}
if len(unhandled) > 0 {
    effects_str := format_effect_row(store, effect_var)
    for effect_str in unhandled {
        diagnostics.collector_add_diag(
            store.collector,
            diagnostics.diag_unhandled_effect_entry(effect_str, effects_str, td.span),
        )
    }
}
```

### Step 2: Extend to check all entrypoints

Currently only `main!` is checked. Extend to check any `pub` const with
effectful type (or any function marked as an entrypoint). Replace:

```odin
if td.name.name != main_name {
    continue
}
```

with a check for all entrypoint candidates. For now, this means all `pub`
top-level `main!` declarations. Future: configurable entrypoint names.

### Test strategy

1. `main!` with 3 unhandled effects -> should see 3 diagnostics, not 1
2. Multiple entrypoints with unhandled effects -> each checked

---

## 19. GAP-9: `Inferred_Constructor` unification ignores `primitive_name`/`arity`

**Files:** `src/semantics/unify.odin`
**Dependencies:** None

### Step 1: Compare fields after type check

At `unify.odin:204-216`, replace:

```odin
case Inferred_Constructor:
    b_cons, ok := b.(Inferred_Constructor)
    if !ok {
        // ... existing type_mismatch diagnostic ...
        return false
    }
    a_cons := a.(Inferred_Constructor)
    if a_cons.primitive_name != b_cons.primitive_name {
        type_a_str := format_inferred_type(store, a_id)
        type_b_str := format_inferred_type(store, b_id)
        va_var := store.vars[int(resolve_var(store, a_id))]
        vb_var := store.vars[int(resolve_var(store, b_id))]
        diagnostics.collector_add_diag(
            store.collector,
            diagnostics.diag_type_mismatch(type_a_str, type_b_str, va_var.span, vb_var.span),
        )
        return false
    }
    if a_cons.arity != b_cons.arity {
        va_var := store.vars[int(resolve_var(store, a_id))]
        diagnostics.collector_add_diag(
            store.collector,
            diagnostics.diag_arity_mismatch(a_cons.arity, b_cons.arity, va_var.span),
        )
        return false
    }
```

### Step 2: Unify type arguments

After name+arity match, if both constructors have type parameters (tracked
via the constructor's linked type vars), those should also be unified. This
requires access to the type parameters, which are stored in the
`Inferred_Newtype` for newtypes or in `store.newtype_decls`.

For now, the name+arity check prevents `List I32` unifying with `Map Str Str`.
Full param unification can be a follow-up.

### New diagnostics needed

`diag_type_mismatch` and `diag_arity_mismatch` already exist.

### Test strategy

1. Unify `List I32` with `Map Str Str` -> type mismatch error
2. Unify `List I32` with `List Str` -> should work (same constructor, different
   param -- this requires further work but at least names match)
3. Unify `List I32` with `List I32` -> succeeds

---

## 20. GAP-10: `Inferred_Effect_Row` occurs check skips `effects[].type_args`

**Files:** `src/semantics/unify.odin`
**Dependencies:** None

### Step 1: Traverse effect type arguments in occurs check

At `unify.odin:837-840`:

```odin
case Inferred_Effect_Row:
    if occurs_check_impl(store, target, v.rest_id, visited) {
        return true
    }
    // Also check type arguments of each effect entry
    for entry in v.effects {
        for type_arg in entry.type_args {
            if occurs_check_impl(store, target, type_arg, visited) {
                return true
            }
        }
    }
```

This requires checking what `Effect_Row_Entry` looks like:

```odin
Effect_Row_Entry :: struct {
    name:      base.Intern_ID,
    type_args: []base.Type_Var_ID,  // <- these need traversal
}
```

If `type_args` is a `[]base.Type_Var_ID`, each element should be traversed.
If it's empty for non-parameterized effects, the loop is a no-op, so this
is safe to add unconditionally.

### New diagnostics needed

None -- the occurs check failure is already reported by the caller.

### Test strategy

1. Define a parameterized effect `Effect![T]` and attempt to unify `T` with
   an effect row containing `Effect![T]` -> should report infinite type
2. Normal effect row unification without cycles -> works as before

---

## 21. GAP-11: `canonicalize_decl` fallthrough returns empty `CDecl_Const`

**Files:** `src/semantics/canonicalize.odin`
**Dependencies:** None

### Step 1: Emit diagnostic in fallthrough

At `canonicalize.odin:293-298`:

```odin
// Unhandled Decl variant
diagnostics.collector_add_diag(
    collector,
    diagnostics.diag_internal("unhandled Decl variant in canonicalize_decl", base.Source_Span_ZERO),
)
cdecl := new(CDecl_Const)
cdecl^ = CDecl_Const {
    span = base.Source_Span_ZERO,
}
return cdecl
```

### Step 2: Convert to total switch

Replace `#partial switch` with total `switch`. Odin will enforce exhaustiveness
at compile time, so adding a new Decl variant will require updating this
function.

### Test strategy

Compile-time guarantee via total switch. No runtime test needed.

---

## 22. GAP-12: `canonicalize_expr` fallthrough returns `CExpr_Int{span=ZERO}`

**Files:** `src/semantics/canonicalize.odin`
**Dependencies:** None

### Step 1: Same fix as GAP-11

At `canonicalize.odin:1135-1140`, add diagnostic emission before the sentinel:

```odin
diagnostics.collector_add_diag(
    collector,
    diagnostics.diag_internal("unhandled Expr variant in canonicalize_expr", base.Source_Span_ZERO),
)
```

### Step 2: Convert to total switch

### Test strategy

Same as GAP-11.

---

## 23. GAP-13: `canonicalize_pattern` fallthrough returns `CPattern_Wildcard`

**Files:** `src/semantics/canonicalize.odin`
**Dependencies:** None

### Step 1: Same fix pattern

At `canonicalize.odin:1282-1287`, add diagnostic and convert to total switch.

### Test strategy

Same as GAP-11.

---

## 24. GAP-14: `generate_derive_stubs` silently skips unknown derive names

**Files:** `src/semantics/canonicalize.odin`
**Dependencies:** None

### Step 1: Emit diagnostic in default case

At `canonicalize.odin:1505`:

```odin
case:
    // Unknown derive target
    diagnostics.collector_add_diag(
        collector,
        diagnostics.diag_internal(
            fmt.tprintf("unrecognized derive: `{}`", derive_name_str),
            d.span,
        ),
    )
```

Better: create a user-facing `diag_unrecognized_derive`:

```odin
diag_unrecognized_derive :: proc(name: string, span: base.Source_Span) -> Diagnostic {
    d := Diagnostic{
        category = .Error,
        message = fmt.tprintf("unrecognized derive: `{}`", name),
        labels = make([dynamic]Label, 1),
        hints = make([dynamic]string, 1),
        span = span,
    }
    append(&d.hints, "available derives: Eq, Clone, Hash, Ord")
    return d
}
```

### Test strategy

1. `derives [Eqq]` -> "unrecognized derive: Eqq" error with hint
2. `derives [Eq]` -> works as before

---

## 25. GAP-15: `collect_pattern_coverage` ignores Record/List/Destructure/Tuple

**Files:** `src/semantics/check_control.odin`
**Dependencies:** None

### Step 1: Implement coverage for each pattern type

At `check_control.odin:305-306`:

**Record patterns:**
```odin
case ^CPattern_Record:
    // A closed record pattern (no rest) covers all fields.
    // Mark as saturated only if the record type is known to be closed.
    if p.rest == nil {
        cov.saturated = true
    }
    for f in p.fields {
        collect_pattern_coverage(f.pattern, cov)
    }
```

**List patterns:**
```odin
case ^CPattern_List:
    // List patterns are never exhaustive (infinite type).
    // Recurse for redundancy detection.
    for el in p.elements {
        collect_pattern_coverage(el, cov)
    }
```

**Destructure patterns:**
```odin
case ^CPattern_Destructure:
    // Destructure is exhaustive if the inner pattern is exhaustive.
    collect_pattern_coverage(p.inner, cov)
```

**Tuple patterns:**
```odin
case ^CPattern_Tuple:
    // Tuple patterns are exhaustive (structurally complete).
    cov.saturated = true
    for el in p.elements {
        collect_pattern_coverage(el, cov)
    }
```

### Step 2: Add `rest` field to `CPattern_Record` if missing

Check if `CPattern_Record` has a `rest` field. If not, add one:
```odin
rest: CPattern,  // nil if no `..rest` in the pattern
```
This is needed to distinguish `{| x, y |}` (exhaustive) from `{| x, ..rest |}` (not exhaustive).

### Test strategy

1. Match on a record type with all fields present -> no non-exhaustive warning
2. Match on a record type with `..rest` -> non-exhaustive warning
3. Match on a tuple -> no non-exhaustive warning
4. Match on a list -> non-exhaustive (lists are infinite)

---

## 26. GAP-16: `typecheck_pattern` fallthrough returns `TPattern_Wildcard{span=ZERO}`

**Files:** `src/semantics/check_control.odin`
**Dependencies:** None

### Step 1: Emit diagnostic in default case

Same pattern as GAP-6/11/12. Add `diag_internal` at the fallthrough point.
Convert to total switch if possible.

### Test strategy

Same as GAP-11.

---

## 27. GAP-17: `emit_binop` -- Div/Mod/Exp emit wrong opcode

**Files:** `src/codegen/emit_expr.odin`
**Dependencies:** None

### Step 1: Add correct Div/Mod opcodes

At `emit_expr.odin:2331-2332`:

```odin
case .Div:
    if operand_type == .I32 {
        emit_instruction(Wasm_I32_Div_S{}, buf)
    } else {
        emit_instruction(Wasm_I64_Div_S{}, buf)
    }
case .Mod:
    if operand_type == .I32 {
        emit_instruction(Wasm_I32_Rem_S{}, buf)
    } else {
        emit_instruction(Wasm_I64_Rem_S{}, buf)
    }
case .Exp:
    // WASM has no native integer exponentiation.
    // Emit a runtime call to camp_int_exp.
    // TODO: implement camp_int_exp runtime function
```

### Step 2: Implement `camp_int_exp` runtime function

Add to `src/codegen/runtime.odin`:

```odin
emit_camp_int_exp :: proc(buf: ^[dynamic]u8, operand_type: base.IR_Wasm_Type) {
    // Simple exponentiation by squaring loop.
    // Pseudocode: result = 1; base = arg0; exp = arg1;
    //   while exp > 0: if exp & 1: result *= base; base *= base; exp >>= 1
    // ... emit wasm bytecode for this loop ...
}
```

Alternatively, use the existing runtime function infrastructure (like
`camp_list_len`) to emit a call to an imported function.

### Test strategy

1. `10 / 3` -> emits `i64.div_s`, runtime result = 3
2. `10 % 3` -> emits `i64.rem_s`, runtime result = 1
3. `2 ^ 10` -> runtime result = 1024 (once exp runtime is implemented)
4. Existing e2e tests that use division should now produce correct results

---

## 28. GAP-18: `emit_binop` -- no F64 arithmetic paths

**Files:** `src/codegen/emit_expr.odin`
**Dependencies:** None

### Step 1: Add F64 branches to all arithmetic operators

For each operator in `emit_binop`, add an F64 path. Example for `.Add`:

```odin
case .Add:
    switch operand_type {
    case .I32: emit_instruction(Wasm_I32_Add{}, buf)
    case .I64: emit_instruction(Wasm_I64_Add{}, buf)
    case .F64: emit_instruction(Wasm_F64_Add{}, buf)
    }
```

Complete list of needed F64 opcodes:

| Operator | I32 | I64 | F64 |
|----------|-----|-----|-----|
| Add | `Wasm_I32_Add` | `Wasm_I64_Add` | `Wasm_F64_Add` |
| Sub | `Wasm_I32_Sub` | `Wasm_I64_Sub` | `Wasm_F64_Sub` |
| Mul | `Wasm_I32_Mul` | `Wasm_I64_Mul` | `Wasm_F64_Mul` |
| Div | `Wasm_I32_Div_S` | `Wasm_I64_Div_S` | `Wasm_F64_Div` |
| Mod | `Wasm_I32_Rem_S` | `Wasm_I64_Rem_S` | N/A (F64 has no rem) |
| Exp | runtime call | runtime call | `Wasm_F64_Mul` loop or runtime |
| Eq | `Wasm_I32_Eq` | `Wasm_I64_Eq` | `Wasm_F64_Eq` |
| Ne | `Wasm_I32_Ne` | `Wasm_I64_Ne` | `Wasm_F64_Ne` |
| Lt | `Wasm_I32_Lt_S` | `Wasm_I64_Lt_S` | `Wasm_F64_Lt` |
| Gt | `Wasm_I32_Gt_S` | `Wasm_I64_Gt_S` | `Wasm_F64_Gt` |
| Le | `Wasm_I32_Le_S` | `Wasm_I64_Le_S` | `Wasm_F64_Le` |
| Ge | `Wasm_I32_Ge_S` | `Wasm_I64_Ge_S` | `Wasm_F64_Ge` |
| And | `Wasm_I32_And` | `Wasm_I64_And` | N/A |
| Or | `Wasm_I32_Or` | `Wasm_I64_Or` | N/A |

Note: F64 has no `Rem` (modulo) -- `Mod` on F64 should emit a runtime call to
`fmod` or similar. F64 `And`/`Or` are bitwise and don't apply to floats.

### Step 2: Also add F32 if needed

Check if the compiler targets F32. If so, add those paths too.

### Test strategy

1. `3.14 + 1.0` -> emits `f64.add`, runtime result approx 4.14
2. `3.14 < 1.0` -> emits `f64.lt`, runtime result = 0 (false)
3. `10.0 / 3.0` -> emits `f64.div`, runtime result approx 3.333...
4. `3.14 % 1.0` -> runtime call, result approx 0.14

---

## 29. GAP-19: `IR_Expr_Nominal_Construct` emits `Wasm_Unreachable`

**Files:** `src/codegen/emit_expr.odin`
**Dependencies:** Understanding of newtype runtime representation

### Step 1: Emit payload code instead of unreachable

Nominal types (newtypes) in Camp are **erased at runtime** -- they have the
same representation as their inner type. The nominal construct should just
emit the payload value:

```odin
case ^ir.IR_Expr_Nominal_Construct:
    // Newtypes are identity wrappers at runtime.
    // If variant == 0, it's a simple wrap: emit the single payload value.
    // If variant != 0, it's a qualified variant: emit as a tag construct.
    if e.variant == 0 && len(e.payload) == 1 {
        return emit_expr(e.payload[0], ctx)
    }
    // Qualified variant: emit as tag construct
    // ... (reuse existing tag construct emission)
```

### Step 2: Handle multi-payload nominal constructs

If the newtype has multiple payload fields (e.g., a newtype wrapping a record),
emit a record/tuple construct instead:

```odin
if e.variant == 0 && len(e.payload) > 1 {
    // Emit as a heap-allocated tuple/record
    // ... reuse existing record emission code
}
```

### Design decision needed

The exact emission depends on how newtypes are represented in the WASM module:
- **Option A:** Complete erasure -- `@MyInt(42)` is just `42` on the stack
- **Option B:** Tagged representation -- `@MyInt(42)` is a 2-word struct (tag + value)

**Recommendation:** Option A (complete erasure). This matches the syntax recipe's
design of newtypes as zero-cost abstractions. The `@` syntax is only for
construction/destruction at the type level; at runtime, the value is the inner
type.

### Test strategy

1. `const x: MyInt = @MyInt(42)` -> compiles and runs, `x` holds 42
2. `@MyPair(1, 2)` wrapping a tuple -> compiles and runs
3. Existing newtype tests should pass

---

## 30. GAP-20: `IR_Method_Call` emits `exit(1)` + `Wasm_Unreachable`

**Files:** `src/codegen/emit_expr.odin`, `src/ir/lower.odin`
**Dependencies:** None

### Step 1: Method calls should not reach codegen

Method calls (UFCS dispatch) should be resolved to direct function calls
during monomorphization or IR lowering. If they reach codegen, it's a
compiler bug.

### Step 2: Replace exit+unreachable with diagnostic

At `emit_expr.odin:~1498`:

```odin
case ^ir.IR_Method_Call:
    // Method calls should be resolved before codegen.
    // If we get here, it's a compiler bug.
    emit_instruction(Wasm_Unreachable{}, ctx.output)
```

### Step 3: Fix the root cause -- resolve methods during IR lowering

The real fix is in `src/ir/lower.odin` (`lower_tmethod_call`). Currently,
intrinsic methods (`.len()`, `.slice()`) are resolved, but non-intrinsic
methods fall through without resolution. Add resolution for trait methods:

```odin
// In lower_tmethod_call, after intrinsic method resolution fails:
method_name := e.method.name
resolved_fn := resolve_trait_method(env.store, receiver_type_var, method_name)
if resolved_fn != base.NO_NAME {
    // Lower as a direct call
    ir_args := make([dynamic]IR_Expr, 0, len(e.args) + 1)
    append(&ir_args, receiver_ir)
    for arg in e.args {
        append(&ir_args, lower_texpr(arg, env))
    }
    call := new(IR_Call)
    call^ = IR_Call {
        callee = base.Canonical_Name{module = base.NO_NAME, name = resolved_fn, is_local = true},
        args = ir_args,
        type = e.type_,
        span = e.span,
    }
    return IR_Expr(call)
}
```

### Test strategy

1. `myStr.len()` -> resolved to intrinsic, works
2. `myList.map(f)` -> resolved to trait method call, works
3. `myCustomType.myMethod()` -> resolved to impl function, works
4. Method call reaching codegen -> unreachable trap (compiler bug visible)

---

## 31. GAP-21: `IR_Decl_Const` non-literal initializers silently dropped

**Files:** `src/codegen/codegen.odin`
**Dependencies:** None

### Step 1: Emit non-literal consts as `_start`-time initialization

Replace the `case:` default at `codegen.odin:780-782`:

```odin
case:
    // Non-literal const: emit as a mutable global initialized in _start
    valtype = .I64  // default
    emit_instruction(Wasm_I64_Const{value = 0}, &init_buf)
    // Schedule init code for _start:
    append(&ctx.pending_const_inits, Const_Init{
        name = c.name,
        value_expr = c.value,
    })
```

This requires:
1. Adding a `pending_const_inits` field to the codegen context
2. Emitting the initialization code in the `_start` function
3. Making the global mutable so it can be written at startup

### Step 2: Alternative -- lower non-literal consts to `let` bindings

If the `_start`-time initialization approach is too complex, an alternative
is to lower non-literal consts to `let` bindings inside `_start` during the
IR lowering phase. This avoids the codegen complexity entirely.

In `src/ir/lower.odin`, during `lower_tdecl_const`, if the const value is not
a literal, emit an `IR_Let` binding in the `_start` function body instead of
an `IR_Decl_Const`.

### Design decision needed

- **Option A:** Mutable global + `_start` init -- preserves const semantics
  (global scope, addressable)
- **Option B:** Lower to `let` in `_start` -- simpler, but loses global
  addressability (can't take a reference to the const)

**Recommendation:** Option A for correctness. Camp constants should be
addressable (e.g., `&MY_CONST`), which requires global scope.

### Test strategy

1. `const x = 42` -> emitted as immutable global (existing behavior)
2. `const x = someCall()` -> emitted as mutable global initialized in `_start`
3. `const x = anotherConst + 1` where `anotherConst` is a non-literal ->
   proper initialization ordering in `_start`

---

## 32. GAP-22: `collect_locals` misses `IR_Wait.timeout`

**Files:** `src/codegen/emit_expr.odin`
**Dependencies:** None

### Step 1: Add timeout traversal

At `emit_expr.odin:102-104`:

```odin
case ^ir.IR_Wait:
    collect_locals(e.base, locals)
    collect_locals(e.expected, locals)
    collect_locals(e.timeout, locals)    // <- ADD THIS LINE
```

This is a one-line fix. `IR_Wait.timeout` is an `IR_Expr` field (defined at
`ir.odin:114`).

### Test strategy

1. Write a program using `AtomicWait` with a timeout expression that
   references a local variable
2. Before fix: local in timeout is not allocated a stack slot ->
   stack corruption or trap
3. After fix: local is allocated, program runs correctly
4. Add a unit test to `test_codegen.odin` that verifies `collect_locals`
   traverses all sub-expressions of `IR_Wait`

---

## 33. GAP-23: `TPattern_Destructure` loses all nested bindings

**Files:** `src/ir/lower.odin`
**Dependencies:** None

### Step 1: Lower destructure to nested field accesses + let bindings

At `lower.odin:1289-1292`, replace the wildcard lowering with proper
destructure lowering. First, verify the `TPattern_Destructure` structure
in `src/semantics/typed.odin` -- it likely has a list of sub-patterns that
correspond to the fields of the destructured type.

**If `TPattern_Destructure` has named sub-patterns:**

```odin
case ^semantics.TPattern_Destructure:
    result := new(IR_Pat_Record)
    result.fields = make([dynamic]IR_Pat_Field, 0, len(p.fields))
    for field_pat in p.fields {
        append(&result.fields, IR_Pat_Field{
            name    = field_pat.name,
            pattern = lower_tpattern(field_pat.pattern, env),
        })
    }
    result.rest = nil
    return IR_Pattern(result)
```

**If `TPattern_Destructure` has positional sub-patterns:**

```odin
case ^semantics.TPattern_Destructure:
    result := new(IR_Pat_Tuple)
    result.elements = make([dynamic]IR_Pat_Tuple_Element, 0, len(p.sub_patterns))
    for sub_pat in p.sub_patterns {
        append(&result.elements, IR_Pat_Tuple_Element{
            pattern = lower_tpattern(sub_pat, env),
        })
    }
    return IR_Pattern(result)
```

### Step 2: Verify the TPattern_Destructure structure

Read `src/semantics/typed.odin` to determine the exact fields before
implementing. The correct lowering depends on whether destructuring is
named or positional.

### Test strategy

1. `let Point(x, y) = point` -> `x` and `y` are properly bound
2. Nested destructure: `let Point(Point(a, b), c) = deep_point` -> all three
   bindings work
3. Destructure in match arm: `case Point(x, y) => x + y` -> correct

---

## 34. GAP-24: `TPattern_Char` lowered to `IR_Pat_Int`

**Files:** `src/ir/lower.odin`
**Dependencies:** None

### Step 1: Document as intentional erasure

At `lower.odin:1267-1270`, add a comment:

```odin
case ^semantics.TPattern_Char:
    // Char patterns are lowered as integer patterns.
    // WASM has no native char type; chars are represented as i64 (Unicode codepoint).
    // This is an intentional erasure -- char-specific error messages are lost,
    // but runtime behavior is correct since char comparison is integer comparison.
    result := new(IR_Pat_Int)
    result.value = i64(p.value)
    return IR_Pattern(result)
```

No code change needed -- this is intentional. The char-to-int erasure is
correct for WASM's type system.

### Test strategy

1. Match on `'a'` -> matches codepoint 97 -- correct
2. Match on emoji multi-byte char -> matches correct codepoint -- correct

---

## 35. GAP-25: `lower_texpr` fallthrough returns `make_ir_lit_int(0, ...)`

**Files:** `src/ir/lower.odin`
**Dependencies:** None

### Step 1: Emit diagnostic in fallthrough

At the end of `lower_texpr` (after the total `switch` block):

```odin
// Unreachable -- total switch should handle all variants.
// This is a safety net for compiler bugs.
fmt.println("WARNING: lower_texpr fell through switch -- unhandled TExpr variant")
return make_ir_lit_int(...)
```

Since the switch is total, this code should be unreachable. Consider replacing
with `unreachable()` for a harder failure during development, or keep the
soft fallback for production builds.

### Test strategy

No user-level test -- this is a compiler safety net.

---

## 36. GAP-26: `lower_tmethod_call` receiver fallthrough

**Files:** `src/ir/lower.odin`
**Dependencies:** None

### Step 1: Consolidate all TExpr variants into extraction group

At `lower.odin:803-836`, the receiver switch extracts `receiver_type_var`
from `r.type_.type_id`. All TExpr variants have a `type_` field. The
fallthrough group (lines 814-835) should also extract the type var.

**Simplest fix:** Move all variants from the fallthrough group into the
extraction group, since they all have `type_`:

```odin
#partial switch r in e.receiver {
case ^semantics.TExpr_Name,
     ^semantics.TExpr_String,
     ^semantics.TExpr_Method_Call,
     ^semantics.TExpr_Field_Access,
     ^semantics.TExpr_Call,
     ^semantics.TExpr_Int,
     ^semantics.TExpr_Float,
     ^semantics.TExpr_Bool,
     ^semantics.TExpr_Tag,
     ^semantics.TExpr_Nominal_Construct,
     ^semantics.TExpr_Record,
     ^semantics.TExpr_List,
     ^semantics.TExpr_Lambda,
     ^semantics.TExpr_Block,
     ^semantics.TExpr_If,
     ^semantics.TExpr_Match,
     ^semantics.TExpr_BinOp,
     ^semantics.TExpr_PrefixOp,
     ^semantics.TExpr_Record_Update,
     ^semantics.TExpr_Assign,
     ^semantics.TExpr_Return,
     ^semantics.TExpr_Crash,
     ^semantics.TExpr_Interpolated_String,
     ^semantics.TExpr_Handle,
     ^semantics.TExpr_Perform,
     ^semantics.TExpr_For,
     ^semantics.TExpr_Par,
     ^semantics.TExpr_Tuple,
     ^semantics.TExpr_Field_Index:
    receiver_type_var = r.type_.type_id
}
```

### Step 2: Apply same fix to the second receiver switch

There's a second `#partial switch` on the receiver around line 730 (the
qualified-tag-construct path). Apply the same consolidation.

### Test strategy

1. `myTuple.len()` -> receiver type extracted, intrinsic resolved if applicable
2. `(complexExpr).someMethod()` -> receiver type extracted
3. All existing method call tests pass

---

## 37. GAP-27: `IR_Construct_Tuple` not handled in effect lowering

**Files:** `src/ir/effect_lower.odin`
**Dependencies:** None

### Step 1: Add `IR_Construct_Tuple` case to `el_lower_expr`

In `el_lower_expr` (line 838+), add after the `IR_Construct_Record` case:

```odin
case ^IR_Construct_Tuple:
    new_elements := make([dynamic]IR_Expr, 0, len(e.elements))
    for el in e.elements {
        append(&new_elements, el_lower_expr(el, env))
    }
    new_tuple := new(IR_Construct_Tuple)
    new_tuple^ = IR_Construct_Tuple {
        elements   = new_elements,
        reuse_addr = e.reuse_addr,
        type       = e.type,
        span       = e.span,
    }
    return IR_Expr(new_tuple)
```

### Step 2: Add `IR_Construct_Tuple` case to `el_replace_resume`

In `el_replace_resume` (line 276+), add:

```odin
case ^IR_Construct_Tuple:
    new_elements := make([dynamic]IR_Expr, 0, len(e.elements))
    for el in e.elements {
        append(&new_elements, el_replace_resume(el, resume_id, resume_param, ev_param, env))
    }
    new_tuple := new(IR_Construct_Tuple)
    new_tuple^ = IR_Construct_Tuple {
        elements   = new_elements,
        reuse_addr = e.reuse_addr,
        type       = e.type,
        span       = e.span,
    }
    return IR_Expr(new_tuple)
```

### Step 3: Add `IR_Construct_Tuple` to the `IR_Let` value fall-through list

At `effect_lower.odin:1194-1228`, add `^IR_Construct_Tuple` to the list of
non-perform IR_Let values that get the default body-lowering treatment.

### Test strategy

1. `perform` inside a tuple element -> evidence passing works correctly
2. `resume` inside a tuple element -> gets rewritten to pass evidence
3. Tuple with no effects inside -> works as before (identity transform)
4. Existing effect handling tests should pass

---

## 38. GAP-28: `IR_Expr_Nominal_Construct` not handled in effect lowering

**Files:** `src/ir/effect_lower.odin`
**Dependencies:** None

### Step 1: Add explicit case in `el_lower_expr`

After the `IR_Construct_Tag` case in `el_lower_expr`:

```odin
case ^IR_Expr_Nominal_Construct:
    new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
    for p in e.payload {
        append(&new_payload, el_lower_expr(p, env))
    }
    new_cons := new(IR_Expr_Nominal_Construct)
    new_cons^ = IR_Expr_Nominal_Construct {
        type_name = e.type_name,
        variant   = e.variant,
        payload   = new_payload,
        span      = e.span,
    }
    return IR_Expr(new_cons)
```

### Step 2: Add to `el_replace_resume`

```odin
case ^IR_Expr_Nominal_Construct:
    new_payload := make([dynamic]IR_Expr, 0, len(e.payload))
    for p in e.payload {
        append(&new_payload, el_replace_resume(p, resume_id, resume_param, ev_param, env))
    }
    new_cons := new(IR_Expr_Nominal_Construct)
    new_cons^ = IR_Expr_Nominal_Construct {
        type_name = e.type_name,
        variant   = e.variant,
        payload   = new_payload,
        span      = e.span,
    }
    return IR_Expr(new_cons)
```

### Test strategy

1. `perform` inside a nominal construct payload -> evidence passing works
2. `resume` inside a nominal construct payload -> gets rewritten
3. Nominal construct with no effects -> identity transform

---

## 39. GAP-29 through GAP-36: Parser -- Syntax Recipe Features Not Yet Parsed

These are all P3 (not yet parsed). Implementation requires parser changes.
Each is described with the specific parser modifications needed.

### GAP-29: As-patterns (`x @ Tag(y)`)

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Parser change:** In `parse_pattern()`, when the current token is an
identifier and the next token is `@`, consume the `@` and parse the right-hand
pattern, then produce `Pattern_As{name = left_id, inner = right_pattern}`.

**AST change:** Add to `ast.odin`:
```odin
Pattern_As :: struct {
    name:  base.Intern_ID,
    inner: Pattern,
    span:  base.Source_Span,
}
```
Add `Pattern_As` to the `Pattern` union.

**Downstream:** Update canonicalize, typecheck, and lower to handle
`Pattern_As` -- bind the name, then recursively process the inner pattern.

### GAP-30: String pattern interpolation

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Parser change:** In `parse_pattern()`, when parsing a string literal in
pattern position, scan for `${...}` interpolation and produce
`Pattern_Interpolated_String{parts = ...}`.

**AST change:** Reuse `String_Part` from `Expr_Interpolated_String`:
```odin
Pattern_String :: struct {
    parts:  []String_Part,  // mix of String_Segment and Pattern
    span:   base.Source_Span,
}
```

**Downstream:** Typecheck each interpolated pattern part. Unify with `Str`.

### GAP-31: Lambda where-clauses

**Files:** `src/frontend/parser.odin`

**Parser change:** After parsing the lambda body, if `where` keyword follows,
parse where-clauses. Add them to the lambda AST node's `where_clauses` field.

**No AST change needed** -- `Expr_Lambda` already has `where_clauses` field
(check `ast.odin`). The parser just doesn't populate it.

### GAP-32: Effect aliases

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Parser change:** In `parse_decl()`, after `effect`, check for `alias`
keyword. If present, parse as effect alias declaration.

**AST change:** Add `Decl_Effect_Alias`:
```odin
Decl_Effect_Alias :: struct {
    name:   base.Intern_ID,
    target: Type,
    is_pub: bool,
    span:   base.Source_Span,
}
```

**Downstream:** Typechecker resolves the alias. During effect row
substitution, expand aliases to their target row.

### GAP-33: Newtype where-clauses & method blocks

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Parser change:** After parsing newtype type params, check for `where`
keyword and parse where-clauses. After the inner type, check for `{` and
parse method declarations.

**AST change:** Add `where_clauses` and `methods` fields to `Decl_Newtype`:
```odin
Decl_Newtype :: struct {
    // ... existing fields ...
    where_clauses: []Where_Clause,
    methods:      []Newtype_Method,
    // ...
}
```

### GAP-34: Type alias type params

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Parser change:** In `parse_decl()` for type aliases, parse `[T]` type
params after the alias name.

**AST change:** Add `type_params` field to `Decl_Alias`:
```odin
Decl_Alias :: struct {
    name:        Canonical_Name,
    is_pub:      bool,
    target:      Type,
    type_params: []Intern_ID,  // <- ADD
    doc_comment: string,
    span:        Source_Span,
}
```

**Downstream:** Typechecker creates type params as fresh type variables.
Canonicalizer propagates them. Lower skips alias decls (already the case).

### GAP-35: Bitwise shift operators (`<<`, `>>`)

**Files:** `src/frontend/lexer.odin`, `src/frontend/parser.odin`,
`src/semantics/check_expr.odin`, `src/codegen/emit_expr.odin`

**Lexer change:** Add `<<` and `>>` as double-token operators.

**Parser change:** Add to operator precedence table (between comparison and
additive, following standard precedence).

**Typechecker change:** Add `case .Lt_Lt, .Gt_Gt:` to `typecheck_binop` --
constrain operands to integer types, result is left operand type.

**Codegen change:** Add `Shl`/`Shr` to `IR_BinOp_Kind`. Emit `Wasm_I32_Shl`/
`Wasm_I64_Shl`/`Wasm_I32_Shr_S`/`Wasm_I64_Shr_S`.

### GAP-36: Type wildcard `_` in type position

**Files:** `src/frontend/parser.odin`

**Parser change:** In `parse_type()`, when the token is `_`, produce
`Type_Wildcard`. The AST node already exists (`ast.odin:566`).

**Downstream:** Typechecker: `Type_Wildcard` becomes a fresh type variable
(`fresh_value_var`). This is the same as an omitted type annotation --
it requests inference.

---

## 40. GAP-37 through GAP-39: Dead AST Nodes

### GAP-37: `Expr_Record_Update` -- defined but never produced

**Files:** `src/frontend/parser.odin`, `src/frontend/ast.odin`

**Option A: Implement record update syntax**

In the parser, after parsing a record literal `{ field: value, ... }`, check
if it begins with an expression (e.g., `{ expr | field: value, ... }`).
If so, parse as `Expr_Record_Update{record = expr, updates = [...]}`.

The syntax recipe Section 4 (Record Literal) specifies record update as
`{ record | field = value }`.

**Option B: Remove the dead node**

If record update is not a priority, remove `Expr_Record_Update` from the AST
union, the typechecker handler (`typecheck_record_update`), and all
downstream code. Re-add when needed.

**Recommendation:** Implement (Option A). Record update is in the syntax
recipe and the typechecker already handles it.

### GAP-38: `Type_Wildcard` -- defined but never produced

**Files:** Same as GAP-36. Fix is the same -- implement `_` in type position.

### GAP-39: `Pattern_Record` missing `..rest` field

**Files:** `src/frontend/ast.odin`, `src/frontend/parser.odin`

**AST change:** Add `rest_name` field to `Pattern_Record`:
```odin
Pattern_Record :: struct {
    fields:   [dynamic]Pattern_Record_Field,
    rest:     base.Intern_ID,  // 0 if no `..rest`, otherwise the rest binding name
    span:     base.Source_Span,
}
```

**Parser change:** When parsing a record pattern, after all fields, check for
`..` followed by an identifier. If present, set `rest` to that identifier.

**Downstream:** In canonicalize/typecheck, the rest binding captures all
unmatched fields as a sub-record. In lower, generate a record construction
from the unmatched fields.

---

## 41. Structural Fix: Convert All `#partial switch` Fallthroughs

This is the single highest-leverage change. It prevents future gaps from being
introduced silently.

### Target functions (in priority order)

| # | File | Function | Current Behavior | Fix |
|---|------|----------|-------------------|-----|
| 1 | `typecheck.odin` | `typecheck_synth` | `#partial switch` returns `TExpr_Int{0}` | Convert to total `switch`, add error case |
| 2 | `typecheck.odin` | `typecheck_decl` | `#partial switch` to `unreachable()` | Verify exhaustiveness |
| 3 | `check_expr.odin` | `typecheck_binop` | `#partial switch` passes left type | Add error-emitting `case:` |
| 4 | `check_expr.odin` | `typecheck_prefixop` | `#partial switch` passes operand type | Add error-emitting `case:` |
| 5 | `canonicalize.odin` | `canonicalize_decl` | `#partial switch` returns empty `CDecl_Const` | Convert to total `switch` |
| 6 | `canonicalize.odin` | `canonicalize_expr` | `#partial switch` returns `CExpr_Int{0}` | Convert to total `switch` |
| 7 | `canonicalize.odin` | `canonicalize_pattern` | `#partial switch` returns `CPattern_Wildcard` | Convert to total `switch` |
| 8 | `check_control.odin` | `typecheck_pattern` | `#partial switch` returns `TPattern_Wildcard{0}` | Convert to total `switch` |
| 9 | `check_control.odin` | `collect_pattern_coverage` | `#partial switch` empty body | Add missing cases |
| 10 | `lower.odin` | `lower_texpr` | total `switch` returns `make_ir_lit_int(0, ...)` | Add `unreachable()` or assert |
| 11 | `lower.odin` | `lower_tmethod_call` (x2) | `#partial switch` sets `receiver_type_var = 0` | Consolidate all variants |
| 12 | `effect_lower.odin` | `el_lower_expr` | `#partial switch` returns `return expr` | Add all missing cases |
| 13 | `effect_lower.odin` | `el_replace_resume` | `#partial switch` returns `return expr` | Add all missing cases |
| 14 | `emit_expr.odin` | `emit_expr` | `#partial switch` emits no code | Add error-emitting default |
| 15 | `emit_expr.odin` | `collect_locals` | `#partial switch` skips sub-exprs | Add all missing cases |
| 16 | `codegen.odin` | decl dispatch loop | `#partial switch` skips consts/effects | Add all missing cases |

### Implementation strategy

**Phase 1: Add diagnostic-emitting defaults to all `#partial switch` functions**

For each function, add a `case:` at the end that:
1. Emits `diag_internal` with the function name and "unhandled variant"
2. Returns a sentinel value that won't silently corrupt downstream passes

**Phase 2: Convert to total `switch` where safe**

Where the union type is fully known (AST, IR, TExpr unions), convert to
total `switch`. Odin enforces exhaustiveness at compile time.

**Phase 3: Add compile-time coverage tests**

For each dispatch function, add a test that verifies every union variant is
handled. This can be done by constructing each variant and ensuring no
internal diagnostic is emitted.

---

## 42. Implementation Order

Ordered by impact and dependency:

| Phase | GAPs | Description |
|-------|------|-------------|
| **1** | 17, 18, 22 | Codegen P0 bugs: wrong opcodes + stack corruption. One-liner and mechanical fixes. |
| **2** | 27, 28 | Effect lowering P0: add tuple/nominal cases. Mechanical recursive lowering. |
| **3** | 9, 10 | Unification P1: constructor name/arity check + effect row occurs check. |
| **4** | 6, 11, 12, 13, 16, 25 | All fallthrough defaults: add diagnostic emission. Structural safety net. |
| **5** | 1 | Trait conformance: call `verify_trait_conformance`. Largest semantic fix. |
| **6** | 23 | Destructure patterns: implement proper lowering. Requires reading TPattern_Destructure. |
| **7** | 2 | Perform arg unification. Requires effect signature table. |
| **8** | 3 | Nominal construct type resolution. Requires env_lookup. |
| **9** | 4, 5, 14 | Binop/prefixop/derive defaults: add diagnostics. Small targeted fixes. |
| **10** | 15 | Pattern exhaustiveness: implement coverage for Record/List/Destructure/Tuple. |
| **11** | 7, 8 | Dead second-pass removal + effect safety improvements. |
| **12** | 19, 20, 21 | Codegen P0 remaining: nominal construct, method calls, non-literal consts. Requires design decisions. |
| **13** | 24, 26 | Semantic holes: char erasure (document), receiver fallthrough. |
| **14** | 29-39 | Parser P3: implement syntax recipe features. Can be parallelized. |
| **15** | Structural | Convert all `#partial switch` to total `switch` + add coverage tests. |
