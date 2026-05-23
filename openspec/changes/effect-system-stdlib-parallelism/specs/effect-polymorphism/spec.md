## ADDED Requirements

### Requirement: Effect Row Variables as Generic Parameters

Effect row variables SHALL be usable as generic type parameters in function signatures. A lowercase identifier in effect row position SHALL be treated as an effect row variable, not a value type variable.

#### Scenario: Effect-polymorphic map function

- **GIVEN** a function `map = |f: |a| -[e]-> b, items: List(a)| -[Parallel! | e]-> List(b)`
- **WHEN** `map` is called with a pure function `|x| x + 1`
- **THEN** the effect row SHALL be `-[Parallel!]->` only

#### Scenario: Effect-polymorphic map with effectful callback

- **GIVEN** a function `map = |f: |a| -[e]-> b, items: List(a)| -[Parallel! | e]-> List(b)`
- **WHEN** `map` is called with `|x| Throw!.throw!(x)`
- **THEN** the effect row SHALL be `-[Parallel! | Throw!(a)]->`

### Requirement: Effect Row Variable Unification

The typechecker SHALL unify effect row variables with concrete effect rows and with other effect row variables. When a row variable is unified with a concrete row, the variable SHALL be bound to that row. When two row variables are unified, they SHALL refer to the same row.

#### Scenario: Row variable unified with concrete row

- **GIVEN** a function parameter with effect row variable `e` and a call site passing a function with row `-[Console! | Throw!([..])]->`
- **WHEN** the typechecker unifies `e` with `-[Console! | Throw!([..])]->`
- **THEN** `e` SHALL be bound to `-[Console! | Throw!([..])]->`

#### Scenario: Row variable unified with another row variable

- **GIVEN** two generic functions with effect row variables `e1` and `e2`
- **WHEN** one calls the other and their effect rows are unified
- **THEN** `e1` and `e2` SHALL refer to the same row

### Requirement: Effect Row Composition

When an effect row contains a row variable and a concrete effect, the row SHALL compose by adding the concrete effect. `-[Parallel! | e]->` unifies with `-[e]->` by adding `Parallel!` to the row.

#### Scenario: Row composition adds effect

- **GIVEN** a callback with effect row `-[e]->` used in a context requiring `-[Parallel! | e]->`
- **WHEN** the typechecker composes the rows
- **THEN** the resulting row SHALL be `-[Parallel! | e]->` — `Parallel!` added, `e` still polymorphic

### Requirement: Effect Row Subtraction with Variables

When a `handle` expression handles an effect from a row containing a row variable, the typechecker SHALL create a constraint that the result row is the variable minus the handled effect. This constraint SHALL be resolved when the variable is instantiated with a concrete row.

#### Scenario: Subtracting handled effect from polymorphic row

- **GIVEN** a `handle Parallel! in body` expression where body has row `-[Parallel! | e]->`
- **WHEN** the typechecker computes the result row
- **THEN** the result row SHALL be `-[e]->` — `Parallel!` removed, `e` preserved

### Requirement: Effect Type Parameter Flag

`Type_Param` SHALL include an `is_effect: bool` field. Lowercase type parameters used in effect row position SHALL have `is_effect = true`. The typechecker SHALL use this flag to create effect row variables (not value variables) for effect parameters.

#### Scenario: Effect type parameter in generic function

- **GIVEN** a function `|f: |a| -[e]-> b|` where `e` appears in effect row position
- **WHEN** the typechecker processes the type parameter
- **THEN** `a` SHALL have `is_effect = false` and `e` SHALL have `is_effect = true`
