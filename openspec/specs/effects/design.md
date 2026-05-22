# Effects — Technical Design

## 1. What Are Algebraic Effects

Algebraic effects model computational side effects as **algebraic operations** that interact with their context via **effect handlers**. The core insight: separate the **specification** of a computation (which effects it performs) from the **interpretation** of those effects (what handlers do when effects are performed).

Key terminology:

| Term | Definition |
|------|-----------|
| Effect operation | Named operation with input/output types: `Get : unit -> int` |
| Perform | Invoking an effect operation — suspends execution, transfers control to handler |
| Effect handler | Intercepts performed effects; like exception handler but receives the delimited continuation |
| Delimited continuation (`k`) | Captured suspended computation from perform site to handler boundary; can be resumed, stored, or discarded |
| Deep handler | Automatically reinstalled after each resume; handles all matching operations in scope |
| Shallow handler | Handles only the first matching operation; not reinstalled after resume |
| One-shot continuation | Must be resumed exactly once; second invocation is a runtime error |

Theoretical foundation: effects originate from universal algebra — each effect is an operation symbol, a computation is a term built from operations, and a handler provides an algebra (model) that interprets them. The free term algebra captures what a computation *does* without committing to what operations *mean*. Handlers provide interpretations. This separation makes effects composable and reinterpretable.

---

## 2. Comparison with Alternative Mechanisms

### 2.1 Algebraic Effects vs. Exceptions

| Aspect | Exceptions | Algebraic Effects |
|--------|-----------|-------------------|
| Resume after catch | No | Yes — continuation allows resumption |
| Return value | Only exception value | Both operation parameters AND return value |
| Continuation available | No | Yes — first-class delimited continuation |
| Composability | Only exception types | Any effect signature — extensible |
| Type tracking | Checked exceptions (rare); unchecked (common) | Effect rows track all effects |

An exception handler is a **special case** of an effect handler where the continuation is never resumed and there is no return value. Algebraic effects are "resumable exceptions" — `perform` is like `raise`, the handler is like `try/with`, but the handler gets a continuation that can be continued with a value.

### 2.2 Algebraic Effects vs. Monads

| Aspect | Monads | Algebraic Effects |
|--------|--------|-------------------|
| Programming style | Monadic bind (`>>=`) / `do` notation | Direct style — normal code |
| Effect composition | Monad transformers (complex, boilerplate-heavy) | Effects combine seamlessly via rows |
| Higher-order functions | Separate `map` and `mapM` versions | One `map` works for all via effect polymorphism |
| Reinterpretation | Hard — changing monad changes types everywhere | Easy — swap the handler, computation unchanged |
| Extensibility | New effect = new monad transformer + lifting | New effect = define operations + handler |
| Performance | Closure creation overhead from bind | Direct execution on native/cps stack |

### 2.3 Algebraic Effects vs. Delimited Continuations

Delimited continuations (`shift`/`reset`) are the operational mechanism underlying algebraic effects:

| Delimited Continuations | Algebraic Effects |
|------------------------|-------------------|
| `reset` (prompt/delimiter) | Handler scope |
| `shift k` (capture continuation) | `perform op` |
| `k v` (resume) | `continue k v` |
| Dynamic prompt identity | Static effect type |

Effect handlers are a **typed, structured, composable** interface to the same mechanism. They have equivalent expressive power — each can encode the other — but effect handlers prevent the unstructured control flow that makes delimited continuations error-prone.

### 2.4 Algebraic Effects vs. Free Monads

Free monads represent a computation as a data structure (syntax tree of operations). Handlers are interpreters of this tree. Algebraic effects are an **optimization** of the free monad approach: the tree is never explicitly constructed — operations are handled on-the-fly via continuations. This eliminates the overhead of building and interpreting the tree, but retains the separation of specification and interpretation.

---

## 3. Implementation Approaches

### 3.1 Fiber-Based (OCaml 5)

The call stack is a linked list of fibers (dynamically growing stack segments). Entering a handler allocates a new fiber. `perform` captures the current fiber as a continuation and jumps to the previous fiber. `continue k v` reinstates the fiber by linking it back.

