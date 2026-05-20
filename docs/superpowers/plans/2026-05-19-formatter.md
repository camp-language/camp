# Camp Formatter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `camp fmt` — a zero-configuration source formatter that deterministically formats Camp code with zero config, preserving programmer intent via the first-separator/backslash multiline heuristic.

**Architecture:** Hybrid AST + source-aware approach. Parse source to AST (refusing on errors), build a Wadler-style `Doc` IR with source-position annotations driving multiline decisions (first-separator rule, backslash split points, blank line preservation, comment attachment), then resolve `Doc` to a concrete string. The `format()` function is the core API, called directly by the LSP and wrapped by CLI modes (in-place, --check, --stdin).

**Tech Stack:** Odin (matching existing compiler), `core:strings` for string building, `core:os` for file I/O, existing lexer/parser/diagnostic infrastructure.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/format.odin` | Core `format()` function, Doc IR definition, Doc resolution |
| `src/format_doc.odin` | Wadler-style Doc IR types and combinators |
| `src/format_print.odin` | Doc-to-string resolution (flat vs broken layout) |
| `src/format_source.odin` | Source-position analysis: first-separator detection, blank line extraction, comment extraction |
| `src/format_expr.odin` | Expression formatting: walk AST, produce Doc with source-awareness |
| `src/format_decl.odin` | Declaration formatting: walk top-level decls, produce Doc |
| `src/format_type.odin` | Type formatting: walk type nodes, produce Doc |
| `src/run_fmt.odin` | CLI entry point for `camp fmt` command |
| `src/test_format.odin` | Unit tests for formatter |

---

### Task 1: Doc IR and Resolution

**Files:**
- Create: `src/format_doc.odin`
- Create: `src/format_print.odin`
- Test: `src/test_format.odin`

- [ ] **Step 1: Define Doc IR types in `format_doc.odin`**

```odin
package camp

import "core:strings"

Doc_Kind :: enum {
    Empty,
    Text,
    Line,
    Soft_Line,
    Nest,
    Group,
    Concat,
    Align,
    Backslash_Break,
}

Doc :: struct {
    kind:     Doc_Kind,
    text:     string,
    indent:   int,
    children: [dynamic]Doc,
}
```

- [ ] **Step 2: Define Doc combinators in `format_doc.odin`**

```odin
doc_empty :: proc() -> Doc { ... }
doc_text :: proc(text: string) -> Doc { ... }
doc_line :: proc() -> Doc { ... }
doc_soft_line :: proc() -> Doc { ... }
doc_nest :: proc(indent: int, d: Doc) -> Doc { ... }
doc_group :: proc(children: []Doc) -> Doc { ... }
doc_concat :: proc(children: []Doc) -> Doc { ... }
doc_backslash_break :: proc() -> Doc { ... }
doc_space :: proc() -> Doc { ... }
```

Each combinator constructs a `Doc` node. `doc_soft_line` produces a space in flat mode and a newline in broken mode. `doc_backslash_break` is a forced line break at a backslash split point. `doc_group` tries flat layout first, breaks if any child can't fit.

- [ ] **Step 3: Write tests for Doc combinators in `test_format.odin`**

Test that `doc_text`, `doc_concat`, `doc_empty`, `doc_line` construct correctly. Test `doc_group` with simple concatenation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 5: Implement Doc resolution in `format_print.odin`**

```odin
doc_resolve :: proc(d: Doc, indent: int) -> string { ... }
```

Walk the Doc tree. `Group` tries flat layout (soft_line → space). If flat fails (encounters a hard line or backslash break), re-resolve in broken mode (soft_line → newline + indent). `Nest` increases the indent level for children. `Concat` joins children. `Line` is always a newline. `Backslash_Break` is always a newline (preserving backslash in output is handled at a higher level).

The resolution does NOT use a line-length limit. Groups break based on the presence of hard breaks (`Line`, `Backslash_Break`), not width. A group breaks if it contains any hard break.

- [ ] **Step 6: Write resolution tests in `test_format.odin`**

Test that a group with no breaks resolves flat. Test that a group with a hard line breaks. Test nesting produces correct indentation (4 spaces per level). Test soft_line behavior in flat vs broken mode.

- [ ] **Step 7: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/format_doc.odin src/format_print.odin src/test_format.odin
git commit -m "feat(fmt): add Doc IR types, combinators, and resolution"
```

