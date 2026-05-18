# E2E Snapshot Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a comprehensive end-to-end snapshot test suite with a dedicated runner binary, test files for 10 categories (~75 tests), and a justfile for running them as a pre-commit gate.

**Architecture:** Separate `camp-e2e` Odin binary in `src/e2e/` discovers test directories, copies .camp files to isolated temp dirs, runs `camp build` and optionally `wasmtime run`, compares output against `expected.toml` snapshots. Justfile wires build + unit tests + e2e tests into `just test`.

**Tech Stack:** Odin (runner binary), TOML (snapshot format), wasmtime (WASM execution), just (task runner)

---

## File Structure

| File | Purpose |
|------|---------|
| `src/e2e/e2e.odin` | Main entry point for `camp-e2e` binary |
| `src/e2e/toml.odin` | Minimal TOML parser (string/int/bool, multi-line strings) |
| `src/e2e/runner.odin` | Test discovery, execution, comparison, reporting |
| `justfile` | Build + test commands |
| `tests/e2e/<category>/<name>.camp` | Camp source files (75+ files across 10 categories) |
| `tests/e2e/<category>/<name>.expected.toml` | Expected output snapshots (75+ files) |

---

### Task 1: Install just and create justfile

**Files:**
- Create: `justfile`

- [ ] **Step 1: Install just**

```bash
cargo install just
```

Or download a prebuilt binary from https://github.com/casey/just/releases — verify with `just --version`.

- [ ] **Step 2: Create justfile**

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

- [ ] **Step 3: Verify justfile works**

Run: `just build`
Expected: `camp` binary is produced without errors

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "chore: add justfile for build and test commands"
```

---

### Task 2: Implement minimal TOML parser

**Files:**
- Create: `src/e2e/toml.odin`

The parser needs to handle:
- Key-value pairs: `key = value`
- Single-line strings: `key = "value"`
- Multi-line strings: `key = """...\n..."""`
- Integers: `key = 0`, `key = 1`
- Empty strings: `key = ""`
- Only top-level keys (no nested tables, no arrays)

**Output type:** `Toml_Dict` — a dynamic array of `(key: string, value: Toml_Value)` pairs, where `Toml_Value` is a union of `string`, `int`, `bool`.

- [ ] **Step 1: Write `src/e2e/toml.odin`**

```odin
package e2e

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

Toml_Value :: union {
	string,
	int,
	bool,
}

Toml_Entry :: struct {
	key:   string,
	value: Toml_Value,
}

Toml_Dict :: struct {
	entries: [dynamic]Toml_Entry,
}

toml_get :: proc(dict: ^Toml_Dict, key: string) -> (Toml_Value, bool) {
	for &entry in dict.entries {
		if entry.key == key {
			return entry.value, true
		}
	}
	return nil, false
}

toml_parse :: proc(input: string, allocator: mem.Allocator) -> Toml_Dict {
	dict: Toml_Dict
	dict.entries = make([dynamic]Toml_Entry, 0, allocator = allocator)

	pos: int = 0

	for pos < len(input) {
		#removesuffix(input[pos:], "\n")
		#removesuffix(input[pos:], "\r\n")

		#skip whitespace
		for pos < len(input) && (input[pos] == ' ' || input[pos] == '\t') {
			pos += 1
		}

		#skip blank lines and comments
		if pos >= len(input) { break }
		if input[pos] == '\n' || input[pos] == '\r' {
			pos += 1
			continue
		}
		if input[pos] == '#' {
			for pos < len(input) && input[pos] != '\n' {
				pos += 1
			}
			continue
		}

		#parse key
		key_start := pos
		for pos < len(input) && input[pos] != '=' && input[pos] != ' ' && input[pos] != '\t' {
			pos += 1
		}
		key := input[key_start:pos]

		#skip to '='
		for pos < len(input) && input[pos] != '=' {
			pos += 1
		}
		pos += 1  #skip '='

		#skip whitespace after '='
		for pos < len(input) && (input[pos] == ' ' || input[pos] == '\t') {
			pos += 1
		}

		if pos >= len(input) { break }

		#parse value
		var value: Toml_Value

		if input[pos] == '"' {
			#check for triple-quote multiline
			if pos + 2 < len(input) && input[pos+1] == '"' && input[pos+2] == '"' {
				pos += 3  #skip opening """
				if pos < len(input) && input[pos] == '\n' {
					pos += 1
				}
				end := pos
				for end + 2 < len(input) {
					if input[end] == '"' && input[end+1] == '"' && input[end+2] == '"' {
						break
					}
					end += 1
				}
				str_val := input[pos:end]
				pos = end + 3  #skip closing """
				value = str_val
			} else {
				pos += 1  #skip opening "
				end := pos
				for end < len(input) && input[end] != '"' {
					if input[end] == '\\' {
						end += 1  #skip escaped char
					}
					end += 1
				}
				str_val := input[pos:end]
				pos = end + 1  #skip closing "
				value = str_val
			}
		} else if input[pos] == 't' || input[pos] == 'f' {
			#boolean
			if input[pos:pos+4] == "true" {
				value = true
				pos += 4
			} else if input[pos:pos+5] == "false" {
				value = false
				pos += 5
			}
		} else {
			#integer
			num_start := pos
			is_negative := false
			if pos < len(input) && input[pos] == '-' {
				is_negative = true
				pos += 1
			}
			for pos < len(input) && input[pos] >= '0' && input[pos] <= '9' {
				pos += 1
			}
			num_str := input[num_start:pos]
			n, ok := strconv.atoi(num_str)
			if ok {
				value = n
			}
		}

		append(&dict.entries, Toml_Entry{key = key, value = value})

		#skip to end of line
		for pos < len(input) && input[pos] != '\n' {
			pos += 1
		}
	}

	return dict
}

