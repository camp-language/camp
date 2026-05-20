# End-to-End Snapshot Testing Design

## Goal

Comprehensive snapshot test suite that validates Camp programs compile and run (or fail) as intended. Tests serve as TDD targets — failing tests define the desired behavior we need to implement.

## Directory Layout

```
tests/e2e/
  <category>/
    <test-name>.camp
    <test-name>.expected.toml
```

Categories reflect pipeline stages and feature domains. Each test is two files: the Camp source and the expected output.

## Snapshot Format

`<test-name>.expected.toml`:

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
3. Copy `.camp` file into the isolated directory (deterministic path for snapshots)
4. Run `camp build /tmp/camp-e2e/<category>/<name>/<name>.camp`, capture stdout/stderr/exit
5. If `expected.toml` has `wasm_exit`, run `wasmtime run <wasm-path>`, capture exit/stdout/stderr
6. Parse `expected.toml`, compare actual vs expected
7. Report: PASS, FAIL (with diff), or SKIP (if wasmtime unavailable and wasm fields present)

### Parallelism

Tests run concurrently with `runtime.cpu_count()` workers. Each test gets its own `/tmp/camp-e2e/<category>/<name>/` directory — no shared state between tests.

### Flags

- `--update` — overwrite `expected.toml` files with actual output, print which files changed
- `--filter <pattern>` — run only tests matching a glob (e.g., `--filter "effects/*"`)
- `--verbose` — show actual output for passing tests too

### WASM Sandboxing

Execution tests leverage wasmtime's WASM sandbox for isolation — no need for chroot or containerization. The compiler writes to the temp directory, wasmtime runs the resulting `.wasm`, and the runner captures exit codes and I/O.

### TOML Parsing

Minimal TOML parser supporting string (single-line and multi-line `"""`), integer, and boolean values. No arrays, tables, or inline tables needed.

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

Hook is opt-in — must be manually installed. Snapshots are committed to the repo so `git diff` after `--update` shows exactly what changed.

## Snapshot Update Workflow

1. Intentional behavior change (e.g., improved error message):
   - `just update-snapshots`
   - `git diff tests/` — review all changes
   - `git add tests/ && git commit`

2. Unintentional failure:
   - Fix the regression
   - Re-run `just test` to confirm snapshots pass again

## Test Categories

### execution/ — Programs that compile and run under wasmtime (currently working)

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
| let-polymorphism | `id = (x) { x } a = id(1) b = id(true)` | Poly instantiation at different types |
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
| unhandled-effect | `effect IO { println } main! = \|\| -> I64 { IO.println("hi") 0 }` | Unhandled effect |
| effectful-naming-no-bang | `effect IO { println } main = \|\| -> {IO} I64 { 0 }` | Missing `!` |
| duplicate-definition | `x = 1 x = 2` | No-shadowing |
| arity-mismatch | `f = (x) -> I64 { x } f(1, 2)` | Wrong arity |
| syntax-error-incomplete | `x =` | Incomplete expression |
| syntax-error-bad-token | `x = @` | Invalid token |
| type-annotation-mismatch | `x: String = 42` | Annotation disagrees |
| apply-non-function | `x = 42 x(1)` | Calling a non-function |
| wrong-arity-annotation | `f = (x, y) -> I64 { x + y } f(1)` | Too few args |
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

### strings/ — String operations (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| string-literal | `main! = \|\| -> I64 { "hello" 0 }` | String in data section |
| string-concat | `main! = \|\| -> I64 { "hello" + " world" 0 }` | Concatenation |
| string-interpolation | `main! = \|\| -> I64 { x = 42 "{x} is the answer" 0 }` | Interpolation |
| string-print | `effect IO { println } main! = \|\| -> {IO} I64 { IO.println("hello") 0 }` | Print to stdout |

### records/ — Record construction + access (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| record-construct | `main! = \|\| -> I64 { p = { x: 1, y: 2 } 0 }` | Record construction |
| record-field-access | `main! = \|\| -> I64 { p = { x: 42, y: 0 } p.x }` | Field access returns value |
| record-nested-access | `main! = \|\| -> I64 { r = { inner: { val: 99 } } r.inner.val }` | Chained access |
| record-modify | `main! = \|\| -> I64 { p = { x: 1, y: 2 } p2 = { x: 10 ..p } p2.x }` | Record update |
| record-as-function-return | `mk = (a) -> { x: I64 } { { x: a } } main! = \|\| -> I64 { mk(42).x }` | Record from function |
| record-field-mismatch | `p = { x: 1 } y = p.y` | Access nonexistent field (error) |

