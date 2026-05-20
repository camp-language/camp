# Testing Design

## Goal

Comprehensive snapshot test suite validating Camp programs compile and run (or fail) as intended. Tests serve as TDD targets — failing tests define the desired behavior we need to implement.

## Directory Layout

```
tests/e2e/
  <category>/
    <test-name>.camp
    <test-name>.expected.toml
```

Categories reflect pipeline stages and feature domains. Each test is two files: Camp source + expected output.

## Snapshot Format

```toml
stdout = """
canonicalized /tmp/camp-e2e/execution/integer-literal/integer-literal.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/execution/integer-literal/integer-literal.camp
compiled /tmp/camp-e2e/execution/integer-literal/integer-literal.camp -> /tmp/camp-e2e/execution/integer-literal/integer-literal.wasm
"""
stderr = ""
exit = 0
wasm_exit = 42
wasm_stdout = ""
wasm_stderr = ""
```

Fields:
- `stdout`, `stderr` — compiler output (always present)
- `exit` — compiler exit code (always present)
- `wasm_exit` — wasmtime exit code (only for execution tests)
- `wasm_stdout`, `wasm_stderr` — wasmtime output (only for execution tests)

WASM fields are optional. Absent = skip WASM execution step.

## Test Runner

### Binary

Separate `camp-e2e` binary (not shipped to language users). Lives in `src/e2e/` as its own Odin package.

### Algorithm

1. Discover all `tests/e2e/<category>/<name>.camp` files
2. For each test, create isolated directory: `/tmp/camp-e2e/<category>/<name>/`
3. Copy `.camp` file into isolated directory (deterministic path for snapshots)
4. Run `camp build /tmp/camp-e2e/<category>/<name>/<name>.camp`, capture stdout/stderr/exit
5. If `expected.toml` has `wasm_exit`, run `wasmtime run <wasm-path>`, capture exit/stdout/stderr
6. Parse `expected.toml`, compare actual vs expected
7. Report: PASS, FAIL (with diff), or SKIP (if wasmtime unavailable and wasm fields present)

### Parallelism

Tests run concurrently with `runtime.cpu_count()` workers. Each test gets its own `/tmp/camp-e2e/<category>/<name>/` directory — no shared state.

### Flags

- `--update` — overwrite `expected.toml` files with actual output, print which files changed
- `--filter <pattern>` — run only tests matching a glob (e.g., `--filter "effects/*"`)
- `--verbose` — show actual output for passing tests too

### WASM Sandboxing

Execution tests use wasmtime's WASM sandbox for isolation — no chroot or containerization needed. The compiler writes to the temp directory, wasmtime runs the `.wasm`, and the runner captures exit codes and I/O.

### TOML Parsing

Minimal TOML parser supporting string (single-line and multi-line `"""`), integer, and boolean values. No arrays, tables, or inline tables.

## Justfile

```justfile
build:
    odin build src -out:camp

build-e2e:
    odin build src/e2e -out:camp-e2e

test-unit:
    odin test src

test-e2e: build build-e2e
    ./camp-e2e

test: test-unit test-e2e

update-snapshots: build build-e2e
    ./camp-e2e --update

test-filter pattern: build build-e2e
    ./camp-e2e --filter {{pattern}}
```

## Pre-commit Hook

```bash
#!/bin/sh
just test || {
    echo "Tests failed. Fix errors or run 'just update-snapshots' if changes are intentional."
    exit 1
}
```

Hook is opt-in (manually installed). Snapshots are committed to the repo so `git diff` after `--update` shows exactly what changed.

## Snapshot Update Workflow

1. Intentional behavior change: `just update-snapshots` → `git diff tests/` → review → `git add tests/ && git commit`
2. Unintentional failure: Fix the regression → re-run `just test`

## Test Categories

### execution/ — Programs that compile and run under wasmtime

| Test | Program | Validates |
|------|---------|-----------|
| integer-literal | `main! = \|\| -> I64 { 42 }` | Basic compilation, proc_exit |
| arithmetic | `main! = \|\| -> I64 { (6 + 3) * 7 - 1 }` | Binops, precedence |
| negation | `main! = \|\| -> I64 { 0 - 42 }` | Negative result via subtraction |
| let-binding | `main! = \|\| -> I64 { x = 42 y = x + 1 y }` | Let bindings, var refs |
| if-else-true | `main! = \|\| -> I64 { if true 1 else 0 }` | True branch |
| if-else-false | `main! = \|\| -> I64 { if false 1 else 0 }` | False branch |
| nested-if | `main! = \|\| -> I64 { if true if false 1 else 2 else 3 }` | Nested conditionals |
| function-call | `add = (a, b) -> I64 { a + b } main! = \|\| -> I64 { add(3, 4) }` | User functions |
| function-identity | `id = (x) -> I64 { x } main! = \|\| -> I64 { id(42) }` | Single-param function |
| block-expression | `main! = \|\| -> I64 { 1 2 3 }` | Block = last expr |
| not-operator | `main! = \|\| -> I64 { if not false 1 else 0 }` | `not` keyword |
| and-or | `main! = \|\| -> I64 { if true and false 1 else if true or false 2 else 0 }` | `and`/`or` |
| comparison-eq | `main! = \|\| -> I64 { if 1 == 1 1 else 0 }` | Equality |
| comparison-neq | `main! = \|\| -> I64 { if 1 != 2 1 else 0 }` | Inequality |
| comparison-lt | `main! = \|\| -> I64 { if 1 < 2 1 else 0 }` | Less than |
| recursive-call | `loop! = (n) -> I64 { if n == 0 0 else loop!(n - 1) } main! = \|\| -> I64 { loop!(5) }` | Self-recursive function |
| multi-decl | `x = 10 y = 20 main! = \|\| -> I64 { x + y }` | Multiple top-level decls |

