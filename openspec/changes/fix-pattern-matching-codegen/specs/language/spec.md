## ADDED Requirements

### Requirement: Bool Exhaustiveness Checking
The compiler SHALL check that match expressions on Bool values cover both `true` and `false`, or include a wildcard/variable pattern.

#### Scenario: Missing false arm rejected
- **WHEN** Camp source contains `match x { true => 1 }` where `x : Bool`
- **THEN** the compiler SHALL report a non-exhaustive match error listing `false` as missing

#### Scenario: Both arms present accepted
- **WHEN** Camp source contains `match x { true => 1 | false => 0 }`
- **THEN** the compiler SHALL accept the match without error

### Requirement: Redundant Pattern Warning
The compiler SHALL warn when a match arm is unreachable because all possible values are already covered by earlier arms.

#### Scenario: Redundant wildcard warning
- **WHEN** Camp source contains `match x { true => 1 | false => 0 | _ => 99 }` where `x : Bool`
- **THEN** the compiler SHALL produce a warning that the wildcard arm is unreachable

## MODIFIED Requirements

### Requirement: Pattern Matching Exhaustiveness
Pattern matching SHALL require exhaustive coverage; the wildcard `_` SHALL match any remaining variants.

#### Scenario: Exhaustive match on closed union
- **GIVEN** a closed tag union `[Ok(a) | Err(e)]` and a match with cases for `Ok` and `Err`
- **WHEN** the compiler checks exhaustiveness
- **THEN** the match SHALL be accepted

#### Scenario: Non-exhaustive match rejected
- **GIVEN** a closed tag union `[Ok(a) | Err(e)]` and a match with only an `Ok` case
- **WHEN** the compiler checks exhaustiveness
- **THEN** it SHALL produce an error

#### Scenario: Wildcard catch-all
- **GIVEN** a match with explicit cases for some variants and `_ =>` as a final case
- **WHEN** the compiler checks exhaustiveness
- **THEN** the match SHALL be accepted

#### Scenario: Redundant wildcard warning
- **GIVEN** a match on a closed union where all variants are already covered explicitly and `_ =>` is present
- **WHEN** the compiler checks exhaustiveness
- **THEN** it SHALL produce a warning that the wildcard is unreachable

#### Scenario: Open union requires at least one handler
- **GIVEN** an open tag union type and a match expression
- **WHEN** the match has at least one case or `_ =>`
- **THEN** the match SHALL be accepted

#### Scenario: Nested pattern exhaustiveness
- **GIVEN** a match arm with a tag pattern containing a nested pattern in its payload
- **WHEN** the compiler checks exhaustiveness
- **THEN** it SHALL recurse into nested patterns to track covered tags
