## MODIFIED Requirements

### Requirement: Lexer tokenization of effectful identifiers
The lexer SHALL append trailing `!` characters (up to 2) to identifier tokens when the `!` immediately follows the identifier body. This applies to both lowercase identifiers and UpperCamelCase identifiers.

#### Scenario: Single-bang identifier
- **GIVEN** source text `main!`
- **WHEN** the lexer tokenizes it
- **THEN** the result SHALL be a single `Identifier` token with text `"main!"`

#### Scenario: Double-bang identifier
- **GIVEN** source text `main!!`
- **WHEN** the lexer tokenizes it
- **THEN** the result SHALL be a single `Identifier` token with text `"main!!"`

#### Scenario: Effect type name with bang
- **GIVEN** source text `IO!`
- **WHEN** the lexer tokenizes it
- **THEN** the result SHALL be a single `Upper_Id` token with text `"IO!"`

#### Scenario: Bang-equal operator unaffected
- **GIVEN** source text `!=`
- **WHEN** the lexer tokenizes it
- **THEN** the result SHALL be a `Bang_Eq` token (not an identifier followed by equals)

#### Scenario: Standalone bang in non-identifier context
- **GIVEN** source text `!x` (where `!` is not preceded by an identifier)
- **WHEN** the lexer tokenizes it
- **THEN** the `!` SHALL produce a `Bang` token

### Requirement: Unary plus prefix operator
The parser SHALL support unary `+` as a prefix operator with the same binding power as unary `-`.

#### Scenario: Positive float literal
- **GIVEN** source text `+3.14`
- **WHEN** the parser processes it
- **THEN** it SHALL parse as a `PrefixOp` with operator `+` and operand `3.14`

#### Scenario: Positive integer literal
- **GIVEN** source text `+42`
- **WHEN** the parser processes it
- **THEN** it SHALL parse as a `PrefixOp` with operator `+` and operand `42`

## ADDED Requirements

### Requirement: Trait method name resolution by convention
When verifying trait conformance for a nominal type `T` declared as `is Trait`, the compiler SHALL look for a standalone function named `T_methodname` in the same module for each method `methodname` required by `Trait`.

#### Scenario: Method found with correct signature
- **GIVEN** a nominal type `@UserId is Eq : U64` and a function `UserId_eq` in the same module with type `|UserId, UserId| -> Bool`
- **WHEN** the compiler verifies conformance
- **THEN** the `eq` method requirement SHALL be satisfied

#### Scenario: Method missing
- **GIVEN** a nominal type `@UserId is Eq : U64` with no `UserId_eq` function in the module
- **WHEN** the compiler verifies conformance
- **THEN** the compiler SHALL produce a "MISSING TRAIT METHOD" error

#### Scenario: Method signature mismatch
- **GIVEN** a nominal type `@UserId is Eq : U64` and a function `UserId_eq` with type `|UserId, UserId| -> I64`
- **WHEN** the compiler verifies conformance
- **THEN** the compiler SHALL produce a "TRAIT METHOD SIGNATURE MISMATCH" error
