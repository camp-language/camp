# Algebraic Effects Implementation Specification

## 1. Overview

This spec defines the implementation plan for algebraic effect handlers in Camp — making effects execute end-to-end from source through WASM code generation. The design follows Koka-style evidence passing (Xie & Leijen, ICFP 2020/2021) with one-shot continuations (OCaml 5-style).

**Current state**: The full front-end pipeline (lexing, parsing, canonicalization, typechecking) handles effect syntax. The back-end (effect_lower, CPS, codegen) has scaffolding but nothing works — `IR_Handle`, `IR_Perform`, and `IR_Method_Call` all compile to `Wasm_Unreachable`.

**Target**: Effect handlers execute correctly in generated WASM. A program like:

```camp
main! = || -[Console | Throw([..])]-> I64 {
    handle Console in {
        Console.println!("Hello, Camp!")
        0
    } with {
        .println!(resume, msg) => {
            wasi_write(msg)
            resume({})
        }
    }
}
```

compiles to a WASM module that prints "Hello, Camp!" and exits 0.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Dispatch mechanism | Evidence passing (Koka-style) | O(1) handler lookup via function table index; no runtime stack walking; compatible with WASM linear memory |
| Continuation model | One-shot (OCaml 5-style) | Sufficient for Throw, Console, Async; no stack copying; simpler WASM codegen; runtime trap on double-resume |
| Operation kinds | All `ctl` initially | Simpler first implementation; `fun`/`val` optimization (tail-resumptive ops compiled as direct calls) deferred without semantic change |
| Evidence layout | Closure records (`fn_idx + env_ptr`) | Handlers close over state; each arm is a closure (function pointer + environment); stored in WASM linear memory |
| Pass architecture | Keep `effect_lower` and `cps` separate | Easier to test/debug each pass independently; same architecture as existing pipeline |
| Deep vs shallow | Deep handlers default (`handle`), shallow via `intercept` | Matches spec §4.4; deep handlers re-install after resume; shallow handlers do not |
| Effect row syntax | `-[Eff1 \| Eff2]->` only | Breaking change from `->{ Eff1, Eff2 }`; aligns with formatter spec; visually distinct from record types; `|` separator consistent with tag unions |
| Handler arm params | `.op!(resume, arg1, arg2) =>` | Resume is the first param; remaining params are the operation's arguments; enables handlers to inspect what was performed |

### 2.1 Why Evidence Passing Over Alternatives

| Approach | Dispatch cost | WASM compatible | Effect safety | Implementation complexity |
|----------|--------------|-----------------|---------------|--------------------------|
| **Evidence passing** (chosen) | O(1) — table index | Yes — explicit params + `call_indirect` | Yes — compile-time row tracking | Moderate |
| Fiber-based (OCaml 5) | O(n) — fiber chain walk | No — needs segmented stack runtime | No — unhandled at runtime | High |
| Runtime search (Eff) | O(n) — handler stack walk | Possible but slow | Yes | Low (interpreter) |

### 2.2 Why One-Shot Over Multi-Shot

Multi-shot continuations (Koka, Eff) enable backtracking and search but require copying the continuation on each additional resume. For WASM:

- Copying means `memcpy` of the environment struct + re-installing evidence — expensive and complex
- One-shot means the continuation closure is consumed on resume — no copying, just `call_indirect` then zero the fn_idx
- Backtracking can be provided later via a dedicated `Choice` effect or explicit state
- OCaml 5 chose one-shot for the same reasons; it covers 90%+ of practical use cases

---

## 3. Syntax Alignment (Phase 0a)

### 3.1 Effect Row Type Syntax: `-[...]->`

**Breaking change**: Replace `->{ Eff1, Eff2 }` with `-[Eff1 | Eff2]->`.

The old syntax uses `{ }` which is ambiguous with record types and uses `,` which is inconsistent with `|`-separated tag unions. The new syntax mirrors tag union brackets and uses `|` separators.

| Before (remove) | After (target) |
|-----------------|----------------|
| `\|x\| -> {IO} Int` | `\|x\| -[IO]-> Int` |
| `\|x\| -> {IO, State} Int` | `\|x\| -[IO \| State]-> Int` |
| `\|x\| -> {e} Int` | `\|x\| -[e]-> Int` |
| `\|x\| -> {Console \| ..}-> Int` | `\|x\| -[Console \| ..]-> Int` |
| `\|x\| -> Int` (pure, no row) | `\|x\| -> Int` (unchanged — empty row is elided) |

