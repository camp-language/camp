# Effects — Behavioral Specification

## Purpose

For the complete syntax reference, see `docs/syntax-recipe.md`.

Define the behavioral requirements for Camp's algebraic effect system: effects as type aliases with `!` names, parameterized effects with tag union widening, Koka-style effect rows for tracking side effects in function types, effect polymorphism via row variables, deep handlers for intercepting operations, one-shot continuations, and compile-time enforcement that all performed effects are handled.

## Requirements

### Requirement: Effect Operations Are Called as Functions

Effect operations SHALL be invoked as ordinary function calls qualified by their effect name. There SHALL be no `perform` or `do` keyword. The `!` suffix on effect type names and operation names SHALL be part of the actual name, not a separate modifier. The effect-qualified call `E.op!(args)` SHALL be syntactically a function call, not a special form.

#### Scenario: Effectful function call syntax

- **WHEN** a Camp program calls `Console.println!("hello")`
- **THEN** it SHALL be syntactically a function call qualified by the `Console!` effect, not a special `perform` form

### Requirement: Effects Are Type Aliases With `!` Names

Effects SHALL be defined using the `:` type alias syntax with the effect name ending in `!`. The `!` is part of the actual name, not a modifier. There SHALL be no `effect` keyword. Effect definitions are type aliases whose body is a record of function signatures. Effect operation names SHALL end with `!`. Operation type annotations SHALL be required.

#### Scenario: Effect definition

- **GIVEN** a definition `Console! : { println!: |Str| -[Console!]-> {} }`
- **WHEN** the compiler processes it
- **THEN** `Console!` SHALL be an effect type with a typed operation `println!`

#### Scenario: Effect name must end with !

- **GIVEN** a definition `Console : { println!: |Str| -> {} }` without `!` on the name
- **WHEN** the compiler processes it
- **THEN** it SHALL be treated as a type alias, not an effect; effect definitions MUST end with `!`

#### Scenario: Non-effect types cannot end with !

- **GIVEN** a definition `@Result! : [Ok(a) | Err(e)]`
- **WHEN** the compiler processes it
- **THEN** it SHALL produce an error — only effect types may end with `!`

#### Scenario: Operation type annotations are required

- **GIVEN** a definition `Console! : { println! }` without a type annotation on `println!`
- **WHEN** the compiler processes it
- **THEN** it SHALL produce an error — effect operation type annotations are required

### Requirement: Parameterized Effects

Effects MAY have type parameters. When a type parameter is used in a tag union position, it SHALL widen through tag row unification as more variants are performed. When a type parameter is used in a value position, it SHALL specialize like any other type parameter. Effect rows SHALL track effect names with their type arguments: `-[Throw!([NotFound | PermissionDenied])]->`.

#### Scenario: Tag union parameter widens

- **GIVEN** a function that calls `Throw.raise!(NotFound)` and `Throw.raise!(PermissionDenied)`
- **WHEN** the typechecker infers the effect row
- **THEN** it SHALL be `-[Throw!([NotFound | PermissionDenied])]->` — the tag union widened through row unification

#### Scenario: Value parameter specializes

- **GIVEN** a function that uses `State!(Int)` and another that uses `State!(Str)`
- **WHEN** the typechecker unifies their effect rows
- **THEN** unification SHALL fail — `State!(Int)` and `State!(Str)` are different effects

#### Scenario: Open tag union parameter for handlers

- **GIVEN** a `handle Throw! in body with { .raise!(resume, err) => ... }` where body has row `-[Throw!([NotFound | ..])]->`
- **WHEN** the handler processes any thrown tag
- **THEN** the open tag union `[NotFound | ..]` SHALL accept any tag variant

### Requirement: Variant Widening Is General Tag Row Unification

Variant widening — where a tag union type parameter on an effect grows as more tag types are performed — SHALL NOT be specific to any particular effect. It SHALL be the natural result of tag row unification applied to effect type parameters. Any effect with a tag union type parameter SHALL exhibit widening behavior.

#### Scenario: Custom effect with widening tag union

- **GIVEN** an effect `Signal! : { emit!: |e| -[Signal!(e)]-> {} }` and a function that calls `Signal.emit!(Click)` then `Signal.emit!(KeyPress)`
- **WHEN** the typechecker infers the effect row
- **THEN** it SHALL be `-[Signal!([Click | KeyPress])]->` — widened through the same tag row unification as Throw!

#### Scenario: Widening is not Throw-specific

- **GIVEN** the Throw! effect definition `Throw!(e) : { raise!: |e| -[Throw!(e)]-> a }`
- **WHEN** compared with the Signal! effect definition
- **THEN** both SHALL use identical tag row unification mechanics — no Throw-specific widening code

### Requirement: Effect Rows Track Effects in Function Types