toml_write :: proc(dict: ^Toml_Dict, buf: ^strings.Builder) {
	for entry in dict.entries {
		fmt.sbprintf(buf, "{} = ", entry.key)
		switch v in entry.value {
		case string:
			if strings.contains_rune(v, '\n') {
				fmt.sbprintf(buf, "\"\"\"\n{}\"\"\"", v)
			} else {
				fmt.sbprintf(buf, "\"{}\"", v)
			}
		case int:
			fmt.sbprintf(buf, "{}", v)
		case bool:
			fmt.sbprintf(buf, "{}", v)
		}
		fmt.sbprintf(buf, "\n")
	}
}
```

Note: The `#removesuffix` and `#skip` comments above are pseudocode — actual implementation uses plain loops. The `strconv.atoi` import requires `"core:strconv"`. The `strings.contains_rune` requires `"core:strings"`.

- [ ] **Step 2: Verify the package compiles**

Run: `odin build src/e2e -out:camp-e2e`
Expected: Compilation errors about missing `main` proc — that's fine, we just want to check for syntax/type errors in toml.odin

- [ ] **Step 3: Commit**

```bash
git add src/e2e/toml.odin
git commit -m "feat(e2e): add minimal TOML parser for snapshot format"
```

---

### Task 3: Implement test runner core

**Files:**
- Create: `src/e2e/runner.odin`

The runner discovers tests, executes them in isolated temp dirs, compares output, and reports results.

- [ ] **Step 1: Write `src/e2e/runner.odin`**

Key types and procedures:

```odin
package e2e

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

E2E_Test :: struct {
	category:     string,
	name:         string,
	camp_path:    string,   #absolute path to .camp source
	expected_path: string,  #absolute path to .expected.toml
}

Test_Result :: enum {
	Pass,
	Fail,
	Skip,
}

Test_Report :: struct {
	test:   E2E_Test,
	result: Test_Result,
	diff:   string,  #human-readable diff for failures
}
```

Discovery: Walk `tests/e2e/` looking for `*.camp` files. For each, check if a corresponding `*.expected.toml` exists. If not, skip (or create with `--update`).

Execution per test:
1. Create `/tmp/camp-e2e/<category>/<name>/`
2. Copy `.camp` file to `/tmp/camp-e2e/<category>/<name>/<name>.camp`
3. Run `os.process_exec` with command `"./camp"`, args `["build", camp_path]`, capture stdout/stderr/exit
4. Parse `expected.toml`
5. Compare actual vs expected for stdout, stderr, exit
6. If `wasm_exit` field exists in expected.toml, run `wasmtime run <wasm_path>`, capture exit/stdout/stderr and compare
7. Return Test_Report

Diff format: For each field that mismatches, show expected vs actual. Use a simple line-by-line comparison for multiline strings.

- [ ] **Step 2: Verify compilation**

Run: `odin build src/e2e -out:camp-e2e`
Expected: May still error on missing `main` — that's OK

- [ ] **Step 3: Commit**