- Capture/resume: O(1) — pointer manipulation only
- One-shot continuations only (no stack copying)
- **Not WASM-compatible**: requires segmented stack runtime, not available in WASM linear memory

### 3.2 CPS Transformation (Eff original, Camp's approach)

Source code is transformed to continuation-passing style. Every effectful function gets an explicit continuation parameter. `perform` becomes a call to the handler with the continuation. Handlers are first-class functions.

- Conceptually clean
- Compatible with WASM — all control flow is explicit function calls
- Enables multi-shot continuations (if continuation is a closure that can be called multiple times)
- Camp uses selective CPS: only effectful call sites get continuation parameters

### 3.3 Free Monad / Interpreter (Haskell libraries)

Computations are represented as GADT data structures. Handlers are interpreters that pattern-match on operations.

- Pure, easy to reason about
- Trivially multi-shot (re-interpret the tree)
- Performance overhead from building and interpreting the tree
- Must use monadic interface (not direct style)

### 3.4 Handler Pipeline / Evidence Passing (Koka, Camp's choice)

Effects tracked as row types in the type system. Handlers compiled via evidence passing: each handler becomes an **evidence record** (a struct of function pointers) passed as an extra argument to effectful functions. `perform` dispatches through the evidence record in O(1).

- O(1) handler lookup — no runtime stack walking
- WASM compatible — explicit parameters + `call_indirect`
- Compile-time effect safety via row types
- Camp's chosen approach

### Why Camp Chose Evidence Passing

| Approach | Dispatch | WASM compatible | Effect safety | Complexity |
|----------|----------|-----------------|---------------|------------|
| **Evidence passing** | O(1) | Yes | Yes | Moderate |
| Fiber-based | O(n) | No | No | High |
| Runtime search | O(n) | Possible but slow | Yes | Low |

---

## 4. Evidence Passing Architecture

### 4.1 Evidence Record Structure

Each handler installs an evidence record in WASM linear memory. For a `handle` with N arms, the record contains N closure slots:

```
Evidence Record (WASM linear memory):
┌──────────────────────────────────┐
│ arm_0_fn_idx:  i32               │  ← table index of handler arm function
│ arm_0_env_ptr: i32               │  ← environment pointer (0 if no captures)
├──────────────────────────────────┤
│ arm_1_fn_idx:  i32               │
│ arm_1_env_ptr: i32               │
├──────────────────────────────────┤
│ ...                              │
└──────────────────────────────────┘
```

Each slot is 8 bytes (two i32s). The record is allocated via `camp_alloc` and initialized at the `handle` entry point.

### 4.2 Handler Arm Function Signatures

All handler arm functions — including Throw! — use the same signature format. There is no non-resuming handler variant. A handler that does not wish to resume simply does not call `resume`, but the continuation is still available.

```
handler_arm(env: i32, op_args..., resume_fn: i32, resume_env: i32, ev: i32) -> result_type
```

| Parameter | Purpose |
|-----------|---------|
| `env` | Handler's captured environment (closed-over variables) |
| `op_args...` | The operation's original arguments (e.g., `msg` for `println!(msg)`) |
| `resume_fn` | Function table index for the one-shot resume continuation |
| `resume_env` | Environment pointer for the resume continuation |
| `ev` | Evidence record pointer (deep handlers: re-installs evidence after resume) |

**Deep handler**: `ev` points to the same evidence record. When `resume` is called, the resumed computation has the handler still installed via the same `ev`.

**Shallow handler**: `ev` is **not** passed to the continuation. The resumed computation runs without the current handler.

**All handlers** receive `resume_fn` and `resume_env`. Whether `resume` is called is a handler implementation choice, not a type-level distinction. Throw! handlers that do not resume simply discard the continuation.

### 4.3 Effect Declaration Mapping

Effects are type aliases with `!` names. The evidence record maps operation names to arm indices at compile time:

```
Console! : { println!: |Str| -[Console!]-> {}, readln!: -[Console!]-> Str }

Evidence record for Console! handler:
  [0] = println! arm closure (fn_idx, env_ptr)
  [1] = readln! arm closure (fn_idx, env_ptr)

IR_Perform Console!.println!("hello") dispatches to:
  ev[0].fn_idx(ev[0].env_ptr, "hello", resume_fn, resume_env, ev)
```

