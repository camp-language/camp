# Domain Specification: Testing

## Purpose

Validate Camp programs compile and run (or fail) as intended through a comprehensive snapshot test suite, serving as TDD targets where failing tests define desired behavior.

## Requirements

### Requirement: Snapshot Test Format

Each test SHALL consist of a Camp source file and an expected-output TOML file.

#### Scenario: Execution test

- Given a Camp source file that compiles and runs
- When the test runner processes it
- Then the `expected.toml` SHALL contain `stdout`, `stderr`, `exit`, `wasm_exit`, `wasm_stdout`, and `wasm_stderr` fields

#### Scenario: Type-checking test

- Given a Camp source file that passes typechecking but may not codegen
- When the test runner processes it
- Then the `expected.toml` SHALL contain `stdout`, `stderr`, and `exit` fields without WASM fields

#### Scenario: Error test

- Given a Camp source file that the compiler rejects
- When the test runner processes it
- Then the `expected.toml` SHALL contain `stdout`, `stderr`, and `exit` (nonzero) fields

#### Scenario: CLI test

- Given a CLI invocation with no Camp source file
- When the test runner processes it
- Then the `expected.toml` SHALL contain `stdout`, `stderr`, and `exit` fields

### Requirement: Test Runner Algorithm

The runner SHALL discover, execute, and compare test results.

#### Scenario: Test discovery

- Given the `tests/e2e/` directory contains categorized test directories
- When the runner starts
- Then it SHALL discover all `<category>/<name>.camp` files

#### Scenario: Isolated execution

- Given a test is discovered
- When the runner executes it
- Then it SHALL create an isolated directory `/tmp/camp-e2e/<category>/<name>/`, copy the source file there, and run `camp build` capturing stdout, stderr, and exit code

#### Scenario: WASM execution

- Given a test's `expected.toml` has `wasm_exit`
- When compilation succeeds
- Then the runner SHALL execute the resulting `.wasm` with wasmtime and capture exit, stdout, and stderr

#### Scenario: WASM skip

- Given a test's `expected.toml` has WASM fields
- When wasmtime is unavailable
- Then the runner SHALL report SKIP

#### Scenario: Comparison and reporting

- Given actual output is captured
- When compared to `expected.toml`
- Then the runner SHALL report PASS (match), FAIL with diff (mismatch), or SKIP

### Requirement: Parallelism

Tests SHALL run concurrently with no shared state.

#### Scenario: Concurrent execution

- Given multiple tests are discovered
- When the runner executes them
- Then it SHALL use `runtime.cpu_count()` workers, each test in its own isolated directory

### Requirement: Update Mode

The runner SHALL support overwriting expected output files.

#### Scenario: Update snapshots

- Given the `--update` flag is passed
- When the runner executes tests
- Then it SHALL overwrite `expected.toml` files with actual output and print which files changed

### Requirement: Filter Mode

The runner SHALL support running a subset of tests.

#### Scenario: Filter by pattern

- Given the `--filter` flag with a glob pattern
- When the runner discovers tests
- Then it SHALL run only tests matching the pattern (e.g., `--filter "effects/*"`)

### Requirement: Verbose Mode

The runner SHALL support showing output for passing tests.

#### Scenario: Verbose output

- Given the `--verbose` flag is passed
- When a test passes
- Then the runner SHALL display the actual output

### Requirement: Test Categories

Tests SHALL be organized into categories reflecting pipeline stages and feature domains.

#### Scenario: Execution category

- Given programs that compile and run under wasmtime
- Then tests SHALL validate compilation, WASM exit codes, and I/O

#### Scenario: Typechecking category

- Given programs that pass typechecking (may not codegen yet)
- Then tests SHALL validate compiler acceptance without WASM execution

#### Scenario: Errors category

- Given invalid programs the compiler rejects
- Then tests SHALL validate error output and nonzero exit codes

#### Scenario: Command-line category

- Given CLI invocations with various arguments
- Then tests SHALL validate usage messages, error messages, and exit codes

#### Scenario: TDD target categories

- Given features not yet implemented (strings, records, tag-unions, pattern-matching, effects, closures, generics)
- Then failing tests SHALL be committed as TDD targets

### Requirement: TOML Parsing

The runner SHALL parse minimal TOML for snapshot files.

#### Scenario: Supported TOML types

- Given a `expected.toml` file
- Then the parser SHALL support string values (single-line and multi-line `"""`), integer values, and boolean values

#### Scenario: Unsupported TOML features

- Given a `expected.toml` uses arrays, tables, or inline tables
- Then the parser is not required to support them

### Requirement: Snapshot Determinism

Snapshots SHALL produce deterministic output across environments.

#### Scenario: Cross-environment consistency

- Given the same Camp source and compiler version
- When snapshots are generated on different machines
- Then the `expected.toml` content SHALL be identical (paths use deterministic temp directories)

### Requirement: Idempotent Snapshot Update

Running `--update` on already-passing snapshots SHALL produce no changes.

#### Scenario: Already-formatted snapshot

- Given a test's `expected.toml` matches actual output
- When `--update` is run
- Then the `expected.toml` file SHALL remain unchanged

For the complete syntax reference, see `docs/syntax-recipe.md`.