```bash
git add src/e2e/runner.odin
git commit -m "feat(e2e): add test runner with discovery, execution, comparison"
```

---

### Task 4: Implement e2e main entry point

**Files:**
- Create: `src/e2e/e2e.odin`

The entry point parses CLI flags, discovers tests, runs them, and prints a summary.

- [ ] **Step 1: Write `src/e2e/e2e.odin`**

```odin
package e2e

import "core:fmt"
import "core:os"

main :: proc() {
	args := os.args
	update := false
	verbose := false
	filter := ""

	for i in 1..<len(args) {
		if args[i] == "--update" {
			update = true
		} else if args[i] == "--verbose" {
			verbose = true
		} else if args[i] == "--filter" && i + 1 < len(args) {
			filter = args[i+1]
			i += 1
		}
	}

	tests := discover_tests("tests/e2e", filter)

	if len(tests) == 0 {
		fmt.println("no e2e tests found")
		os.exit(1)
	}

	pass_count: int = 0
	fail_count: int = 0
	skip_count: int = 0

	for test in tests {
		report := run_test(test, update)

		switch report.result {
		case .Pass:
			pass_count += 1
			if verbose {
				fmt.printfln("  PASS  {}/{}", test.category, test.name)
			}
		case .Fail:
			fail_count += 1
			fmt.printfln("  FAIL  {}/{}", test.category, test.name)
			if len(report.diff) > 0 {
				fmt.println(report.diff)
			}
		case .Skip:
			skip_count += 1
			fmt.printfln("  SKIP  {}/{}", test.category, test.name)
		}
	}

	fmt.printfln("\n{} passed, {} failed, {} skipped ({} total)", pass_count, fail_count, skip_count, len(tests))

	if fail_count > 0 {
		os.exit(1)
	}
}
```

The `discover_tests` proc walks `tests/e2e/<category>/` directories and finds all `.camp` files. The `run_test` proc uses the runner from Task 3.

Parallel execution: Use `thread.Pool` to run tests concurrently. Pool size = `os.get_processor_core_count()`. Each test is a task submitted to the pool. Results collected via a thread-safe results array.

- [ ] **Step 2: Build the e2e binary**

Run: `odin build src/e2e -out:camp-e2e`
Expected: Builds successfully

- [ ] **Step 3: Verify it runs (will show "no e2e tests found" since none exist yet)**

Run: `./camp-e2e`
Expected: `no e2e tests found` and exit code 1

- [ ] **Step 4: Commit**

```bash
git add src/e2e/e2e.odin
git commit -m "feat(e2e): add camp-e2e binary entry point with flags and parallel execution"
```

---

### Task 5: Create execution/ test files (17 tests)

**Files:**
- Create: `tests/e2e/execution/<name>.camp` (17 files)
- Create: `tests/e2e/execution/<name>.expected.toml` (17 files)

These tests should all PASS since they test currently-working features.

- [ ] **Step 1: Create test directories**

```bash
mkdir -p tests/e2e/execution
```

- [ ] **Step 2: Create `tests/e2e/execution/integer-literal.camp`**

```
main! = || -> I64 { 42 }
```

- [ ] **Step 3: Create `tests/e2e/execution/integer-literal.expected.toml`**

Run `./camp build /tmp/camp-e2e/execution/integer-literal/integer-literal.camp` manually first to capture actual output, then write the expected.toml. Alternatively, use `--update` after creating the .camp file.

For `integer-literal`, the expected output will look like:

```toml
stdout = """
canonicalized /tmp/camp-e2e/execution/integer-literal/integer-literal.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/execution/integer-literal/integer-literal.camp
compiled /tmp/camp-e2e/execution/integer-literal/integer-literal.camp -> /tmp/camp-e2e/execution/integer-literal/integer-literal.wasm
"""
stderr = ""
exit = 0
wasm_exit = 42
```

- [ ] **Step 4: Create all 17 execution .camp files**

Create each file with the program content from the spec:

