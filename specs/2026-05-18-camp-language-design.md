# Camp Language Design Specification

> *"A language that doesn't affect the way you think about programming is not worth knowing."* — Alan Perlis

## Table of Contents

1. [Overview](#1-overview)
2. [Design Philosophy and Influences](#2-design-philosophy-and-influences)
3. [Type System and Syntax](#3-type-system-and-syntax)
4. [Effect System](#4-effect-system)
5. [Compilation Pipeline](#5-compilation-pipeline)
6. [Memory Management](#6-memory-management)
7. [Standard Library and Runtime](#7-standard-library-and-runtime)
8. [Module System and Packages](#8-module-system-and-packages)
9. [Concurrency Model](#9-concurrency-model)
10. [Metaprogramming](#10-metaprogramming)
11. [Testing](#11-testing)
12. [Open Design Questions](#12-open-design-questions)
13. [References](#13-references)
14. [Appendix: Design Decision Ledger](#appendix-a-design-decision-ledger)
15. [Appendix: Comparison with Related Languages](#appendix-b-comparison-with-related-languages)
16. [Appendix: Syntax Reference Card](#appendix-c-syntax-reference-card)

---

## 1. Overview

Camp is a general-purpose, strictly-typed functional programming language that compiles to WASM/WASI. It features Koka-style algebraic effects for safe, composable side-effect tracking, structural typing with row polymorphism for sum and product types, and Perceus reference counting for deterministic memory management with guaranteed destructive-read semantics.

The compiler is written in Odin — deliberately never bootstrapped — and prioritizes fast compilation via data-oriented design, arena allocation per compilation phase, and parallel per-file front-end processing.

### Key Properties

| Property | Decision | Rationale |
|----------|----------|-----------|
| **Paradigm** | Functional, strict evaluation | Algebraic effects pair naturally with strict evaluation; laziness introduces unpredictable performance |
| **Type system** | Strict, statically typed, principal type inference | Sound, decidable, principal — following Roc's model (Ref: [Roc type system](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md)) |
| **Effect system** | Koka-style tracked algebraic effects | Effect rows in types prove all effects are handled; lexical handlers give predictable semantics |
| **Memory** | Perceus reference counting | Deterministic deallocation, guaranteed in-place reuse, no runtime GC dependency, path to native backends |
| **Compilation target** | WASM/WASI | Near-native performance, JIT via runtime, broad deployment (local, container, browser) |
| **Implementation** | Odin | SOA types, arena allocators, tagged unions, WASM target support — optimal for compiler implementation |
| **Code generation** | Direct WASM emission | No LLVM dependency = faster compilation; runtime JIT compensates for lack of LLVM optimization |

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Camp Source (.camp)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │   Parse     │  Pratt parser
                    │  (per-file) │  → Surface AST
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │Canonicalize │  Deferred imports, derive expansion
                    │  (partial)  │  → Canonical AST  (cacheable)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Typecheck   │  Bidirectional inference (Level)
                    │  (partial)  │  → Typed IR  (cacheable)
                    └──────┬──────┘
                           │
              ┌────────────▼────────────┐
              │  Module Graph Combination│  Finish canonicalize + typecheck
              │    (whole-program)       │  Resolve deferred imports
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │Effect Lower │  perform → continuation calls
                    │             │  → Effect-lowered IR
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │Closure Conv │  Free vars → environment structs
                    │             │  → Closure-converted IR
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │CPS Transform│  Effectful fns → continuation-passing
                    │  + Inlining │  Coroutines → state machines
                    │             │  → CPS IR
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │Perceus RC   │  Insert inc/dec, reuse analysis
                    │  Insertion  │  deferred decrement optimization
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │WASM Codegen│  Direct binary emission
                    │             │  → .wasm module
                    └─────────────┘
```

---

## 2. Design Philosophy and Influences

### 2.1 Core Principles

1. **Effects are the abstraction layer.** Algebraic effects subsume monads, exceptions, async/await, and state management. One mechanism replaces many. Effect rows in types make side effects explicit and provably handled.

2. **Structural typing by default, nominal when needed.** Tag unions and records are structural — their type is determined by their shape, not a name. Nominal typing is available via newtypes for encapsulation, trait opt-in, and derive targets.

3. **Fast compilation is a feature.** The compiler is never bootstrapped. It's written in Odin for maximum control over memory layout and allocation. Per-file front-end phases are parallelizable and cacheable. Direct WASM emission avoids the LLVM bottleneck.

4. **One way to do things.** When two mechanisms overlap, pick one. This drove the decisions to drop `?` (Throw handles error propagation), drop `with`/`use` (effect handlers cover the same ground), and use Iter-only for collections (not separate eager List ops).

5. **No hidden control flow.** Effectful functions are marked with `!` at both definition and call sites. Mutable variables are marked with `$` at every use. Effect operations are qualified by their effect name. The reader always knows when non-local control flow may occur.

6. **The compiler never crashes.** Every "impossible" state becomes an `InternalCompilerError` diagnostic rather than a panic, segfault, or abort. Three error categories: warnings, errors, internal errors.

### 2.2 Language Influences

| Language | What Camp Takes | What Camp Rejects | Key Reference |
|----------|----------------|-------------------|---------------|
| **Koka** | Algebraic effects with tracked effect rows, lexical handlers, Perceus RC, effect polymorphism | Multi-shot continuations (Camp uses one-shot like OCaml 5), effect inheritance (Camp uses composition) | [koka-lang.github.io](https://koka-lang.github.io) |
| **Roc** | Structural tag unions, `!` suffix convention, `$`-prefix for vars, `?` for Try propagation (influenced the error discussion), platform model (influenced pluggable allocators) | Platform host model (Camp has its own runtime), separate type annotations above definitions, thick arrow `=>` for effectful types | [roc-lang.org](https://roc-lang.org), [Roc new compiler tutorial](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md) |
| **OCaml 5** | One-shot continuations, deep + shallow handlers, effect operations as normal function calls | Unchecked effects (Camp enforces effect safety at compile time), effect polymorphism via modular implicits | [ocaml.org](https://ocaml.org) |
| **Zig** | Comptime evaluation, error return traces (deferred for Camp), no hidden allocations principle, cross-compilation as a first-class concern | Comptime as full replacement for generics (Camp uses both), manual memory management everywhere (Camp uses Perceus) | [ziglang.org](https://ziglang.org) |
| **Rust** | Well-integrated stdlib philosophy, `pub` visibility, derive macros, structured concurrency, UFCS, `r#` raw identifiers (adapted to backticks) | Borrow checker, lifetime annotations, full type classes with coherence, zero-cost abstraction via LLVM | [rust-lang.org](https://rust-lang.org) |
| **Gleam** | Unified namespace, `use` callback inversion (influenced the discussion, ultimately dropped in favor of effect handlers), deliberate simplicity | No type classes at all (Camp has lightweight traits) | [gleam.run](https://gleam.run) |
| **Unison** | Abilities as effects, `Exception`/`Throw`/`Abort` hierarchy, always-qualified effect operations, bridge functions between effects and values | Content-addressed code, ability to have multiple instances of same ability | [unison-lang.org](https://unison-lang.org) |
| **Effekt** | `do` keyword for effect invocation (Camp uses `!` suffix instead), `with` for handler binding, explicit capability passing | Effect handlers as capabilities only | [effekt-lang.org](https://effekt-lang.org) |
| **Odin** | `#soa` types for data-oriented design, context-based allocators, tagged unions, arena allocation | No comptime, no macro system | [odin-lang.org](https://odin-lang.org) |

### 2.3 Design Decision Process

Every major design decision was evaluated against three criteria:

1. **Compilation speed** — Does this feature add passes, increase IR complexity, or require whole-program analysis?
2. **Type system coherence** — Does this feature interact cleanly with effect rows, row polymorphism, and structural typing?
3. **Ergonomic simplicity** — Does this feature follow the "one way to do things" principle, or does it introduce redundancy?

---

## 3. Type System and Syntax

### 3.1 Naming Conventions

| Category | Convention | Examples | Rationale |
|----------|-----------|----------|-----------|
| Types | UpperCamelCase | `Int`, `List`, `UserId` | Universal convention across ML/Rust/Java family |
| Tags | UpperCamelCase, no prefix | `Ok`, `Err`, `NotFound`, `True` | Tags are UpperCamelCase; functions are lowercase. Case alone disambiguates tags from functions. |
| Type/effect variables | lowercase | `a`, `b`, `e`, `rest` | ML tradition — instantly distinguishes variables from concrete types. `List(a)` vs `List(User)`. |
| Functions | lowercase (snake_case or camelCase TBD) | — | UpperCamelCase identifiers are always types or tags; lowercase are always functions or variables |
| Variables | lowercase (same as functions) | — | Same as functions |
| Mutable variables | `$` prefix | `$count`, `$buffer` | Visual marker at every use site — mutation is always visible |

### 3.2 Primitive Types

| Type | Size | Description |
|------|------|-------------|
| `I8` | 8-bit | Signed integer |
| `I16` | 16-bit | Signed integer |
| `I32` | 32-bit | Signed integer |
| `I64` | 64-bit | Signed integer |
| `U8` | 8-bit | Unsigned integer |
| `U16` | 16-bit | Unsigned integer |
| `U32` | 32-bit | Unsigned integer |
| `U64` | 64-bit | Unsigned integer |
| `F32` | 32-bit | IEEE 754 single-precision float |
| `F64` | 64-bit | IEEE 754 double-precision float |
| `Bool` | 1-bit | `True` or `False` |

**Design decision**: Fixed-size numeric types (like Roc/Rust) rather than unbounded integers. Rationale: maps cleanly to WASM's i32/i64/f32/f64 types, no runtime overhead for bigint checks, predictable performance. Unbounded integers can be a library type if needed.

**Default number type**: Unannotated integer literals default to `I64`; unannotated float literals default to `F64`. These map directly to WASM's i64/f64 types. Explicit annotations always override: `x: U8 = 42`.

| Literal | Default type | Override example |
|---------|-------------|-----------------|
| `42` | `I64` | `x: U8 = 42` |
| `3.14` | `F64` | `y: F32 = 3.14` |

**Design decision**: I64/F64 was chosen over no-default, I32/F64, and Dec (Roc's choice). I64 avoids the most common overflow class; F64 is the standard float precision; both map directly to WASM primitives. Dec (fixed-point decimal) would solve `0.1 + 0.2 = 0.3` but adds runtime overhead and is overkill for non-financial code. It can be a library type.

### 3.3 Standard Library Types (Heap-Allocated)

| Type | Description | Memory representation |
|------|-------------|----------------------|
| `Str` | UTF-8 string | Pointer + length (not zero-terminated) |
| `List(a)` | Persistent linked list or rope | Pointer + length + refcount |
| `Bytes` | Raw byte sequence | Pointer + length + refcount |
| `Map(k, v)` | Hash map | HAMT or similar persistent structure |
| `Set(a)` | Hash set | HAMT or similar persistent structure |
| `Iter(a)` | Lazy iterator pipeline | Closure chain (fused by inlining) |
| `Handle(a)` | Async coroutine handle | State machine pointer |

These are not primitives — they are defined in the standard library with Perceus-managed reference counting. Their internal representation is an implementation detail, not part of the language specification.

### 3.4 Tag Unions (Structural, Roc-style)

**Origin**: The tag union system is taken from Roc ([Roc new compiler tutorial](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md)). Tags are structural discriminated unions with optional payloads per variant. At compile time, the set of variants is inferred from which tags are used in a given scope.

**No `#` prefix**: Tags are written as bare UpperCamelCase names. Functions and variables are always lowercase. Case alone disambiguates: `Ok(42)` is a tag (uppercase), `ok(42)` is a function call (lowercase). This follows Roc's design.

**Open vs closed tag unions**:

| Syntax | Meaning |
|--------|---------|
| `[Ok(a) \| Err(e)]` | **Closed** — exactly these tags, no others |
| `[Ok(a) \| Err(e) \| ..]` | **Open** — at least these tags, possibly more, rest not captured |
| `[Ok(a) \| Err(e) \| ..rest]` | **Open** — at least these tags, rest captured as row variable |
| `[..]` | **Fully open** — zero or more tags (the "any" case) |

**Tag construction**:
```
Ok(42)                           -- tag with payload
Err("something went wrong")      -- tag with payload
None                             -- tag with no payload (no parens needed)
True                             -- tag with no payload
```

**Nominal tag qualification**: Tags of nominal types are qualified by the type name at construction, matching Roc's model:
```
Result.Ok(42)                    -- qualified by nominal type
Result.Err("fail")               -- qualified by nominal type

import Result exposing [Ok, Err]  -- import unqualified
Ok(42)                           -- now unqualified
```

Structural tags (not belonging to a nominal type) are always unqualified.

**Pattern matching** — strict exhaustiveness:
```
match result {
  Ok(value) => value
  Err(msg) => handle_error(msg)
}

match maybe_name {
  Some(name) => greet(name)
  None => greet("stranger")
}

-- Wildcard catch-all:
match result {
  Ok(value) => value
  _ => fallback              -- catches any remaining variants
}
```

**Exhaustiveness rules**:
- Closed tag unions require all variants covered — either explicitly or via `_ =>`
- Open tag unions require at least one handler; `_ =>` covers remaining tags
- `_ =>` is always allowed and covers remaining variants
- The compiler warns if `_ =>` is unreachable (meaning all variants were already covered)
- This matches Rust's approach: exhaustiveness is enforced, wildcards are permitted, redundant wildcards are warned

**Variant set inference**: The type of a tag union is inferred from the tags that appear in a scope. If a function returns `Ok(42)` in one branch and `Err("fail")` in another, the inferred return type is `[Ok(Int) | Err(Str)]`. Adding a new branch that returns `Timeout` widens the type to `[Ok(Int) | Err(Str) | Timeout]`. All call sites that pattern match must handle the full set.

**Design decision — structural vs nominal tags**: Tags are structural — `Ok(42)` doesn't belong to a named type unless qualified (e.g., `Result.Ok(42)`). The type is the set of possible tags. Nominal aliases can be created with newtypes: `Result(a, e) := [Ok(a) | Err(e)]`. This gives you both structural flexibility (tags compose freely) and nominal identity when you need it (for trait implementations, derive targets, encapsulation).

**Design decision — no `#` prefix**: Roc demonstrates that bare UpperCamelCase tags work well. The key enabler is the naming convention rule: functions/values are lowercase, types/tags are UpperCamelCase. This means `Ok(42)` is unambiguously a tag (uppercase first letter), and `ok(42)` is unambiguously a function call (lowercase first letter). No type inference needed for disambiguation — it's purely syntactic. The `#` prefix adds visual noise without resolving any ambiguity that case doesn't already resolve.

**Alternative considered**: Keeping `#` for extra safety even though case disambiguates. Rejected because the redundancy adds noise with no benefit — the case rule is simpler and sufficient.

### 3.5 Records (Structural, Row-Polymorphic)

Records are anonymous products with insignificant field order. Row variables enable polymorphism — a function can accept any record that has the required fields, regardless of what other fields it may contain. The `..` operator is used consistently for "and possibly more" across records, tag unions, patterns, and Throw.

**Open vs closed records**:

| Syntax | Meaning |
|--------|---------|
| `{ name: Str, age: U64 }` | **Closed** — exactly these fields, no others |
| `{ name: Str, .. }` | **Open** — at least `name`, possibly more, rest not captured |
| `{ name: Str, ..rest }` | **Open** — at least `name`, rest captured as row variable |

**Construction, update, and destructuring**:
```
{ name: Str, age: U64 }           -- closed type
{ name: Str, .. }                 -- open type (rest not captured)
{ name: Str, ..rest }             -- open type with row variable
{ name: "Camp", age: 1 }         -- construction
{ ..record, name: "new" }         -- functional update (creates new record)
{ name, age } = record            -- closed destructuring (exact fields)
{ name, .. } = record             -- open destructuring (allows extra fields)
record.name                        -- field access (dot syntax)
```

**Row polymorphism**:
```
greet = |person: { name: Str, .. }| {
  "Hello, ${person.name}!"
}

-- Both calls type-check because the open record type accepts extra fields:
greet({ name: "Alice", age: 30 })
greet({ name: "Bob", department: "Engineering" })
```

**Consistent `..` syntax**: The `..` operator means "and possibly more" in type and destructuring contexts:
- `{ name: Str, .. }` — open record type
- `{ name, .. } = record` — open destructuring (ignores extra fields)
- `[Ok(a) | ..]` — open tag union type
- `Throw([..])` — can throw any tag
- `{ ..record, name: "new" }` — record update

Note: `_` (not `..`) is used as the wildcard in pattern matching, following universal language convention.

**Field order insignificance**: `{ name: Str, age: U64 }` and `{ age: U64, name: Str }` are the same type. This is standard row polymorphism as described by Rémy (1994) and implemented in Koka, PureScript, and others.

**Alternative considered**: Order-significant records (simpler implementation). Rejected because:
- Field order shouldn't be semantically meaningful
- Order-independence matches mathematical record notation
- Most row-polymorphic languages treat order as insignificant
- Implementation complexity is manageable (sort fields at canonicalization)

### 3.6 Newtypes (Nominal)

Newtypes create a distinct type wrapping an existing type. They provide nominal identity for structural types, enabling trait implementations and encapsulation.

**Syntax**:
```
UserId is Hash := U64
OrderId := U64
@derive [Display, Hash, Eq, Serialize]
ProductId := U64
```

- `:=` creates the newtype
- `is` declares trait conformance
- `@derive` auto-generates trait implementations

**Construction and destruction** (nominal types are qualified at construction):
```
uid: UserId = UserId(42)           -- qualified construction
inner: U64 = uid.inner()          -- access inner value

-- Or import unqualified:
import UserId exposing [UserId]
uid = UserId(42)
```

**Why newtypes instead of named record types**: Camp chose newtype-style nominal typing (like Roc) rather than named records for several reasons:
- Records are structural — adding nominal records would create a parallel type system with complex interaction rules
- Newtypes are simpler: one wrapped type, clear construction/destruction
- Most use cases for nominal types (type safety, trait impls, derive) are served by newtypes
- Named records can be simulated: `User := { name: Str, age: U64 }` wraps a structural record in a newtype

**Alternative considered**: Named record types like `type User = { name: Str, age: U64 }` with nominal identity. Rejected because it creates two kinds of records (structural and nominal) with confusing interaction. Newtypes are the single nominal mechanism.

### 3.7 Functions

All functions use `|args| body` syntax — from top-level definitions to anonymous lambdas. This is the only function syntax in Camp. There is no `fn` keyword, no `def` keyword, no `func` keyword.

**The `!` suffix convention**: Effectful functions are named with a `!` suffix. This is a naming convention enforced by the compiler — a function whose effect row is non-empty must have `!` in its name. A function named without `!` must have an empty effect row.

**Type annotation syntax**: Type parameters, argument types, and return type are all embedded within the function's arg block:

```
-- Named function definition:
add = <a>|x: a, y: a| -> a { x + y }

-- Type-only declaration (for traits, interfaces):
add : <a>|a, a| -> a

-- Anonymous function:
|x: Int, y: Int| -> Int { x + y }

-- Effectful function:
read_line! = || ->{ Console } Str { Console.readln!() }

-- Generic with trait constraint:
format = <a is Display>|x: a| -> Str { x.display() }
```

**Syntax breakdown**:
```
name = <type_params>|param: type, ...| ->return_type { body }
     ^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^   ^^^^^^
     generic vars   parameters+types    return type   block body

name : <type_params>|type, type, ...| ->return_type
     ^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^
     generic vars   type-only params    return type
```

**Key design decisions**:

1. **`=` for definitions, `:` for declarations**: Following the ML tradition of `let x = expr`. The binding syntax `add = ...` is consistent with all other value bindings.

2. **Generic params before `|`**: `<a>` comes before the parameter list. This groups the type-level information together at the start of the function signature.

3. **Return type after `|`...`| -> `**: The return type follows the parameter list, connected by `->`. This is the standard ML-family convention.

4. **Block body required for typed function definitions**: A function with a return type annotation must use `{ }` for its body. This eliminates ambiguity about where the type signature ends and the body begins. Anonymous functions without type annotations can have expression bodies: `|x| x + 1`.

5. **Effect row in the return type**: `->{ Eff1, Eff2 }` comes after `->`. The presence of effects after the arrow implies effectfulness — no need for a separate thick arrow (`=>`) as in Roc. This simplifies the syntax: one arrow form, with the effect row as an optional component.

6. **`!` suffix for effectful names**: The compiler enforces that a function named with `!` has a non-empty effect row, and vice versa. This makes effectfulness visible at every call site without a separate keyword.

**Alternatives considered**:

| Alternative | Example | Why rejected |
|-------------|---------|--------------|
| `fn` keyword | `fn add(x: Int, y: Int) -> Int { ... }` | C-family syntax doesn't match ML-family language |
| Separate type annotation | `add : Int, Int -> Int` on one line, `add = \|x, y\| x + y` on next | Requires two statements per function; breaks the single-definition pattern |
| Roc-style separate annotation | `add : Int, Int -> Int` above `add = \|x, y\| x + y` | Same issue — two statements, also Roc is moving away from this |
| Thick arrow `=>` | `echo! : Str => Str` | Redundant — the `!` suffix and effect row already communicate effectfulness |
| `do` keyword for effect calls | `do Async.yield!()` | `!` suffix on the function name already marks the call as effectful; `do` adds no information |

### 3.8 Logic Operators

`and` / `or` keywords for boolean logic. No `&&` / `||` symbol operators.

**Rationale**: The `||` operator creates a syntactic ambiguity with empty-argument function syntax. `|| { body }` is a function that takes no arguments, but `||` could also be read as a logical OR. Using `and`/`or` keywords eliminates this ambiguity entirely.

**Precedent**: Python, Ada, VHDL, and Gleam all use keyword-based logic operators. This is well-established in languages that prioritize readability over brevity.

### 3.9 Var Syntax (Local Mutation)

Mutation is stack-local only — mutable bindings can exist only inside function bodies. The `$` prefix is required for both declaration and every use site. There is no `var` keyword — `$` alone signals mutability.

```
sum = |numbers: List(Int)| -> Int {
  $total = 0
  for n in numbers.iter() {
    $total = $total + n
  }
  $total
}
```

**Rules**:
- `$name = value` where `$name` doesn't exist in scope → declares a mutable binding
- `$name = value` where `$name` exists in the same function scope → reassignment
- `$name = value` where `$name` exists in an enclosing scope → error (shadowing banned)
- `$` prefix is banned on immutable bindings — `$` means "this is mutable" and is only valid where mutation occurs

**Design decision — `$` prefix at use sites**: Taken from Roc. The `$` prefix makes mutation immediately visible when reading code. Without it, you'd need to check the declaration site to know whether a binding is mutable — the `$` convention puts that information at every use site.

**Design decision — stack-local only**: Stronger than "local refs" (which would allow non-escaping ref cells). Stack-local mutation means:
- No aliasing analysis needed
- No borrow checker needed
- The compiler can always tell whether a value is mutable by looking at its declaration
- Interaction with Perceus is simple — vars are stack-allocated, no refcount overhead

**Alternative considered**: Local refs that don't escape (like Swift's `inout` but scoped). Rejected because it adds escape analysis complexity for marginal benefit. Stack-local vars with `for` loops cover the common use cases.

### 3.10 Dot Lambdas

A dot lambda is a leading `.` followed by a method/field chain, creating an anonymous function that applies the chain to its argument.

| Syntax | Desugars to |
|--------|-------------|
| `.foo(x)` | `\|a\| a.foo(x)` |
| `.name` | `\|a\| a.name` |
| `.foo().bar(x)` | `\|a\| a.foo().bar(x)` |
| `.record.field.method(x)` | `\|a\| a.record.field.method(x)` |

**Rules**:
- Valid in any expression position
- Effect rows propagate naturally — `.read!()` desugars to an effectful lambda
- Mixes field access and method calls freely
- `..` is spread syntax, not a double dot lambda — no ambiguity

**Design decision**: Dot lambdas are desugared at canonicalization. The surface AST preserves the dot lambda structure for tooling (formatter, LSP, error messages), but the typechecker and later stages see a plain lambda.

### 3.11 Traits

Traits are structurally verified but nominally declared. A type must explicitly declare `is Trait` to satisfy the trait, and the compiler verifies that the required methods exist and have the correct signatures.

**Syntax**:
```
trait Display {
  display : Self -> Str
}

trait Eq {
  eq : Self, Self -> Bool
}

trait Ord is Eq {
  compare : Self, Self -> Ordering
}

UserId is Hash := U64
```

**Key properties**:
- **Structural verification**: The compiler checks that the type's methods match the trait's required signatures by shape, not by name resolution
- **Nominal opt-in**: Types must explicitly declare `is Trait` — structural conformance alone is insufficient
- **Tree inheritance**: Traits can inherit from other traits with `is`. `Ord is Eq` means any type that `is Ord` must also implement `Eq`
- **Orphan rule**: `is` declarations must be in the module that defines the type or the module that defines the trait. This prevents two modules from independently and contradictorily implementing the same trait for the same type
- **No higher-kinded types**: Type parameters are always kind `*`. No type constructor parameters (`* -> *`)
- **No overlapping instances**: Each type can have at most one `is` declaration per trait

**Constraints in function signatures**:
```
format = <a is Display>|x: a| -> Str { x.display() }

lookup = <a is Hash, b>|key: a, map: Map(a, b)| -> Some(b) | None { ... }
```

**Trait method dispatch**: UFCS (Uniform Function Call Syntax). `x.display()` desugars to `Display.display(x)`. This works consistently whether `display` is a trait method or a standalone function.

**Design decision — why `is` instead of `implements`**: `is` is more terse and reads naturally: `UserId is Hash` vs `UserId implements Hash`. The shorter keyword reduces visual noise in type annotations and trait declarations.

**Alternative considered — full Rust-style traits**: Complete type class system with associated types, overlapping instances via specialization, and coherence through orphan rules. Rejected because:
- Significantly more complex type inference
- Slower compilation (coherence checking, instance resolution)
- Camp's structural verification + nominal opt-in covers 90% of use cases
- Can be extended incrementally if needed

**Alternative considered — Roc-style `where` clauses**: `stringify : a -> Str where [a.to_str : a -> Str]`. Rejected because:
- No named abstractions (can't define `Hashable`, `Display` as reusable contracts)
- Method resolution by name only — less precise than trait dispatch
- No derivation target — `@derive` needs a named trait to implement

### 3.12 Effect Rows

Every function type includes an effect row — a set of effects that the function may perform. This is the core of Camp's effect tracking system, following Koka's design.

**Syntax**:
```
a -> b                      -- pure (empty effect row, elided)
a ->{ Eff1, Eff2 } b        -- effectful (explicit effect row)
a ->{ e } b                 -- effect row variable (polymorphic)
a ->{ Throw(NotFound) } b   -- parameterized effect
```

**Effect row properties**:
- Rows are sets — order is insignificant, duplicates are removed
- The empty row is elided: `Int -> Int` means `Int ->{} Int`
- Row variables (`e`, `rho`) enable effect polymorphism — a generic function propagates whatever effects its arguments have
- Effect rows compose: if `f : a ->{ E1 } b` and `g : b ->{ E2 } c`, then `g(f(x)) : a ->{ E1, E2 } c`

**Effect row in function definitions**:
```
-- Pure function (empty row):
add : Int, Int -> Int

-- Effectful function (explicit row):
echo! : Str ->{ Console } {}

-- Polymorphic effect propagation:
map = <a, b, e>|f: |a| ->{ e } b, list: List(a)| ->{ e } List(b) { ... }
```

### 3.13 Inline Type Annotations

Types are annotated inline with `:`, never as a separate declaration above the binding.

```
x: Int = 3
name: Str = "Camp"
items: List(Int) = [1, 2, 3]
handler: Handle(Int) = Async.spawn!(|| { 42 })
```

**Design decision**: Roc and Haskell use separate type annotation lines (`x : Int` above `x = 3`). Camp uses inline annotations (`x: Int = 3`) for several reasons:
- Single statement per binding — less visual noise
- No ambiguity about which annotation applies to which binding
- Consistent with Rust's `let x: i32 = 3` convention
- Works naturally with function signatures embedded in the arg block

### 3.14 No Shadowing

All shadowing is forbidden. A binding name cannot be reused in the same scope or any nested scope.

**Rules**:
- Same-scope rebinding (`x = 1; x = 2`) is an error
- Nested-scope shadowing (`x = 1; if true { x = 2 }`) is also an error
- Destructuring must use fresh names: `{ name, age } = record` fails if `name` exists in scope
- Import names that conflict with existing bindings are an error

**Design decision**: Roc forbids all shadowing and reassignment. Camp adopts the same policy. Rationale:
- Eliminates an entire class of refactoring bugs (extracting a function silently changes behavior if a binding was shadowed)
- Makes code more predictable — a name always refers to the same binding
- With algebraic effects, shadowing becomes more dangerous — an effect handler could capture a binding that gets shadowed, leading to confusing behavior

**Alternative considered**: Nested-scope shadowing only (like F#). This would allow `let x = 1; let x = 2` in nested scopes but forbid same-scope rebinding. Rejected because the marginal ergonomics gain doesn't justify the complexity and refactoring risk.

### 3.15 Unified Namespace

One namespace per module for functions, values, types, traits, effects, and aliases. No separate type/value namespaces.

**Rationale**: Separate namespaces (as in OCaml and Haskell) create ambiguity with UFCS. Does `x.method()` mean calling a function `method` on `x`, or accessing a function-valued field? A unified namespace eliminates this question. Gleam uses a unified namespace for the same reason.

**Consequence**: A module cannot export both a type `Result` and a function `Result`. This is rarely a problem in practice — types and their companion functions typically share the same name and are accessed via the module (e.g., `Result.is_ok`).

### 3.16 Visibility

`pub` keyword marks exports. Everything else is private to the module.

**Rationale**: Rust-style `pub` is simple, well-understood, and doesn't require a separate interface file. The alternative — explicit export lists like Roc's `app [main!] { ... }` — requires maintaining a separate list that can drift out of sync with the implementation.

### 3.17 Raw Identifiers

Backtick-wrapped identifiers escape keyword conflicts: `` `do` ``, `` `is` ``, `` `type` ``.

**Design decision**: Chosen over Rust's `r#` prefix. Rationale:
- Backticks are visually consistent with Camp's style (they look like quoting, which is semantically accurate — you're "quoting" a keyword to use it as a name)
- Scala and Haskell use backtick identifiers, providing precedent
- `r#` is Rust-specific and visually jarring in a non-Rust language

### 3.18 Destructive Read Guarantee

Perceus destructive-read / last-use optimization is a guaranteed language semantic, not an optional optimization. The compiler proves last-use and reuses allocations in-place. `var` bindings participate in reuse analysis.

**Implications**:
- When the compiler determines a value is consumed for the last time, it may mutate it in-place rather than allocating a new copy
- This is a semantic guarantee, not just a performance optimization — programmers can reason about when reuse occurs
- The type system and borrow analysis must be strong enough to identify last uses
- This interacts with `var` bindings: `$x = $x + 1` on a last-use `$x` can reuse the allocation

**Reference**: Koka's Perceus implementation makes reuse analysis a language-level guarantee. See [Perceus: Garbage Free Reference Counting with Reuse](https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf) (Reinking, Xie, de Moura, Leijen — PLDI'21).

---

## 4. Effect System

### 4.1 Overview

Camp's effect system is its central abstraction mechanism. It follows Koka's design: effects are tracked in function types, handlers are lexically scoped, and the compiler enforces that all effects are handled. One mechanism replaces exceptions, async/await, state management, and more.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Effect System Architecture                                         │
│                                                                     │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐        │
│  │  Throw   │   │  Async   │   │  File    │   │ Console  │  ...    │
│  │ effect   │   │  effect  │   │  effect  │   │  effect  │        │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘        │
│       │              │              │              │                │
│       └──────────────┴──────────────┴──────────────┘                │
│                      │                                              │
│              ┌───────▼───────┐                                      │
│              │  Effect Row  │  Tracked in function types            │
│              │  { E1, E2 } │  Ensures all effects are handled      │
│              └───────┬───────┘                                      │
│                      │                                              │
│       ┌──────────────┼──────────────┐                               │
│       │              │              │                                │
│  ┌────▼────┐  ┌─────▼─────┐  ┌────▼─────┐                         │
│  │  Deep   │  │  Shallow  │  │ Runtime  │                          │
│  │ handler │  │(intercept)│  │ handler  │                           │
│  └─────────┘  └───────────┘  └──────────┘                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Effect Definitions

An effect declares a namespace of operations. Each operation is a function signature. Operations that perform effects carry `!` in their name (following the same convention as all effectful functions).

```
effect Async {
  yield!    : || ->{ Async } {}
  spawn!    : |thunk: || ->{ Async } a| ->{ Async } Handle(a)
  join!     : Handle(a) ->{ Async } a
  cancel!   : Handle(a) ->{ Async } {}
}
```

**Self-referential types**: An effect's operations include the effect itself in their effect row. `yield! : || ->{ Async } {}` means "calling `yield!` performs the `Async` effect." This is consistent — the effect row in the type tells you what calling this function will do.

**Operations are just functions**: There is no `perform` keyword. Effect operations are called like any other function: `Async.yield!()`. The `!` suffix on the operation name and the effect row in the type already communicate effectfulness.

**Design decision — no `perform`/`do` keyword**: Research showed that most algebraic effect languages invoke operations as plain function calls (Koka, Unison, Links). Only OCaml 5 and Eff use an explicit `perform` keyword, and Effekt uses `do`. Camp chose the implicit approach because:
- The `!` suffix already marks effectful calls
- Effect operations are qualified by their effect name (`Async.yield!`)
- No new syntax category needed — effect calls are just function calls
- Consistent with Koka and Unison

**Invocation alternatives considered**:

| Syntax | Language | Camp assessment |
|--------|----------|----------------|
| Bare call: `Async.yield()` | Koka, Unison, Links | Almost adopted, but the `!` suffix makes `Async.yield!()` more consistent |
| `perform Async.yield()` | OCaml 5, Eff | Too verbose; `perform` adds no information the type doesn't already provide |
| `do Async.yield()` | Effekt | Short but `do` is a common variable name; requires raw identifier escape |
| `!Async.yield()` | — | `!` as prefix conflicts with "not" operator in many languages |
| `Async.yield!()` | Camp | The `!` suffix follows Camp's own convention for effectful functions; no new keyword needed |

### 4.3 Effect Composition (No Inheritance)

Effects compose via aliases, not inheritance. This is a deliberate departure from the initial design, which considered `effect File is Io`.

**Problem with effect inheritance**: If `File is Io` and both define a `read!` operation, which `read!` does `File.read!` refer to? The collision is unavoidable when operations share names across an inheritance hierarchy.

**Research finding**: No mainstream effect language supports effect inheritance (Koka, Unison, Effekt, OCaml 5, Eff all use flat effect composition). Effects compose by set union in the type, not by subtyping.

**Solution — aliases for effect grouping**:
```
effect File {
  open!   : Str ->{ File, Throw(NotFound | PermissionDenied) } Handle
  close!  : Handle ->{ File } {}
  read!   : Handle ->{ File, Throw(Eof) } Str
  write!  : Handle, Str ->{ File } {}
}

effect Console {
  print!    : Str ->{ Console } {}
  printerr! : Str ->{ Console } {}
  readln!   : || ->{ Console } Str
}

alias Io = File | Console
```

`Io` is a type alias for the union `File | Console`. Functions can use `->{ Io }` as shorthand for `->{ File, Console }`. Operations are always qualified by their defining effect: `File.read!`, `Console.print!` — no ambiguity.

**Why `is` still applies to traits but not effects**: Traits define method signatures on types — inheritance there means "this trait requires all methods of the parent trait." Effects define operations in a namespace — inheritance would mean "this effect's operations include the parent's," which creates the collision. The `is` keyword applies to traits (where it makes sense) and trait constraints in type parameters, but not to effect composition.

### 4.4 Handlers

Handlers are lexically scoped — they only affect code within their `in { ... }` block. Two kinds:

#### Deep Handlers (Default)

A deep handler is re-installed after each `resume`. It handles all operations of its effect type that occur in the scoped block, including after resumptions.

```
handle Async in {
  Async.yield!()
  Async.yield!()
  Async.yield!()
} with {
  .yield!(resume) => {
    count = count + 1
    resume({})
  }
  .spawn!(resume, body) => { ... }
  .join!(resume, handle) => { ... }
}
```

Each `yield!` call is caught by the handler. The handler increments `count` and resumes. Deep semantics mean the handler stays installed after each resume — all three `yield!` calls are handled.

**Use cases**: General effect handling — exception catching, state management, I/O dispatch, async scheduling. This is the common case (~90% of handlers).

#### Shallow Handlers (`intercept`)

A shallow handler handles one operation and does not re-install itself. Only the first matching operation is caught; subsequent operations propagate to an outer handler (if any).

```
intercept Async in {
  Async.yield!()    -- caught by this handler
  Async.yield!()    -- NOT caught — propagates to outer handler
} with {
  .yield!(resume) => resume({})
}
```

**Use cases**: Stateful protocols where the set of handled effects changes over time. For example:
- Authentication → operation → cleanup (the handler changes after auth completes)
- Opening a file, reading, then closing (the handler evolves through phases)
- Any state machine modeled as an effect

**Syntax choice — `intercept` vs alternatives**:

| Syntax | Assessment |
|--------|------------|
| `handle!` | Confusing — `!` means effectfulness, not shallowness |
| `handle~` | Tilde suggests transient; no precedent in mainstream languages |
| `intercept` | Clear semantic — intercept one operation, don't re-install. Distinct keyword avoids confusion with `handle`. |

**Reference**: OCaml 5 provides both deep and shallow handlers with distinct syntax. See [OCaml 5 effect handlers](https://v2.ocaml.org/api/Effect.Deep.html) and [Effect.Shallow](https://v2.ocaml.org/api/Effect.Shallow.html).

### 4.5 One-Shot Continuations

Each `resume` can be called at most once. A second invocation is a runtime error (or a compile-time error when detectable).

**Design decision**: This follows OCaml 5's choice. Multi-shot continuations (as in Koka and Eff) allow a resume to be called multiple times, enabling backtracking and search as effects. However:
- Multi-shot requires copying stack frames at each continuation capture — significant runtime overhead
- One-shot is sufficient for the primary use cases: exceptions, async, state management
- Backtracking can be implemented with explicit state rather than multi-shot continuations
- One-shot enables simpler CPS compilation — the state machine has a linear progression

**Reference**: OCaml 5 explicitly chose one-shot continuations for performance and simplicity. See [OCaml 5 effects tutorial](https://ocaml.org/docs/effects-tutorial).

### 4.6 Throw Effect

`Throw` is Camp's built-in error effect. Its parameter is a tag union (using the same `[..]` syntax) that widens as more tag types are thrown.

```
Throw.throw! : <e>[e] ->{ Throw([e]) } a
```

**Throw variant union widening**:
```
parse_int! : Str ->{ Throw(NotFound) } Int

find_user! : UserId ->{ Throw(NotFound | PermissionDenied) } User

-- A function calling both:
process! : Str ->{ Throw(NotFound | PermissionDenied | BadNumStr) } User
```

**Open vs closed Throw types**:
```
Throw(NotFound)                           -- closed: exactly this tag
Throw(NotFound | PermissionDenied)        -- closed: exactly these tags
Throw([NotFound | ..])                    -- open: at least NotFound, possibly more
Throw([..])                               -- fully open: can throw any tag (the "any" case)
```

`Throw([..])` is used in `main!` to declare that the program may throw any unhandled tag. The runtime handler for `Throw([..])` renders the unhandled tag to stderr and exits non-zero.

**Throwing tags**:
```
parse_int! = |s: Str| ->{ Throw(BadNumStr) } Int {
  match Int.from_str(s) {
    Some(n) => n
    None => Throw.throw!(BadNumStr)
  }
}
```

### 4.7 Error Model

Camp uses a dual error model, following the pattern established by Koka and Unison:

| Error type | Mechanism | Example | When to use |
|-----------|-----------|---------|-------------|
| **Exceptional** | `Throw` effect | File not found, network timeout, parse failure | Errors that should propagate far; handled at boundaries |
| **Structural** | Tag union return | `List.first` → `Some(a) | None` | Absence/failure is a natural part of the computation; handled locally by pattern matching |

**Why both**: Research across Koka, Unison, Effekt, and OCaml 5 shows that effect languages converge on this dual approach. Using Throw for everything would force every `List.first` call to install a Throw handler — awkward for "expected" absence. Using tag unions for everything removes the control-flow power of effect-based error handling and forces manual propagation.

**No `?` operator**: Unlike Roc and Rust, Camp has no `?` operator for early-return on error. Rationale:
- Throw propagation is automatic via effect rows — a function that calls `Throw.throw!` gets `Throw(E)` in its effect row; no explicit propagation syntax needed
- Tag union results are handled by pattern matching — the `?` operator would only bridge tag unions to Throw, which is a specialized case
- One way to do things: Throw for exceptional errors, pattern match for structural absence

**Handlers bridge the two worlds**: A handler can convert Throw to a tag union at boundaries:
```
to_result = |action: || ->{ Throw(e) } a| -> [Ok(a) | Err(e)] {
  handle Throw in {
    Ok(action())
  } with {
    .throw!(resume, err) => Err(err)
  }
}
```

**Research basis**:
- **Koka**: Has both `raise`/`exn` effect and `maybe`/`either` types. `List.head` returns `maybe`. File operations use `exn`. Handlers bridge them.
- **Unison**: Has `Exception`, `Throw e`, `Abort` abilities plus `Optional`, `Either` types. `List.at` returns `Optional`. File operations use `Exception`. `toOptional!`, `toEither` bridge them.
- **Roc**: Uses `Try` tag union exclusively (no effects yet). All fallible operations return `Try`. The `?` operator is crucial for propagation.
- **OCaml 5**: Uses exceptions primarily, `option`/`result` secondarily. Effects are for concurrency, not error handling.

### 4.8 Effect Safety

Compile-time enforcement. Unhandled effects are errors. A function's effect row must be a subset of the effects handled by its caller's context.

**The whole point**: Without compile-time enforcement, effect tracking is just Java checked exceptions with extra steps. The primary value of tracked effects is that the type system proves all effects are handled. Camp enforces this.

**`main!`'s effect row is the declaration**: The runtime provides handlers for whatever effects `main!` lists in its row. No separate `app` or `entry` declaration needed.

```
-- A program that can print to console and throw errors:
main! = || ->{ Console, Throw([..]) } {
  Console.println!("Hello, Camp!")
  {}
}

-- A pure program that does nothing effectful:
main! = || -> {} {
  42
}
```

**The `Throw([..])` syntax**: `Throw([..])` means "this function can throw any tag." It's an open tag union with zero or more tags. The runtime handler for `Throw([..])` renders the unhandled tag to stderr and exits with a non-zero code. This is the escape hatch for programs that don't want to enumerate every possible error type. The `[..]` syntax is consistent with open tag unions everywhere — `[Ok(a) | ..]` means "at least Ok, possibly more"; `[..]` means "zero or more tags."

### 4.9 Effect Polymorphism

Row variables enable generic effect propagation:

```
map = <a, b, e>|f: |a| ->{ e } b, list: List(a)| ->{ e } List(b) { ... }
```

`e` is an effect row variable. `map` propagates whatever effects `f` has — if `f` is pure, `map` is pure; if `f` throws, `map` throws.

**Interaction with `!` naming**: A function whose effect row includes a variable may or may not be effectful depending on instantiation. The compiler requires `!` in the name if the function *can* be effectful (i.e., if the effect row is non-empty in any instantiation). This means generic functions with effect variables use `!`.

### 4.10 Handler Branding

**Status**: Deferred. Effects are matched by type for now.

**The problem**: If two handlers for the same effect type are nested, the inner handler shadows the outer. You can't have two concurrent `State(Int)` handlers managing different state — they'd interfere. Handler branding (as in Koka's `named effect`) would give each handler a distinct identity.

**Why deferred**: Branding adds complexity to the effect system, and the common cases (one handler per effect type) don't need it. If composition problems arise in practice, branding can be added without breaking existing handler syntax — a branded handler just adds an identity qualifier.

**Reference**: Koka's `named effect` (added in v3.1) provides handler branding. See [Koka named effects](https://koka-lang.github.io/koka/doc/koka/samples/named-effects.html).

---

## 5. Compilation Pipeline

### 5.1 Implementation Language: Odin

The Camp compiler is written in [Odin](https://odin-lang.org). It will never be bootstrapped — fast compilation is a core feature, and a self-hosted compiler would necessarily be slower to compile.

**Why Odin over C3**: Extensive research compared the two languages for compiler implementation:

| Criterion | Odin | C3 |
|-----------|------|----|
| **SOA types** | First-class `#soa` — columnar layout with identical access syntax | None — manual parallel arrays |
| **Arena allocators** | Context-based implicit allocators (`mem.Arena`, `mem.Pool`, etc.) | Temp allocator only (`@pool`) — less flexible |
| **Tagged unions** | Built-in with type switch (`union { ... }` + `switch _ in v`) | C-style untagged unions only |
| **Concurrency** | Basic threading (`core:thread`, `core:sync`) | No built-in threading |
| **WASM target** | `wasm32`/`wasm64p32` supported | Not available |
| **Maps** | Built-in `map[K]V` with context allocator | `HashMap{K,V}` in stdlib |
| **Metaprogramming** | Minimal (`when`, `#assert`, runtime reflection) | Semantic macros, comptime eval, `$foreach` |
| **Build system** | None (bring your own) | Integrated `project.json` |
| **Maturity** | 10 years, production software (JangaFX EmberGen) | ~7 years, less battle-tested |

**Key insight**: For compiler writing, Odin's tagged unions (for AST/IR node variants), arena allocators with context system (for per-phase memory management), and SOA types (for columnar IR traversals) directly address the most common compiler data structures. C3's metaprogramming advantage is less critical for a compiler's inner loops.

**How Odin's features map to Camp's compiler**:

```
┌─────────────────────────────────────────────────────────────┐
│  Odin Feature           │  Camp Compiler Use Case           │
├─────────────────────────┼───────────────────────────────────┤
│  #soa types             │  Columnar AST/IR traversal:       │
│                         │  iterate over all node types for  │
│                         │  dispatch without touching other  │
│                         │  fields                           │
├─────────────────────────┼───────────────────────────────────┤
│  Tagged unions          │  IR node variants:                 │
│                         │  IR_Node :: union { ^IR_Const,    │
│                         │    ^IR_BinOp, ^IR_Call, ... }     │
│                         │  with type switch for dispatch    │
├─────────────────────────┼───────────────────────────────────┤
│  Arena allocators       │  Per-phase bump allocation:       │
│  (context.allocator)    │  parse arena → canonicalize arena │
│                         │  → typecheck arena → ...          │
│                         │  Reset/destroy after each phase   │
├─────────────────────────┼───────────────────────────────────┤
│  mem.Arena              │  No individual frees needed —    │
│                         │  destroy the arena at phase end   │
├─────────────────────────┼───────────────────────────────────┤
│  Built-in map[K]V       │  Symbol tables, type caches,     │
│                         │  import resolution tables         │
├─────────────────────────┼───────────────────────────────────┤
│  core:thread/pool       │  Parallel per-file parsing,       │
│                         │  canonicalization, typechecking    │
├─────────────────────────┼───────────────────────────────────┤
│  WASM target            │  Camp could eventually compile    │
│                         │  its own runtime to WASM           │
└─────────────────────────┴───────────────────────────────────┘
```

### 5.2 Target Platform

**Primary**: WASM/WASI (wasmtime as reference runtime)

**Why WASM/WASI**:
1. **Near-native performance** — WASM runs at near-native speed both locally and in containers
2. **GC available for free** — the WASM GC proposal (Phase 4, shipped in Chrome 119, Firefox 120, Safari 17.4) provides runtime-managed garbage collection (Camp uses Perceus instead, but the runtime JIT still provides optimization)
3. **Sufficient standard library** — WASI Preview 2 provides filesystem, clocks, random, HTTP, CLI args, networking, and I/O polling
4. **No backend compilation cost** — Camp emits WASM directly; the runtime JIT optimizes at load time. This means Camp's compiler can be much faster than one that goes through LLVM

**WASI Preview 2 coverage**: WASI provides effectful primitives (filesystem I/O, networking, environment, clocks, random). Camp's stdlib provides pure computation and Camp-level abstractions. The boundary is clean.

**Raw WASM imports**: When WASI doesn't cover a need, Camp allows raw WASM imports via `unsafe`:
```
unsafe import "wasi_snapshot_preview1" "fd_write" as fd_write!
```

The `unsafe` keyword signals this is an escape hatch, not the norm. Raw imports are untyped from WASM's perspective — you trust the host to provide the right function with the right signature.

### 5.3 Pipeline Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Per-File Front-End (Parallelizable)             │
│                                                                     │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐               │
│  │  Parse   │───▶│Canonicalize  │───▶│  Typecheck   │               │
│  │ (Pratt)  │    │  (partial)   │    │  (partial)   │               │
│  └─────────┘    └──────────────┘    └──────────────┘               │
│       │               │                    │                        │
│  Surface AST    Canonical AST         Typed IR                       │
│                 (deferred imports)   (deferred constraints)          │
│                                                                     │
│                     Cacheable by file content hash                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Module Graph Combination   │
              │   (whole-program)            │
              │                              │
              │   • Finish canonicalization  │
              │     (resolve deferred        │
              │      imports)                │
              │   • Finish typechecking      │
              │     (cross-module           │
              │      constraints)            │
              └──────────────┬──────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│                  Whole-Program Back-End                              │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │Effect Lower  │─▶│Closure Conv  │─▶│CPS Transform │              │
│  │              │  │              │  │  + Inlining   │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│        │                  │                  │                       │
│  Effect-lowered    Closure-converted    CPS IR                       │
│       IR                IR             (state machines)               │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐                               │
│  │Perceus RC    │─▶│WASM Codegen  │                               │
│  │ Insertion    │  │              │                               │
│  └──────────────┘  └──────────────┘                               │
│        │                  │                                        │
│  RC-annotated      .wasm binary                                    │
│     CPS IR                                                          │
└─────────────────────────────────────────────────────────────────────┘
```

#### Phase 1: Parse

**Algorithm**: Pratt parsing ([top-down operator precedence](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html))

**Input**: Source text (UTF-8)
**Output**: Surface AST
**Scope**: Per-file, fully parallelizable

**Why Pratt parsing**: Pratt parsers are simple to implement, handle operator precedence naturally, and produce clean ASTs. Matklad's analysis shows they are both simpler and more powerful than recursive descent for expression-heavy languages. Reference: [Simple but Powerful Pratt Parsing](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html)

**Data structure**: Surface AST nodes are Odin tagged unions:
```odin
Expr :: union {
  ^Expr_Int,
  ^Expr_Str,
  ^Expr_Tag,
  ^Expr_Record,
  ^Expr_Call,
  ^Expr_Match,
  ^Expr_Lambda,
  ^Expr_Block,
  ^Expr_Var,
  ^Expr_BinOp,
  ...
}
```

#### Phase 2: Canonicalize (Partial)

**Input**: Surface AST
**Output**: Canonical AST (with deferred imports)
**Scope**: Per-file, cacheable by file content hash

**What it does**:
1. Expand `@derive` annotations into trait implementation stubs
2. Normalize syntax (desugar, normalize record field order)
3. Resolve what's possible from the file alone (local bindings, local types)
4. Record deferred imports — assume imported items exist, mark them as unresolved

**Deferred imports**: The canonicalizer does NOT read other files. It assumes that `import List exposing [map]` means `List` is a module and `map` is a valid export. This assumption is verified during module graph combination. This design enables:
- Fully deterministic per-file processing (no dependence on file resolution order)
- Cacheability — if a file's content hash hasn't changed, its partial canonicalization is reused
- Parallelism — all files are canonicalized independently

**Finishing canonicalization**: During module graph combination, deferred imports are resolved. If an imported module doesn't exist, or an imported name isn't exported, that's an error.

#### Phase 3: Typecheck (Partial)

**Algorithm**: Bidirectional type inference based on the [Level paper (PLDI'25)](https://xnning.github.io/papers/pldi25level.pdf)

**Input**: Canonical AST (with deferred imports)
**Output**: Typed IR (with deferred cross-module constraints)
**Scope**: Per-file, cacheable by file content hash

**What it does**:
1. Infer types for all local bindings
2. Infer effect rows for all functions
3. Infer variant unions for tag unions and Throw
4. Verify trait constraints on local types
5. Record deferred constraints — cross-module type equalities, imported type verification

**The Level algorithm**: Level is a novel approach to type inference that provides sound, decidable, principal type inference with effect rows and row polymorphism. It extends bidirectional typechecking with effect row unification, handling the interaction between row variables and effect polymorphism.

**Finishing typechecking**: During module graph combination, cross-module constraints are unified. If a function's type doesn't match its import site's expectation, that's an error.

#### Phase 4: Module Graph Combination

**Input**: All per-file typed IRs
**Output**: Whole-program typed IR (fully resolved)

**What it does**:
1. Build the module dependency graph
2. Resolve deferred imports — verify modules exist, names are exported, types match
3. Unify cross-module type constraints
4. Verify effect row compatibility across module boundaries
5. Detect cyclic dependencies (error)

**Caching implication**: Only changed files and files that depend on changed files need re-processing. The module graph determines the invalidation set.

#### Phase 5: Effect Lower

**Input**: Whole-program typed IR
**Output**: Effect-lowered IR

**What it does**:
1. Translate each `perform` (effect operation call) into a continuation invocation
2. Deep handlers become continuation constructors that re-install themselves after resume
3. Shallow (`intercept`) handlers become single-shot continuation constructors
4. `Throw.throw!` becomes a parameterized effect operation with variant union tracking

**Key transformation**: Before effect lowering, an effect operation call is just a function call with an effect row annotation. After effect lowering, the call is replaced with a continuation construction — the operation's arguments and the current continuation are packaged into a value that's passed to the handler.

```
-- Before effect lowering:
Console.println!("Hello")
-- The type system knows this performs Console

-- After effect lowering:
handle_Console_println("Hello", current_continuation)
-- The operation is replaced with a call to the handler,
-- passing both the arguments and the current continuation
```

#### Phase 6: Closure Convert

**Input**: Effect-lowered IR
**Output**: Closure-converted IR

**What it does**:
1. Identify free variables in each anonymous function
2. Create an environment struct containing the free variables
3. Convert each anonymous function to a top-level function that takes the environment as an extra parameter
4. Replace closure creation sites with `make_closure(closure_fn, env)`

**Why before CPS**: Closure conversion must happen before CPS because CPS introduces additional continuations that would themselves need closure conversion. Doing it in this order keeps the transformation simple.

#### Phase 7: CPS Transform + Inlining

**Input**: Closure-converted IR
**Output**: CPS IR (continuation-passing style)

**What it does**:
1. Every effectful function receives an additional continuation parameter
2. `resume` becomes a direct continuation call
3. Stackless coroutines fall out naturally — `Async` handlers with deferred continuations become state machines
4. **Inlining pass**: Collapse iterator chains by inlining `Iter` adapter methods and closures into the consumer. This is the key optimization for zero-cost abstractions.

**CPS and effects are one mechanism**: The CPS transform and effect lowering are deeply connected. Effect operations *are* delimited continuations — `perform` captures the continuation up to the handler. By compiling effects via CPS, both mechanisms are unified:

```
┌──────────────────────────────────────────────────────────────┐
│  Effect operation call                                       │
│  ┌─────────────────┐                                        │
│  │  Async.yield!()  │                                        │
│  └────────┬────────┘                                        │
│           │                                                  │
│    ┌──────▼──────┐                                          │
│    │ CPS capture │  Current continuation becomes a parameter │
│    │  k = ...    │  to the handler                          │
│    └──────┬──────┘                                          │
│           │                                                  │
│    ┌──────▼──────┐                                          │
│    │ Handler     │  Handler receives operation args + k     │
│    │ decides:    │  - Call k immediately (resume)          │
│    │             │  - Defer k (suspend coroutine)          │
│    │             │  - Never call k (abort/throw)           │
│    └─────────────┘                                          │
└──────────────────────────────────────────────────────────────┘
```

**Inlining for zero-cost Iter**: The inlining pass within CPS is critical for Camp's collection strategy. Without inlining, lazy `Iter` chains have 1.5-3x overhead per element due to closure dispatch. With inlining:
- `list.iter().map(f).filter(p).collect()` collapses into a single loop
- Iterator adapter methods are inlined into the consumer
- Closures passed to `map`/`filter` are inlined (they're known at compile time in a statically-typed language)
- Dead code elimination removes intermediate iterator state structs

**Research basis**: Rust achieves zero-cost iterators through LLVM inlining + SROA + DCE. Without LLVM, a compiler that does inlining + DCE gets within ~5-20% of hand-written loops — more than acceptable for WASM targets. The WASM runtime's JIT further optimizes hot loops.

**Reference**: [Simple but Powerful Pratt Parsing](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html), [Level type inference](https://xnning.github.io/papers/pldi25level.pdf)

#### Phase 8: Perceus RC Insertion

**Input**: CPS IR
**Output**: RC-annotated CPS IR

**What it does**:
1. **Liveness analysis** — identify which variables hold references at each program point (O(n) per function)
2. **RC instruction insertion** — emit `inc` (copy), `dec` (drop), or nothing (borrowed/last-use) at each binding site
3. **Reuse analysis** — detect when a reference is the last use before being overwritten, enabling destructive read / in-place update (O(n × k) per function, where k is the number of allocation sites — in practice k is small, so effectively O(n))
4. **Deferred decrement optimization** — batch reference count decrements at function exit points rather than executing them immediately (peephole optimization, O(n))

**All passes are per-function**: No whole-program analysis is needed for Perceus. Separate compilation is fully supported. Cross-module calls emit standard `inc`/`dec` at function boundaries. Reuse only happens within a function body.

**Compilation cost estimate**: ~5-15% over a baseline compiler that uses runtime GC. The Perceus passes are simple dataflow analyses — not expensive compared to optimization passes like register allocation.

**Reference**: [Perceus: Garbage Free Reference Counting with Reuse](https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf) (Reinking, Xie, de Moura, Leijen — PLDI'21)

#### Phase 9: WASM Codegen

**Input**: RC-annotated CPS IR
**Output**: WASM binary (.wasm)

**What it does**:
1. Map CPS IR to WASM structured control flow (blocks, loops, ifs)
2. Emit WASM function definitions with continuation parameters
3. Emit WASM linear memory operations for heap allocation
4. Emit Perceus RC operations as WASM function calls
5. Generate WASM component model async functions for coroutines
6. Emit WASI imports for effect handler runtime
7. Emit type definitions for camp_alloc, camp_inc, camp_dec, etc.

**Direct emission — no IR to IR to target**: Camp emits WASM directly from its CPS IR. There is no intermediate representation like LLVM IR or Cranelift IR. This is the key to fast compilation — no optimization backend means no backend compilation cost.

**What you lose without LLVM**: SROA (Scalar Replacement of Aggregates) and SIMD vectorization. These would bring ~5-20% improvement for tight numeric loops. For most collection operations (non-numeric, non-tight-loop), the overhead is negligible. The WASM runtime's JIT compensates for hot paths.

### 5.4 Compilation Model

**Separate front-end, whole-program backend**:
- Phases 1-3 (Parse, Canonicalize, Typecheck) are per-file: parallelizable, cacheable
- Module Graph Combination links all per-file results
- Phases 5-9 (Effect Lower through Codegen) are whole-program

**This is the Zig model**: Each file is independently analyzed, then the whole program is combined for code generation and optimization. This maximizes parallelism in the expensive front-end phases while enabling whole-program optimization at the back end.

### 5.5 Caching

```
┌─────────────────────────────────────────────────────────┐
│  Cache Key:  SHA-256(file_contents)                      │
│                                                         │
│  Per-file cache stores:                                 │
│  • Surface AST (from Parse)                             │
│  • Partial Canonical AST (from Canonicalize)             │
│  • Partial Typed IR (from Typecheck)                     │
│                                                         │
│  Cache invalidation:                                    │
│  • File content changed → re-parse, re-canonicalize,     │
│    re-typecheck that file                               │
│  • Import dependency changed → re-typecheck affected     │
│    files (determined by module graph)                    │
│  • No change → reuse cached results                     │
│                                                         │
│  Whole-program phases are never cached                   │
│  (they depend on the full module graph)                 │
└─────────────────────────────────────────────────────────┘
```

### 5.6 Compiler Safety

The compiler never panics, crashes, or segfaults. Every "impossible" state becomes a diagnostic.

**Three error categories**:

| Category | Severity | Examples | Action |
|----------|----------|----------|--------|
| **Warning** | Non-fatal | Unused binding, unreachable code, unnecessary `_ =>` | Report, continue compilation |
| **Error** | Fatal (user) | Type mismatch, unhandled effect, missing import, non-exhaustive match | Report, stop compilation |
| **Internal error** | Fatal (compiler bug) | "Impossible" type after typecheck, unexpected IR node, invariant violation | Report with internal context, stop compilation. Never panic/abort. |

**Implementation**: The error collector is a thread-safe accumulator. Every compiler function returns a result type (or uses Odin's multiple-return pattern). "Impossible" cases use an `InternalError` diagnostic constructor instead of `assert()` or `panic()`.

### 5.7 Comptime Evaluation

Pure functions (empty effect row) can be evaluated at compile time when all arguments are known.

**Uses**:
- **Generic specialization**: Monomorphize generic functions at compile time
- **Type introspection**: `type_info(UserId)` returns field names, types, offsets at compile time
- **Derive macro expansion**: `@derive [Display]` runs a comptime function that generates the trait implementation
- **Compile-time constants**: `const MAX_SIZE = compute_max_size!()` where `compute_max_size` is pure

**Purity requirement**: Comptime functions must have an empty effect row. The compiler verifies this. If a comptime function's effect row is non-empty, that's a compile error. This ensures comptime evaluation is deterministic and side-effect-free.

**Reference**: Zig's comptime is more powerful (allows side effects, arbitrary code execution). Camp's comptime is deliberately limited to pure functions — this is simpler to implement and safer to use.

### 5.8 Data-Oriented Design

Camp's compiler follows [Practical Data-Oriented Design](https://www.josherich.me/podcast/andrew-kelley-practical-data-oriented-design-dod) principles (as advocated by Andrew Kelley for Zig):

- **Odin `#soa` types**: Transform arrays of structs into structs of arrays for columnar traversal. Iterate over all node types in the AST without touching other fields. Cache-friendly access patterns.
- **Arena allocation per phase**: Each compilation phase uses a `mem.Arena`. All allocations within a phase go to the arena. At phase end, the entire arena is destroyed — no individual frees. Odin's `context.allocator` system makes this seamless.
- **Linear traversals**: Where possible, a single pass over the IR handles multiple concerns (e.g., type inference + effect row inference in one traversal).
- **Concurrent execution**: Per-file phases run in parallel via Odin's `core:thread/pool`.

---

## 6. Memory Management

### 6.1 Perceus Reference Counting

Camp uses [Perceus](https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf) reference counting with guaranteed destructive-read semantics.

**Why Perceus over runtime GC**:

| Factor | Perceus RC | WASM GC |
|--------|-----------|---------|
| Compilation overhead | ~5-15% extra (3 per-function passes) | None |
| In-place updates | Yes (destructive read) | No |
| Runtime dependency | Minimal (~1KB RC lib) | Requires GC-capable VM |
| Cycle collection | Needs backup cycle collector | Automatic |
| Generated code size | 10-30% larger (inc/dec ops) | Smaller |
| Path to native backend | Easy (RC is self-contained) | Need to implement a GC |
| Deterministic deallocation | Yes (ref count reaches 0 at predictable points) | No (GC collects at unpredictable points) |

**Key advantage**: Destructive read / in-place reuse. When the compiler determines a value is consumed for the last time, it can mutate it in-place rather than allocating a new copy. This turns many "functional but allocates" patterns into "functional but in-place" — the programmer writes pure functional code, but the generated code mutates in-place when safe.

**Example**:
```
-- Source code:
increment_all = |list: List(Int)| -> List(Int) {
  list.iter().map(|x| x + 1).collect()
}

-- Without destructive read: allocates a new list, increments ref on old list,
-- then decrements old list ref when it goes out of scope
--
-- With destructive read: reuses the old list's allocation in-place,
-- mutating each element. No allocation, no ref count churn.
```

### 6.2 Perceus Compilation Cost Analysis

All three Perceus passes are **per-function** and **linear in function size**:

| Pass | What it does | Complexity | Cost |
|------|-------------|------------|------|
| **Liveness / RC insertion** | Track which variables hold references; emit `inc`/`dec` | O(n) per function | Cheap — single-pass dataflow |
| **Reuse analysis** | Detect last-use; match allocation sites with reuse candidates | O(n × k) per function (k = allocation sites, typically 1-3) | Moderate — backward dataflow, but still linear in practice |
| **Deferred decrement** | Batch `dec` operations at exit points | O(n) per function | Cheap — peephole optimization |

**Total compilation overhead**: ~5-15% over a baseline compiler using runtime GC. The Perceus passes are simple dataflow analyses, not expensive optimization passes. In a typical compiler with 10-30 passes, adding 2-3 more is ~10-20% more pass work, but Perceus passes are cheap relative to heavy passes like register allocation.

**Frame-limited reuse** (Lorenzen 2021): Reuse analysis is limited to the current stack frame, making it purely local. No interprocedural analysis needed. Works perfectly with separate compilation. Still captures the vast majority of reuse opportunities.

**Reference**: [Perceus: Garbage Free Reference Counting with Reuse](https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf), [Functional But In-Place](https://www.microsoft.com/en-us/research/publication/functional-but-in-place/) (Lorenzen, Leijen — ICFP'23)

### 6.3 Cycle Collection

Reference counting cannot collect cycles. Camp includes a backup cycle collector for cyclic data structures (e.g., doubly-linked lists, mutual references).

**Design**: The cycle collector runs periodically (or on allocation pressure). It uses a trial deletion approach — temporarily decrement references for suspected cycle members, then restore if they're still reachable. This is the approach used by Swift's ARC and Python's gc module.

**Minimizing cycles**: Camp's pure-functional design and stack-local mutation minimize cycles by construction. Cycles can only arise from:
- Explicit circular data structure construction
- Effect handlers that capture and re-install themselves (which is handled by the handler infrastructure)

### 6.4 Pluggable Allocator

Camp's memory allocator is pluggable — different WASM hosts can provide custom allocators.

**Default**: WASI linear memory allocator (bump allocator for short-lived allocations, free-list for long-lived)

**Why pluggable**: Different deployment targets benefit from different strategies:
- Request-handling WASM components: arena allocation per request, skip deallocation entirely
- Long-running servers: generational allocation for better locality
- Embedded WASM runtimes: minimal allocation footprint

**Interface**: The allocator provides `alloc(size) -> ptr`, `dealloc(ptr, size)`, and `realloc(ptr, old_size, new_size)`. Perceus's RC operations use this interface — `inc` and `dec` don't allocate, but `clone` (when destructive-read isn't possible) calls `alloc`.

**Reference**: Roc's platform model allows the host to control memory management strategy. Camp adopts a lighter version — the allocator is pluggable, but the RC strategy is fixed.

---

## 7. Standard Library and Runtime

### 7.1 Design Philosophy

A well-integrated standard library is a secret sauce for language success (following Rust's model). All types in the stdlib should "just work together" — iterators, results, options, and collections compose seamlessly.

**The split**: The stdlib provides pure computation and Camp-level abstractions. WASI provides effectful primitives. The boundary is clean: effects come from WASI, computation comes from Camp.

```
┌─────────────────────────────────────────────────────────────┐
│  Camp Standard Library                                      │
│                                                             │
│  Pure computation:                                          │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐            │
│  │ Int  │ │Float │ │ Bool │ │ Str  │ │ List │ ...        │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘            │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐            │
│  │ Iter │ │ Map  │ │ Set  │ │Result│ │Option│ ...        │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘            │
│                                                             │
│  Effect definitions:                                       │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │ File │ │Console│ │Async │ │Throw │ │ Env  │ ...       │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘           │
│                                                             │
│  Traits:                                                    │
│  Display, Hash, Eq, Ord, Clone, Serialize, Deserialize     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                 ┌──────────▼──────────┐
                 │   Camp Runtime       │
                 │   (minimal)          │
                 │                      │
                 │  • Effect handler    │
                 │    dispatch          │
                 │  • Perceus RC ops    │
                 │  • Pluggable alloc   │
                 └──────────┬──────────┘
                            │
                 ┌──────────▼──────────┐
                 │   WASI Preview 2    │
                 │                      │
                 │  • Filesystem        │
                 │  • I/O polling       │
                 │  • Clocks/random     │
                 │  • HTTP/network      │
                 │  • CLI args/env      │
                 │  • Component async   │
                 └─────────────────────┘
```

### 7.2 Collection Strategy: Iter-Only

All collection operations live in `Iter`. `List`, `Map`, `Set` implement `iter()` returning an `Iter(a)`. There are no separate eager `List.map` or `List.filter` — use `list.iter().map(f).collect()`.

**Why Iter-only**: Having both eager List operations and lazy Iter operations (like Kotlin) creates API surface duplication and forces users to choose between two equivalent paths. Rust avoids this by having Iter own everything and relying on LLVM inlining to eliminate overhead.

**Research on performance**: Without inlining, lazy Iter chains have 1.5-3x overhead per element (closure dispatch). With inlining + DCE:
- Iterator chains collapse into single loops (no intermediate allocations)
- Closure calls become direct function calls (then eliminated)
- Within ~5-20% of hand-written loops (the gap is from lack of SROA/vectorization without LLVM)

**Camp's approach**: The inlining pass in the CPS compilation phase collapses Iter chains. This is the critical optimization. Without it, the Iter-only strategy would have unacceptable overhead for small collections.

| Optimization | Effect on Iter chains | Camp implements? |
|-------------|----------------------|-------------------|
| Inlining | Collapses adapter methods and closures into consumer | Yes (CPS phase) |
| DCE | Removes dead iterator state structs | Yes (after inlining) |
| SROA | Breaks structs into scalar values (register allocation) | No (would need LLVM) |
| SIMD vectorization | Processes multiple elements per instruction | No (would need LLVM) |

**What you lose**: ~5-20% for tight numeric loops vs LLVM-compiled code. The WASM runtime's JIT compensates for hot paths. For most collection operations (non-numeric, non-tight-loop), the overhead is negligible.

### 7.3 Stdlib Modules

| Module | Category | Contents | Notes |
|--------|----------|----------|-------|
| `Int` | Pure | `I8`..`I64`, `U8`..`U64` operations | Arithmetic, comparison, conversion, bitwise |
| `Float` | Pure | `F32`, `F64` operations | Arithmetic, comparison, trig, rounding |
| `Bool` | Pure | `True`, `False` | Logic, comparison |
| `Str` | Pure | UTF-8 string operations | Concat, split, trim, find, slice, interpolate, length, chars |
| `List` | Pure | `List(a)` with `iter()` | Construct, first, last, length, append, sort |
| `Iter` | Pure | Lazy iterator pipeline | map, filter, fold, collect, chain, enumerate, take, skip, zip, find, count, for_each |
| `Map` | Pure | `Map(k, v)` with `iter()` | get, insert, remove, contains, keys, values, size |
| `Set` | Pure | `Set(a)` with `iter()` | insert, remove, contains, union, intersection, difference |
| `Bytes` | Pure | `Bytes` operations | Raw byte sequences, hex, base64, encode, decode |
| `Result` | Pure | Tag union helpers | Combinators for `Ok(a) | Err(e)` patterns: map, and_then, or_else, unwrap |
| `Option` | Pure | Tag union helpers | Combinators for `Some(a) | None`: map, and_then, or_else, unwrap |
| `File` | Effect | File I/O | `open!`, `close!`, `read!`, `write!` — handlers map to WASI filesystem |
| `Console` | Effect | Terminal I/O | `print!`, `printerr!`, `readln!` — handlers map to WASI stdio |
| `Async` | Effect | Concurrency | `yield!`, `spawn!`, `join!`, `cancel!` — handlers map to WASM component async |
| `Throw` | Effect | Error effect | `throw!` operation, variant union tracking |
| `Env` | Effect | CLI args, env vars | `args!`, `get_env!` — WASI-backed |
| `Time` | Effect | Clock, duration | `now!`, `sleep!` — WASI-backed |
| `Random` | Effect | Random generation | `int!`, `float!`, `bytes!` — WASI-backed |
| `Path` | Pure | File path manipulation | Join, split, extension, directory, filename — pure string operations |
| `Fmt` | Pure | Formatting | `Display` trait, `format` function, string interpolation helpers |
| `Hash` | Pure | Hashing | `Hash` trait, hash functions (SipHash, FNV) |
| `Serialize` | Pure | Serialization | `Serialize`, `Deserialize` traits, JSON, binary format |
| `Eq` | Pure | Equality | `Eq` trait, structural equality default, reference equality |
| `Ord` | Pure | Ordering | `Ord` trait, `Ordering` type (`Less | Equal | Greater`), comparison for sorting |

### 7.4 Effect Definitions in the Stdlib

```
effect File {
  open!   : Str ->{ File, Throw(NotFound | PermissionDenied) } Handle
  close!  : Handle ->{ File } {}
  read!   : Handle ->{ File, Throw(Eof) } Str
  write!  : Handle, Str ->{ File } {}
}

effect Console {
  print!    : Str ->{ Console } {}
  printerr! : Str ->{ Console } {}
  readln!   : || ->{ Console } Str
}

effect Async {
  yield!  : || ->{ Async } {}
  spawn!  : |thunk: || ->{ Async } a| ->{ Async } Handle(a)
  join!   : Handle(a) ->{ Async } a
  cancel! : Handle(a) ->{ Async } {}
}

effect Env {
  args!    : || ->{ Env } List(Str)
  get_env! : Str ->{ Env, Throw(NotFound) } Str
}

effect Time {
  now!   : || ->{ Time } U64
  sleep! : U64 ->{ Time } {}
}

effect Random {
  int!   : Int, Int ->{ Random } Int
  float! : || ->{ Random } F64
  bytes! : U64 ->{ Random } Bytes
}

alias Io = File | Console
```

### 7.5 Stdlib Traits

| Trait | Methods | Derivable? | Notes |
|-------|---------|------------|-------|
| `Display` | `display : Self -> Str` | Yes | String representation |
| `Hash` | `hash : Self -> U64` | Yes | Hash code for Map/Set |
| `Eq` | `eq : Self, Self -> Bool` | Yes | Equality comparison |
| `Ord is Eq` | `compare : Self, Self -> Ordering` | Yes | Ordering for sorting |
| `Clone` | `clone : Self -> Self` | Yes | Explicit deep copy |
| `Serialize` | `serialize : Self -> Bytes` | Yes | Binary serialization |
| `Deserialize` | `deserialize : Bytes -> Ok(Self) | Err(Str)` | Yes | Binary deserialization |

### 7.6 Runtime

The Camp runtime is minimal. It provides:

| Component | Responsibility | Size estimate |
|-----------|---------------|---------------|
| **Effect handler dispatch** | Route effect operations to the correct handler | ~2-4 KB |
| **WASI syscall bindings** | Map Camp effects to WASI calls (fd_write, path_open, etc.) | ~1-2 KB |
| **WASM component async bridge** | Map `Async` yield/resume to component model async | ~2-3 KB |
| **Perceus RC runtime** | `camp_inc`, `camp_dec`, `camp_dec_deferred`, `camp_alloc`, `camp_dealloc`, `camp_reuse_check` | ~1-2 KB |
| **Pluggable allocator interface** | `camp_alloc`, `camp_dealloc` function pointers | ~0.5 KB |
| **Cycle collector** | Trial-deletion cycle detector | ~1-2 KB |

**Total runtime: ~8-14 KB**. This is embedded in the generated WASM module.

---

## 8. Module System and Packages

### 8.1 Modules

- **One file per module**: `List.camp` defines the `List` module
- **File name = module name**: `List.camp` → module `List`
- **Multiple types per module**: A module can define multiple types, functions, traits, effects, and aliases
- **No nested modules**: Modules are flat — no `List::Iter` or `Collections::Map`
- **No interface files**: No `.campi` files — `pub` controls visibility

### 8.2 Imports

```
import List exposing [map, filter, fold]     -- specific names into scope
import Result                                -- module qualified access: Result.is_ok
import My.Module as M                        -- alias: M.function()
```

**Rules**:
- `import Module` — brings the module into scope; access members as `Module.member`
- `import Module exposing [name, ...]` — brings specific names into unqualified scope
- `import Module as Alias` — use `Alias.member` instead of `Module.member`
- Name conflicts are errors — disambiguate with qualified access

**No shadowing of imports**: An import that brings a name into scope that already exists is an error. Use qualified access or a different alias.

### 8.3 Packages

**Package management**: Git-based, following Go's model.

**`camp.toml`**:
```toml
[package]
name = "my-app"
version = "0.1.0"

[dependencies]
serde = { git = "https://github.com/camp-lang/serde", tag = "v0.2.0" }
http = { git = "https://github.com/camp-lang/http", rev = "a1b2c3d" }
```

**Why git-based**: No central infrastructure needed. Dependencies are git repos with a `camp.toml` at their root. Resolved by tag, branch, or commit hash. A central registry can be added later without changing the format.

**Why not a central registry (yet)**: A registry requires hosting infrastructure, name squating prevention, and governance. Git-based dependencies work immediately and can be extended incrementally.

### 8.4 Package Types and Project Structure

Camp follows Rust's model: packages are either executables (with `main!`), libraries (with public API but no `main!`), or both.

**Default executable** (no explicit config needed):
```
my-app/
  camp.toml              -- [package] name = "my-app", version = "0.1.0"
  src/
    Main.camp            -- entry point (defines main!)
    Utils.camp
  tests/
    UtilsTest.camp
```

**Library package**:
```
my-lib/
  camp.toml              -- [package] name = "my-lib", version = "0.1.0"
                           -- [lib]
  src/
    Lib.camp             -- no main!, exports public API
    Internal.camp        -- private module
  tests/
    LibTest.camp
```

**Both (or non-standard names)**:
```toml
[package]
name = "my-app"
version = "0.1.0"

[lib]
path = "src/Lib.camp"

[[bin]]
name = "cli"
path = "src/Cli.camp"

[[bin]]
name = "server"
path = "src/Server.camp"
```

**Rules**:
- A library package cannot define `main!`
- An executable package must define exactly one `main!`
- When a package is used as a dependency, its `Lib.camp` (or configured `[lib]` path) is the import root
- `camp build` builds all targets; `camp run` runs the default binary
- `camp test` discovers all `test`/`expect` declarations across all source and test files
- Default entry points: `src/Main.camp` for executables, `src/Lib.camp` for libraries
- `camp.toml` only needs explicit `[lib]`/`[[bin]]` entries when names are non-standard or there are multiple targets

### 8.5 Prelude

Every Camp file automatically imports the **Prelude** — a set of types, tags, traits, effects, and functions so commonly used that requiring explicit imports would be noise.

**Prelude contents**:

| Category | Items |
|----------|-------|
| **Types** | `Bool`, `List`, `Str`, `I8`..`I64`, `U8`..`U64`, `F32`, `F64`, `Bytes`, `Map`, `Set`, `Iter`, `Handle`, `Ordering` |
| **Tags** | `True`, `False`, `Ok`, `Err`, `Some`, `None`, `Less`, `Equal`, `Greater` |
| **Traits** | `Display`, `Hash`, `Eq`, `Ord`, `Clone`, `Serialize`, `Deserialize` |
| **Effects** | `Throw`, `Async`, `Console`, `File`, `Env`, `Time`, `Random` |
| **Aliases** | `Io = File | Console` |
| **Functions** | `identity`, `always`, `compose`, `flip`; basic operations on `Int`, `Str`, `List`, `Iter` |

**Design decision**: The prelude follows Rust's model — it includes only items that are used in virtually every program. Domain-specific modules (e.g., `Serialize`, `Path`, `Fmt`) are not in the prelude and must be imported explicitly. This keeps the prelude small while eliminating the most common import boilerplate.

**Disabling the prelude**: `import Camp exposing []` at the top of a file opts out of the prelude. This is useful for modules that want to avoid name collisions with prelude items.

### 8.6 FFI

**WASI**: Effect handlers map to WASI syscalls implicitly — the runtime provides the bridge.

**Raw WASM imports** (escape hatch):
```
unsafe import "wasi_snapshot_preview1" "fd_write" as fd_write!
```

The `unsafe` keyword signals: this is not the normal way. Raw imports bypass Camp's type system and effect tracking. Use only when WASI doesn't cover a need.

### 8.7 Entry Point

`main!` in `Main.camp`. Its effect row is the declaration:

```
main! = || ->{ Console, Throw([..]) } {
  Console.println!("Hello, Camp!")
  {}
}
```

The runtime reads `main!`'s effect row and provides handlers for every listed effect. If `Console` is in the row, the runtime installs a WASI-backed Console handler. If it's not, no I/O is available. `Throw([..])` means the program can throw any tag — the runtime handler renders unhandled tags to stderr and exits non-zero.

---

## 9. Concurrency Model

### 9.1 Overview

Camp uses stackless coroutines modeled via the `Async` effect, compiled using CPS. This is Rust's concurrency model (stackless, state-machine-based coroutines) rather than Go's (green threads with growable stacks).

```
┌─────────────────────────────────────────────────────────────┐
│  Concurrency Architecture                                   │
│                                                             │
│  Camp Source              CPS Compilation         Runtime    │
│  ───────────              ──────────────         ───────    │
│                                                             │
│  Async.spawn!(|| {     →  State machine S1     →  wasmtime  │
│    long_task!()           with live vars           schedules│
│  })                        as struct fields       S1.resume │
│                                                             │
│  Async.yield!()        →  S1 suspends:         →  host     │
│                          capture continuation     decides   │
│                          defer to handler          when to   │
│                                                   resume    │
│                                                             │
│  Async.join!(handle)   →  S1 completes:        →  host      │
│                          resume caller with       returns    │
│                          return value             result    │
└─────────────────────────────────────────────────────────────┘
```

### 9.2 Why Stackless (Not Green Threads)

| Approach | Memory per coroutine | Scheduling | Implementation complexity |
|----------|---------------------|------------|--------------------------|
| **Stackless (Camp)** | ~100 bytes (state machine struct) | Cooperative (host-driven) | Moderate — CPS transform + state machine |
| **Green threads (Go)** | ~2-8 KB minimum (growable stack) | Preemptive (runtime scheduler) | High — stack copying, scheduler, preemption |
| **OS threads** | ~1-8 MB (native stack) | OS preemptive | Low (OS handles it) |

**Camp chose stackless because**:
1. Low memory per coroutine enables millions of concurrent operations
2. Cooperative scheduling maps naturally to WASM's single-threaded execution model
3. WASM component model async uses stackless coroutines — natural compilation target
4. No runtime scheduler complexity — the host (wasmtime) manages resumption

### 9.3 Async Effect

```
effect Async {
  yield!  : || ->{ Async } {}
  spawn!  : |thunk: || ->{ Async } a| ->{ Async } Handle(a)
  join!   : Handle(a) ->{ Async } a
  cancel! : Handle(a) ->{ Async } {}
}
```

**Operations**:
- `yield!()` — cooperatively suspend the current coroutine, returning control to the scheduler
- `spawn!(thunk)` — start a new concurrent computation, return a Handle
- `join!(handle)` — wait for a coroutine to complete, get its result
- `cancel!(handle)` — cancel a coroutine (best-effort)

### 9.4 Compilation to State Machines

CPS transform turns coroutines into state machines:

```
-- Source:
fetch_two! = || ->{ Async, File, Throw(IoError) } (Str, Str) {
  h1 = Async.spawn!(|| { File.read!("a.txt") })
  h2 = Async.spawn!(|| { File.read!("b.txt") })
  a = Async.join!(h1)
  b = Async.join!(h2)
  (a, b)
}

-- After CPS + state machine extraction:
-- State 0: spawn h1, spawn h2, yield (waiting for both)
-- State 1: join h1 (result available), join h2 (result available), return (a, b)
--
-- The state machine struct:
-- struct FetchTwo State {
--   state: U8,       -- 0 or 1
--   h1: Handle(Str), -- live variable
--   h2: Handle(Str), -- live variable
--   a: Str,          -- live variable (set in state 1)
-- }
```

**Live variables become struct fields**: Every variable that's alive across a suspension point becomes a field in the state machine struct. This is how Rust's async/await works — the `Future` struct contains all live `await`-crossing variables.

### 9.5 WASM Component Model Async Bridge

The WASM component model (Preview 2+) defines async function types that can yield and be resumed. This is the natural compilation target for Camp's coroutines:

```
┌────────────────────────────────────────────────────┐
│  Camp Async          →    WASM Component Async      │
│                                                    │
│  Async.yield!()     →    yield to host             │
│  handler resumes    →    host calls resume         │
│  Async.spawn!(f)    →    create new async context  │
│  Async.join!(h)     →    await on async context    │
│                                                    │
│  The handler is compiled as a WASM async function  │
│  that manages the coroutine state machine.         │
└────────────────────────────────────────────────────┘
```

**For I/O-bound concurrency**: `wasi:io/poll` drives resumption. A coroutine waiting on file I/O yields; the host polls the file descriptor; when data is available, the host resumes the coroutine.

### 9.6 Structured Concurrency

`spawn!` returns a Handle. The Handle must be `join!`ed or `cancel!`ed before the enclosing handler exits.

**Unjoined handles**: Compile-time warning (or runtime error in debug builds). This prevents leaked coroutines — every spawned task must have a defined outcome.

**Why structured**: Following Rust's scoped threads and Swift's structured concurrency model. Unstructured concurrency (fire-and-forget) leads to resource leaks, use-after-free, and unpredictable behavior.

### 9.7 No Shared Mutable State

Camp's stack-local mutation model means coroutines cannot share mutable data. Communication goes through:
- Values returned via `join!`
- Effect handlers that manage shared state (e.g., a `Channel` effect)

This eliminates data races by construction — no locks, no atomics, no mutex needed.

### 9.8 Channel Effect (Future Stdlib)

```
effect Channel {
  send!    : Handle(a), a ->{ Channel } {}
  receive! : Handle(a) ->{ Channel } a
}
```

Channels are a stdlib abstraction, not a language primitive. A handler manages an internal queue. This follows the same pattern as all Camp effects — the operation is declared, the handler provides the implementation.

### 9.9 Cooperative Concurrency

No blocking I/O. All I/O effects are handled by the runtime, which integrates with `wasi:io/poll`. A coroutine waiting on I/O yields; the host resumes it when data is available.

**No preemption**: Coroutines run until they `yield!` or perform an I/O operation. This is cooperative scheduling — the runtime doesn't preempt running coroutines. For CPU-intensive work, insert `Async.yield!()` periodically to allow other coroutines to run.

### 9.10 Example — Concurrent File Reads

```
main! = || ->{ Async, File, Throw(IoError) } {
  h1 = Async.spawn!(|| { File.read!("a.txt") })
  h2 = Async.spawn!(|| { File.read!("b.txt") })
  a = Async.join!(h1)
  b = Async.join!(h2)
  Console.println!("Combined: ${a} ${b}")
  {}
}
```

The `Async` handler spawns both reads as state machines, registers them with `wasi:io/poll`, and resumes each when its I/O completes. The `join!` calls suspend the main coroutine until both reads finish.

---

## 10. Metaprogramming

### 10.1 Design Philosophy

Metaprogramming is a Pandora's box — it breaks compilation speed, error messages, and IDE support. Camp starts with the minimum viable metaprogramming and adds more only if the need is proven.

**The spectrum**:

| Approach | Power | Compilation cost | Error quality | Camp's stance |
|----------|-------|-----------------|---------------|---------------|
| Gleam `use`/`with` | Low (callback inversion) | None | Great (it's just code) | Dropped — effect handlers cover the same ground |
| Derive macros | Medium (trait impl generation) | Small | Good (restricted scope) | **Included** |
| Comptime evaluation | Medium (pure function evaluation at compile time) | Small | Good (it's just code) | **Included** |
| Procedural macros | High (arbitrary code generation) | Moderate | Poor (generated code is opaque) | **Deferred** |
| Full quasiquotation | Maximum | High | Variable | **Deferred** |

### 10.2 Derive Macros

```
@derive [Display, Hash, Eq, Serialize]
UserId := U64
```

**How it works**: `@derive` triggers a comptime function that generates trait implementations. The derive function receives type information at compile time and produces the trait method implementations as AST nodes.

**Scope**: Derive macros can ONLY generate trait implementations. They cannot:
- Add new functions or values to the module
- Modify existing code
- Generate arbitrary code

This restriction keeps derive macros safe and predictable. The generated code always conforms to a known interface (the trait signature).

### 10.3 Comptime Evaluation

Pure functions (empty effect row) can be evaluated at compile time when all arguments are known.

**Uses**:
```
-- Generic specialization (comptime monomorphization):
map = <a, b, e>|f: |a| ->{ e } b, list: List(a)| ->{ e } List(b)
-- When called as map(|x| x + 1, [1, 2, 3]), the compiler
-- specializes to map_Int_Int_pure at comptime

-- Type introspection:
fields = comptime type_info(UserId).fields
-- Returns field names, types, offsets at compile time

-- Compile-time constants:
max_size: U64 = comptime compute_max_size()
-- compute_max_size must be pure (empty effect row)

-- Derive expansion:
-- @derive [Display] on UserId generates:
--   UserId is Display := U64 {
--     display = |self| self.inner().display()
--   }
```

**Purity enforcement**: The compiler verifies that comptime functions have an empty effect row. If a function's effect row is non-empty, it cannot be evaluated at comptime. This ensures determinism and no side effects during compilation.

**Comparison with Zig's comptime**: Zig's comptime allows arbitrary code execution (including side effects like file I/O). Camp's comptime is deliberately restricted to pure functions — simpler, safer, and more predictable.

### 10.4 Why Not Procedural Macros (Yet)

Full procedural macros (like Rust's) can generate arbitrary code. They're powerful but have significant costs:
- **Compilation speed**: Running arbitrary code at compile time is slow
- **Error messages**: Errors in generated code point to the macro invocation, not the generated code — confusing
- **IDE support**: Generated code is invisible to autocomplete, go-to-definition, and refactoring tools
- **Hygiene**: Name capture and scoping in generated code is hard to get right

**The watt model**: [dtolnay/watt](https://github.com/dtolnay/watt) shows that procedural macros can run in WASM at compile time with minimal overhead. If Camp adds procedural macros later, this would be the approach — macros compile to WASM, the Camp compiler executes them in a sandboxed runtime.

**Why defer**: The combination of derive macros, comptime evaluation, and algebraic effects covers most motivations for metaprogramming:
- **Code generation for boilerplate** → derive macros
- **Type-level programming** → comptime evaluation
- **Callback inversion / DSLs** → effect handlers
- **Compile-time constants** → comptime evaluation

If a need arises that these can't serve, procedural macros can be added following the watt model.

---

## 11. Testing

### 11.1 Test Declarations

Two keywords: `test` for named test functions, `expect` for inline boolean assertions.

```
test "addition works" = {
  expect add(2, 3) == 5
  expect add(0, 0) == 0
}

test "list operations" = {
  result = [1, 2, 3].iter().map(|x| x * 2).collect()
  expect result == [2, 4, 6]
}

-- expect can also appear inside any function body:
parse_int! = |s: Str| ->{ Throw(BadNumStr) } Int {
  expect s.len() > 0
  match Int.from_str(s) {
    Some(n) => n
    None => Throw.throw!(BadNumStr)
  }
}
```

**`test`**: Defines a named test case. Must be at module level. Discovered by `camp test`.

**`expect`**: Asserts a boolean condition. Can appear inside `test` blocks or any function body. In test builds, a failing `expect` is a test failure. In optimized builds (`--opt=speed`), `expect` is skipped entirely (like Zig's approach).

### 11.2 Parallel Test Execution

`camp test` discovers all `test` and `expect` declarations and runs them in parallel using `Async.spawn!`/`Async.join!`.

**Test runner handlers**: The test runner provides default effect handlers:
- `Console` → captures output (available for assertions, suppressed by default)
- `Throw` → test failure with error display
- `Async` → real async scheduling (tests can use coroutines)
- `File` → temp directory isolation (each test gets a clean filesystem)

**Reference**: Zig's test runner runs tests in parallel with the same `test`/`expect` design. See [Zig testing](https://ziglang.org/documentation/master/#Zig-Test).

---

## 12. Open Design Questions

### 12.1 Function/Variable Naming Convention

**Status**: TBD — snake_case vs camelCase for function/variable names

**Confirmed**: Functions and variables are always **lowercase**. This is required for tag disambiguation — UpperCamelCase identifiers are always types or tags, lowercase are always functions or variables. The remaining question is which lowercase convention:

**snake_case** (Rust, Gleam, Python tradition):
- `my_function`, `user_name`, `parse_int!`
- Consistent with most systems programming languages
- Easy to read, no ambiguity about word boundaries

**camelCase** (Koka, OCaml, Java tradition):
- `myFunction`, `userName`, `parseInt!`
- More common in functional language ecosystems
- Shorter identifiers for the same concept

**Decision needed**: This is a style decision that should be made before the stdlib is written. The convention becomes part of the language's identity.

### 12.2 Handler Branding

**Status**: Deferred

Effects are matched by type for now. If two handlers for the same effect type are nested, the inner shadows the outer. This prevents having two concurrent `State(Int)` handlers.

**When to revisit**: If real-world Camp code frequently needs multiple handlers of the same effect type, branding should be added. Koka's `named effect` provides a model — it can be added without breaking existing syntax.

### 12.3 Error Return Traces

**Status**: Deferred (standard stack traces for now)

Zig-style error return traces (recording the propagation chain, not just the catch-site stack) would be useful for debugging effect-based error flow. However:
- Error return traces break referential transparency (calling the same function from different sites produces different traces)
- They special-case `Throw` vs other effects, which is inconsistent
- An opt-in mechanism for auto-injecting trace context into `Throw` variants needs further design

**Potential future approach**: An opt-in `@trace` annotation that wraps `Throw.throw!` to include call-site information in the thrown tag. This preserves referential transparency (the trace is part of the value) and doesn't special-case the effect system.

### 12.4 WASM GC Backend

**Status**: Possible future addition

Perceus is the primary strategy. A WASM GC backend could be added as an alternative compilation target. This would be a different backend, not a mixed runtime — Camp with Perceus compiles to linear memory, Camp with WASM GC compiles to managed heap objects.

**Why consider it**: WASM GC produces smaller binaries and requires no RC runtime. For deployment targets where binary size matters (browsers), WASM GC may be preferable.

**Why not now**: Perceus gives Camp path to native backends and in-place updates. WASM GC can be added later without changing the language semantics.

### 12.5 Language Name

**Status**: "Camp" is the working name

The name is short, related to the creator's moniker (smores → s'mores at a campfire), and no other programming language uses it. It may change before 1.0.

---

## 13. References

### Academic Papers

1. **Perceus**: Reinking, Xie, de Moura, Leijen. "Perceus: Garbage Free Reference Counting with Reuse." PLDI'21. [PDF](https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf)

2. **Functional But In-Place**: Lorenzen, Leijen. "Functional But In-Place." ICFP'23. [PDF](https://www.microsoft.com/en-us/research/publication/functional-but-in-place/)

3. **Level Type Inference**: Xie, et al. "Level type inference." PLDI'25. [PDF](https://xnning.github.io/papers/pldi25level.pdf)

4. **Koka Effect Handlers**: Leijen. "Koka: Programming with Row-polymorphic Effect Handlers." 2014-onwards. [koka-lang.github.io](https://koka-lang.github.io)

5. **Row Polymorphism**: Rémy. "Type Inference for Records in a Natural Extension of ML." 1994.

6. **Algebraic Effects and Handlers**: Plotkin, Pretnar. "Handlers of Algebraic Effects." 2009.

7. **OCaml 5 Effects**: Doligez, et al. "Multicore OCaml." 2020-onwards. [ocaml.org](https://ocaml.org/docs/effects-tutorial)

### Language Documentation

8. **Roc**: [roc-lang.org](https://roc-lang.org), [New Compiler Tutorial](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md)

9. **Koka**: [koka-lang.github.io](https://koka-lang.github.io)

10. **Gleam**: [gleam.run](https://gleam.run), [Gleam Tour — use](https://tour.gleam.run/advanced-features/use/)

11. **Unison**: [unison-lang.org](https://unison-lang.org)

12. **Effekt**: [effekt-lang.org](https://effekt-lang.org)

13. **Zig**: [ziglang.org](https://ziglang.org)

14. **Odin**: [odin-lang.org](https://odin-lang.org)

15. **C3**: [c3-lang.org](https://c3-lang.org)

### Technical References

16. **Pratt Parsing**: Matklad. "Simple but Powerful Pratt Parsing." 2020. [Blog post](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html)

17. **Data-Oriented Design**: Andrew Kelley. "Practical Data-Oriented Design." [Podcast/transcript](https://www.josherich.me/podcast/andrew-kelley-practical-data-oriented-design-dod)

18. **WASM Component Model**: [GitHub](https://github.com/WebAssembly/component-model)

19. **WASI Preview 2**: [GitHub](https://github.com/WebAssembly/WASI/tree/main/wasip2)

20. **Watt (procedural macros in WASM)**: dtolnay/watt. [GitHub](https://github.com/dtolnay/watt)

21. **WASM GC Proposal**: [GitHub](https://github.com/WebAssembly/gc)

---

## Appendix A: Design Decision Ledger

Every major design decision, its alternatives, and the rationale for the chosen path.

| # | Decision | Chosen | Alternatives Considered | Rationale |
|---|----------|--------|------------------------|-----------|
| 1 | Effect model | Koka-style tracked, lexical handlers | Eff-style (tracked, dynamic), Unison (inferred-only) | Lexical handlers are predictable; tracked effects enable compile-time safety |
| 2 | Sum types | Structural tag unions (Roc-style) | Named constructors (Rust/Haskell) | Structural tags compose freely; nominal aliases available via newtypes |
| 3 | Product types | Row-polymorphic anonymous records | Order-significant records, named records | Standard row polymorphism; field order shouldn't be semantic |
| 4 | Nominal types | Newtypes only | Named records, full nominal system | Single nominal mechanism; newtypes wrap structural types for identity |
| 5 | Mutation scope | Stack-local only (var, no refs) | Local refs (non-escaping), full refs | Simplest; no aliasing analysis needed; for loops cover common cases |
| 6 | Memory management | Perceus RC | WASM GC, hybrid | In-place updates; path to native backends; ~5-15% compilation overhead |
| 7 | GC strategy | Perceus with guaranteed destructive read | Best-effort reuse | Semantic guarantee enables programmer reasoning about reuse |
| 8 | Implementation language | Odin | C3 | SOA types, arena allocators, tagged unions, WASM target, more mature |
| 9 | Compilation target | WASM/WASI | Native (LLVM), JVM | Near-native performance, JIT, broad deployment, WASI stdlib |
| 10 | Code generation | Direct WASM emission | LLVM, Cranelift | Faster compilation; runtime JIT compensates for lack of LLVM optimization |
| 11 | Compilation pipeline | Layered IR (6+ IRs) | Flat pipeline, hybrid (3 IRs) | Each IR is a testable boundary; effect lowering and CPS are separate passes |
| 12 | Parsing | Pratt parsing | Recursive descent | Simpler, handles precedence naturally |
| 13 | Type inference | Level (PLDI'25) bidirectional | Hindley-Milner, Algorithm W | Handles effect rows and row polymorphism correctly |
| 14 | Effect invocation | No keyword (bare call with `!`) | `perform`, `do`, `^` prefix | `!` suffix already marks effectful calls; consistent with function naming |
| 15 | Effect composition | Aliases (`alias Io = File \| Console`) | Inheritance (`effect File is Io`) | No operation name collisions; matches all mainstream effect languages |
| 16 | Handler types | Deep (default) + shallow (`intercept`) | Deep only, shallow only | Deep covers 90%; shallow needed for stateful protocols |
| 17 | Continuations | One-shot | Multi-shot | Faster, simpler, safer with linear resources; backtracking via explicit state |
| 18 | Error model | Dual (Throw + tag unions) | Throw-only, Result-only | Matches Koka/Unison pattern; Throw for exceptional, tag unions for structural |
| 19 | `?` operator | None | Roc-style early-return | Throw propagation is automatic via effect rows; one way to do things |
| 20 | Ad-hoc polymorphism | Structural traits with `is` | Full type classes, Roc `where` clauses | Simpler than Haskell type classes; more powerful than Roc where clauses |
| 21 | Trait keyword | `is` | `implements` | More terse; reads naturally |
| 22 | Shadowing | Forbidden (all) | Nested OK, same-scope forbidden, all allowed | Eliminates refactoring bugs; Roc model |
| 23 | Namespace | Unified | Split (type/value) | Simpler UFCS; Gleam model |
| 24 | Var syntax | `$` prefix at use sites | No marker | Mutation visible at a glance; Roc model |
| 25 | Module system | Flat file-based | Hierarchical | Simplest; fast to compile |
| 26 | Interface files | None | Optional `.campi`, required | `pub` controls visibility; no separate interface maintenance |
| 27 | Visibility | `pub` keyword | Explicit export list (Roc) | Simpler; doesn't drift out of sync |
| 28 | Package management | Git-based | Central registry | No infrastructure needed; can add registry later |
| 29 | Numeric types | Fixed-size | Unbounded default | Maps cleanly to WASM; predictable performance |
| 30 | String encoding | UTF-8 default | Str + Bytes distinct from day 1 | UTF-8 is the universal standard; Bytes available when needed |
| 31 | Concurrency model | Stackless coroutines (CPS) | Green threads, OS threads | Low memory per coroutine; maps to WASM component async |
| 32 | Async mechanism | `Async` effect | `async/await` syntax | Effects subsume async/await; one mechanism for all control flow |
| 33 | Metaprogramming | Derive + comptime | Full procedural macros, none | Covers most needs; procedural macros can be added later |
| 34 | Collection API | Iter-only (with inlining) | Separate List + Iter | Single API surface; inlining collapses chains; ~5-20% overhead vs LLVM |
| 35 | Logic operators | `and`/`or` keywords | `&&`/`||` symbols | Avoids `\|\|` ambiguity with empty-arg functions |
| 36 | Raw identifiers | Backtick-wrapped | `r#` prefix (Rust) | Visually consistent; Scala/Haskell precedent |
| 37 | Type variable casing | Lowercase | Uppercase (Rust-style) | ML tradition; distinguishes variables from concrete types at a glance |
| 38 | Function syntax | `\|args\| body` | `fn` keyword, `def` keyword | Only function syntax; consistent from top-level to anonymous |
| 39 | Type annotations | Inline (`x: Int = 3`) | Separate line (Roc/Haskell) | Single statement; no ambiguity |
| 40 | Effect row syntax | After `->` with `{}` | Thick arrow `=>`, separate annotation | One arrow form; effect row is an optional component of the return type |
| 41 | FFI | WASI + raw WASM imports (`unsafe`) | WASI only | WASI covers standard needs; `unsafe` is the escape hatch |
| 42 | Error tracing | Standard stack traces (defer Zig-style) | Error return traces | Traces break referential transparency; standard traces work for now |
| 43 | Handler branding | Deferred | Branded handlers (Koka named effects) | Not needed for common cases; can add without breaking syntax |
| 44 | Allocator | Pluggable | Fixed (WASI linear memory) | Different deployment targets benefit from different strategies |
| 45 | Tag prefix | No prefix (bare UpperCamelCase) | `#` prefix | Case disambiguates: tags are UpperCamelCase, functions are lowercase |
| 46 | Default number type | I64 / F64 | No default, I32/F64, Dec | Direct WASM mapping; I64 avoids common overflows |
| 47 | Row poly syntax | `..rest` (Roc-style) | `\| rho` (ML-style) | Aligns type and usage syntax; `..` is consistent "and possibly more" |
| 48 | Open/closed types | `..` for open, no `..` for closed | Always closed, always open, `| rho` only | Consistent across records and tag unions; Roc model |
| 49 | Throw Any syntax | `Throw([..])` | `Throw(Any)`, `Throw(..)` | `Throw([..])` uses the tag union syntax consistently |
| 50 | Var keyword | None (`$` prefix only) | `var $x = 0` | `$` alone signals mutability; `var` adds no information |
| 51 | Pattern wildcard | `_` (universal convention) | `.. =>` | `_` is the standard across all languages; `..` is for open types |
| 52 | Nominal tag qualification | Required (`Result.Ok`) with import escape | Always bare | Prevents tag name collisions; Roc model |

---

## Appendix B: Comparison with Related Languages

| Feature | Camp | Koka | Roc | Gleam | Rust | Unison |
|---------|------|------|-----|-------|------|--------|
| **Typing** | Strict, inferred | Strict, inferred | Strict, inferred | Strict, inferred | Strict, inferred | Strict, inferred |
| **Effects** | Tracked, lexical, safe | Tracked, lexical, safe | None (platform model) | None | None | Tracked abilities |
| **Effect safety** | Compile-time enforced | Compile-time enforced | N/A | N/A | N/A | Compile-time enforced |
| **Sum types** | Structural tag unions | Nominal + structural | Structural tags | Nominal | Nominal enums | Nominal |
| **Product types** | Row-polymorphic records | Row-polymorphic records | Structural records | Nominal records | Nominal structs | Nominal records |
| **Mutation** | Stack-local only | Full (with `var`) | Stack-local only | None | Full (borrow checker) | None |
| **Memory** | Perceus RC | Perceus RC | Platform-provided | BEAM GC | Manual + RC | BEAM GC |
| **Compilation** | Direct WASM | Via C/gcc | Via Zig/LLVM | To BEAM/JS | LLVM | Self-hosted |
| **Error handling** | Throw + tag unions | exn + maybe/either | Try tag unions | Result type | Result + panic | Exception + Optional |
| **Concurrency** | Async effect (coroutines) | Async effect | None | OTP processes | async/await + threads | Abilities |
| **Metaprogramming** | Derive + comptime | None | None | None | Derive + proc macros | None |
| **Implementation** | Odin | Haskell | Zig | Erlang | Rust | Unison |
| **Target** | WASM/WASI | Native | Native | BEAM/JS | Native | BEAM |

---

## Appendix C: Syntax Reference Card

### Types

```
I64, U64, etc.         -- primitive integer types: I8, I16, I32, I64, U8, U16, U32, U64
F32, F64               -- floating point
Bool                   -- True | False
Str                    -- UTF-8 string
List(a)                -- linked list
Map(k, v)              -- hash map
Set(a)                 -- hash set
Iter(a)                -- lazy iterator
Handle(a)              -- async coroutine handle
[Ok(a) | Err(e)]       -- closed tag union
[Ok(a) | Err(e) | ..] -- open tag union (at least these, possibly more)
[..]                   -- fully open tag union (zero or more tags)
{ name: Str, age: U64 }  -- closed record
{ name: Str, .. }     -- open record (at least name, possibly more)
{ name: Str, ..rest } -- open record with row variable
UserId := U64          -- newtype
```

### Bindings

```
x: I64 = 3                             -- constant binding
$count: I64 = 0                         -- mutable binding (function body only, no var keyword)
UserId is Hash := U64                   -- newtype with trait
@derive [Display, Hash] OrderId := U64  -- newtype with derived traits
```

### Functions

```
add = <a>|x: a, y: a| -> a { x + y }   -- named function definition
add : <a>|a, a| -> a                    -- type-only declaration
|x: I64, y: I64| -> I64 { x + y }      -- anonymous function
read_line! = || ->{ Console } Str { … } -- effectful function
map = <a, b, e>|f: |a| ->{ e } b, list: List(a)| ->{ e } List(b) { … }
```

### Effects

```
effect Async {
  yield! : || ->{ Async } {}
}

handle Async in { … } with { .yield!(resume) => resume({}) }
intercept Async in { … } with { .yield!(resume) => resume({}) }
```

### Pattern Matching

```
match result {
  Ok(value) => value
  Err(msg) => handle_error(msg)
}

match maybe {
  Some(x) => x
  None => default
  _ => fallback                          -- wildcard (covers remaining)
}
```

### Collections

```
[1, 2, 3]                              -- list literal
list.iter().map(|x| x * 2).filter(|x| x > 3).collect()  -- iterator chain
list.first()                            -- → Some(a) | None
map.get(key)                            -- → Some(v) | None
```

### Error Handling

```
Throw.throw!(NotFound)                  -- throw an error
parse! : Str ->{ Throw(BadNumStr) } I64 -- throw in type signature
main! : || ->{ Console, Throw([..]) } {} -- main can throw any tag

-- Handler bridges Throw to tag union:
to_result = |action: || ->{ Throw(e) } a| -> [Ok(a) | Err(e)] {
  handle Throw in {
    Ok(action())
  } with {
    .throw!(resume, err) => Err(err)
  }
}
```

### Concurrency

```
task = Async.spawn!(|| { long_computation!() })
result = Async.join!(task)
Async.yield!()                          -- cooperative yield
Async.cancel!(task)                     -- cancel a coroutine
```

### Imports and Modules

```
import List exposing [map, filter]
import Result
import My.Module as M
import Result exposing [Ok, Err]        -- import tags unqualified
```

### Testing

```
test "addition" = {
  expect add(2, 3) == 5
}

expect list.len() == 3                  -- inline assertion
```

### Misc

```
Console.println!("Hello!")              -- effectful I/O
File.read!("data.txt")                  -- effectful file read
`do`                                    -- raw identifier (backtick-wrapped)
{ name, age } = record                  -- record destructuring (closed)
{ name, .. } = record                   -- record destructuring (open, allows extra fields)
{ ..record, name: "new" }              -- record update
x and y                                 -- logical AND
x or y                                  -- logical OR
Result.Ok(42)                           -- nominal type qualified construction
42                                      -- default integer type: I64
3.14                                    -- default float type: F64
```