**Parsing rules**:
- After `->`, if `-[` follows, parse an effect row
- Effect row: one or more `Upper_Id` separated by `|`, inside `-[ ... ]->`
- Open row: `-[Console | ..]->` (at least Console, possibly more)
- Row variable: `-[e]->` (lowercase, polymorphic)
- Fully open: `-[..]->` (zero or more effects)
- Empty row: elided entirely — `-> Int` means `->[]-Int` (pure)

**Implementation in `parser_parse_function_type`**:
- After `->`, check for `-[` (`.LBrack`) instead of `{` (`.LBrace`)
- Parse names separated by `|` (`.Pipe`) instead of `,` (`.Comma`)
- Expect `]->` as closing sequence: `]` then `->`
- After the effect row, parse the return type

**Estimated scope**: ~40 lines in `parser.odin`, ~20 lines in `format_type.odin`

### 3.2 Handler Arm Parameters: `.op!(resume, args...) =>`

**Current parser**: `.op!(resume) => body` — only one identifier inside parens.

**Target**: `.op!(resume, arg1, arg2, ...) => body` — resume plus the operation's arguments.

A handler for `Console.println!(msg)` needs access to `msg`. The operation's arguments are passed alongside `resume` so the handler can inspect and act on them.

```camp
handle Console in {
    Console.println!("hello")
} with {
    .println!(resume, msg) => {
        // resume: the one-shot continuation
        // msg: the Str argument from Console.println!("hello")
        wasi_write(msg)
        resume({})
    }
}
```

**Rules**:
- `resume` is always the first parameter
- Remaining parameters correspond positionally to the effect operation's parameters
- The `!` after the op name is required (all effect operations carry `!`)
- Parameters are comma-separated inside `()`
- The `=>` fat arrow separates the parameter list from the handler body

**Implementation in `parser_parse_handle`**:
- After `.op!(`, parse a comma-separated list of identifiers
- First identifier is always `resume`
- Store all identifiers in a `params: [dynamic]Intern_ID` field on `Handler_Arm` (replacing the single `resume_id`)

**AST change**:
```
Handler_Arm :: struct {
    op:        Intern_ID,
    params:    [dynamic]Intern_ID,   // was: resume_id: Intern_ID
    body:      Expr,
}
```

The first element of `params` is always `resume`. This replaces the single `resume_id: Intern_ID` field.

**Canonical, IR, and formatter changes**: Propagate the `params` list through all pipeline stages. `IR_Handler_Arm` also gains `params: [dynamic]Intern_ID`.

**Estimated scope**: ~20 lines in `parser.odin`, ~10 lines in `ast.odin`, ~20 lines in `canonicalize.odin`, ~15 lines in `ir.odin`, ~15 lines in `lower.odin`, ~10 lines in `format_expr.odin`, ~10 lines in `effect_lower.odin`, ~10 lines in `cps.odin`, ~10 lines in `closure_convert.odin`, ~10 lines in `rc.odin`

### 3.3 Effect Operation Declarations: No Change

The current parser syntax `effect IO { println!: Str }` matches the language design spec (§4.2) and is correct. The formatter spec's compact rendering (`effect IO { println! readln! }`) is a display choice for simple examples, not a syntax change. The parser continues to require `:` + type after each operation name.

### 3.4 E2E Test Rewrite

All 8 effect-related e2e test files use the oldest syntax and fail at parse time. They need complete rewrite with the correct syntax.

| File | Current syntax | Target syntax |
|------|---------------|---------------|
| `effect-declare-and-handle.camp` | `effect IO { println }` + `handle IO.println("hi") with { IO.println(s) -> resume(()) }` | `effect IO { println!: Str }` + `handle IO in { IO.println!("hi") } with { .println!(resume, s) => resume({}) }` |
| `effect-deep-handler.camp` | Similar | Similar update |
| `effect-perform-return-value.camp` | `effect Ask { read }` | `effect Ask { read!: I64 }` |
| `effect-shallow-handler.camp` | `intercept IO.println(...)` | `intercept IO in { ... } with { .println!(resume, s) => ... }` |
| `effect-multiple-operations.camp` | `effect IO { println, readln }` | `effect IO { println!: Str, readln!: Str }` |
| `effect-multiple-effects.camp` | `effect IO { println }` + `effect State { get, put }` | `effect IO { println!: Str }` + `effect State { get!: I64, put!: I64 }` |
| `effect-unhandled.camp` | `IO.println("hi")` | `IO.println!("hi")` |
| `effect-handler-resume-twice.camp` | `resume(()) resume(())` | Two sequential `resume({})` calls (runtime trap expected for one-shot) |

