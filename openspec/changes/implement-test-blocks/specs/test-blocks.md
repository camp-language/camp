# Specs: Implement Test Blocks & Stdlib Test Coverage

## expect Expression (Intrinsic)

### First-Class Expect Expression
- Given an expression `expect condition`
- When compiled in debug or test mode
- Then the condition SHALL be evaluated at runtime
- And if the condition is `True`, execution SHALL continue
- And if the condition is `False`, execution SHALL terminate with exit code 1
- And the failure message SHALL include the condition source text

### Expect with Doc Comment Message
- Given a `///` doc comment on the line before `expect condition`
- When the expect fails
- Then the failure message SHALL show the doc comment text instead of the condition source text

### Expect in Production Mode
- Given an expression `expect condition`
- When compiled in production mode
- Then the `expect` and its sub-expression SHALL be compiled to a no-op
- And the condition SHALL NOT be evaluated at runtime
- And the sub-expression's effects SHALL NOT appear in the effect row

### Expect Effect Row
- Given an `expect` expression whose sub-expression has effects (e.g., `expect Console.println!("hi") == ()`)
- When compiled in debug or test mode
- Then the effect row SHALL include the sub-expression's effects
- When compiled in production mode
- Then the `expect` is removed entirely and contributes no effects

### Expect Type Constraint
- Given an `expect` expression
- When type-checked in any mode
- Then the condition SHALL unify with `Bool`
- And the `message` field, if present, SHALL unify with `Str`

## test Named Test Block

### Test Block Parsing
- Given a declaration `test "name" { body }`
- When parsed
- Then the parser SHALL consume `test`, string literal, `{`, block body, and `}` exactly once
- And the parser SHALL NOT consume an additional `}` after the block

### Test Block Execution
- Given a file with `test "name" { body }` declarations
- When `camp test <file>` is run
- Then each test block SHALL be compiled as a synthetic `main!` function with the test body
- And each SHALL be executed via wasmtime
- And exit code 0 SHALL mean PASS; nonzero SHALL mean FAIL

### Top-Level expect as Synthetic Test
- Given a top-level `expect condition` declaration
- When `camp test <file>` is run
- Then it SHALL be treated as a named test with name `"expect at line {N}"`
- And the condition SHALL be compiled as an `Expr_Expect` intrinsic
- And pass/fail SHALL be determined the same way as named test blocks

### Test Block Exclusion from Production
- Given a file containing `test "name" { ... }` declarations
- When compiled in production mode (via `camp build`)
- Then test blocks SHALL be excluded from the compiled output entirely

## Doc Comment Attachment

### Doc Comment Accumulation
- Given one or more `///` doc comment lines before a declaration
- When the parser reaches the declaration
- Then the accumulated doc comment text SHALL be attached to the declaration
- And the pending doc comment buffer SHALL be cleared after attachment

### Doc Comment on expect
- Given a `///` doc comment immediately before `expect condition`
- When the expect fails
- Then the failure message SHALL be the doc comment text

### Doc Comment on Other Declarations
- Given a `///` doc comment before a `const`, `type`, `effect`, or `trait` declaration
- When the parser processes the declaration
- Then the doc comment SHALL be attached to the declaration for future use (documentation generation, etc.)

## Compilation Modes

### Build Mode Enum
- `Build_Mode :: enum { Debug, Test, Production }`
- `camp build` SHALL default to Production mode
- `camp test` SHALL use Test mode
- `camp check` SHALL use Debug mode
- `camp build --debug` SHALL use Debug mode

### Mode-Dependent expect Behavior
- Given debug or test mode, `expect` SHALL produce a runtime check
- Given production mode, `expect` SHALL produce no code (no-op)

### Mode-Dependent todo Behavior
- Given debug or test mode, `todo` SHALL compile to a runtime panic
- Given production mode, `todo` SHALL produce a compilation error

## Stdlib Test Coverage

### Pure Camp Module Coverage
- Given a pure Camp stdlib module (Result, Bool, Iter, List, Num.I64, etc.)
- When test blocks are written in the module file
- Then every public function SHALL have at least one `test` block
- And each test block SHALL contain at least one `expect` assertion
- And test blocks SHALL cover: happy path, error/boundary cases, and type-correctness

### Intrinsic Module Coverage
- Given an intrinsic stdlib module (Str, Map, Set, Bytes, Path, Duration, Fmt)
- When test coverage is needed
- Then E2E execution tests SHALL be written in `tests/e2e/stdlib/<module>/`
- And each public function SHALL be exercised by at least one E2E test
- And `wasm_stdout` SHALL be used to verify output

### Trait/Effect Declaration Coverage
- Given a trait or effect declaration module (Eq, Ord, Console!, etc.)
- When test coverage is needed
- Then E2E typechecking tests SHALL verify that programs using the trait/effect compile correctly
- And negative tests SHALL verify that misuse produces type errors