There is no `effect` keyword. Effects are parsed as type aliases whose names end with `!`.

### 4.4 Effect Propagation Through Function Calls

Every effectful function receives evidence parameters — one `i32` per effect in its effect row. This is the core of evidence passing: handlers are passed as extra arguments rather than looked up at runtime.

```
// Before evidence passing:
read_line! = || -[Console!]-> Str { Console!.readln!() }

// After evidence passing:
read_line! = (ev_Console: i32) -> Str {
    // Console!.readln!() dispatches through ev_Console
}
```

`IR_Decl_Fn` gains an `effects: [dynamic]Canonical_Name` field (replacing the meaningless `effect_row: IR_Type`). At each call to an effectful function, the caller passes evidence for each effect in the callee's `effects` list.

### 4.5 IR Transformations

**`IR_Handle` becomes**:
1. Generate one `IR_Decl_Fn` per handler arm
2. Allocate evidence record: `let _ev_N = camp_alloc(N * 8)`
3. Initialize record: store `fn_idx` and `env_ptr` for each arm
4. Transform the body with `_ev_N` in the evidence environment
5. Deallocate: `camp_dealloc(_ev_N, N * 8)`

**`IR_Perform` becomes**:
1. Look up evidence variable for this effect from the environment
2. Compute arm index from operation name (compile-time known)
3. Load `fn_idx = i32.load(ev + arm_index * 8)` and `env_ptr = i32.load(ev + arm_index * 8 + 4)`
4. Generate `IR_Closure_Call` with arguments: `(env_ptr, op_args..., resume_closure, ev)`

---

## 5. CPS Continuation Capture

### 5.1 `IR_Resume` Node

```odin
IR_Resume :: struct {
    resume_id: Intern_ID,
    value:     IR_Expr,
    type:      IR_Type,
    span:      Source_Span,
}
```

Codegen: `IR_Resume` compiles to `call_indirect` on the resume closure:

```
1. Load resume_fn_idx from the resume closure record
2. One-shot check: if fn_idx == 0, trap (double-resume)
3. Zero the fn_idx in the resume closure (mark as consumed)
4. Load resume_env_ptr from the resume closure record
5. call_indirect(resume_env_ptr, resume_value, resume_fn_idx)
```

### 5.2 Continuation Capture at Perform Sites

The CPS transform captures "the rest of the computation" at each `IR_Perform` site and passes it as a resume closure to the handler.

**Transformation for `IR_Let` where value is `IR_Perform`**:

```
// Before CPS:
let x = E.op(y) in g(x)

// After CPS:
let k = closure(fn=kc_fn, env=kc_env) in
  E.op_handler(ev_env, y, k.fn_idx, k.env_ptr, ev)
where kc_fn(env, x) = g(x)
```

Implementation:
1. Create a fresh continuation name `kc`
2. Generate `IR_Decl_Fn{name=kc, params=[x: result_type], body=cps_transform(body, k_name)}`
3. Create a closure record for the continuation: `IR_Closure{fn_name=kc, ...}`
4. Replace the let-perform with a call to the handler arm, passing the continuation closure
5. Return the handler call as a tail call

### 5.3 Deep Handler Semantics in CPS

The captured continuation's environment includes the current evidence record pointer. When `resume` is called, the continuation's body runs with `ev` in scope. Any further `perform` of the same effect dispatches to the same handler.

Codegen difference:
- Deep: `kc_fn(kc_env, x, ev)` — `ev` is passed

### 5.4 Shallow Handler Semantics in CPS

The captured continuation's environment does **not** include the current evidence record pointer. When `resume` is called, the continuation runs without the current handler. Any further `perform` propagates to an outer handler.

Codegen difference:
- Shallow: `kc_fn(kc_env, x)` — `ev` is **not** passed

---

## 6. WASM Codegen for Effects

### 6.1 Handler Arm Functions → WASM Table Entries

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

### 6.2 Evidence Record Allocation + Initialization

```wasm
;; Allocate evidence record: N arms × 8 bytes
(call $camp_alloc (i32.const <N * 8>))
(local.set $ev)

;; Store fn_idx for arm 0 (println handler)
(i32.store (local.get $ev) (i32.const <handler_println_table_idx>))
;; Store env_ptr for arm 0
(i32.store (i32.add (local.get $ev) (i32.const 4)) (local.get $handler_env))
;; ... repeat for each arm
```

