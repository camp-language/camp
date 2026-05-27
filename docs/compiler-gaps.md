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