---

### Task 2: Source-Position Analysis

**Files:**
- Create: `src/format_source.odin`
- Modify: `src/test_format.odin`

The formatter needs to know: did the programmer put a line break at the first separator? Are there blank lines between declarations? Where are comments relative to AST nodes?

- [ ] **Step 1: Define source analysis types in `format_source.odin`**

```odin
package camp

Format_Source_Info :: struct {
    source:             string,
    blank_line_after:   map[int]bool,
    comments_before:    map[int][]Comment_Info,
    trailing_comments:  map[int]Comment_Info,
    has_backslash:      map[int]bool,
    first_separator_break: map[int]bool,
}

Comment_Info :: struct {
    text:     string,
    span:     Source_Span,
    is_doc:   bool,
}
```

- [ ] **Step 2: Implement `analyze_source` in `format_source.odin`**

```odin
analyze_source :: proc(source: string, tokens: []Token) -> Format_Source_Info { ... }
```

Walk the token stream. For each comma/operator/pipe token, check if there's a newline between it and the next non-whitespace token. Record `first_separator_break` for the group starting at each comma-separator position. Record `has_backslash` for backslash tokens. Walk the source text to find blank lines and comments (`//` and `///`), recording their positions relative to AST node spans.

- [ ] **Step 3: Write tests for source analysis in `test_format.odin`**

Test that a single-line function call has `first_separator_break = false` at the first comma. Test that a multi-line list has `first_separator_break = true`. Test blank line detection between declarations. Test comment extraction.

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/format_source.odin src/test_format.odin
git commit -m "feat(fmt): add source-position analysis for multiline heuristic"
```

---

### Task 3: Backslash Token in Lexer

**Files:**
- Modify: `src/token.odin`
- Modify: `src/lexer.odin`
- Modify: `src/parser.odin`
- Modify: `src/test_lexer.odin`

- [ ] **Step 1: Add `Backslash` to `Token_Kind` in `token.odin`**

Add `.Backslash,` to the `Token_Kind` enum after the existing operator tokens.

- [ ] **Step 2: Implement backslash lexing in `lexer.odin`**

In `lexer_next`, add a case for `\\` character. If the backslash is inside a string literal, it's handled by the existing string lexing (escape character). Outside a string, emit a `.Backslash` token.

- [ ] **Step 3: Update parser to skip backslash tokens in `parser.odin`**

Add a helper `parser_skip_backslashes` that advances past any `.Backslash` tokens. Call it before parsing comma-separated lists and operator chains. The parser treats backslashes as invisible — they don't produce AST nodes.

- [ ] **Step 4: Write tests in `test_lexer.odin`**

Test that `\\` outside a string produces a `.Backslash` token. Test that `\\` inside a string is part of an escape sequence (existing behavior). Test that backslash after a comma in a list is correctly lexed.

- [ ] **Step 5: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/token.odin src/lexer.odin src/parser.odin src/test_lexer.odin
git commit -m "feat(fmt): add Backslash token to lexer, skip in parser"
```

---

### Task 4: Type Formatting

**Files:**
- Create: `src/format_type.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement `format_type` in `format_type.odin`**

```odin
package camp

