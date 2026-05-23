## MODIFIED Requirements

### Requirement: Effect row syntax uses bracket-arrow notation
Effect rows in type signatures SHALL use `-[Eff1 | Eff2]->` syntax. The `->{ Eff1, Eff2 }` syntax is NOT valid. An elided (empty) effect row is written as a plain `->` with no brackets.

#### Scenario: Single effect in type signature
- **WHEN** a function signature includes one effect
- **THEN** it uses `-[Console!]->` notation, e.g., `|Str| -[Console!]-> {}`

#### Scenario: Multiple effects in type signature
- **WHEN** a function signature includes multiple effects
- **THEN** they are pipe-separated inside brackets, e.g., `-[Console! | File!]->`

#### Scenario: Pure function type signature
- **WHEN** a function has no effects
- **THEN** the effect row is elided, e.g., `|I64, I64| -> I64`

### Requirement: No effect keyword
There SHALL be no `effect` keyword. Effect types are defined using the `:` type alias syntax with `!` suffix on the name.

#### Scenario: Effect type declaration
- **WHEN** declaring the `Console!` effect
- **THEN** the syntax is `Console! : { println!: |Str| -[Console!]-> {}, ... }`, not `effect Console { ... }`

### Requirement: Effect names have bang suffix
All effect type names SHALL end with `!`. Effect rows SHALL reference effect names with their `!` suffix.

#### Scenario: Effect name in type signature
- **WHEN** writing a function that uses the Console effect
- **THEN** the effect row is `-[Console!]->`, not `-[Console]->`