### typechecking/ — Passes typecheck (may not codegen yet)

| Test | Program | Validates |
|------|---------|-----------|
| lambda-inference | `f = (x) { x }` | Level inference, generalization |
| let-polymorphism | `id = (x) { x } a = id(1) b = id(true)` | Poly instantiation |
| record-literal | `p = { x: 1, y: 2 }` | Record construction |
| record-nested | `p = { inner: { x: 1 } }` | Nested records |
| tag-construction | `x = Ok(42)` | Tag construction |
| tag-union-type | `x : Ok(I64) \| Error(String) = Ok(42)` | Tag union annotation |
| effect-declaration | `effect IO { println }` | Effect declaration |
| effectful-function | `greet! = (name) -> {IO} String { name }` | Effect annotation |
| handle-expression | `handle ... with { ... }` | Handler syntax |
| perform-call | `IO.println("hi")` | Perform syntax |
| function-type-annotation | `f = (x: I64) -> I64 { x + 1 }` | Explicit type annotations |
| type-annotation-matches | `x: I64 = 42` | Annotation agrees with inferred |
| bool-type | `b = true b2 = false` | Bool literal typing |
| string-type | `s = "hello"` | String literal typing |
| float-type | `f = 3.14` | Float literal typing |
| if-both-branches-same-type | `x = if true 1 else 2` | If branch unification |
| if-branch-mismatch | `x = if true 1 else "no"` | If branch type error |
| function-param-inference | `f = (x) { x + 1 }` | Param type inferred from usage |
| higher-order-function | `apply = (f, x) { f(x) }` | Function as parameter |
| return-type-annotation | `f = (x) -> I64 { x }` | Explicit return type |

### errors/ — Compiler rejects invalid programs

| Test | Program | Validates |
|------|---------|-----------|
| type-mismatch-binop | `x = 42 y = x + true` | Type error in binop |
| undefined-name | `x = y` | Undefined variable |
| unhandled-effect | Unhandled effect usage | Unhandled effect |
| effectful-naming-no-bang | Missing `!` on effectful function | Effectful naming |
| duplicate-definition | `x = 1 x = 2` | No-shadowing |
| arity-mismatch | `f = (x) -> I64 { x } f(1, 2)` | Wrong arity |
| syntax-error-incomplete | `x =` | Incomplete expression |
| syntax-error-bad-token | `x = @` | Invalid token |
| type-annotation-mismatch | `x: String = 42` | Annotation disagrees |
| apply-non-function | `x = 42 x(1)` | Calling a non-function |
| wrong-arity-annotation | Too few args | Arity error |
| if-non-bool-condition | `x = if 42 1 else 0` | Non-bool condition |
| missing-else | `x = if true 1` | If without else |
| recursive-type-error | `f = (x) { f(x) }` | Infinite type / occurs check |

### command-line/ — CLI behavior

| Test | Input | Validates |
|------|-------|-----------|
| no-arguments | (none) | Usage message, exit 1 |
| unknown-command | `camp foo` | Unknown command error |
| non-camp-file | `camp build test.txt` | Extension validation |
| file-not-found | `camp build /nonexistent.camp` | File not found |

### TDD Target Categories

**strings/**: string-literal, string-concat, string-interpolation, string-print

**records/**: record-construct, record-field-access, record-nested-access, record-modify, record-as-function-return, record-field-mismatch

**tag-unions/**: tag-construct-ok, tag-construct-error, tag-match-simple, tag-match-branches-exhaustive, tag-match-non-exhaustive, tag-match-nested, tag-wildcard, tag-type-mismatch

**pattern-matching/**: match-int-literal, match-bool, match-with-guard, match-or-pattern, match-variable-bind, match-record-pattern, match-string-literal

**effects/**: effect-declare-and-handle, effect-perform-return-value, effect-multiple-operations, effect-deep-handler, effect-shallow-handler, effect-multiple-effects, effect-unhandled, effect-handler-resume-twice

**closures/**: closure-free-var, closure-nested, closure-mutation-simulated, higher-order-map, higher-order-filter, function-composition, partial-application, recursive-closure

**generics/**: identity-function, generic-pair, generic-list-map, generic-function-compose, generic-with-constraint

## TDD Workflow

1. Write failing test with desired `expected.toml`
2. Run `just test-e2e` — see the test fail
3. Implement the feature
4. Run `just test-e2e` — see the test pass
5. Commit both test and implementation

Failing tests are committed alongside passing ones. The runner reports them as FAIL — they are the to-do list made visible.
