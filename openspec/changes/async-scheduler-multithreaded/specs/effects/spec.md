## MODIFIED Requirements

### Requirement: Handler Arm Parameters Include Resume and Operation Args

Handler arms SHALL receive `resume` as their first parameter, followed by the operation's arguments. `resume` SHALL always be the first parameter. Remaining parameters SHALL correspond positionally to the operation's declared parameters. The `!` after the operation name SHALL be required.

This requirement is MODIFIED for `Spawn!` and `Async!` handler arms: the `join!` arm SHALL re-throw errors stored in the handle's result slot when the result tag indicates a thrown error.

#### Scenario: Handler arm receives operation arguments

- **GIVEN** an effect `Ask! : { ask!: |Str| -[Ask!]-> Str }`
- **WHEN** a handler for `Ask!` is defined
- **THEN** the arm SHALL receive `.ask!(resume, question)` with `resume` first, then `question`

#### Scenario: Spawn join! arm re-throws stored error

- **GIVEN** a `Spawn!` handler arm `.join!(resume, handle)` where the handle's result slot tag indicates a thrown error
- **WHEN** the handler arm processes the join
- **THEN** the arm SHALL perform `Throw!.throw!(error_value)` in the caller's context before calling `resume`

## ADDED Requirements

### Requirement: Effect Row Propagation Through Handle Type

The `Handle(a, e)` type SHALL carry the spawned thunk's effect row `e` as a type parameter. Effect handlers for `Spawn!` and `Async!` SHALL propagate `e` through `join!` into the caller's effect row. This ensures that effects performed by the spawned thunk are statically tracked at the `join!` call site.

#### Scenario: Pure spawned thunk has empty effect row

- **GIVEN** `Spawn!.spawn!(|| 42)` where the thunk is pure
- **WHEN** the typechecker infers the handle type
- **THEN** the handle SHALL have type `Handle(Int, {})` and `join!` SHALL only add `Spawn!` to the caller's effect row

#### Scenario: Effectful spawned thunk propagates effects

- **GIVEN** `Spawn!.spawn!(|| Console!.println!("hi"))` where the thunk performs `Console!`
- **WHEN** the typechecker infers the handle type
- **THEN** the handle SHALL have type `Handle({}, Console!)` and `join!` SHALL add `Spawn! | Console!` to the caller's effect row

### Requirement: Error Result Slot Tag in Handle Table

The handle table's result slot SHALL use a two-word format: `(tag: u32, value: u32)`. Tag 0 SHALL indicate a normal result. Tag 1 SHALL indicate a thrown error. When `join!` reads a result slot with tag 1, it SHALL re-throw the error value via `Throw!.throw!` in the caller's context.

#### Scenario: Normal completion stores tag 0

- **GIVEN** a spawned task completes normally with result 42
- **WHEN** the scheduler stores the result in the handle table
- **THEN** the result slot SHALL be `(tag=0, value=42)`

#### Scenario: Thrown error stores tag 1

- **GIVEN** a spawned task throws `ParseError`
- **WHEN** the scheduler stores the error in the handle table
- **THEN** the result slot SHALL be `(tag=1, value=<ParseError_tag_union_ptr>)`

#### Scenario: Cross-instance error serialization

- **GIVEN** a spawned task in a separate WASM instance throws `ParseError`
- **WHEN** the error is propagated across the instance boundary
- **THEN** the error tag and payload SHALL be serialized, transmitted to the joining instance, deserialized, and re-thrown via `Throw!.throw!`