Also update the typechecking and error test files:
| `effect-declaration.camp` | `effect IO { println }` | `effect IO { println!: Str }` |
| `effectful-function.camp` | `greet! = (name) -> {IO} String { name }` | `greet! = \|name: Str\| -[IO]-> Str { name }` |
| `handle-expression.camp` | `handle IO.println(...) with { ... }` | `handle IO in { ... } with { .println!(resume, s) => ... }` |
| `unhandled-effect.camp` | `main! = \|\| -> I64 { IO.println("hi") 0 }` | `main! = \|\| -[IO]-> I64 { IO.println!("hi") 0 }` |
| `effectful-naming-no-bang.camp` | `main = \|\| -> {IO} I64 { 0 }` | `main = \|\| -[IO]-> I64 { 0 }` |

**Estimated scope**: ~16 files rewritten

---

## 4. Phase 0b: Fix Existing Bugs

Six bugs block effect execution. Fix in this order (from the compiler correctness spec):

### 4.1 H2: `IR_Crash` Node

**Problem**: `CExpr_Crash` discards crash semantics; no `IR_Crash` in the IR union.

**Fix**: Add `IR_Crash` to `IR_Expr`, lower `CExpr_Crash` to `IR_Crash`, add traversal cases in all mid-end passes, codegen emits `Wasm_Unreachable`.

**Scope**: ~15 lines across 6 files

### 4.2 M4: Missing Handler Evidence Parameter

**Problem**: When `IR_Perform` finds no handler on the evidence stack (`ev_var == NO_NAME`), the evidence argument is silently omitted. The handler function expects it but the call site doesn't provide it.

**Fix**: When `ev_var == NO_NAME`, emit a diagnostic and lower the perform to `IR_Literal_Int{0}`. Unhandled performs are caught by the typechecker before `effect_lower` runs, so this case indicates a compiler bug.

**Scope**: ~5 lines in `effect_lower.odin`

### 4.3 M9: Generalization at Level — Unsound Child Levels

**Problem**: `generalize_at_level` marks all variables at level L as `LEVEL_GENERIC` without checking that children of `Inferred_Type` structures are also at level ≤ L.

**Fix**: Add recursive `all_children_at_or_below_level` check before generalizing.

**Scope**: ~45 lines in `types.odin`

### 4.4 C8: Closure Body Nil

**Problem**: Closure conversion creates `IR_Decl_Fn` with `body = IR_Expr(nil)`. The original lambda body is never transferred. Free variables are never captured.

**Fix**: Add `body` field to `IR_Closure`, transfer body during lowering, compute free variables during closure conversion, generate env allocation and field stores.

**Scope**: ~90 lines across `ir.odin`, `lower.odin`, `closure_convert.odin`

### 4.5 C7: Non-Name Callee Lowering

**Problem**: Higher-order calls like `(f x) y` call nonexistent functions. No `call_indirect`.

**Fix**: Add `IR_Closure_Call`, lower non-name callees to it, codegen uses WASM table + `call_indirect`. This is the mechanism resume will use.

**Scope**: ~110 lines across `lower.odin`, `closure_convert.odin`, `codegen.odin`

### 4.6 M5: CPS No Continuations Generated

**Problem**: CPS transform threads continuation names but never creates new continuation functions. Only `IR_Return` becomes a tail-call.

**Fix**: For `IR_Let` where value is an effectful `IR_Call`, generate a continuation function and pass it as an extra argument.

**Scope**: ~60 lines in `cps.odin`

**Exit criterion**: All 117 unit tests + 101 e2e tests pass.

---

## 5. Phase 1: Effect Row Subtraction in Typechecker

### 5.1 Problem

When `typecheck_synth` handles `CExpr_Handle`, it returns a fresh empty effect row instead of computing `{original_row} \ {handled_effect}`. This means the typechecker cannot prove that effects have been handled, making effect safety enforcement unreliable.

### 5.2 Design

After typechecking the handle body:

1. Extract the body's inferred effect row (a `Type_Var_ID` of kind `.Row_Effect`)
2. If the handled effect is explicitly present in the row, remove it
3. If the row has a rest variable, the subtraction preserves it
4. Unify the result with the handle expression's expected effect row
5. For effect-polymorphic rows (variable `e`): create a constraint that `e` minus the handled effect equals the result row

### 5.3 New Helper

```
subtract_effect_from_row(store: ^Type_Store, row: Type_Var_ID, effect: Intern_ID) -> Type_Var_ID
```

Resolves the row. If the effect is found in `effect_names`, remove it and return a new row. If not found (effect already absent), return the row unchanged. If the row is a variable, create a constraint.