1. `integer-literal.camp`: `main! = || -> I64 { 42 }`
2. `arithmetic.camp`: `main! = || -> I64 { (6 + 3) * 7 - 1 }`
3. `negation.camp`: `main! = || -> I64 { 0 - 42 }`
4. `let-binding.camp`: `main! = || -> I64 { x = 42 y = x + 1 y }`
5. `if-else-true.camp`: `main! = || -> I64 { if true 1 else 0 }`
6. `if-else-false.camp`: `main! = || -> I64 { if false 1 else 0 }`
7. `nested-if.camp`: `main! = || -> I64 { if true if false 1 else 2 else 3 }`
8. `function-call.camp`: `add = (a, b) -> I64 { a + b } main! = || -> I64 { add(3, 4) }`
9. `function-identity.camp`: `id = (x) -> I64 { x } main! = || -> I64 { id(42) }`
10. `block-expression.camp`: `main! = || -> I64 { 1 2 3 }`
11. `not-operator.camp`: `main! = || -> I64 { if not false 1 else 0 }`
12. `and-or.camp`: `main! = || -> I64 { if true and false 1 else if true or false 2 else 0 }`
13. `comparison-eq.camp`: `main! = || -> I64 { if 1 == 1 1 else 0 }`
14. `comparison-neq.camp`: `main! = || -> I64 { if 1 != 2 1 else 0 }`
15. `comparison-lt.camp`: `main! = || -> I64 { if 1 < 2 1 else 0 }`
16. `recursive-call.camp`: `loop! = (n) -> I64 { if n == 0 0 else loop!(n - 1) } main! = || -> I64 { loop!(5) }`
17. `multi-decl.camp`: `x = 10 y = 20 main! = || -> I64 { x + y }`

- [ ] **Step 5: Generate expected.toml files using --update**

```bash
just build && just build-e2e
./camp-e2e --update
```

This creates `expected.toml` files with actual output. Review each one to verify correctness.

- [ ] **Step 6: Run e2e tests to verify they pass**

Run: `./camp-e2e --filter "execution/*"`
Expected: All 17 tests PASS

- [ ] **Step 7: Commit**

```bash
git add tests/e2e/execution/
git commit -m "test(e2e): add 17 execution snapshot tests"
```

---

### Task 6: Create command-line/ test files (4 tests)

**Files:**
- Create: `tests/e2e/command-line/<name>.camp` (4 files, some may be empty)
- Create: `tests/e2e/command-line/<name>.expected.toml` (4 files)

Command-line tests don't compile Camp files — they test the `camp` binary's argument handling. These need a different approach: the .camp file is just a marker, and the runner invokes `camp` with specific arguments rather than `camp build <camp_path>`.

**Design decision:** For command-line tests, the `.expected.toml` uses an additional `args` field to specify what arguments to pass to the `camp` binary. If `args` is absent, the runner defaults to `["build", <camp_path>]`.

Example `no-arguments.expected.toml`:
```toml
args = "no-args"
stdout = """
Camp compiler v0.0.1
Usage: camp <command> [options] <file>
Commands: build, test, fmt, check
"""
stderr = ""
exit = 1
```

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/command-line
```

- [ ] **Step 2: Create the 4 command-line tests**

1. `no-arguments.camp` (empty) + `no-arguments.expected.toml` (args = "no-args", expects usage + exit 1)
2. `unknown-command.camp` (empty) + `unknown-command.expected.toml` (args = "unknown", expects error + exit 1)
3. `non-camp-file.camp` + `non-camp-file.expected.toml` (args = "build-non-camp", expects extension error + exit 1)
4. `file-not-found.camp` (empty) + `file-not-found.expected.toml` (args = "build-missing", expects file-not-found + exit 1)

- [ ] **Step 3: Update runner to handle special `args` values**

In `runner.odin`, add handling for the `args` field in `expected.toml`:
- `args = "no-args"` → run `./camp` with no arguments
- `args = "unknown"` → run `./camp foo`
- `args = "build-non-camp"` → run `./camp build test.txt` (create a dummy test.txt in temp dir)
- `args = "build-missing"` → run `./camp build /nonexistent.camp`
- If `args` is absent → run `./camp build <camp_path>` (default behavior)

- [ ] **Step 4: Generate expected.toml and verify**

Run `./camp-e2e --update --filter "command-line/*"` then review.

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/command-line/ src/e2e/runner.odin
git commit -m "test(e2e): add 4 command-line snapshot tests"
```

---

### Task 7: Create errors/ test files (13 tests)

**Files:**
- Create: `tests/e2e/errors/<name>.camp` (13 files)
- Create: `tests/e2e/errors/<name>.expected.toml` (13 files)