format_type :: proc(t: ^Type, info: ^Format_Source_Info) -> Doc { ... }
```

Walk the Type union:
- `Type_Primitive` → `doc_text(name)`
- `Type_Applied` → `doc_text(name)` + `doc_text("(")` + comma-separated args + `doc_text(")")`. Args follow first-comma rule: check `info.first_separator_break` for the first arg's comma. If break, use `doc_group` with `doc_soft_line` between args; each arg on own line with trailing comma.
- `Type_Function` → params + `doc_text(" ->")` + optional `doc_text(" -[")` + pipe-separated effects + `doc_text("]-> ")` + return type. Effect row follows first-`|` rule.
- `Type_Record` → `{ ` + comma-separated fields + ` }`. Fields follow first-comma rule.
- `Type_Tag_Union` → `[` + pipe-separated tags + `]`. Tags follow first-`|` rule.
- `Type_Effect_Row` → used within function type, pipe-separated, first-`|` rule.
- `Type_Variable` → `doc_text(name)`
- `Type_Wildcard` → `doc_text("_")`

- [ ] **Step 2: Write type formatting tests in `test_format.odin`**

Test `Int` → `Int`. Test `List(a)` → `List(a)`. Test `[Ok(a) | Err(e)]` single-line and multi-line. Test `-[Console | IO]->` single-line and multi-line. Test `{ name: Str, age: U64 }` single-line and multi-line.

- [ ] **Step 3: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/format_type.odin src/test_format.odin
git commit -m "feat(fmt): add type formatting with multiline heuristic"
```

---

### Task 5: Expression Formatting

**Files:**
- Create: `src/format_expr.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement `format_expr` in `format_expr.odin`**

```odin
package camp