### 5.4 Test Cases

```camp
// Single effect removed:
handle E in { E.op!(); x } with { .op!(resume) => resume({}) }
// Body row: {E}. Handle row: {} (E removed).

// Nested handlers:
handle E1 in {
    handle E2 in { E1.op!(); E2.op!() } with { .op!(resume) => resume({}) }
} with { .op!(resume) => resume({}) }
// Inner handle removes E2, leaving {E1}. Outer handle removes E1, leaving {}.

// Effect-polymorphic function inside handle:
map! = <a, b, e>|f: |a| -[e]-> b, xs: List(a)| -[e]-> List(b) { ... }
// e propagates correctly through handle boundaries
```

**Scope**: ~40 lines in `typecheck.odin`

---

## 6. Phase 2: Rewrite `effect_lower` — Evidence Passing

### 6.1 Current Problems

| Problem | Location | Description |
|---------|----------|-------------|
| `make_handler` is a no-op | `effect_lower.odin:105-113` | Calls a nonexistent runtime function |
| Evidence variable is always 0 | `effect_lower.odin:112` | `IR_Literal_Int{value = 0}` |
| Handler names don't match callee names | `effect_lower.odin:76-80, 157-161` | `handler_N` vs `effect.module/op` |
| Resume never connected | `effect_lower.odin:84` | `resume_id` typed as `Funcref` but nothing constructs the continuation |
| Effect row discarded | `lower.odin` | `IR_Decl_Fn.effect_row` is always `IR_Type{.Void, ...}` |

### 6.2 Evidence Passing Design

Each handler arm becomes a **closure** — a function pointer paired with an environment pointer. The collection of handler arm closures forms an **evidence record** — a struct in WASM linear memory that the perform site dispatches through.

#### 6.2.1 Evidence Record Structure

For a `handle` with N arms, the evidence record contains N closure slots:

```
Evidence Record (in WASM linear memory):
┌──────────────────────────────────┐
│ arm_0_fn_idx:  i32               │  ← table index of handler arm function
│ arm_0_env_ptr: i32               │  ← environment pointer (or 0 if no captures)
├──────────────────────────────────┤
│ arm_1_fn_idx:  i32               │
│ arm_1_env_ptr: i32               │
├──────────────────────────────────┤
│ ...                              │
└──────────────────────────────────┘
```

Each slot is 8 bytes (two i32s). The record is allocated via `camp_alloc` and initialized at the `handle` entry point.

#### 6.2.2 Handler Arm Function Signature

Each handler arm function receives:

```
handler_arm(env: i32, op_args..., resume_fn: i32, resume_env: i32, ev: i32) -> result_type
```

| Parameter | Purpose |
|-----------|---------|
| `env` | Handler's captured environment (closed-over variables) |
| `op_args...` | The operation's original arguments (e.g., `msg` for `println!(msg)`) |
| `resume_fn` | Function table index for the one-shot resume continuation |
| `resume_env` | Environment pointer for the resume continuation |
| `ev` | Evidence record pointer (for deep handlers to re-install evidence after resume) |

**Deep handler**: The `ev` parameter points to the same evidence record. When `resume` is called, the resumed computation has the handler still installed (via the same `ev`).

**Shallow handler**: The `ev` parameter is **not** passed to the continuation. The resumed computation runs without the current handler.

#### 6.2.3 Effect Declaration Mapping

The evidence record needs to map operation names to arm indices. This is a compile-time concern:

```
effect Console {
    println!: Str       // arm index 0
    readln!: Str        // arm index 1
}

Evidence record for Console handler:
  [0] = println arm closure (fn_idx, env_ptr)
  [1] = readln arm closure (fn_idx, env_ptr)

IR_Perform Console.println!("hello") dispatches to:
  ev[0].fn_idx(ev[0].env_ptr, "hello", resume_fn, resume_env, ev)
```

The operation-to-index mapping is determined by the effect definition's operation order. The compiler knows the index at compile time.

#### 6.2.4 IR Transformations