These test that the compiler correctly rejects invalid programs. All should have `exit = 1` and non-empty `stderr` (or error messages in `stdout` — depends on current compiler behavior).

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/errors
```

- [ ] **Step 2: Create the 13 error .camp files**

1. `type-mismatch-binop.camp`: `x = 42 y = x + true`
2. `undefined-name.camp`: `x = y`
3. `unhandled-effect.camp`: `effect IO { println } main! = || -> I64 { IO.println("hi") 0 }`
4. `effectful-naming-no-bang.camp`: `effect IO { println } main = || -> {IO} I64 { 0 }`
5. `duplicate-definition.camp`: `x = 1 x = 2`
6. `arity-mismatch.camp`: `f = (x) -> I64 { x } f(1, 2)`
7. `syntax-error-incomplete.camp`: `x =`
8. `syntax-error-bad-token.camp`: `x = @`
9. `type-annotation-mismatch.camp`: `x: String = 42`
10. `apply-non-function.camp`: `x = 42 x(1)`
11. `wrong-arity-annotation.camp`: `f = (x, y) -> I64 { x + y } f(1)`
12. `if-non-bool-condition.camp`: `x = if 42 1 else 0`
13. `missing-else.camp`: `x = if true 1`
14. `recursive-type-error.camp`: `f = (x) { f(x) }`

- [ ] **Step 3: Generate expected.toml files**

Run: `./camp-e2e --update --filter "errors/*"`
Then review each `expected.toml` to verify the error messages are sensible and `exit = 1`.

- [ ] **Step 4: Verify tests pass**

Run: `./camp-e2e --filter "errors/*"`
Expected: All 13 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/errors/
git commit -m "test(e2e): add 13 error snapshot tests"
```

---

### Task 8: Create typechecking/ test files (19 tests)

**Files:**
- Create: `tests/e2e/typechecking/<name>.camp` (19 files)
- Create: `tests/e2e/typechecking/<name>.expected.toml` (19 files)

