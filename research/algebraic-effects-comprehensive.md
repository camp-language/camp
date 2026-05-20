# Comprehensive Research: Algebraic Effects

## 1. What Are Algebraic Effects? Core Concepts, Theory, and Terminology

### Definition
Algebraic effects are a **mathematical approach to modeling computational effects** (side effects) in programming languages. Rather than treating effects as monolithic operations that directly interact with the runtime environment, algebraic effects model them as **algebraic operations** that interact with their context — specifically, with **effect handlers** that define what the operations actually do.

The core insight: instead of baking the semantics of effects into the language runtime, you separate the **specification** of a computation (which effects it performs) from the **interpretation** of those effects (what handlers do when effects are performed).

### Key Terminology

- **Effect operation (or operation signature):** A named operation with input and output types, e.g., `Get : unit -> int` or `Set : int -> unit`. These are the "interface" of an effect — they say what you can call, not what it does.

- **Perform:** The act of invoking an effect operation. When a computation `perform (Get ())`, execution is **suspended** and control transfers to the nearest enclosing handler for that effect. This is analogous to raising an exception, but crucially, the computation can be **resumed** afterward.

- **Effect handler:** A construct that intercepts performed effects and defines what happens. Like an exception handler, it catches the effect. Unlike an exception handler, it also receives the **delimited continuation** — the suspended computation from the point of `perform` to the handler boundary — allowing it to resume the computation with a value.

- **Delimited continuation (k):** The captured suspended computation between the `perform` site and the handler. It can be resumed with a value (`continue k v`), resumed with an exception (`discontinue k e`), stored for later use, or even discarded.

- **Deep handler:** A handler that is **automatically reinstalled** after each effect is handled. The captured continuation includes the handler, so subsequent effects from the same computation are also handled. This is the default in most implementations.

- **Shallow handler:** A handler that handles **only the first effect** performed. The continuation does not include the handler, so after resumption, no handler is in place. The programmer must explicitly provide a new handler (possibly different) for the next effect. Useful for encoding protocols/state machines over effect sequences.

- **Fiber:** In OCaml's implementation, a runtime-managed, dynamically-growing segment of the call stack. The program stack is a linked list of fibers. A new fiber is allocated for each handler scope; capturing a continuation just captures a reference to the fiber segment (no copying required).

- **One-shot (linear) continuation:** A continuation that must be resumed **exactly once** — either with `continue` or `discontinue`. Resuming more than once raises an error. This is the model OCaml 5 uses, as it's much cheaper than multi-shot (no stack copying needed) and sufficient for concurrency.

- **Multi-shot continuation:** A continuation that can be resumed multiple times. Supported in Eff and Koka. Enables backtracking/search strategies but requires copying stack frames.

### Theoretical Foundation

Algebraic effects originate from **universal algebra** applied to computational effects. The idea is that computational effects can be modeled as operations of an **algebraic theory**:

- Each effect is an **operation symbol** (like `Get`, `Set`, `Raise`, `Fork`, `Yield`)
- A computation is a **term** built from these operations
- A handler provides an **algebra** (a model) for the theory — it interprets the operations

The key theoretical property is that the **free term algebra** captures the essence of a computation: it's the computation described only by which operations it performs, without committing to what those operations *mean*. Handlers then provide **interpretations** of these terms. This separation is what makes effects **composable** and **reinterpretable**.

Plotkin and Pretnar's foundational insight: just as algebraic theories have free algebras and models, effectful computations have a notion of "effect signature" (the operations) and "handlers" (the models/algebras that give semantics to those operations).

---

## 2. Key Academic Papers

### Foundational Papers

1. **Plotkin, G.D. and Power, J.** — "Algebraic Operations and Generic Effects" (2003)
   - Introduced the concept of algebraic operations for computational effects
   - Showed that many effects can be described as operations of an algebraic theory
   - Established the connection between universal algebra and computational effects

2. **Plotkin, G.D. and Pretnar, M.** — "Handlers of Algebraic Effects" (2009, published in ESOP 2009)
   - The foundational paper introducing effect handlers
   - Defined the concept of handling algebraic effects
   - Showed that handlers correspond to models of the algebraic theory
   - Introduced the operational semantics of effect handling