Every function type SHALL include an effect row declaring which effects the function may perform. The effect row SHALL appear between `-[` and `]->` in the function type arrow. An elided effect row (plain `->`) SHALL denote the empty row — a pure function.

#### Scenario: Effect-polymorphic function type

- **WHEN** a function has type `|f: |a| -[e]-> b| -[e]-> List(b)`
- **THEN** the effect row variable `e` SHALL propagate whatever effects `f` performs

### Requirement: Effect Polymorphism

Effect row variables SHALL be generic type parameters that can be instantiated at call sites. A function that accepts an effect-polymorphic callback SHALL propagate the callback's effects into its own effect row via row composition. The typechecker SHALL support unification of effect row variables with concrete effect rows and with other effect row variables.

#### Scenario: Effect polymorphism through map

- **GIVEN** `map = |f: |a| -[e]-> b, items: List(a)| -[Parallel! | e]-> List(b)`
- **WHEN** `map` is called with a pure function `|x| x + 1`
- **THEN** the effect row SHALL be `-[Parallel!]->` only

- **WHEN** `map` is called with an effectful function `|x| Throw.raise!(x)`
- **THEN** the effect row SHALL be `-[Parallel! | Throw!(a)]->`

#### Scenario: Effect row variable unification

- **GIVEN** two functions with effect row variables `e1` and `e2`
- **WHEN** one calls the other and the effect rows are unified
- **THEN** the unification SHALL compose the rows, adding any concrete effects from the callee to the caller's row

### Requirement: Effect Row Syntax

Effect rows SHALL use the syntax `-[Eff1 | Eff2]->` with `|` separators inside `-[ ... ]->`. Supported forms SHALL include: singleton rows, multi-effect rows, row variables, open rows, and fully open rows.

#### Scenario: Open row type

- **WHEN** a function type uses `-[E | ..]->`
- **THEN** it SHALL denote at least effect `E` and possibly more

### Requirement: Deep Handlers Reinstall After Resume

A deep handler (the `handle` keyword) SHALL be automatically re-installed after each `resume` call. All matching operations in the scoped block — including those after resumption — SHALL be handled by the same handler.

#### Scenario: Deep handler handles all operations

- **WHEN** a `handle Async!` block contains multiple `Async.yield!()` calls
- **THEN** each call SHALL be caught by the same handler after `resume` reinstalls it

### Requirement: One-Shot Continuations

Each `resume` continuation SHALL be called at most once. A second invocation of the same `resume` SHALL be a runtime error (trap in WASM).

#### Scenario: One-shot violation is a runtime trap

- **WHEN** a handler calls `resume(42)` followed by `resume(99)` on the same continuation
- **THEN** the second call SHALL trigger a runtime trap

### Requirement: Throw! Is a Normal Effect in the Prelude

`Throw!` SHALL be a normal effect defined in the prelude, not a built-in with special syntax. Its definition SHALL be `Throw!(e) : { raise!: |e| -[Throw!(e)]-> a }`. Handlers for `Throw!` MAY call `resume` — there is no non-resuming restriction. The common pattern of not resuming is a handler implementation choice, not a language constraint. The runtime SHALL provide a default handler for `Throw!([..])` in `main!` that renders the unhandled tag to stderr and exits non-zero.

#### Scenario: Throw! as prelude effect

- **GIVEN** the prelude definition `Throw!(e) : { raise!: |e| -[Throw!(e)]-> a }`
- **WHEN** a program calls `Throw.raise!(NotFound)`
- **THEN** it SHALL perform the `raise!` operation of the `Throw!` effect, adding `Throw!([NotFound])` to the effect row

#### Scenario: Resuming Throw! handler

- **GIVEN** a handler `handle Throw! in risky_op() with { .raise!(resume, _) => resume(0) }`
- **WHEN** `risky_op()` throws an error
- **THEN** the handler SHALL provide `0` as the result and computation SHALL continue — resuming from Throw! is permitted

#### Scenario: Non-resuming Throw! handler

- **GIVEN** a handler `handle Throw! in risky_op() with { .raise!(resume, err) => Err(err) }`
- **WHEN** `risky_op()` throws an error
- **THEN** the handler SHALL return `Err(err)` without calling `resume` — computation after the throw is abandoned

#### Scenario: Default runtime handler for Throw!

- **WHEN** `main!` declares `-[Throw!([..])]->` and an unhandled tag is thrown
- **THEN** the runtime default handler SHALL render the tag to stderr and exit with code 1

### Requirement: Parallel!, Spawn!, and Async! Are Prelude Effects

`Parallel!`, `Spawn!`, and `Async!` SHALL be normal effects defined in the prelude by the compiler, alongside `Console!`, `Throw!`, `File!`, `Env!`, `Time!`, and `Random!`.

The prelude SHALL inject these effects with the following operation signatures:

- **Parallel!(a)** : `{ map!: |fn, iterable| -[Parallel!(a) | (fn effects)]-> List(b), for_each!: |fn, iterable| -[Parallel!(a) | (fn effects)]-> {}, filter!: |fn, iterable| -[Parallel!(a) | (fn effects)]-> List(a), any!: |fn, iterable| -[Parallel!(a) | (fn effects)]-> Bool, all!: |fn, iterable| -[Parallel!(a) | (fn effects)]-> Bool, reduce!: |fn, init, iterable| -[Parallel!(a) | (fn effects)]-> b }`
- **Spawn!** : `{ spawn!: |fn| -[Spawn!]-> Handle(a), join!: |handle| -[Spawn!]-> a }`
- **Async!** : `{ spawn!: |fn| -[Async!]-> Handle(a), join!: |handle| -[Async!]-> a, cancel!: |handle| -[Async!]-> {}, yield!: || -[Async!]-> {} }`

#### Scenario: Parallel!, Spawn!, Async! available without imports

- **GIVEN** a Camp program without explicit imports of Parallel!, Spawn!, or Async!
- **WHEN** the program performs `Parallel.map!(fn, xs)`
- **THEN** it SHALL compile and add `Parallel!(a)` to the effect row

#### Scenario: Shadowing prelude effects

- **WHEN** a module declares a type named `Parallel!` or `Spawn!`
- **THEN** it SHALL shadow the prelude definition within that module only

### Requirement: Evidence Record Layout

Each handled effect parameter SHALL receive a 4-byte evidence slot on the WASM call stack. The evidence slot SHALL contain a closure pointer (function index) as an `i32`. The callee's function index, environment pointer, and one-shot flag SHALL be loaded from within the closure at dispatch time, rather than stored as separate stack slots.

#### Scenario: Evidence slot size

- **WHEN** the compiler allocates evidence for a handled effect
- **THEN** each evidence slot SHALL advance the stack offset by exactly 4 bytes

### Requirement: Effect Safety — Unhandled Effects Are Compile-Time Errors

A function's effect row SHALL be a subset of the effects handled by its caller's context. If a function performs an effect that no enclosing handler covers, the typechecker SHALL emit a compile-time error.

#### Scenario: Unhandled effect at compile time

- **WHEN** `main!` declares `|| -> I64` and calls `Console.println!("oops")`
- **THEN** the typechecker SHALL emit an error for unhandled effect `Console!`

### Requirement: Handler Arm Parameters Include Resume and Operation Args

Handler arms SHALL receive `resume` as their first parameter, followed by the operation's arguments. `resume` SHALL always be the first parameter. Remaining parameters SHALL correspond positionally to the operation's declared parameters. The `!` after the operation name SHALL be required.

#### Scenario: Handler arm receives operation arguments

- **GIVEN** an effect `Ask! : { ask!: |Str| -[Ask!]-> Str }`
- **WHEN** a handler for `Ask!` is defined
- **THEN** the arm SHALL receive `.ask!(resume, question)` with `resume` first, then `question`

#### Scenario: Handler arm type checked against operation declaration

- **GIVEN** an effect `Console! : { println!: |Str| -[Console!]-> {} }` and a handler arm `.println!(resume, msg) => resume(0)`
- **WHEN** the typechecker verifies the handler
- **THEN** it SHALL check that `msg` has type `Str` and the arm's return type matches the `handle` block's expected type

### Requirement: Effect Composition Via Aliases

Effects SHALL compose by set union in the type, not by subtyping. There SHALL be no `effect File! is Io` syntax. Instead, aliases SHALL group effects: `Io!: [File! | Console!]`. Operations SHALL always be qualified by their defining effect.

#### Scenario: Effect composition via alias

- **WHEN** `Io!: [File! | Console!]` is defined
- **THEN** `Io!` SHALL expand to `[File! | Console!]` and operations SHALL still be qualified individually as `File.write!` and `Console.println!`

### Requirement: Effect Row Subtraction When Handling

When a `handle` expression handles effect `E`, the resulting effect row SHALL be the original row minus `E`. This subtraction SHALL be computed by the typechecker. Nested handlers SHALL subtract cumulatively. For effect-polymorphic rows (row variable `e`), the typechecker SHALL create a constraint that `e` minus the handled effect equals the result row. For parameterized effects, subtraction removes the effect regardless of its type arguments.

#### Scenario: Effect row subtraction after handling

- **WHEN** a `handle Console!` block has body with row `-[Console! | Throw!([..])]->`
- **THEN** the resulting row SHALL be `-[Throw!([..])]->` — `Console!` removed by the handler

#### Scenario: Parameterized effect row subtraction

- **WHEN** a `handle Throw!` block has body with row `-[Throw!([NotFound | PermissionDenied]) | Console!]->`
- **THEN** the resulting row SHALL be `-[Console!]->` — `Throw!` removed regardless of its type arguments