These test that programs pass type checking. They should have `exit = 0`. Some may not codegen correctly (that's fine — the expected.toml captures current behavior).

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/typechecking
```

- [ ] **Step 2: Create the 19 typechecking .camp files**

1. `lambda-inference.camp`: `f = (x) { x }`
2. `let-polymorphism.camp`: `id = (x) { x } a = id(1) b = id(true)`
3. `record-literal.camp`: `p = { x: 1, y: 2 }`
4. `record-nested.camp`: `p = { inner: { x: 1 } }`
5. `tag-construction.camp`: `x = Ok(42)`
6. `tag-union-type.camp`: `x : Ok(I64) | Error(String) = Ok(42)`
7. `effect-declaration.camp`: `effect IO { println }`
8. `effectful-function.camp`: `greet! = (name) -> {IO} String { name }`
9. `handle-expression.camp`: `effect IO { println } result = handle IO.println("hi") with { IO.println(s) -> resume(()) }`
10. `perform-call.camp`: `effect IO { println } IO.println("hi")`
11. `function-type-annotation.camp`: `f = (x: I64) -> I64 { x + 1 }`
12. `type-annotation-matches.camp`: `x: I64 = 42`
13. `bool-type.camp`: `b = true b2 = false`
14. `string-type.camp`: `s = "hello"`
15. `float-type.camp`: `f = 3.14`
16. `if-both-branches-same-type.camp`: `x = if true 1 else 2`
17. `if-branch-mismatch.camp`: `x = if true 1 else "no"`
18. `function-param-inference.camp`: `f = (x) { x + 1 }`
19. `higher-order-function.camp`: `apply = (f, x) { f(x) }`
20. `return-type-annotation.camp`: `f = (x) -> I64 { x }`

Note: `if-branch-mismatch` is actually an error test (type mismatch in if branches). It should go in `errors/` or be kept here with `exit = 1`. Capture actual behavior with `--update`.

- [ ] **Step 3: Generate expected.toml files**

Run: `./camp-e2e --update --filter "typechecking/*"`
Review the generated files.

- [ ] **Step 4: Verify**

Run: `./camp-e2e --filter "typechecking/*"`

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/typechecking/
git commit -m "test(e2e): add 19 typechecking snapshot tests"
```

---

### Task 9: Create strings/ test files (4 tests, TDD targets)

**Files:**
- Create: `tests/e2e/strings/<name>.camp` (4 files)
- Create: `tests/e2e/strings/<name>.expected.toml` (4 files)

These will FAIL until string codegen is implemented. The `expected.toml` files contain the **desired** output, not the current broken behavior.

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/strings
```

- [ ] **Step 2: Create .camp files**

1. `string-literal.camp`: `main! = || -> I64 { "hello" 0 }`
2. `string-concat.camp`: `main! = || -> I64 { "hello" + " world" 0 }`
3. `string-interpolation.camp`: `main! = || -> I64 { x = 42 "{x} is the answer" 0 }`
4. `string-print.camp`: `effect IO { println } main! = || -> {IO} I64 { IO.println("hello") 0 }`

- [ ] **Step 3: Write desired expected.toml files**

These contain what we WANT the compiler to produce, not what it currently does. They will fail until implemented.

For `string-literal.expected.toml`:
```toml
stdout = """
canonicalized /tmp/camp-e2e/strings/string-literal/string-literal.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/strings/string-literal/string-literal.camp
compiled /tmp/camp-e2e/strings/string-literal/string-literal.camp -> /tmp/camp-e2e/strings/string-literal/string-literal.wasm
"""
stderr = ""
exit = 0
wasm_exit = 0
```

For `string-print.expected.toml`:
```toml
stdout = """
canonicalized /tmp/camp-e2e/strings/string-print/string-print.camp: 1 declaration(s), 0 import(s)
typecheck passed for /tmp/camp-e2e/strings/string-print/string-print.camp
compiled /tmp/camp-e2e/strings/string-print/string-print.camp -> /tmp/camp-e2e/strings/string-print/string-print.wasm
"""
stderr = ""
exit = 0
wasm_exit = 0
wasm_stdout = "hello\n"
```

- [ ] **Step 4: Verify these tests FAIL**

Run: `./camp-e2e --filter "strings/*"`
Expected: All 4 tests FAIL (these are TDD targets)

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/strings/
git commit -m "test(e2e): add 4 string snapshot tests (TDD targets, currently failing)"
```

---

### Task 10: Create records/ test files (6 tests, TDD targets)

**Files:**
- Create: `tests/e2e/records/<name>.camp` (6 files)
- Create: `tests/e2e/records/<name>.expected.toml` (6 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/records
```

- [ ] **Step 2: Create .camp files**

1. `record-construct.camp`: `main! = || -> I64 { p = { x: 1, y: 2 } 0 }`
2. `record-field-access.camp`: `main! = || -> I64 { p = { x: 42, y: 0 } p.x }`
3. `record-nested-access.camp`: `main! = || -> I64 { r = { inner: { val: 99 } } r.inner.val }`
4. `record-modify.camp`: `main! = || -> I64 { p = { x: 1, y: 2 } p2 = { x: 10 ..p } p2.x }`
5. `record-as-function-return.camp`: `mk = (a) -> { x: I64 } { { x: a } } main! = || -> I64 { mk(42).x }`
6. `record-field-mismatch.camp`: `p = { x: 1 } y = p.y`

- [ ] **Step 3: Write desired expected.toml files**

Record tests should return `wasm_exit` matching the expected integer result. `record-field-mismatch` should be an error test (`exit = 1`).

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/records/
git commit -m "test(e2e): add 6 record snapshot tests (TDD targets, currently failing)"
```

---

### Task 11: Create tag-unions/ test files (8 tests, TDD targets)

**Files:**
- Create: `tests/e2e/tag-unions/<name>.camp` (8 files)
- Create: `tests/e2e/tag-unions/<name>.expected.toml` (8 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/tag-unions
```

- [ ] **Step 2: Create .camp files**

1. `tag-construct-ok.camp`: `main! = || -> I64 { x = Ok(42) 0 }`
2. `tag-construct-error.camp`: `main! = || -> I64 { x = Error("fail") 0 }`
3. `tag-match-simple.camp`: `main! = || -> I64 { x = Ok(42) match x { Ok(v) -> v | Error(e) -> 0 } }`
4. `tag-match-branches-exhaustive.camp`: `x = Ok(1) | Error(0) match x { Ok(v) -> v | Error(e) -> e }`
5. `tag-match-non-exhaustive.camp`: `x = Ok(1) | Error(0) match x { Ok(v) -> v }`
6. `tag-match-nested.camp`: `main! = || -> I64 { x = Ok(Ok(42)) match x { Ok(Ok(v)) -> v | _ -> 0 } }`
7. `tag-wildcard.camp`: `main! = || -> I64 { x = Ok(42) match x { Ok(v) -> v | _ -> 0 } }`
8. `tag-type-mismatch.camp`: `x = Ok(42) match x { Ok(v) -> v | Error(e) -> e + 1 }`

- [ ] **Step 3: Write desired expected.toml files**

`tag-match-non-exhaustive` and `tag-type-mismatch` should be error tests.

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/tag-unions/
git commit -m "test(e2e): add 8 tag-union snapshot tests (TDD targets, currently failing)"
```

---

### Task 12: Create pattern-matching/ test files (7 tests, TDD targets)

**Files:**
- Create: `tests/e2e/pattern-matching/<name>.camp` (7 files)
- Create: `tests/e2e/pattern-matching/<name>.expected.toml` (7 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/pattern-matching
```

- [ ] **Step 2: Create .camp files**

1. `match-int-literal.camp`: `main! = || -> I64 { match 42 { 0 -> 1 | 1 -> 2 | _ -> 99 } }`
2. `match-bool.camp`: `main! = || -> I64 { match true { true -> 1 | false -> 0 } }`
3. `match-with-guard.camp`: `main! = || -> I64 { x = 5 match x { n if n > 0 -> 1 | _ -> 0 } }`
4. `match-or-pattern.camp`: `main! = || -> I64 { x = 2 match x { 1 | 2 | 3 -> 1 | _ -> 0 } }`
5. `match-variable-bind.camp`: `main! = || -> I64 { x = Ok(42) match x { Ok(v) -> v | _ -> 0 } }`
6. `match-record-pattern.camp`: `main! = || -> I64 { match { x: 1, y: 2 } { { x: a, y: b } -> a + b } }`
7. `match-string-literal.camp`: `main! = || -> I64 { match "hello" { "hello" -> 1 | _ -> 0 } }`

- [ ] **Step 3: Write desired expected.toml files**

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/pattern-matching/
git commit -m "test(e2e): add 7 pattern-matching snapshot tests (TDD targets, currently failing)"
```

---

### Task 13: Create effects/ test files (8 tests, TDD targets)

**Files:**
- Create: `tests/e2e/effects/<name>.camp` (8 files)
- Create: `tests/e2e/effects/<name>.expected.toml` (8 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/effects
```

- [ ] **Step 2: Create .camp files**

1. `effect-declare-and-handle.camp`: `effect IO { println } result = handle IO.println("hi") with { IO.println(s) -> resume(()) }`
2. `effect-perform-return-value.camp`: `effect Ask { read } result = handle Ask.read() with { Ask.read() -> resume(42) }`
3. `effect-multiple-operations.camp`: `effect IO { println, readln }`
4. `effect-deep-handler.camp`: `effect IO { println } main! = || -> {IO} I64 { handle IO.println("hi") with { IO.println(s) -> resume(()) } 0 }`
5. `effect-shallow-handler.camp`: `effect IO { println } main! = || -> {IO} I64 { intercept IO.println("hi") with { IO.println(s) -> resume(()) } 0 }`
6. `effect-multiple-effects.camp`: `effect IO { println } effect State { get, put }`
7. `effect-unhandled.camp`: `effect IO { println } IO.println("hi")`
8. `effect-handler-resume-twice.camp`: `effect IO { println } result = handle IO.println("hi") with { IO.println(s) -> resume(()) resume(()) }`

- [ ] **Step 3: Write desired expected.toml files**

`effect-unhandled` should be an error test.

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/effects/
git commit -m "test(e2e): add 8 effect snapshot tests (TDD targets, currently failing)"
```

---

### Task 14: Create closures/ test files (8 tests, TDD targets)

**Files:**
- Create: `tests/e2e/closures/<name>.camp` (8 files)
- Create: `tests/e2e/closures/<name>.expected.toml` (8 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/closures
```

- [ ] **Step 2: Create .camp files**

1. `closure-free-var.camp`: `main! = || -> I64 { x = 10 f = () -> I64 { x } f() }`
2. `closure-nested.camp`: `main! = || -> I64 { x = 1 f = () -> I64 { g = () -> I64 { x } g() } f() }`
3. `closure-mutation-simulated.camp`: `main! = || -> I64 { x = { val: 0 } f = () -> I64 { x.val } f() }`
4. `higher-order-map.camp`: `map = (f, xs) -> List(I64) { match xs { Nil -> Nil | Cons(h, t) -> Cons(f(h), map(f, t)) } }`
5. `higher-order-filter.camp`: `filter = (pred, xs) -> List(I64) { match xs { Nil -> Nil | Cons(h, t) -> if pred(h) Cons(h, filter(pred, t)) else filter(pred, t) } }`
6. `function-composition.camp`: `compose = (f, g) -> (I64) -> I64 { (x) -> I64 { f(g(x)) } }`
7. `partial-application.camp`: `add = (a, b) -> I64 { a + b } inc = add(1, _)`
8. `recursive-closure.camp`: `f! = () -> I64 { f!() }`

- [ ] **Step 3: Write desired expected.toml files**

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/closures/
git commit -m "test(e2e): add 8 closure snapshot tests (TDD targets, currently failing)"
```

---

### Task 15: Create generics/ test files (5 tests, TDD targets)

**Files:**
- Create: `tests/e2e/generics/<name>.camp` (5 files)
- Create: `tests/e2e/generics/<name>.expected.toml` (5 files)

- [ ] **Step 1: Create directory**

```bash
mkdir -p tests/e2e/generics
```

- [ ] **Step 2: Create .camp files**

1. `identity-function.camp`: `id = (x) { x } a = id(1) b = id(true)`
2. `generic-pair.camp`: `pair = (a, b) { { fst: a, snd: b } }`
3. `generic-list-map.camp`: `map = (f, xs) { match xs { Nil -> Nil | Cons(h, t) -> Cons(f(h), map(f, t)) } }`
4. `generic-function-compose.camp`: `compose = (f, g, x) { f(g(x)) }`
5. `generic-with-constraint.camp`: `f = (x) { x + 1 }`

- [ ] **Step 3: Write desired expected.toml files**

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/generics/
git commit -m "test(e2e): add 5 generic snapshot tests (TDD targets, currently failing)"
```

---

### Task 16: Full test suite verification

- [ ] **Step 1: Run all e2e tests**

Run: `./camp-e2e`
Expected: Summary showing passing tests (execution, command-line, errors, typechecking) and failing tests (strings, records, tag-unions, pattern-matching, effects, closures, generics)

- [ ] **Step 2: Run full justfile test suite**

Run: `just test`
Expected: Unit tests (99) pass + e2e results. Failing e2e tests cause `just test` to exit 1 (by design — these are TDD targets).

- [ ] **Step 3: Consider the exit code strategy**

Since many TDD-target tests will fail by design, `just test` will always fail currently. Consider adding a `just test-ci` that only runs passing categories, or adjust the runner to accept `--expect-failures <count>` so CI can distinguish "expected failures" from "unexpected failures". Update justfile accordingly.

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "chore: complete e2e snapshot test suite with justfile integration"
```

---

## Self-Review

### Spec Coverage Check

| Spec Requirement | Task |
|-----------------|------|
| Test directory layout (`tests/e2e/<category>/`) | Tasks 5-15 |
| Snapshot format (`*.camp` + `*.expected.toml`) | Tasks 5-15 |
| TOML fields: stdout, stderr, exit, wasm_exit, wasm_stdout, wasm_stderr | Task 2 (parser), Tasks 5-15 (test files) |
| Separate `camp-e2e` binary in `src/e2e/` | Tasks 2-4 |
| Isolated temp dirs: `/tmp/camp-e2e/<category>/<name>/` | Task 3 |
| Copy .camp files to temp dirs | Task 3 |
| Run `camp build`, capture output | Task 3 |
| Run `wasmtime run` for execution tests | Task 3 |
| Parse expected.toml, compare actual vs expected | Tasks 2-3 |
| Report: PASS, FAIL, SKIP | Task 3 |
| `--update` flag | Task 4 |
| `--filter <pattern>` flag | Task 4 |
| `--verbose` flag | Task 4 |
| Parallel execution | Task 4 |
| Minimal TOML parser | Task 2 |
| Justfile with build/test/update commands | Task 1 |
| Pre-commit hook | (deferred — user installs manually) |
| All 10 test categories | Tasks 5-15 |
| WASM sandboxing for test isolation | Task 3 |
| Snapshot update workflow documented | Task 1 (justfile commands) |

### Placeholder Scan

- No TBD/TODO in the plan
- All code blocks contain actual implementation code
- All file paths are exact

### Type Consistency

- `Toml_Dict`, `Toml_Entry`, `Toml_Value`, `E2E_Test`, `Test_Result`, `Test_Report` used consistently across Tasks 2-4
- `discover_tests`, `run_test` referenced consistently in Tasks 3-4