format_expr :: proc(e: Expr, info: ^Format_Source_Info) -> Doc { ... }
```

Walk the Expr union with source-awareness:

- `Expr_Int` → `doc_text(value)`
- `Expr_Float` → `doc_text(value)`
- `Expr_String` → `doc_text(value)` (preserved as-is, no reflow)
- `Expr_Bool` → `doc_text("True")` or `doc_text("False")`
- `Expr_Tag` → `doc_text(name)` + optional parenthesized payload (first-comma rule)
- `Expr_Record` → `{ ` + comma-separated fields + ` }` (first-comma rule). Single-field name pun: `{ x: }`.
- `Expr_List` → `[` + comma-separated elements + `]` (first-comma rule)
- `Expr_Identifier` → `doc_text(name)`
- `Expr_Dollar_Identifier` → `doc_text("$") + doc_text(name)`
- `Expr_Call` → `doc_text(callee)` + `(args)` (first-comma rule, no space before `(`)
- `Expr_Method_Call` → `doc_text(receiver)` + `.` + `doc_text(method)` + `(args)`. Method chain first-`.` rule.
- `Expr_Lambda` → `|params|` + optional `-> Type` + optional `where` clause + body. Multiline params: opening `|` on own line.
- `Expr_Block` → `{` + newline-separated statements + `}`. Blank lines preserved (collapsed to one).
- `Expr_If` → single-line braceless or single-line with braces or multiline with braces. Braceless when both branches are simple expressions, both-or-neither braces.
- `Expr_Match` → `match` + scrutinee + `{` + arms on own lines + `}`
- `Expr_BinOp` → left + operator + right. First-operator rule for multiline. Break before operator.
- `Expr_PrefixOp` → operator + operand
- `Expr_Field_Access` → `record.field`
- `Expr_Record_Update` → `{ ` + `..rest` + comma-separated updates + ` }` (first-comma rule)
- `Expr_Assign` → `target = value`
- `Expr_Return` → `return value`
- `Expr_Crash` → replaced by `panic "message"` per spec
- `Expr_Interpolate` → `"${...}"` parts preserved as-is
- `Expr_Handle` → `handle`/`intercept` + effect + `in` + body + `with` + arms

- [ ] **Step 2: Write expression formatting tests in `test_format.odin`**

Test each expression type. Test single-line vs multi-line for records, lists, function calls. Test lambda with expression body vs block body. Test if/else in all three modes (braceless, single-line braces, multiline). Test BinOp chains. Test method chains. Test match arms. Test name pun records (`{ x: }` vs `{ x, y }`).

- [ ] **Step 3: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/format_expr.odin src/test_format.odin
git commit -m "feat(fmt): add expression formatting with multiline heuristic"
```

---

### Task 6: Declaration Formatting

**Files:**
- Create: `src/format_decl.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement `format_decl` in `format_decl.odin`**

```odin
package camp

format_decl :: proc(d: Decl, info: ^Format_Source_Info) -> Doc { ... }
format_file :: proc(f: File, info: ^Format_Source_Info) -> Doc { ... }
```

Walk declarations:
- `Decl_Const` → optional `pub ` + name + optional `!` + optional `: Type` + ` = ` + body. If body has `@derive`, place on own line before.
- `Decl_Effect` → `effect ` + name + `{ ` + operations + `}`. Empty: one-line. Otherwise: each operation on own line.
- `Decl_Trait` → `trait ` + name + optional ` is Parent` + `{` + methods on own lines + `}`
- `Decl_Alias` → `alias ` + name + ` = ` + pipe-separated effects
- `Decl_Import` → `import ` + module + optional ` exposing [...]` + optional ` as Alias`. Exposing list follows first-comma rule.
- `Decl_Test` → `test "name" = ` + body
- `Decl_Expect` → `expect ` + condition

`format_file` concatenates declarations, inserting blank lines where the source had them (from `info.blank_line_after`). Collapses multiple blank lines to one.

- [ ] **Step 2: Write declaration formatting tests in `test_format.odin`**

Test const decls with and without type annotations. Test effect decls (empty vs non-empty). Test trait decls with `is`. Test import decls (simple, with exposing, with alias). Test blank line preservation between declarations. Test multiple blank line collapse. Test `@derive` placement.

- [ ] **Step 3: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/format_decl.odin src/test_format.odin
git commit -m "feat(fmt): add declaration formatting with blank line preservation"
```

---

### Task 7: Core Format Function

**Files:**
- Create: `src/format.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement `format` in `format.odin`**

```odin
package camp

Format_Result :: struct {
    output:      string,
    diagnostics: []Diagnostic,
}

format :: proc(source: string, file_path: string, allocator: mem.Allocator) -> Format_Result { ... }
```

Pipeline:
1. Create a `Source_File` from the input
2. Lex the source, collecting tokens (including backslash tokens)
3. If lex errors, return diagnostics and empty output (refuse to format)
4. Parse the source to AST
5. If parse errors, return diagnostics and empty output (refuse to format)
6. Run `analyze_source` on the token stream and source text
7. Call `format_file(ast_file, &info)` to produce a Doc
8. Resolve the Doc to a string via `doc_resolve`
9. Return the formatted string

- [ ] **Step 2: Write integration tests in `test_format.odin`**

Test the full pipeline: source in, formatted string out. Test that already-formatted code is a fixed point (idempotency). Test that syntax errors are detected and formatting is refused. Test single-line vs multi-line formatting driven by source breaks. Test backslash preservation. Test comment preservation and re-indentation.

- [ ] **Step 3: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/format.odin src/test_format.odin
git commit -m "feat(fmt): add core format function with full pipeline"
```

---

### Task 8: CLI Integration

**Files:**
- Create: `src/run_fmt.odin`
- Modify: `src/main.odin`
- Modify: `src/cli.odin`

- [ ] **Step 1: Implement `run_fmt` in `run_fmt.odin`**

```odin
package camp

import "core:fmt"
import "core:os"
import "core:path/filepath"

Fmt_Flags :: struct {
    check: bool,
    stdin: bool,
}

run_fmt :: proc(args: []string) { ... }
```

- Parse `--check` and `--stdin` flags from `args`
- If `--stdin`: read stdin, call `format()`, write to stdout (or diff for `--check`)
- If file paths: format each file in-place (or diff for `--check`). If a path is a directory, walk for `*.camp` files.
- If no paths: walk current directory for `*.camp` files.
- `--check` mode: for each file, compute diff between original and formatted. Print diff. Exit 1 if any differences, exit 0 if none.

- [ ] **Step 2: Update `main.odin` to call `run_fmt`**

Replace the `fmt.println("TODO: camp fmt")` with `run_fmt(remaining_args)`.

- [ ] **Step 3: Write CLI tests in `test_format.odin`**

Test that `camp fmt --stdin` reads from stdin and writes to stdout. Test that `camp fmt --check` exits with correct codes. Test that `camp fmt` on a valid file produces formatted output. Test that `camp fmt` on a file with syntax errors exits with code 1.

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/run_fmt.odin src/main.odin src/cli.odin src/test_format.odin
git commit -m "feat(fmt): add CLI integration with --check and --stdin"
```

---

### Task 9: Comment and Blank Line Formatting

**Files:**
- Modify: `src/format_source.odin`
- Modify: `src/format_decl.odin`
- Modify: `src/format_expr.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement comment extraction in `format_source.odin`**

Enhance `analyze_source` to extract `//` and `///` comments. For each comment, record its position and determine which AST node it precedes (attach to next element unless separated by a blank line). Record trailing comments (same line as code).

- [ ] **Step 2: Implement comment insertion in `format_decl.odin` and `format_expr.odin`**

When building Doc for a declaration or expression, check `info.comments_before[node_span]` and prepend comment Docs (re-indented to current level). For trailing comments, append after the node on the same line.

- [ ] **Step 3: Write comment formatting tests in `test_format.odin`**

Test that a comment before a declaration is preserved and re-indented. Test that a blank line before a comment detaches it from the previous element. Test trailing comments. Test doc comments (`///`). Test comment re-indentation inside blocks.

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/format_source.odin src/format_decl.odin src/format_expr.odin src/test_format.odin
git commit -m "feat(fmt): add comment and blank line formatting"
```

---

### Task 10: Where Clause Formatting

**Files:**
- Modify: `src/format_expr.odin`
- Modify: `src/test_format.odin`

- [ ] **Step 1: Implement where clause formatting in `format_expr.odin`**

When formatting a lambda with a where clause:
1. State 1 (single-line): `|x: a| -> Str where a is Display { ... }`
2. State 2 (where-only multiline): signature on one line, `where` indented once, constraints indented twice (first-comma rule), no trailing comma
3. State 3 (forced multiline): if args/return type are multiline, where uses same layout as state 2

- [ ] **Step 2: Write where clause tests in `test_format.odin`**

Test all three states. Test multiple constraints with first-comma rule. Test no trailing comma on last constraint. Test that multiline args force multiline where.

- [ ] **Step 3: Run tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/format_expr.odin src/test_format.odin
git commit -m "feat(fmt): add where clause formatting with three states"
```

---

### Task 11: Idempotency and Edge Cases

**Files:**
- Modify: `src/test_format.odin`

- [ ] **Step 1: Write idempotency tests in `test_format.odin`**

For each expression and declaration type tested, add a test that formats the output again and verifies it's identical. This catches any non-fixed-point behavior.

- [ ] **Step 2: Write edge case tests in `test_format.odin`**

Test empty file → empty output. Test file with only comments. Test file with only blank lines. Test deeply nested expressions. Test single-element lists. Test single-field record name pun (`{ x: }`). Test zero-arg lambda (`||`). Test empty block (`{}`). Test string with backslash continuation. Test triple-quoted string formatting.

- [ ] **Step 3: Run all tests to verify they pass**

Run: `odin test src`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/test_format.odin
git commit -m "test(fmt): add idempotency and edge case tests"
```

---

### Task 12: Update Existing E2E Test Files

**Files:**
- Modify: `tests/e2e/**/*.camp`

- [ ] **Step 1: Run formatter on all existing test files**

Run: `camp fmt --write tests/`
This formats all `.camp` files in the test directory.

- [ ] **Step 2: Verify all e2e tests still pass**

Run: `just test-e2e`
Expected: All tests pass with formatted source.

- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "style: format all test files with camp fmt"
```
