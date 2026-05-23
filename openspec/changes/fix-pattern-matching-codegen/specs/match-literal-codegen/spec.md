## ADDED Requirements

### Requirement: Bool Match Codegen
The compiler SHALL generate correct WASM for match expressions on Bool values, using nested `if/else` blocks with `i32.eq` comparison against 0 or 1.

#### Scenario: Match true returns first arm
- **GIVEN** Camp source `match true { true => 1 | false => 0 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 1

#### Scenario: Match false returns second arm
- **GIVEN** Camp source `match false { true => 1 | false => 0 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 0

#### Scenario: Bool match with wildcard
- **GIVEN** Camp source `match true { false => 0 | _ => 1 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 1

### Requirement: Int Match Codegen
The compiler SHALL generate correct WASM for match expressions on Int (I64) values, using nested `if/else` blocks with `i64.eq` comparison.

#### Scenario: Match integer literal
- **GIVEN** Camp source `match 42 { 1 => 0 | 42 => 1 | _ => 2 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 1

#### Scenario: Match integer wildcard fallback
- **GIVEN** Camp source `match 99 { 1 => 0 | 42 => 1 | _ => 2 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 2

### Requirement: String Match Codegen
The compiler SHALL generate correct WASM for match expressions on String values, using nested `if/else` blocks with `camp_str_eq` runtime call for comparison.

#### Scenario: Match string literal
- **GIVEN** Camp source `match "hello" { "world" => 0 | "hello" => 1 | _ => 2 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 1

### Requirement: Tag Union Match Codegen
The compiler SHALL generate correct WASM for match expressions on tag union values using `brtable` dispatch, where each tag constructor stores its positional index as the tag discriminant byte.

#### Scenario: Match Ok tag extracts payload
- **GIVEN** Camp source `match Ok(42) { Ok(v) => v | Error(e) => 0 }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 42

#### Scenario: Match Error tag extracts payload
- **GIVEN** Camp source `match Error(7) { Ok(v) => v | Error(e) => e }`
- **WHEN** compiled and executed
- **THEN** the program SHALL exit with code 7
