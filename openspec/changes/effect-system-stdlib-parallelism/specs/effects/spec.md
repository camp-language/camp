## MODIFIED Requirements

### Requirement: Effect Definition Syntax

Effects SHALL be defined using the `:` syntax with the effect name ending in `!`. The `!` is part of the actual name, not a modifier. There SHALL be no `effect` keyword. Effect operation names SHALL also end with `!`. Effect operation type annotations SHALL be required.

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

### Requirement: Throw Effect for Error Propagation

`Throw!` SHALL be a normal effect defined in the prelude: `Throw! : { throw!: |e| -[Throw!(e)]-> a }`. Its parameter SHALL be a tag union that widens as more tag types are thrown through general tag row unification. `Throw!` handlers MAY call `resume` — there is no non-resuming restriction. The common pattern of not resuming is a handler implementation choice. The runtime SHALL provide a default handler for `Throw!([..])` in `main!` that renders the unhandled tag to stderr and exits non-zero.

#### Scenario: Throw! as prelude effect

- **GIVEN** the prelude definition `Throw! : { throw!: |e| -[Throw!(e)]-> a }`
- **WHEN** a program calls `Throw!.throw!(NotFound)`
- **THEN** it SHALL perform the `throw!` operation of the `Throw!` effect, adding `Throw!([NotFound])` to the effect row

#### Scenario: Resuming Throw! handler

- **GIVEN** a handler `handle Throw! in risky_op() with { .throw!(resume, _) => resume(0) }`
- **WHEN** `risky_op()` throws an error
- **THEN** the handler SHALL provide `0` as the result and computation SHALL continue — resuming from Throw! is permitted

#### Scenario: Non-resuming Throw! handler

- **GIVEN** a handler `handle Throw! in risky_op() with { .throw!(resume, err) => Err(err) }`
- **WHEN** `risky_op()` throws an error
- **THEN** the handler SHALL return `Err(err)` without calling `resume` — computation after the throw is abandoned

#### Scenario: Fully open Throw! in main

- **WHEN** `main!` declares `-[Throw!([..])]->` and an unhandled tag is thrown
- **THEN** the runtime default handler SHALL render the tag to stderr and exit with code 1

### Requirement: Handler Arm Parameters Include Resume and Operation Args

Handler arms SHALL receive `resume` as their first parameter, followed by the operation's arguments. `resume` SHALL always be the first parameter. Remaining parameters SHALL correspond positionally to the operation's declared parameters. The `!` after the operation name SHALL be required. All handlers — including Throw! — use the same arm signature.

#### Scenario: Handler arm type checked against operation declaration

- **GIVEN** an effect `Console! : { println!: |Str| -[Console!]-> {} }` and a handler arm `.println!(resume, msg) => resume(0)`
- **WHEN** the typechecker verifies the handler
- **THEN** it SHALL check that `msg` has type `Str` and the arm's return type matches the `handle` block's expected type

### Requirement: Effect Row Subtraction When Handling

When a `handle` expression handles effect `E`, the resulting effect row SHALL be the original row minus `E`. This subtraction SHALL be computed by the typechecker. Nested handlers SHALL subtract cumulatively. For effect-polymorphic rows (row variable `e`), the typechecker SHALL create a constraint that `e` minus the handled effect equals the result row. For parameterized effects, subtraction removes the effect regardless of its type arguments.

#### Scenario: Parameterized effect row subtraction

- **WHEN** a `handle Throw!` block has body with row `-[Throw!([NotFound | PermissionDenied]) | Console!]->`
- **THEN** the resulting row SHALL be `-[Console!]->` — `Throw!` removed regardless of its type arguments

## ADDED Requirements

### Requirement: Parameterized Effects

Effects MAY have type parameters. When a type parameter is used in a tag union position, it SHALL widen through tag row unification as more variants are performed. Effect rows SHALL track effect names with their type arguments.

#### Scenario: Tag union parameter widens

- **GIVEN** a function that calls `Throw!.throw!(NotFound)` and `Throw!.throw!(PermissionDenied)`
- **WHEN** the typechecker infers the effect row
- **THEN** it SHALL be `-[Throw!([NotFound | PermissionDenied])]->` — the tag union widened through row unification

### Requirement: Variant Widening Is General Tag Row Unification

Variant widening SHALL NOT be specific to any particular effect. It SHALL be the natural result of tag row unification applied to effect type parameters. Any effect with a tag union type parameter SHALL exhibit widening behavior.

#### Scenario: Custom effect with widening tag union

- **GIVEN** an effect `Signal! : { emit!: |e| -[Signal!(e)]-> {} }` and a function that calls `Signal!.emit!(Click)` then `Signal!.emit!(KeyPress)`
- **WHEN** the typechecker infers the effect row
- **THEN** it SHALL be `-[Signal!([Click | KeyPress])]->` — widened through the same tag row unification as Throw!

### Requirement: Effect Polymorphism

Effect row variables SHALL be generic type parameters that can be instantiated at call sites. A function that accepts an effect-polymorphic callback SHALL propagate the callback's effects into its own effect row via row composition.

#### Scenario: Effect polymorphism through map

- **GIVEN** `map = <a, b, e>|f: |a| -[e]-> b, items: List(a)| -[Parallel! | e]-> List(b)`
- **WHEN** `map` is called with a pure function `|x| x + 1`
- **THEN** the effect row SHALL be `-[Parallel!]->` only

- **WHEN** `map` is called with an effectful function `|x| Throw!.throw!(x)`
- **THEN** the effect row SHALL be `-[Parallel! | Throw!(a)]->`