### 6.3 Perform → `call_indirect` via Evidence

```wasm
;; Load handler function index: ev[arm_index * 8]
(i32.load (i32.add (local.get $ev) (i32.const <arm_index * 8>)))
(local.set $handler_fn)

;; Load handler environment: ev[arm_index * 8 + 4]
(i32.load (i32.add (local.get $ev) (i32.const <arm_index * 8 + 4>)))
(local.set $handler_env)

;; Call handler with (env, op_args..., resume_fn, resume_env, ev)
(call_indirect (type $handler_sig)
  (local.get $handler_env)
  (local.get $msg)
  (local.get $resume_fn)
  (local.get $resume_env)
  (local.get $ev)
  (local.get $handler_fn))
```

### 6.4 Resume → `call_indirect` on Continuation

```wasm
;; Load function index
(i32.load (local.get $resume_closure))
(local.set $resume_fn)

;; One-shot check: if fn_idx == 0, trap
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

### 6.5 Effectful Main Codegen

Instead of replacing effectful `main!` with `unreachable`:

1. Generate `main!` as a regular function with evidence parameters for each effect in its row
2. Generate a `_start` function that:
   - Allocates evidence records for each effect in `main!`'s effect row
   - For `Console!`: handler calls WASI `fd_write`
   - For `Throw!([..])`: handler prints tag to stderr + `proc_exit(1)` (does not call resume)
   - For other effects: handler prints "unhandled effect" + `camp_exit(1)`
   - Calls `main!` with evidence arguments
   - Returns result as WASM exit code

---

## 7. Phase-by-Phase Implementation Plan

| Phase | Name | Scope (lines) | Depends On | What Works After |
|-------|------|---------------|------------|-----------------|
| **0a** | Parser syntax alignment | ~100 | — | Parser accepts `-[...]->` and `.op!(resume, args)` |
| **0b** | Fix existing bugs | ~325 | 0a | Bugs fixed, CPS + closures working |
| **1** | Effect row subtraction | ~40 | 0b | Typechecker correctly models handled effects |
| **2** | Rewrite effect_lower | ~320 | 1 | Evidence passing works, handler records allocated |
| **3** | CPS continuation capture | ~230 | 2 | Resume mechanism works |
| **4** | WASM codegen for effects | ~350 | 3 | Effects execute in WASM |
| **5** | Effect `:` syntax migration | ~200 | 4 | No `effect` keyword; effects are type aliases with `!` names |
| **6** | Parameterized effects + variant widening | ~150 | 5 | Effects can have type parameters; tag union params widen |
| **7** | Effect polymorphism | ~250 | 6 | Effect row variables as generic parameters; row variable unification |
| **8** | Console! + Throw! in prelude | ~50 | 7 | Both as normal effects in prelude; Throw! resumable like any other |

**Total estimated scope**: ~2,015 lines

### Phase 0a: Parser Syntax Alignment

**Effect row type syntax**: Replace `->{ Eff1, Eff2 }` with `-[Eff1 | Eff2]->`. Parsing rules: after `->`, if `-[` follows, parse an effect row with `|`-separated `Upper_Id` names inside `-[ ... ]->`.

**Handler arm parameters**: `.op!(resume, arg1, arg2, ...) => body`. AST change: `Handler_Arm.params: [dynamic]Intern_ID` replaces `resume_id: Intern_ID`. First element is always `resume`.

**Estimated scope**: ~100 lines in `parser.odin`, `ast.odin`, `format_type.odin`

### Phase 0b: Fix Existing Bugs

Six bugs block effect execution:

| Bug | Description | Scope |
|-----|-------------|-------|
| H2: `IR_Crash` | `CExpr_Crash` discards crash semantics; no `IR_Crash` node | ~15 lines |
| M4: Missing handler evidence | `ev_var == NO_NAME` omits evidence argument | ~5 lines |
| M9: Generalization at level | Child levels not checked before generalizing | ~45 lines |
| C8: Closure body nil | `IR_Decl_Fn.body` is nil after closure conversion | ~90 lines |
| C7: Non-name callee | No `call_indirect` for higher-order calls | ~110 lines |
| M5: CPS no continuations | CPS transform never creates continuation functions | ~60 lines |

### Phase 1: Effect Row Subtraction

New helper: `subtract_effect_from_row(store, row, effect) -> Type_Var_ID`. Resolves the row. If effect found in `effect_names`, remove it and return new row. If not found, return row unchanged. If row is a variable, create a constraint.

**Scope**: ~40 lines in `typecheck.odin`

### Phase 2: Rewrite effect_lower — Evidence Passing

Replace the no-op `make_handler` and zero-evidence-variable with real evidence passing. Each `IR_Decl_Fn` with non-empty `effects` gets evidence params prepended. Each `IR_Call` to an effectful function appends evidence arguments. Each `IR_Perform` dispatches through the evidence record.

**Scope**: ~320 lines across `effect_lower.odin`, `ir.odin`, `lower.odin`

### Phase 3: CPS Continuation Capture

Add `IR_Resume` node. CPS transform captures continuation at `IR_Perform` sites. Deep handlers pass `ev` to continuation; shallow handlers do not. One-shot enforcement: zero `fn_idx` on first resume, trap on null. All effects — including Throw! — use the same continuation capture mechanism.

**Scope**: ~230 lines in `cps.odin`, `ir.odin`

### Phase 4: WASM Codegen for Effects

Handler arm functions → WASM table entries. Evidence record allocation + initialization. Perform → `call_indirect` via evidence. Resume → `call_indirect` on continuation with one-shot check. Effectful main codegen. All handlers use the same arm signature (including Throw!).

**Scope**: ~350 lines in `codegen.odin`

### Phase 5: Effect `:` Syntax Migration

Remove the `effect` keyword from the lexer and parser. Extend `:` definition parsing to recognize names ending in `!` as effect definitions. Effect operation type annotations become required. Update all e2e tests.

**Parser changes**: When parsing a `:` definition, if the name ends with `!` and the body is a record of function signatures, produce `CDecl_Effect`. If the name doesn't end with `!` and the body is a record, produce `CDecl_Trait`. If the body is a type (not a record), produce `CDecl_Alias`.

**Scope**: ~200 lines in `lexer.odin`, `parser.odin`, `canonicalize.odin`, `format_decl.odin`, e2e tests

### Phase 6: Parameterized Effects + General Variant Widening

Effects gain type parameters: `Throw! : { throw!: |e| -[Throw!(e)]-> a }`. Effect rows now track effect names with type arguments: `-[Throw!([NotFound | PermissionDenied])]->`.

**Variant widening is just tag row unification** applied to effect type parameters — no Throw-specific code. When two effect rows both contain `Throw!`, unify their type arguments. If both are tag unions, merge via tag row unification (widening). If both are value types, require exact match (specialization).

**Scope**: ~150 lines in `typecheck.odin`, `unify.odin`, `types.odin`

### Phase 7: Effect Polymorphism

Effect row variables as generic parameters. `Type_Param` gains `is_effect: bool`. Effect row variable unification extending the existing row unification infrastructure. Effect row composition: `-[Parallel! | e]->` unifies with `-[e]->` by adding `Parallel!`. Effect row subtraction with variables: `handle Parallel! in body` where body has row `-[Parallel! | e]->` produces row `-[e]->`.

**Scope**: ~250 lines in `typecheck.odin`, `unify.odin`, `types.odin`

### Phase 8: Console! + Throw! in Prelude

Both Console! and Throw! are defined as normal effects in the prelude (Odin-injected type declarations). Throw! uses the same handler arm signature as all other effects — no special non-resuming path. The default runtime handler for `Throw!([..])` in `main!` simply does not call resume; it prints the tag and exits.

**Scope**: ~50 lines in `typecheck.odin` (prelude injection), `codegen.odin` (default handler)

---

## 8. Languages That Implement Algebraic Effects

### Eff

- **Authors**: Andrej Bauer, Matija Pretnar (University of Ljubljana)
- **Implementation**: Originally CPS-based; current version uses OCaml 5 effect handlers
- **Key features**: ML-style syntax, first-class effects and handlers, multi-shot continuations, parametric polymorphism
- **Limitation**: Effects are **not** tracked in the type system — unhandled effects are runtime errors
- **Philosophy**: Effects are first-class citizens; ML-style references are defined, not primitive

### Koka

- **Author**: Daan Leijen (Microsoft Research)
- **Key features**: Row-polymorphic effect types, effect inference, deep and shallow handlers, handler-local resources
- **Compilation**: CPS-based IR, reference counting (Perceus), compiles to C/JS/Wasm
- **Architecture**: Effect rows in the type system enable compile-time effect safety; tilde-arrow syntax for effect-polymorphic functions
- **Relevance to Camp**: Koka is Camp's primary design ancestor — row-polymorphic effect types, direct style, and evidence passing compilation strategy

### OCaml 5

- **Key features**: One-shot (linear) continuations, deep and shallow handlers, fiber-based implementation, `Effect.t` extensible variant type
- **No effect safety**: Unhandled effects raise `Effect.Unhandled` at runtime. Effect system under active development (Leo White, Jane Street)
- **Design philosophy**: Effect handlers primarily for concurrency (schedulers, async I/O). One-shot continuations are sufficient and much cheaper than multi-shot
- **Relevance to Camp**: OCaml 5's one-shot design rationale directly influenced Camp's choice

### Unison

- **Key features**: "Abilities" system (Unison's term for effects), effect handlers as primary abstraction for side effects, content-addressed code
- **Effect tracking**: Strong effect tracking in the type system
- **All I/O, state, concurrency**: Expressed through ability handlers

---

## 9. Key Research References

### Foundational Papers

| Paper | Authors | Year | Key Contribution | Relevance to Camp |
|-------|---------|------|-----------------|-------------------|
| "Algebraic Operations and Generic Effects" | Plotkin & Power | 2003 | Algebraic operations for effects | Theoretical foundation |
| "Handlers of Algebraic Effects" | Plotkin & Pretnar | 2009 | Effect handlers | Core concept |
| "An Introduction to Algebraic Effects and Handlers" | Pretnar | 2015 | Tutorial — theory and semantics | Background reference |

### Eff Language

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|-----------------|
| "Programming with Algebraic Effects and Handlers" | Bauer & Pretnar | 2012 | Eff language introduction |
| "An Effect System for Algebraic Effects and Handlers" | Bauer & Pretnar | 2013 | Effect system with inference, proven safe |

### Koka and Evidence Passing

| Paper | Authors | Year | Key Contribution | Relevance to Camp |
|-------|---------|------|-----------------|-------------------|
| "Koka: Programming with Row-Polymorphic Effect Types" | Leijen | 2014 | Row-polymorphic effect types | Effect row design |
| "Algebraic Effect Handlers with Resources and Deep/Shallow Handlers" | Leijen | 2018 | Resources + deep/shallow formalization | Handler design |
| "Effect Handlers, Evidently" | Xie et al. | 2020 | Evidence passing, O(1) dispatch | **Core compilation strategy** |
| "Generalized Evidence Passing for Effect Handlers" | Xie & Leijen | 2021 | Yield bubbling, selective CPS → C | WASM backend reference |
| "Type Directed Compilation of Row-Typed Algebraic Effects" | Leijen | 2017 | Selective CPS: only `ctl` ops need CPS | Future `fun`/`val` optimization |

### Multicore OCaml

| Paper | Authors | Year | Key Contribution | Relevance to Camp |
|-------|---------|------|-----------------|-------------------|
| "Retrofitting Parallelism onto OCaml" | Dolan et al. | 2020 | Fiber-based handlers, one-shot continuations | One-shot design rationale |

### Memory Management

| Paper | Authors | Year | Key Contribution | Relevance to Camp |
|-------|---------|------|-----------------|-------------------|
| "Perceus: Garbage Free Reference Counting with Reuse" | Reinking et al. | 2021 | Precise RC for evidence vectors + handler closures | Memory management for effect runtime |

### Relationship to Delimited Continuations

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|-----------------|
| "Handling Algebraic Effects" | Plotkin & Pretnar | 2013 | Effect handlers generalize delimited continuations; formal relationship with `shift`/`reset` |