### tag-unions/ — Tag construction + matching (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| tag-construct-ok | `main! = \|\| -> I64 { x = Ok(42) 0 }` | Tag construction |
| tag-construct-error | `main! = \|\| -> I64 { x = Error("fail") 0 }` | Error variant |
| tag-match-simple | `main! = \|\| -> I64 { x = Ok(42) match x { Ok(v) -> v \| Error(e) -> 0 } }` | Match on tag |
| tag-match-branches-exhaustive | `x = Ok(1) \| Error(0) match x { ... }` | Exhaustive matching |
| tag-match-non-exhaustive | `x = Ok(1) \| Error(0) match x { Ok(v) -> v }` | Missing branch (error) |
| tag-match-nested | `x = Ok(Ok(42)) match x { Ok(Ok(v)) -> v \| _ -> 0 }` | Nested pattern |
| tag-wildcard | `match x { Ok(v) -> v \| _ -> 0 }` | Wildcard pattern |
| tag-type-mismatch | `x = Ok(42) match x { Ok(v) -> v \| Error(e) -> e + 1 }` | Branch type mismatch (error) |

### pattern-matching/ — General match expressions (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| match-int-literal | `main! = \|\| -> I64 { match 42 { 0 -> 1 \| 1 -> 2 \| _ -> 99 } }` | Match on int literal |
| match-bool | `main! = \|\| -> I64 { match true { true -> 1 \| false -> 0 } }` | Match on bool |
| match-with-guard | `match x { n if n > 0 -> 1 \| _ -> 0 }` | Guard clauses |
| match-or-pattern | `match x { 1 \| 2 \| 3 -> "small" \| _ -> "big" }` | Or patterns |
| match-variable-bind | `match x { Ok(v) -> v }` | Variable binding in pattern |
| match-record-pattern | `match { x: 1, y: 2 } { { x: a, y: b } -> a + b }` | Record destructuring |
| match-string-literal | `match "hello" { "hello" -> 1 \| _ -> 0 }` | String pattern |

### effects/ — Algebraic effect handlers (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| effect-declare-and-handle | `effect IO { println } handle IO.println("hi") with { IO.println(s) -> resume(()) }` | Basic handler |
| effect-perform-return-value | `effect Ask { read } handle Ask.read() with { Ask.read() -> resume(42) }` | Perform returns a value |
| effect-multiple-operations | `effect IO { println, readln }` | Effect with multiple ops |
| effect-deep-handler | `handle expr with { ... }` | Deep handler (resume continues) |
| effect-shallow-handler | `intercept ... with { ... }` | Shallow handler (intercept keyword) |
| effect-multiple-effects | `effect IO { println } effect State { get, put } handle ... with { ... }` | Multiple effects |
| effect-unhandled | `effect IO { println } IO.println("hi")` | Unhandled effect (error outside handle) |
| effect-handler-resume-twice | `handle ... with { Op(x) -> resume(1) resume(2) }` | Resume called twice |

### closures/ — Closures and higher-order functions (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| closure-free-var | `main! = \|\| -> I64 { x = 10 f = () -> I64 { x } f() }` | Captures free variable |
| closure-nested | `main! = \|\| -> I64 { x = 1 f = () -> I64 { g = () -> I64 { x } g() } f() }` | Nested closure |
| closure-mutation-simulated | `main! = \|\| -> I64 { x = { val: 0 } f = () -> I64 { x.val } f() }` | Closure over record |
| higher-order-map | `map = (f, xs) -> List(I64) { ... }` | Map with function arg |
| higher-order-filter | `filter = (pred, xs) -> List(I64) { ... }` | Filter with predicate |
| function-composition | `compose = (f, g) -> (I64) -> I64 { (x) -> I64 { f(g(x)) } }` | Compose two functions |
| partial-application | `add = (a, b) -> I64 { a + b } inc = add(1, _)` | Partial application |
| recursive-closure | `f! = () -> I64 { f!() }` | Self-referential closure |

### generics/ — Polymorphism and type abstraction (TDD target)

| Test | Program | Validates |
|------|---------|-----------|
| identity-function | `id = (x) { x } a = id(1) b = id(true)` | Let-polymorphism |
| generic-pair | `pair = (a, b) { { fst: a, snd: b } }` | Generic data structure |
| generic-list-map | `map = (f, xs) { match xs { Nil -> Nil \| Cons(h, t) -> Cons(f(h), map(f, t)) } }` | Recursive generic |
| generic-function-compose | `compose = (f, g, x) { f(g(x)) }` | Generic composition |
| generic-with-constraint | `f = (x) { x + 1 }` | Inferred numeric constraint |

## TDD Workflow

1. Write failing test in appropriate category with desired `expected.toml`
2. Run `just test-e2e` — see the test fail
3. Implement the feature
4. Run `just test-e2e` — see the test pass
5. Commit both test and implementation

Failing tests are committed alongside passing ones. The runner reports them as FAIL — they are the to-do list made visible.
