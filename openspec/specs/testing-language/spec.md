# Testing Language Features — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's testing language features: the `expect` assertion expression, the `test` named-test-block declaration, the `todo` placeholder operator, and the `camp test` command that discovers and executes both named tests and doctests.

## Requirements

### Requirement: expect Expression

The `expect` keyword SHALL accept a boolean expression. If the expression evaluates to `False`, the program SHALL fail. In production mode, `expect` SHALL be compiled to a no-op.

#### Scenario: expect with true expression

- **GIVEN** an expression `expect 1 + 1 == 2`
- **WHEN** evaluated in debug or test mode
- **THEN** the expression `1 + 1 == 2` SHALL evaluate to `True` and the program SHALL continue

#### Scenario: expect with false expression

- **GIVEN** an expression `expect 1 + 1 == 3`
- **WHEN** evaluated in debug or test mode
- **THEN** the expression `1 + 1 == 3` SHALL evaluate to `False` and the program SHALL fail with an error

#### Scenario: expect in production mode

- **GIVEN** an expression `expect some_condition`
- **WHEN** compiled in production mode
- **THEN** the `expect` and its expression SHALL be compiled to a no-op — the expression SHALL NOT be evaluated at runtime

#### Scenario: expect effect row

- **GIVEN** an `expect` expression whose boolean sub-expression has effects (e.g., `expect Console.println!("test") == {}`)
- **WHEN** the effect row is computed for the containing function
- **THEN** the effect row SHALL include the sub-expression's effects in debug/test mode; in production mode, the `expect` is removed entirely and its effects are not present

### Requirement: test Named Test Block

The `test` keyword SHALL define a named test block. Test blocks SHALL be discovered and executed by `camp test`.

#### Scenario: Named test block

- **GIVEN** a declaration `test "addition works" { expect 1 + 1 == 2 }`
- **WHEN** `camp test` is run
- **THEN** the test block SHALL be discovered, compiled, and executed; if the `expect` fails, the test SHALL fail with the name "addition works"

#### Scenario: Test block identification

- **GIVEN** a test block `test "addition works" { ... }` in `Math.camp` at line 10
- **WHEN** the test fails
- **THEN** the error message SHALL include the test name "addition works" and the file path `Math.camp:10`

#### Scenario: Test block with setup code

- **GIVEN** a test block containing setup code and multiple expects
- **WHEN** `camp test` is run
- **THEN** all code in the block SHALL execute; if any `expect` fails, the entire test block SHALL fail

#### Scenario: Test blocks in production mode

- **GIVEN** a file containing `test "name" { ... }` declarations
- **WHEN** compiled in production mode
- **THEN** test blocks SHALL be excluded from the compiled output entirely

### Requirement: todo Placeholder Operator

The `todo` keyword SHALL be a placeholder expression that compiles in debug mode and causes a compilation error in production mode. It SHALL have type `forall a. a` and an empty effect row.

#### Scenario: todo as return value

- **GIVEN** a function `f = || -> Int { todo }`
- **WHEN** compiled in debug mode
- **THEN** the function SHALL compile; if called at runtime, it SHALL panic with "not yet implemented"

#### Scenario: todo with message

- **GIVEN** a function `f = || -> Int { todo("implement sorting") }`
- **WHEN** called at runtime in debug mode
- **THEN** it SHALL panic with the message "implement sorting"

#### Scenario: todo in production mode

- **GIVEN** a function `f = || -> Int { todo }`
- **WHEN** compiled in production mode
- **THEN** the compiler SHALL produce an error — `todo` is not allowed in production builds

#### Scenario: todo type is polymorphic

- **GIVEN** a function `f = || -> Str { todo }` and another `g = || -> Bool { todo }`
- **WHEN** compiled in debug mode
- **THEN** both SHALL type-check — `todo` unifies with any expected type

#### Scenario: todo in function argument position

- **GIVEN** an expression `some_function(todo, 42)`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the expected parameter type

#### Scenario: todo in record field position

- **GIVEN** an expression `{ name: todo, age: 30 }`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the expected type of the `name` field

#### Scenario: todo in match arm position

- **GIVEN** a match expression with an arm `_ => todo`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the match result type

#### Scenario: todo effect row is empty

- **GIVEN** a function `compute = || -> Int { todo }`
- **WHEN** the compiler infers the effect row
- **THEN** the effect row SHALL be empty — `compute` is pure and does NOT require `!` in its name

#### Scenario: todo in effectful function

- **GIVEN** a function `compute! = || -[Console!]-> Int { Console.println!("debug"); todo }`
- **WHEN** the compiler infers the effect row
- **THEN** the effect row SHALL include `Console!` from the `println!` call — `todo` does not add effects

### Requirement: Unified Test Command

`camp test` SHALL discover and execute both doctests (code blocks in doc comments) and named test blocks.

#### Scenario: Running all tests

- **GIVEN** a project with doc comments containing code blocks and files with `test` declarations
- **WHEN** `camp test` is run
- **THEN** both doctests and named test blocks SHALL be discovered, compiled, and executed

#### Scenario: Test summary

- **GIVEN** `camp test` completes
- **WHEN** results are reported
- **THEN** the runner SHALL display a summary showing the number of doctests and named tests that passed, failed, or were skipped