3. **Plotkin, G.D. and Pretnar, M.** — "Handling Algebraic Effects" (2013, Logical Methods in Computer Science)
   - Extended version with more complete treatment
   - Formal treatment of the relationship between handlers and algebras

### The Eff Language Papers

4. **Bauer, A. and Pretnar, M.** — "Programming with Algebraic Effects and Handlers" (2012, presented at CW)
   - Introduced the Eff programming language
   - Showed practical programming with algebraic effects and handlers

5. **Bauer, A. and Pretnar, M.** — "An Effect System for Algebraic Effects and Handlers" (2013, arXiv:1306.6316, published in LMCS 2014)
   - **The key paper on effect systems for algebraic effects**
   - Defined an expressive effect system for core Eff
   - Proved safety of operational semantics with respect to the effect system
   - Gave domain-theoretic denotational semantics using Pitts's minimal invariant relations
   - Proved adequacy and developed tools for contextual equivalences
   - Derived equations for mutable state including commutativity for non-interfering references
   - **Formalized in Twelf**

6. **Bauer, A. and Pretnar, M.** — "Programming with Algebraic Effects and Handlers" (2015, J. Logical and Algebraic Methods in Programming)
   - Journal version with comprehensive treatment of the Eff language

### Effect Handlers and Delimited Continuations

7. **Plotkin, G.D. and Pretnar, M.** — "Handling Algebraic Effects" (2013)
   - Showed that effect handlers generalize delimited continuations
   - Established the formal relationship between `shift`/`reset` and handlers

8. **Priestley, M.** — Various work on the relationship between algebraic effects and other control mechanisms

### Koka and Multicore OCaml Papers

9. **Leijen, D.** — "Koka: Programming with Row-Polymorphic Effect Types" (2014, MSFP)
   - Introduced Koka's effect system with row polymorphism
   - Showed how to infer effect rows

10. **Leijen, D.** — "Algebraic Effect Handlers with Resources and Deep/Shallow Handlers" (2018, ESOP)
    - Extended effect handlers with resources
    - Formalized deep and shallow handlers
    - Key paper for understanding the handler design space

11. **Dolan, S., Eliopoulos, M., Sivaramakrishnan, K., and Madhavapeddy, A.** — "Retrofitting Parallelism onto OCaml" (2020, ICFP)
    - The Multicore OCaml paper
    - Describes the fiber-based implementation of effect handlers
    - One-shot continuations for efficient concurrency
    - **Citation: https://dl.acm.org/doi/10.1145/3408995**

12. **Sivaramakrishnan, K.C., Dolan, S., and Madhavapeddy, A.** — "Retroactive Concurrency" and related Multicore OCaml papers

### Type Systems and Row Polymorphism

13. **Leijen, D.** — "Structured Asynchrony with Algebraic Effects" (2017)
14. **Leijen, D.** — "Type Classes as Functors and Extensible Interpretations" (2015)

### Tutorials and Surveys

15. **Pretnar, M.** — "An Introduction to Algebraic Effects and Handlers" (2015, invited tutorial at DALI)
    - The best tutorial introduction to the field
    - Covers both theory and practice

16. **Bauer, A. and Pretnar, M.** — "Eff: A Functional Programming Language Based on Algebraic Effects and Handlers" (OOPSLA 2021 artifact)

---

## 3. How Algebraic Effects Differ from Exceptions, Monads, and Other Mechanisms

### Algebraic Effects vs. Exceptions

| Aspect | Exceptions | Algebraic Effects |
|--------|-----------|-------------------|
| Resume? | No — once caught, cannot resume | Yes — continuation allows resumption |
| Return value | Only exception value | Both operation parameters AND return value |
| Continuation | Not available | Available as first-class value |
| Composability | Only exception types | Any effect signature — extensible |
| Type tracking | Checked exceptions (rare); unchecked (common) | Effect systems can track all effects |

An exception handler is a **special case** of an effect handler where:
- The continuation is never resumed (always discarded)
- There is no return value from the "effect" to the handler
- The effect is one-way: just a signal