**`IR_Handle` becomes**:
1. Generate one `IR_Decl_Fn` per handler arm (the arm's body as a top-level function)
2. Generate evidence record allocation: `let _ev_N = camp_alloc(N * 8)`
3. Generate evidence record initialization: store `fn_idx` and `env_ptr` for each arm
4. Transform the body with `_ev_N` in the evidence environment
5. After the body, deallocate the evidence record: `camp_dealloc(_ev_N, N * 8)`

**`IR_Perform` becomes**:
1. Look up the evidence variable for this effect from the environment
2. Compute the arm index from the operation name (compile-time known)
3. Load `fn_idx = i32.load(ev + arm_index * 8)` and `env_ptr = i32.load(ev + arm_index * 8 + 4)`
4. Generate `IR_Closure_Call` to the loaded closure with arguments: `(env_ptr, op_args..., resume_closure, ev)`

**Resume closure**: At this stage, the resume closure is a placeholder (Phase 3 fills it in). The evidence passing structure is established here; the CPS integration creates the actual continuation closures.

#### 6.2.5 Effect Propagation Through Function Calls

Every effectful function receives evidence parameters. This is the core of evidence passing — handlers are passed as extra arguments rather than looked up at runtime.

**New field on `IR_Decl_Fn`**:

```
IR_Decl_Fn :: struct {
    name:         Canonical_Name,
    is_effectful: bool,
    params:       [dynamic]IR_Param,
    return_type:  IR_Type,
    effects:      [dynamic]Canonical_Name,  // NEW: effects this function may perform
    body:         IR_Expr,
    span:         Source_Span,
}
```

The `effects` field replaces the meaningless `effect_row: IR_Type` (which was always `IR_Type{.Void, ...}`). It's populated during lowering from the typechecker's inferred effect row.

**Calling convention change**:

```
// Before evidence passing:
read_line! = || -> Str { Console.readln!() }

// After evidence passing:
read_line! = (ev_Console: i32) -> Str {
    // Console.readln!() dispatches through ev_Console
}
```

At each call to an effectful function, the caller passes the evidence for each effect in the callee's `effects` list. The evidence is threaded from the caller's own evidence parameters.

**Implementation**:
1. In `lower.odin`: extract effect names from typechecker results, populate `IR_Decl_Fn.effects`
2. In `effect_lower.odin`: for each `IR_Decl_Fn` with non-empty `effects`, prepend evidence params (one `i32` per effect)
3. At each `IR_Call` to an effectful function, append evidence arguments matching the callee's `effects` list
4. At each `IR_Perform`, look up the evidence for the performed effect from the current function's evidence params

**Estimated scope**: ~250-350 lines rewriting `effect_lower.odin`, ~30 lines in `ir.odin`, ~40 lines in `lower.odin`

---

## 7. Phase 5: `Throw` Effect — First Working Effect

**Phase numbering note**: Phase 5 comes before Phase 3 because `Throw` handlers never resume — they don't need the full CPS continuation capture machinery. This gives an early win with a working effect.

### 7.1 `Throw` as a Built-In Effect

Per the language design spec (§4.6), `Throw` is Camp's built-in error effect:

```camp
effect Throw {
    throw! : <a>[a] -[Throw([a])]-> a
}
```

Key properties:
- `Throw.throw!(tag)` performs the `Throw` effect with a tag union argument
- `Throw(NotFound)` and `Throw(BadInput)` are the same effect with different tag union parameters
- The handler catches all `Throw` operations
- **The handler never calls `resume`** — like an exception handler, it either returns a value directly or re-throws

### 7.2 Non-Resuming Handlers — Simpler Than Resuming

A non-resuming handler (like Throw) is simpler because:
- No continuation capture at the perform site
- The handler arm body returns a value directly (no `resume` call)
- The perform site doesn't need a resume closure argument
- The handler arm function signature omits `resume_fn` / `resume_env`

**Handler arm signature for Throw**:
```
handler_throw(env: i32, err: i32, ev: i32) -> result_type
```

No `resume_fn` / `resume_env` parameters. The handler just returns a value.

**Perform site for Throw**:
```
ev[0].fn_idx(ev[0].env_ptr, err_value, ev)
```

No resume closure passed. The handler returns the result directly.

### 7.3 Example Program

```camp
main! = || -[Throw([..])]-> I64 {
    result = handle Throw in {
        Throw.throw!(NotFound)
        42
    } with {
        .throw!(resume, err) => 0
    }
    result
}
```

This compiles and runs. The `Throw.throw!(NotFound)` dispatches to the handler. The handler returns `0`. The `handle` expression evaluates to `0`. `main!` returns `0`.

Note: `resume` is still listed as a parameter in the handler arm syntax (for consistency), but it is never called. The handler body simply returns `0`.

### 7.4 Runtime Handler for Uncaught Throw

When `main!` has `Throw([..])` in its effect row, the runtime provides a default handler that:

1. Receives the thrown tag value
2. Renders the tag name to stderr (via WASI `fd_write`)
3. Exits with code 1 (via WASI `proc_exit`)

This is the runtime "last resort" handler — similar to an unhandled exception handler in other languages.

**Implementation**:
- In `codegen.odin`: when `main!` has `Throw([..])`, emit a handler function that calls WASI `fd_write` + `proc_exit`
- Register it as the evidence for the `Throw` effect
- Pass it as an evidence argument when calling the user's `main!`

### 7.5 Built-In Effect Declaration

`Throw` must be auto-declared in the typechecker's initial environment so it's always available without an explicit `effect Throw { ... }` declaration:

- Register `Throw` in `store.declared_effects`
- Register `throw!` as an operation with the appropriate type
- The parameterized tag union `Throw([e])` uses the type system's existing tag union mechanism

**Estimated scope**: ~100 lines in `codegen.odin` for runtime handler + effectful main, ~50 lines for `Throw` built-in in `typecheck.odin`

---

## 8. Phase 3: CPS Continuation Capture

### 8.1 Add `IR_Resume` Node

```odin
IR_Resume :: struct {
    resume_id: Intern_ID,
    value:     IR_Expr,
    type:      IR_Type,
    span:      Source_Span,
}
```

- Add to `IR_Expr` union in `ir.odin`
- Add traversal cases in: `effect_lower.odin`, `closure_convert.odin`, `cps.odin`, `rc.odin`, `codegen.odin`

**Codegen**: `IR_Resume` compiles to `call_indirect` on the resume closure:

```
1. Load resume_fn_idx from the resume closure record
2. One-shot check: if fn_idx == 0, trap (double-resume)
3. Zero the fn_idx in the resume closure (mark as consumed)
4. Load resume_env_ptr from the resume closure record
5. call_indirect(resume_env_ptr, resume_value, resume_fn_idx)
```

### 8.2 Continuation Capture at Perform Sites

The CPS transform must capture "the rest of the computation" at each `IR_Perform` site and pass it as a resume closure to the handler.

**Transformation for `IR_Let` where value is `IR_Perform`**:

```
// Before CPS:
let x = E.op(y) in g(x)

// After CPS:
let k = closure(fn=kc_fn, env=kc_env) in
  E.op_handler(ev_env, y, k.fn_idx, k.env_ptr, ev)
where kc_fn(env, x) = g(x)
```

**Implementation in `cps_transform_expr`**:

1. For `IR_Let` where value is `IR_Perform`:
   - Create a fresh continuation name `kc`
   - Generate `IR_Decl_Fn{name=kc, params=[x: result_type], body=cps_transform(body, k_name)}`
   - Create a closure record for the continuation: `IR_Closure{fn_name=kc, ...}`
   - Replace the let-perform with a call to the handler arm function, passing the continuation closure
   - The handler arm function signature includes `resume_fn` and `resume_env` parameters
   - Return the handler call as a tail call

2. For `IR_Perform` not in a `let` (e.g., as an argument):
   - Should have been lifted into a let-binding by canonicalization
   - If not, add a lifting step or emit a diagnostic

### 8.3 Deep Handler Semantics in CPS

For a **deep handler**, the handler is re-installed after each resume. This means:

- The captured continuation's environment includes the current evidence record pointer
- When the continuation is called (resume), it restores the evidence record
- Any further `perform` of the same effect within the resumed computation dispatches to the same handler

**Implementation**: The continuation function receives the `ev` parameter and stores it in its environment. When resume is called, the continuation's body runs with `ev` in scope.

### 8.4 Shallow Handler Semantics in CPS

For a **shallow handler** (`intercept`), the handler is NOT re-installed after resume:

- The captured continuation's environment does NOT include the current evidence record pointer
- When the continuation is called (resume), it runs without the current handler
- Any further `perform` of the same effect within the resumed computation propagates to an outer handler

**Implementation**: The continuation function does NOT receive the `ev` parameter. The evidence for the current effect is absent in the continuation's scope.

**Difference in codegen**:
- Deep: `kc_fn(kc_env, x, ev)` — ev is passed
- Shallow: `kc_fn(kc_env, x)` — ev is NOT passed

**Estimated scope**: ~200 lines in `cps.odin`, ~30 lines for `IR_Resume` across `ir.odin` + mid-end passes

---

## 9. Phase 4: WASM Codegen for Effects

### 9.1 Handler Arm Functions → WASM Table Entries

Each handler arm function becomes a WASM function added to the function table:

```wasm
(table $functable 10 funcref)
(elem $table_offset
  (func $handler_println $handler_readln ...))

(func $handler_println
  (param $env i32) (param $msg i32)
  (param $resume_fn i32) (param $resume_env i32)
  (param $ev i32)
  (result i32)
  ...)
```

### 9.2 Evidence Record Allocation + Initialization

Generate WASM code to allocate and initialize the handler closure record:

```wasm
;; Allocate evidence record: N arms × 8 bytes (fn_idx + env_ptr per arm)
(call $camp_alloc (i32.const <N * 8>))
(local.set $ev)

;; Store fn_idx for arm 0 (println handler)
(i32.store (local.get $ev) (i32.const <handler_println_table_idx>))
;; Store env_ptr for arm 0 (captured variables, or 0 if none)
(i32.store (i32.add (local.get $ev) (i32.const 4)) (local.get $handler_env))
;; ... repeat for arm 1, arm 2, ...
```

### 9.3 Perform → `call_indirect` via Evidence

```wasm
;; IR_Perform Console.println!("hello")
;; ev points to evidence record
;; arm_index is compile-time known (0 for println, 1 for readln)

;; Load handler function index: ev[arm_index * 8]
(i32.load (i32.add (local.get $ev) (i32.const <arm_index * 8>)))
(local.set $handler_fn)

;; Load handler environment: ev[arm_index * 8 + 4]
(i32.load (i32.add (local.get $ev) (i32.const <arm_index * 8 + 4>)))
(local.set $handler_env)

;; Call handler with (env, op_args..., resume_fn, resume_env, ev)
(call_indirect (type $handler_sig)
  (local.get $handler_env)
  (local.get $msg)              ;; op arg
  (local.get $resume_fn)        ;; continuation fn_idx
  (local.get $resume_env)       ;; continuation env_ptr
  (local.get $ev)               ;; evidence record (for deep handlers)
  (local.get $handler_fn))      ;; table index
```

### 9.4 Resume → `call_indirect` on Continuation

```wasm
;; IR_Resume(resume_id, value)
;; resume_id refers to a closure record: { fn_idx, env_ptr }

;; Load function index
(i32.load (local.get $resume_closure))
(local.set $resume_fn)

;; One-shot check: if fn_idx == 0, this is a double-resume → trap
(if (i32.eqz (local.get $resume_fn))
  (then
    (call $camp_print_str (i32.const <"one-shot violation">))
    (call $camp_exit (i32.const 1))))

;; Mark as consumed: zero out fn_idx
(i32.store (local.get $resume_closure) (i32.const 0))

;; Load environment pointer
(i32.load (i32.add (local.get $resume_closure) (i32.const 4)))
(local.set $resume_env)

;; Call the continuation
(call_indirect (type $cont_sig)
  (local.get $resume_env)
  (local.get $resume_value)
  (local.get $resume_fn))
```

### 9.5 Effectful Main Codegen

Remove the current behavior where effectful `main!` is replaced with `unreachable`.

Instead:
1. Generate `main!` as a regular function with evidence parameters for each effect in its row
2. Generate a `_start` function that:
   a. Allocates evidence records for each effect in `main!`'s effect row
   b. For `Console`: creates a handler that calls WASI `fd_write`
   c. For `Throw([..])`: creates a handler that prints the tag to stderr and calls `proc_exit(1)`
   d. For other effects: creates a handler that calls `camp_exit(1)` with an "unhandled effect" message
   e. Calls `main!` with the evidence arguments
   f. Returns the result as the WASM exit code

**Estimated scope**: ~300-400 lines in `codegen.odin`

---

## 10. Phase 6: Console Effect + Resuming Handlers

### 10.1 Console Runtime Handler

A `Console` handler maps to WASI `fd_write`:

```camp
effect Console {
    println! : Str -[Console]-> {}
    printerr! : Str -[Console]-> {}
    readln! : || -[Console]-> Str
}
```

The runtime handler for `Console.println!`:
1. Receives `msg` (a string pointer in linear memory)
2. Constructs an `iovec` structure pointing to the string data
3. Calls WASI `fd_write(fd=1, iovs_ptr, iovs_len, nwritten_ptr)` to write to stdout
4. Calls `resume({})` to continue the computation

### 10.2 Example

```camp
main! = || -[Console | Throw([..])]-> I64 {
    handle Console in {
        Console.println!("Hello, Camp!")
        Console.println!("Goodbye!")
        0
    } with {
        .println!(resume, msg) => {
            wasi_write(msg)
            resume({})
        }
    }
}
```

This exercises:
- Resuming handlers (resume called once, in tail position)
- Deep handler semantics (handler re-installed after each resume — both `println!` calls are handled)
- Continuation capture at perform sites (each `println!` captures "the rest of the computation")
- Console handler maps to WASI `fd_write`

**Estimated scope**: ~50 lines for Console runtime handler in `codegen.odin`

---

## 11. Phase 7: Shallow Handlers + State Effect

### 11.1 Shallow Handler Semantics

`intercept` installs a handler that handles **only the first** matching operation. After resume, the handler is NOT re-installed:

```camp
intercept Async in {
    Async.yield!()     // caught by this handler
    Async.yield!()     // NOT caught — propagates to outer handler
} with {
    .yield!(resume) => resume({})
}
```

**Implementation difference from deep**:
- Deep: the evidence record pointer is passed to the continuation (so the handler stays installed)
- Shallow: the evidence record pointer is NOT passed to the continuation (so the handler is gone after resume)

This is a small codegen difference — the continuation function signature has one fewer parameter for shallow handlers.

### 11.2 State Effect

```camp
effect State {
    get! : || -[State]-> I64
    put! : I64 -[State]-> {}
}

run_state = |init: I64, action: || -[State]-> a| -> a {
    $state = init
    handle State in {
        action()
    } with {
        .get!(resume) => resume($state)
        .put!(resume, v) => { $state = v; resume({}) }
    }
}
```

This exercises:
- Handler closures that capture mutable state (`$state`)
- Multiple operations per effect (`get!` and `put!`)
- The handler environment contains the mutable variable

**Estimated scope**: ~50 lines for shallow handler evidence difference, + State effect as stdlib

---

## 12. Implementation Order Summary

| Phase | Name | Scope (lines) | Depends On | What Works After |
|-------|------|---------------|------------|-----------------|
| **0a** | Parser syntax alignment | ~100 | — | Parser accepts `-[...]->` and `.op!(resume, args)` |
| **0b** | Fix existing bugs | ~325 | 0a | Bugs fixed, CPS + closures working |
| **1** | Effect row subtraction | ~40 | 0b | Typechecker correctly models handled effects |
| **2** | Rewrite effect_lower | ~320 | 1 | Evidence passing works, handler records allocated |
| **5** | Throw (non-resuming) | ~150 | 2 | First working effect: exceptions |
| **3** | CPS continuation capture | ~230 | 2 | Resume mechanism works |
| **4** | WASM codegen for effects | ~350 | 3 | Effects execute in WASM |
| **6** | Console (resuming) | ~50 | 4 | I/O works, deep handlers proven |
| **7** | Shallow + State | ~50 | 6 | Full effect system working |

**Total estimated scope**: ~1,615 lines

---

## 13. Key Research References

| Paper | Year | Key Contribution | Relevance to Camp |
|-------|------|-----------------|-------------------|
| "Effect Handlers, Evidently" — Xie et al. | 2020 | Evidence passing, scoped resumptions, O(1) dispatch | Core compilation strategy — evidence as function arguments |
| "Generalized Evidence Passing for Effect Handlers" — Xie & Leijen | 2021 | Yield bubbling, selective CPS → C compilation | Implementation reference for WASM backend |
| "Type Directed Compilation of Row-Typed Algebraic Effects" — Leijen | 2017 | Selective CPS: only `ctl` ops need CPS | Future optimization: `fun`/`val` ops as direct calls |
| "Algebraic Effects for Functional Programming" — Leijen | 2016 | Row-polymorphic effect types, handler semantics | Effect row design, handler syntax |
| "Perceus: Garbage Free Reference Counting with Reuse" — Reinking et al. | 2021 | Precise RC for evidence vectors + handler closures | Memory management for effect runtime |
| "An Introduction to Algebraic Effects and Handlers" — Pretnar | 2015 | Tutorial — theory and semantics | Background reference |
| OCaml 5 Effects Tutorial | 2023 | One-shot continuations, deep/shallow handlers | One-shot design rationale |

---

## 14. Future Work (Out of Scope)

These features are deliberately deferred:

| Feature | Reason for Deferral |
|---------|-------------------|
| `fun`/`val` operation kinds | All ops treated as `ctl` initially; tail-resumptive optimization adds no semantics, only performance |
| Multi-shot continuations | One-shot covers primary use cases; multi-shot requires stack copying and is incompatible with one-shot runtime guarantee |
| Handler branding (named effects) | Spec §4.10 explicitly defers this; only matters with multiple concurrent handlers of the same effect type |
| Effect masking/overriding | Koka's `mask behind<E>` — not needed until handler branding is implemented |
| `Async` effect + state machine extraction | Requires working CPS + resuming handlers first; then Async is an effect with a scheduler handler |
| Effect polymorphism inference improvements | Effect variables already work in the typechecker; evidence passing needs to thread effect-polymorphic evidence — can be refined after basic effects work |
