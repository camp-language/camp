## ADDED Requirements

### Requirement: Effects Can Have Type Parameters

Effect type aliases SHALL support type parameters, enabling parameterized effects such as `Throw!(e)` and `State!(s)`.

#### Scenario: Parameterized Throw! effect

- **GIVEN** an effect `Throw! : { throw!: |e| -[Throw!(e)]-> a }`
- **WHEN** a function calls `Throw!.throw!(NotFound)`
- **THEN** the effect row SHALL include `Throw!([NotFound])` with the type argument

#### Scenario: Parameterized State! effect

- **GIVEN** an effect `State! : { get!: || -[State!(s)]-> s, put!: |s| -[State!(s)]-> {} }`
- **WHEN** a function uses `State!(Int)`
- **THEN** `State!(Int)` and `State!(Str)` SHALL be different effects — type arguments are part of the effect identity for value-type parameters

### Requirement: Tag Union Type Parameters Widen Through Row Unification

When an effect has a type parameter used in tag union position, and two occurrences of the effect are unified, the type parameters SHALL unify via tag row unification — accumulating variants from both sides.

#### Scenario: Two throw sites widen the tag union

- **GIVEN** a function that calls `Throw!.throw!(NotFound)` in one branch and `Throw!.throw!(PermissionDenied)` in another
- **WHEN** the typechecker unifies the two `Throw!` occurrences
- **THEN** the type parameter SHALL widen to `[NotFound | PermissionDenied]` via tag row unification

#### Scenario: Custom effect with widening tag union

- **GIVEN** an effect `Signal! : { emit!: |e| -[Signal!(e)]-> {} }` and a function calling `Signal!.emit!(Click)` then `Signal!.emit!(KeyPress)`
- **WHEN** the typechecker infers the effect row
- **THEN** it SHALL be `-[Signal!([Click | KeyPress])]->` — widened via the same mechanism as Throw!

### Requirement: Variant Widening Is Not Effect-Specific

Variant widening SHALL be the natural result of tag row unification applied to effect type parameters. The typechecker SHALL NOT contain any effect-specific widening code. Any effect with a tag union type parameter SHALL exhibit widening behavior.

#### Scenario: No Throw-specific widening code

- **GIVEN** the typechecker's effect row unification implementation
- **WHEN** examining the code path for unifying two occurrences of the same effect with tag union parameters
- **THEN** the code SHALL use the same `unify_tag_union_rows` function for all effects — no special case for Throw!

### Requirement: Effect Rows Track Type Arguments

Effect rows SHALL track effect names with their type arguments. `-[Throw!([NotFound])]->` and `-[Throw!([PermissionDenied])]->` are different rows that unify to `-[Throw!([NotFound | PermissionDenied])]->`.

#### Scenario: Effect row with type argument in function type

- **GIVEN** a function type `|| -[Throw!([NotFound | PermissionDenied])]-> I64`
- **WHEN** the compiler processes the type
- **THEN** the effect row SHALL contain `Throw!` with its tag union type argument `[NotFound | PermissionDenied]`