Algebraic effects are "resumable exceptions" — Leo White (Jane Street) described them as such. The `perform` is like `raise`, the handler is like `try/with`, but the handler gets a continuation `k` that can be `continue`d with a value.

### Algebraic Effects vs. Monads

| Aspect | Monads | Algebraic Effects |
|--------|--------|-------------------|
| Programming style | Must use monadic bind (`>>=`) / `do` notation | Direct style — write normal code |
| Effect composition | Monad transformers (complex, boilerplate-heavy) | Effects combine seamlessly |
| Higher-order functions | Need separate `map` and `mapM` versions | One `map` works for all |
| Type tracking | Effect encoded in the monad type | Effect tracked separately by effect system |
| Performance | Creates intermediate closures/data structures; relies on optimizer inlining | Direct execution on native stack; continuations are stack segments |
| Reinterpretation | Hard — changing the monad changes types everywhere | Easy — swap the handler, computation stays the same |
| Extensibility | Adding new effect = new monad transformer + lifting instances | Adding new effect = define new operations + handler |

Key advantages of algebraic effects over monads (from Leo White's Jane Street talk):

1. **No monadic bind tax**: You write `x = f(); g(x)` not `f >>= fun x -> g x`
2. **No separate `map`/`mapM`**: `List.map` works for effectful functions without needing `List.mapM`
3. **Easy effect mixing**: A function performing both `Async` and `Throw NotFound` just has both in its effect type; no need to create a combined monad or monad transformer
4. **Better performance**: No closure creation overhead from bind; computations run on the native call stack

The monadic approach forces you to "split the world" into pure functions and effectful computations — you need two copies of every higher-order function. With effects, you use effect polymorphism: `List.map` has type `'a -> 'b) -{'e}-> 'c list -> 'd list` where `'e` is an effect variable that propagates the callee's effects.

### Algebraic Effects vs. Delimited Continuations

Delimited continuations (`shift`/`reset`, `control`/`prompt`) are the **operational mechanism** underlying algebraic effects. The relationship:

- `perform` ≈ `shift` (capture continuation up to nearest delimiter)
- Handler scope ≈ `reset` (establishes the delimiter)
- Effect handlers are a **more structured, typed, composable** interface to delimited continuations

See Section 10 for full details.

### Algebraic Effects vs. Free Monads

Free monads are the **data structure encoding** of algebraic effects. A free monad represents a computation as a data structure (a syntax tree of operations). Effect handlers are then interpreters of this data structure.

| Aspect | Free Monads | Algebraic Effects |
|--------|-------------|-------------------|
| Representation | Explicit data structure (tree) | Implicit (continuation on stack) |
| Performance | Overhead of building tree + interpreting | Direct execution |
| Granularity | Whole-program interpretation | Per-operation handling |
| Programming style | Must use monadic interface | Direct style |

The free monad approach is conceptually clean but has practical performance issues. Algebraic effects can be seen as an **optimization** of the free monad approach where the "tree" is never explicitly constructed — instead, operations are handled on-the-fly via continuations.

---

## 4. The Relationship Between Algebraic Effects and Effect Handlers

The relationship is **fundamental and inseparable** — they are two sides of the same coin:

- **Algebraic effects** are the **interface**: the set of operations a computation may perform. They define *what* can be asked.
- **Effect handlers** are the **implementation**: the code that says what happens when an operation is performed. They define *how* to answer.

Analogy from OOP:
- Effect operations ≈ abstract methods of an interface
- Effect handlers ≈ concrete implementations of that interface
- `perform` ≈ calling the method on the interface
- The handler ≈ the dynamic dispatch

But unlike OOP, the "dispatch" happens based on the **dynamic scope** (the nearest enclosing handler), not the object type. And the handler gets the **continuation** — it can resume, modify, or discard the suspended computation.

### Handler Semantics

When a computation performs an effect:
1. Execution is **suspended** at the `perform` site
2. The **delimited continuation** `k` is captured (from `perform` up to the handler)
3. Control **jumps** to the handler with the effect value and continuation
4. The handler can:
   - `continue k v` — resume the computation with value `v`
   - `discontinue k e` — resume with an exception `e`
   - Store `k` for later resumption (e.g., in a scheduler queue)
   - Never resume `k` (e.g., like an exception handler)
5. With a **deep** handler, the handler is reinstalled when `k` is resumed
6. With a **shallow** handler, the handler is not reinstalled; programmer must provide a new one

### Handler Composition

Handlers compose naturally by nesting:
```
try
  try
    perform E1; perform E2
  with
  | effect E1, k -> ... (* handles E1 *)
with
| effect E2, k -> ... (* handles E2 *)
```

Each handler handles its effects; unhandled effects propagate to outer handlers.

---

## 5. Implementation Approaches and Strategies

### 5.1 Continuation-Based (Fiber/Segmented Stack) — OCaml 5, Multicore OCaml

**Architecture:**
- The call stack is a **linked list of fibers** (dynamically growing stack segments)
- Entering a handler allocates a new fiber
- `perform` captures the current fiber as a continuation (heap object pointing to the stack segment) and jumps to the previous fiber
- `continue k v` reinstates the fiber by linking it back to the current stack
- **No stack copying** — just pointer manipulation

**Key design decisions in OCaml 5:**
- **One-shot continuations only** — must be resumed exactly once
- Dynamic check prevents double-resumption (`Continuation_already_resumed` exception)
- No static linearity enforcement
- Capturing a continuation is O(1) — just captures a reference
- Resuming is O(1) — links stack segments

**Advantages:** Very fast capture/resume; minimal overhead for the common case
**Disadvantages:** No multi-shot; must handle linearity discipline manually

### 5.2 CPS (Continuation-Passing Style) Transformation — Eff (original version)

**Architecture:**
- Source code is transformed to CPS before execution
- Every function gets an explicit continuation parameter
- `perform` becomes a call to the handler with the continuation
- Handlers are first-class functions

**Advantages:** Conceptually clean; easy to implement multi-shot continuations
**Disadvantages:** CPS-transformed code can be hard to debug; performance overhead from closure allocation; tail-call optimization becomes critical

### 5.3 Free Monad / Interpreter Approach — Conceptual / Haskell Libraries

**Architecture:**
- Computations are represented as free monad data structures
- Operations are constructors in a GADT
- Handlers are interpreters that pattern-match on the operations

```haskell
data Effect op a where
  Get :: Effect op Int
  Set :: Int -> Effect op ()

runState :: s -> Free (Effect op) a -> (s, a)
runState = foldFree (\case Get -> ...; Set n -> ...)
```

**Advantages:** Pure; easy to reason about; trivially multi-shot (just re-interpret the tree)
**Disadvantages:** Performance overhead from building and interpreting the tree; must use monadic interface

### 5.4 Handler Pipeline / Effect Row Approach — Koka

**Architecture:**
- Effects are tracked in the type system as **row types**
- Handlers are compiled using a combination of CPS and efficient runtime support
- Koka uses a **handler pipeline**: when a handler is installed, it's pushed onto a handler stack
- Operations perform a "search" through the handler stack for a matching handler
- Koka supports both deep and shallow handlers
- Koka has a sophisticated **effect inference** algorithm

**Key innovation:** Koka adds **resources** to handlers — handler-local state that is automatically managed:
```
handler state<handler s> {
  fun get() { s }
  fun set(x) { s := x }
}
```

### 5.5 Efficient Runtime with Stack Copying — Eff (current version, OOPSLA 2021)

The current version of Eff (as of the OOPSLA 2021 artifact) is implemented in OCaml 5, leveraging OCaml's native effect handlers. The original Eff was implemented via CPS transformation.

---

## 6. Languages That Implement Algebraic Effects

### 6.1 Eff

- **Authors:** Andrej Bauer and Matija Pretnar (University of Ljubljana)
- **Website:** http://www.eff-lang.org/
- **Repository:** https://github.com/matijapretnar/eff
- **Implementation:** Originally CPS-based; current version uses OCaml 5 effect handlers
- **Key features:**
  - ML-style syntax (OCaml-like)
  - First-class effects and handlers
  - Multi-shot continuations
  - Parametric polymorphism and type inference
  - Effects are **not** tracked in the type system (no effect system in the language)
  - **Research prototype** — explicitly not recommended for production
- **Philosophy:** Effects are first-class citizens; any computational effect can be defined as a set of operations + a handler. ML-style references are a **defined concept** in Eff, not a primitive.

### 6.2 Koka

- **Author:** Daan Leijen (Microsoft Research)
- **Website:** https://koka-lang.github.io/
- **Key features:**
  - **Row-polymorphic effect types** — effects are tracked in the type system
  - Effect inference (effects are usually inferred, not annotated)
  - Deep and shallow handlers
  - Handler-local **resources**
  - Compiles to C, JavaScript, and Wasm
  - **Strongly typed** effect tracking
  - Direct style programming (no monadic notation needed)
  - Tilde-arrow syntax: `a -> b` (pure) vs `a -> b -{e}-> c` (effectful)
- **Architecture:**
  - Uses a CPS-based intermediate representation for effect handler compilation
  - Reference counting memory management
  - Effect rows in the type system enable compile-time effect safety

### 6.3 OCaml 5 (Effect Handlers)

- **Part of OCaml since version 5.0** (merged from Multicore OCaml project)
- **Key features:**
  - **One-shot (linear) continuations** — must be resumed exactly once
  - Deep and shallow handlers
  - Fiber-based implementation (linked list of stack segments)
  - `Effect.t` — extensible variant type for declaring effects
  - `Effect.Deep` and `Effect.Shallow` modules
  - `continue`, `discontinue`, `perform` primitives
  - **No effect safety** — unhandled effects raise `Effect.Unhandled` at runtime (unlike Koka/Eff which can track effects in types)
- **Design philosophy:**
  - Effect handlers are primarily for **concurrency** (schedulers, async I/O)
  - One-shot continuations are sufficient for concurrency
  - One-shot is much cheaper to implement (no stack copying)
  - Linearity prevents double-use of resources like file descriptors
  - OCaml's effect handlers are **synchronous** — cannot perform effects from signal handlers, finalizers, or C callbacks

### 6.4 Multicore OCaml (Historical)

- **Repository:** https://github.com/ocaml-multicore/ocaml-multicore (archived, merged into OCaml)
- **Paper:** "Retrofitting Parallelism onto OCaml" (ICFP 2020)
- This was the research project that brought effect handlers and parallelism to OCaml
- Now part of mainline OCaml 5.x

### 6.5 Unison

- **Website:** https://www.unison-lang.org/
- **Key features:**
  - Algebraic effects are fundamental to Unison's design
  - Abilities system (Unison's term for effects)
  - Effect handlers as the primary abstraction for side effects
  - All I/O, state, concurrency expressed through ability handlers
  - **Content-addressed code** — code is identified by hash
  - Strong effect tracking in the type system

### 6.6 Other Languages and Libraries

- **Links:** An ML-family language with first-class effects and effect handlers (research language)
- **Helium:** Research language based on algebraic effects
- **Haskell libraries:** `freer-simple`, `polysemy`, `eff`, `effectful` — libraries implementing algebraic effects via free monads / extensible effects in Haskell
- **Effekt:** A research language with effect handlers and capability-based effect safety (https://effekt-lang.org/)
- **Caramel:** OCaml-to-JavaScript compiler with effect handler support

---

## 7. High-Level Architecture of Each Language's Implementation

### Eff
```
Source (OCaml-like syntax)
  → Parser
  → Type checker (Hindley-Milner, no effect tracking)
  → [Current: compiles using OCaml 5 effect handlers runtime]
  → [Original: CPS transformation + OCaml backend]
  → Execution
```
- Effects declared with `effect` keyword
- Handlers with `with ... handler ...` syntax
- Multi-shot continuations supported
- No effect system — unhandled effects are runtime errors

### Koka
```
Source
  → Parser
  → Type checker with row-polymorphic effect types
  → Effect inference
  → CPS conversion (for handler compilation)
  → Optimization passes
  → Code generation (C / JS / Wasm)
```
- Effect rows in types: `(int) -> int -{div, state}>`
- Handler compilation uses a sophisticated CPS transformation
- Resources enable handler-local state with automatic management
- Effect inference means most code needs no effect annotations

### OCaml 5
```
Source (OCaml syntax + effect extensions)
  → Parser
  → Type checker (standard OCaml type system, no effect tracking [yet])
  → Code generation (native / bytecode)
  → Runtime: fiber-based stack management
```
- Effects declared by extending `Effect.t` (extensible variant)
- Handlers use `try ... with | effect E, k -> ...` syntax
- Runtime manages fibers (stack segments) directly
- Fiber allocation: small initial size, dynamically grows
- Continuation capture: O(1), just captures reference to fiber
- Continuation resume: O(1), links fiber back onto stack

### Unison
```
Source (Unison syntax with abilities)
  → Parser
  → Type checker with ability/effect tracking
  → Compilation to bytecode
  → Execution on Unison runtime
```
- Effects called "abilities"
- Ability requests use syntax like `Nat.increment`
- Handler syntax with `handle` blocks

---

## 8. Common Implementation Challenges and Solutions

### Challenge 1: Multi-shot vs. One-shot Continuations

**Problem:** If a continuation can be resumed multiple times, the stack segment it references may be in an inconsistent state after the first resumption. Multi-shot requires **copying the stack** when capturing a continuation.

**Solutions:**
- **OCaml 5:** One-shot only. Dynamic check (`Continuation_already_resumed`). Cheaper, sufficient for concurrency.
- **Eff/Koka:** Multi-shot supported via stack copying when capturing. More expressive (enables backtracking, probabilistic programming) but more expensive.
- **Hybrid approach:** Distinguish "resumable exceptions" (one-shot, fast) from "general effects" (potentially multi-shot) at the type level.

### Challenge 2: Effect Safety (Unhandled Effects)

**Problem:** If a computation performs an effect that has no handler, the program crashes (like an unhandled exception).

**Solutions:**
- **Koka:** Row-polymorphic effect types. The type system ensures all effects are handled. Function types include effect rows.
- **Eff (language):** No effect system in the language; unhandled effects are runtime errors.
- **OCaml 5:** No effect system yet. Unhandled effects raise `Effect.Unhandled`. An effect system is under active development (Leo White's work at Jane Street).
- **Type-based approach:** Effect variables and effect rows in function types ensure that callers must handle or propagate effects.

### Challenge 3: Interaction with C Code / Foreign Function Interface

**Problem:** Effect handlers use non-standard control flow. C code on the stack between the `perform` and the handler breaks the model.

**Solutions:**
- **OCaml 5:** Effects **cannot cross C callbacks**. If an effect is performed and there's a C frame between the perform and the handler, it raises `Effect.Unhandled`. Libraries using C callbacks must be carefully mixed with effect-using code.
- **Koka:** Manages this via its compilation strategy (CPS-based).

### Challenge 4: Interaction with Asynchronous Callbacks (Signals, Finalizers)

**Problem:** Performing effects from signal handlers, finalizers, GC alarms, or memprof callbacks is problematic because there may not be a handler in the right place.

**Solutions:**
- **OCaml 5:** Effects are **synchronous** — cannot perform from these contexts. Attempting to do so raises `Effect.Unhandled`.

### Challenge 5: Resource Leaks from Unresumed Continuations

**Problem:** If a continuation is captured but never resumed (or discontinued), the fiber's memory and any resources held by the suspended computation leak.

**Solutions:**
- **OCaml 5 discipline:** Every continuation must be resumed exactly once. Use `discontinue k e` to unwind with an exception, allowing `finally` blocks to run.
- **Finalizers:** `Gc.finalise (fun k -> discontinue k Unwind) k` — but runtime cost is higher than explicit resumption.
- **Koka:** Automatic resource management through handler-local resources.

### Challenge 6: Stack Management Overhead

**Problem:** Creating a fiber for every handler scope can be expensive if handlers are deeply nested or used in tight loops.

**Solutions:**
- **OCaml 5:** Fibers start small and grow dynamically. Not allocated for `try/with` exception handlers (only for effect handlers). Fiber reuse when possible.
- **Optimization:** Compiler can avoid fiber allocation when effects are not performed in the handler body.

### Challenge 7: Effect Polymorphism and Type Inference

**Problem:** Tracking effects in the type system adds complexity to type inference. Need to infer effect rows, handle effect variables for higher-order functions.

**Solutions:**
- **Koka:** Row-polymorphic effect inference. Most functions have an inferred effect variable `'e` that propagates effects from function arguments. The `~` (tilde) arrow is syntactic sugar for this common pattern.
- **Bauer & Pretnar:** Effect system with inference for core Eff (formalized but not fully in the Eff language).

---

## 9. Type Systems for Algebraic Effects

### Row Polymorphism

The most prominent approach, used by **Koka**:

- Effects are represented as **rows** — ordered sequences of effect labels with an optional row variable for extensibility
- Example type: `(int) -> int -{div, state<s>}>` — function that may divide and access state
- **Row polymorphism:** `(a) -> b -{e|r}>` — function that performs effect `e` and possibly others captured by row variable `r`
- **Permutation:** Rows can be permuted when effect labels are different: `-{div, state}> = -{state, div}>`
- **Subtyping:** It's safe to have more effects than required: a function that only needs `div` can run in a context that handles `div` and `state`

### Effect Variables

For higher-order functions, effect variables express **effect polymorphism**:
```
map : (a -> b -{e}->) -> list a -> list b -{e}->
```
This says: map takes a function that may perform effect `e`, and map itself may perform effect `e`. The same `e` ensures effect propagation.

### Tilde Arrow Notation (Koka)

Since most functions follow the pattern of "propagate the effects of my function argument", Koka introduces syntactic sugar:
- `a ~{e}-> b` means `a -> b -{e}->` — a function that propagates effect `e`
- Straight arrow `a -> b` means the function is pure (no effects)
- This makes the common case concise

### Bauer-Pretnar Effect System

From "An Effect System for Algebraic Effects and Handlers" (arXiv:1306.6316):
- **Effect types** are sets of operation signatures
- An expression has both a **value type** and an **effect type**
- Effect annotations on function types: `a -> b ! {Get, Set}`
- The effect system is designed to be **inferrable**
- Proven safe with respect to operational semantics
- Adequate denotational semantics via domain theory
- Derives useful contextual equivalences including commutativity for non-interfering state

### OCaml's Emerging Effect System (Under Development)

From Leo White's Jane Street talk:
- Distinguishes **pure** functions from **effectful** ones
- **Tracked exceptions** (via `throw`) vs. **untracked exceptions** (via `raise`)
- An `IO` effect for native OCaml side effects
- Effect variables for higher-order functions
- Backwards-compatible with current OCaml (effect annotations can be inferred/omitted)
- Tilde arrow as sugar for effect-polymorphic functions

---

## 10. The Relationship to Delimited Continuations

### Formal Relationship

Algebraic effect handlers **generalize** delimited continuations. The relationship is:

| Delimited Continuations | Algebraic Effects |
|------------------------|-------------------|
| `reset` (prompt/delimiter) | Handler scope (`try ... with effect ...`) |
| `shift k` (capture continuation) | `perform op` (captures continuation + effect value) |
| `k v` (resume continuation) | `continue k v` |
| Dynamic prompt identity | Static effect type |

**Key differences:**

1. **Typed vs. untyped:** Delimited continuations are usually dynamically typed (prompt identity is a runtime value). Algebraic effects are **typed** — each effect operation has a specific input and output type.

2. **Structured:** Effect handlers provide a more structured interface. The `try ... with effect` syntax makes it clear what effects are being handled and what happens for each one. Delimited continuations are more "powerful but dangerous" — you can implement any control operator with them, but the code can be hard to understand.

3. **Composable:** Multiple effect handlers compose naturally (nesting). Multiple `reset`/`shift` pairs compose too, but reasoning about which `shift` captures which `reset` can be confusing.

4. **Effect safety:** With effect types, you can statically ensure all effects are handled. With delimited continuations, a `shift` without a matching `reset` is a runtime error.

### Encoding Delimited Continuations as Algebraic Effects

You can implement `shift`/`reset` using algebraic effects:

```
effect Shift : (('a -> 'b) -> 'b) -> 'a

fun shift(f) = perform Shift(f)

fun reset(thunk) =
  try thunk()
  with
  | effect Shift(f), k ->
    f(fun x -> continue k x)
```

This is the standard encoding. The `Shift` effect takes a function that receives the continuation as an argument (the standard `shift` interface).

### Encoding Algebraic Effects as Delimited Continuations

Conversely, every algebraic effect handler can be expressed using delimited continuations:

```
let prompt = new_prompt()
fun perform(op) = shift (fun k -> set_prompt(prompt, (op, k)))
fun handle(thunk) =
  reset prompt (fun () ->
    match thunk() with
    | (op, k) -> /* handler code with access to k */
  )
```

This shows they have **equivalent expressive power**. The difference is in the programming model: algebraic effects provide a **typed, structured, composable** interface to the same underlying mechanism.

### The Deeper Theoretical Connection

Plotkin and Pretnar showed that:
- The **free algebra** for an effect signature corresponds to the syntax tree of operations
- A **handler** for that signature is an **algebra morphism** from the free algebra
- The universal property of the free algebra ensures that any such morphism is unique
- This is exactly analogous to how `fold` (catamorphism) works for algebraic data types
- Delimited continuations provide the **operational** mechanism; algebraic effects provide the **algebraic** structure

---

## Appendix: Key References Summary

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|-----------------|
| "Algebraic Operations and Generic Effects" | Plotkin & Power | 2003 | Algebraic operations for effects |
| "Handlers of Algebraic Effects" | Plotkin & Pretnar | 2009 | Effect handlers |
| "Programming with Algebraic Effects and Handlers" | Bauer & Pretnar | 2012 | Eff language |
| "An Effect System for Algebraic Effects and Handlers" | Bauer & Pretnar | 2013 | Effect system for Eff |
| "Koka: Programming with Row-Polymorphic Effect Types" | Leijen | 2014 | Row-polymorphic effects |
| "An Introduction to Algebraic Effects and Handlers" | Pretnar | 2015 | Tutorial |
| "Algebraic Effect Handlers with Resources" | Leijen | 2018 | Resources + deep/shallow |
| "Retrofitting Parallelism onto OCaml" | Dolan et al. | 2020 | Multicore OCaml / fibers |
| "Effective Programming" (talk) | Leo White | ~2019 | OCaml effect system design |

---

## Appendix: Code Examples

### OCaml 5 — User-Level Thread Scheduler

```ocaml
open Effect
open Effect.Deep

type _ Effect.t += Fork : (unit -> unit) -> unit t
                   | Yield : unit t

let fork f = perform (Fork f)
let yield () = perform Yield

let run (main : unit -> unit) : unit =
  let run_q = Queue.create () in
  let enqueue k v = Queue.push (fun () -> continue k v) run_q in
  let dequeue () =
    if Queue.is_empty run_q then ()
    else (Queue.pop run_q) ()
  in
  let rec spawn f =
    match f () with
    | () -> dequeue ()
    | effect Yield, k -> enqueue k (); dequeue ()
    | effect (Fork f), k -> enqueue k (); spawn f
  in
  spawn main
```

### Eff — State Handler

```eff
effect lookup : unit -> int
effect update : int -> unit

let handler state (s : int) : 'a -> 'a =
  handler
  | val x -> fun _ -> x
  | effect lookup (), k -> fun s -> continue k s s
  | effect update s', k -> fun _ -> continue k () s'
```

### Koka — Effect with Handler

```koka
effect state<s> {
  fun get() : s
  fun set(x : s) : ()
}

fun run_state<s, a>( init : s, action : () -> a / {state<s>} ) : (s, a) {
  with handler {
    fun get() { resume(s) }
    fun set(x) { s := x; resume(()) }
  }
  (s, action())
}
```
