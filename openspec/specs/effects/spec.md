# Effects — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's algebraic effect system: Koka-style effect rows for tracking side effects in function types, deep and shallow handlers for intercepting operations, one-shot continuations, and compile-time enforcement that all performed effects are handled.

## Requirements

### Requirement: Effect Operations Are Called as Functions

Effect operations SHALL be invoked as ordinary function calls qualified by their effect name. There SHALL be no `perform` or `do` keyword. The `!` suffix on effect type names and operation names SHALL be part of the actual name, not a separate modifier. The effect-qualified call `E!.op!(args)` SHALL be syntactically a function call, not a special form.

#### Scenario: Effectful function call syntax

- **WHEN** a Camp program calls `Console!.println!("hello")`
- **THEN** it SHALL be syntactically a function call qualified by the `Console!` effect, not a special `perform` form

### Requirement: Effect Definition Syntax

Effects SHALL be defined using the `:` syntax with the effect name ending in `!`. The `!` is part of the actual name, not a modifier. Effect operation names SHALL also end with `!`.

#### Scenario: Effect definition

- **GIVEN** a definition `Console! : { println!(Str) }`
- **WHEN** the compiler processes it
- **THEN** `Console!` SHALL be an effect type with an operation `println!`

#### Scenario: Effect name must end with !

- **GIVEN** a definition `Console : { println(Str) }` without `!` on the name
- **WHEN** the compiler processes it
- **THEN** it SHALL be treated as a type alias, not an effect; effect definitions MUST end with `!`

#### Scenario: Non-effect types cannot end with !

- **GIVEN** a definition `@Result! : [Ok(a) | Err(e)]`
- **WHEN** the compiler processes it
- **THEN** it SHALL produce an error — only effect types may end with `!`

### Requirement: Effect Rows Track Effects in Function Types

Every function type SHALL include an effect row declaring which effects the function may perform. The effect row SHALL appear between `-[` and `]->` in the function type arrow. An elided effect row (plain `->`) SHALL denote the empty row — a pure function.

#### Scenario: Effect-polymorphic function type

- **WHEN** a function has type `|f: |a| -[e]-> b| -[e]-> List(b)`
- **THEN** the effect row variable `e` SHALL propagate whatever effects `f` performs

### Requirement: Effect Row Syntax

Effect rows SHALL use the syntax `-[Eff1 | Eff2]->` with `|` separators inside `-[ ... ]->`. Supported forms SHALL include: singleton rows, multi-effect rows, row variables, open rows, and fully open rows.

#### Scenario: Open row type

- **WHEN** a function type uses `-[E | ..]->`
- **THEN** it SHALL denote at least effect `E` and possibly more

### Requirement: Deep Handlers Reinstall After Resume

A deep handler (the `handle` keyword) SHALL be automatically re-installed after each `resume` call. All matching operations in the scoped block — including those after resumption — SHALL be handled by the same handler.

#### Scenario: Deep handler handles all operations

- **WHEN** a `handle` block contains multiple `Async.yield!()` calls
- **THEN** each call SHALL be caught by the same handler after `resume` reinstalls it

### Requirement: Shallow Handlers Do Not Reinstall

A shallow handler (the `intercept` keyword) SHALL handle only the first matching operation. After `resume`, the handler SHALL NOT be re-installed. Subsequent operations of the same effect SHALL propagate to an outer handler.

#### Scenario: Shallow handler handles only the first operation

- **WHEN** an `intercept` block contains two `Async.yield!()` calls
- **THEN** the first SHALL be caught by the handler and the second SHALL propagate to an outer handler

### Requirement: One-Shot Continuations

Each `resume` continuation SHALL be called at most once. A second invocation of the same `resume` SHALL be a runtime error (trap in WASM).

#### Scenario: One-shot violation is a runtime trap

- **WHEN** a handler calls `resume(42)` followed by `resume(99)` on the same continuation
- **THEN** the second call SHALL trigger a runtime trap

### Requirement: Throw Effect for Error Propagation

`Throw` SHALL be Camp's built-in error effect. Its parameter SHALL be a tag union that widens as more tag types are thrown. `Throw` handlers SHALL never call `resume` — they SHALL return a value directly or re-throw. The runtime SHALL provide a default handler for `Throw([..])` in `main!` that renders the unhandled tag to stderr and exits non-zero.

#### Scenario: Throw as non-resuming handler

- **WHEN** a `handle Throw` block executes `Throw.throw!(NotFound)`
- **THEN** the handler SHALL return a value without calling `resume`

#### Scenario: Fully open Throw in main

- **WHEN** `main!` declares `-[Throw([..])]->` and an unhandled tag is thrown
- **THEN** the runtime default handler SHALL render the tag to stderr and exit with code 1

### Requirement: Effect Safety — Unhandled Effects Are Compile-Time Errors

A function's effect row SHALL be a subset of the effects handled by its caller's context. If a function performs an effect that no enclosing handler covers, the typechecker SHALL emit a compile-time error.

#### Scenario: Unhandled effect at compile time

- **WHEN** `main!` declares `|| -> I64` and calls `Console.println!("oops")`
- **THEN** the typechecker SHALL emit an error for unhandled effect `Console`

### Requirement: Handler Arm Parameters Include Resume and Operation Args

Handler arms SHALL receive `resume` as their first parameter, followed by the operation's arguments. `resume` SHALL always be the first parameter. Remaining parameters SHALL correspond positionally to the operation's parameters. The `!` after the operation name SHALL be required.

#### Scenario: Handler arm receives operation arguments

- **WHEN** a handler for `Ask.ask! : Str -[Ask]-> Str` is defined
- **THEN** the arm SHALL receive `.ask!(resume, question)` with `resume` first, then `question`

### Requirement: Effect Composition Via Aliases

Effects SHALL compose by set union in the type, not by subtyping. There SHALL be no `effect File is Io` syntax. Instead, aliases SHALL group effects: `alias Io = File | Console`. Operations SHALL always be qualified by their defining effect.

#### Scenario: Effect composition via alias

- **WHEN** `alias Io = File | Console` is defined
- **THEN** `Io` SHALL expand to `File | Console` and operations SHALL still be qualified individually as `File.write!` and `Console.println!`

### Requirement: Effect Row Subtraction When Handling

When a `handle` expression handles effect `E`, the resulting effect row SHALL be the original row minus `E`. This subtraction SHALL be computed by the typechecker. Nested handlers SHALL subtract cumulatively. For effect-polymorphic rows (row variable `e`), the typechecker SHALL create a constraint that `e` minus the handled effect equals the result row.

#### Scenario: Effect row subtraction after handling

- **WHEN** a `handle Console` block has body with row `{Console | Throw([..])}`
- **THEN** the resulting row SHALL be `{Throw([..])}` — `Console` removed by the handler
