# Doc Comments — Technical Design

> Technical design for Camp's documentation comment system, doctests, `expect`
> assertions, `test` blocks, `todo` placeholder operator, and the `camp doc` /
> `camp test` toolchain. See `spec.md` for behavioral requirements.

---

## 1. Design Philosophy and Influences

### 1.1 Core Principles

1. **Examples are tests.** Code in documentation is verified by the compiler.
   Stale examples are caught automatically. Documentation that compiles is
   documentation you can trust.

2. **Doc comments are source of truth.** There is one place to write
   documentation: the `///` comment attached to the declaration. No separate
   documentation files, no generated stubs.

3. **Hidden lines keep examples clean.** Import boilerplate and setup code can
   be hidden from rendered docs while still being compiled. Readers see the
   essence; the compiler sees the full picture.

4. **Incomplete code is first-class.** The `todo` operator allows examples to
   demonstrate partial implementations. Examples don't need to be fully
   working programs — they need to type-check.

5. **Consistent prefix width.** All doc-comment line prefixes (`///` and `//#`)
   are exactly 3 characters, keeping code blocks perfectly indented regardless
   of which prefix is used.

### 1.2 Language Influences

| Language | What Camp Takes | What Camp Rejects |
|----------|----------------|-------------------|
| **Rust** | `///` doc comments, fenced code blocks in docs, doctests in `cargo test`, `# ` hidden lines (adapted to `//#`), `todo!()` macro (adapted to bare `todo` keyword) | Inner doc comments (`//!` — Camp uses first-`///` convention), `!` never type (Camp uses `forall a. a`) |
| **Roc** | `expect` assertion in doc examples, `Debug.todo` (adapted to `todo`) | 5-space indentation for code blocks (Camp uses fenced blocks), `##` doc prefix (Camp uses `///`) |
| **Gleam** | `///` doc comment prefix, `todo` keyword | `////` module doc prefix (Camp uses first-`///` convention) |
| **Haskell** | `$setup` hidden setup concept (adapted to `//#` hidden lines) | `-- \|` doc prefix, `>>>` REPL-style doctests |
| **Go** | Example functions concept (adapted to doc code blocks + `expect`) | `// Output:` pattern matching, indented code blocks |
| **Unison** | Code in docs is typechecked and verified | `{{ }}` doc literal syntax, content-addressed docs |
| **Scala** | `???` as universally-typed placeholder (adapted to `todo`) | `Nothing` bottom type (Camp uses `forall a. a`) |
| **Agda/Idris** | Holes as first-class development tool (adapted to `todo` for incomplete examples) | Interactive metavariables (too complex for Camp's compilation model) |

---

## 2. Comment System Design

### 2.1 Syntax

| Prefix | Meaning | Compiled? | Shown in docs? |
|--------|---------|-----------|----------------|
| `//` | Regular comment | No | No |
| `///` | Doc comment (in prose: Markdown; in code blocks: visible code) | Doc prose: no. Code block: yes | Yes |
| `//#` | Hidden line (code blocks only) | Yes | No |

The `//#` prefix is only valid inside fenced code blocks within doc comments.
Using `//#` in doc comment prose (outside a code block) is a compiler error.

### 2.2 Why `//#` for Hidden Lines

Rust uses `# ` (hash + space) to hide lines. Camp adapts this with `//#`
instead, for three reasons:

1. **Consistent indentation.** `///` and `//#` are both 3 characters. Every
   line in a code block has the same visual structure: 3-char prefix + space +
   content. No misalignment.

2. **Comment-family semantics.** `//` is Camp's comment prefix. `//#` starts
   with `//`, making it visually part of the comment system. The `#` suffix
   marks it as a rendering directive rather than a comment.

3. **No collision with Camp syntax.** `#` alone isn't a Camp token, but using
   it as a line prefix could conflict with future syntax. `//#` is unambiguous.

### 2.3 Migration from `--`/`---` to `//`/`///`

Camp currently uses `--` for comments and `---` for doc comments. This design
switches to `//`/`///`. Migration steps:

1. **Lexer change**: Replace `--` single-line comment token with `//`.
   Replace `---` doc comment detection with `///`.
2. **Formatter change**: Update `collect_comments` in `format_source.odin` to
   detect `//`, `///`, and `//#` instead of `--` and `---`.
3. **Test updates**: All e2e snapshot tests containing `--` comments must be
   updated to `//`. Run `just update-snapshots` after the lexer change.
4. **Kitchen sink**: Update `tests/e2e/language/kitchen-sink/Main.camp` to use
   new comment syntax.

### 2.4 Doc Comment Attachment

```
/// This doc comment attaches to `greet`.
pub greet = |name: Str| -> Str { "Hello, ${name}!" }

/// This doc comment attaches to `@Result`.
@Result(a, e) : [Ok(a) | Err(e)]

/// Module doc: this is the first /// in the file.
/// It attaches to the module itself.
```

**Attachment rules:**

- Consecutive `///` lines are merged into a single doc comment.
- The merged doc comment attaches to the next declaration.
- A blank line between the last `///` and the declaration breaks attachment.
- The first `///` in a file (before any declaration) is the module doc.

### 2.5 Doc Comment Targets

| Target | Example |
|--------|---------|
| Function | `/// Docs before pub greet = ...` |
| Nominal type | `/// Docs before @Result(a, e) : ...` |
| Type alias | `/// Docs before Coords : ...` |
| Effect | `/// Docs before Console! : ...` |
| Trait | `/// Docs before Eq : ...` |
| Module | First `///` in the file |
| Effect operation | `/// Docs before println!: ...` inside effect body |
| Trait method | `/// Docs before eq: ...` inside trait body |
| Tag variant | `/// Docs before Ok(a) \| ...` in tag union |
| Record field | `/// Docs before name: Str` in record type |
| Function parameter | `/// Docs before param` in multiline arg list |

### 2.6 Parameter Documentation

Function parameters are documented with `///` on the preceding line when the
parameter list is split across lines:

```
/// Creates a greeting message.
pub greet =
  /// The name of the person to greet.
  |name: Str,
  /// How many times to repeat the greeting.
  times: U64|
  -> Str {
    ...
  }
```

---

## 3. Doc Comment Content (Markdown)

### 3.1 Markdown Processing

The content of a `///` doc comment (after stripping the `/// ` prefix) is
CommonMark Markdown. The doc renderer and doctest runner parse this Markdown to
extract structure and code blocks.

**Processing steps:**

1. Strip the `/// ` (or `//# `) prefix from each line.
2. Concatenate lines into a Markdown string.
3. Parse the Markdown into a document tree.
4. Extract fenced code blocks with `camp` language tag (or no tag).
5. Strip `//# ` lines from code blocks for rendering (keep for compilation).

### 3.2 Code Block Structure

A code block inside a doc comment:

```
/// Computes the sum of a list.
///
/// # Examples
///
/// ```camp
/// //# import List
/// 
/// // Sum the numbers 1 through 5
/// result = List.sum([1, 2, 3, 4, 5])
/// expect result == 15
/// ```
pub sum = |list: List(I64)| -> I64 { ... }
```

When the doctest runner processes this:

1. **Extraction**: Strip `/// ` and `//# ` prefixes from code block lines.
2. **Hidden lines**: `//# import List` becomes `import List` in the compiled
   code but is omitted from rendered docs.
3. **Regular comments**: `// Sum the numbers 1 through 5` is both compiled
   (as a Camp comment) and shown in rendered docs.
4. **Compilation**: The extracted code is compiled as a standalone `.camp` file.
5. **Execution**: Since the block contains `expect`, it is executed.

The compiled code becomes:

```camp
import List

// Sum the numbers 1 through 5
result = List.sum([1, 2, 3, 4, 5])
expect result == 15
```

The rendered documentation shows:

```camp
// Sum the numbers 1 through 5
result = List.sum([1, 2, 3, 4, 5])
expect result == 15
```

### 3.3 Code Block Annotations

Annotations are comma-separated after the language tag:

| Annotation | Compile? | Execute? | Must fail? |
|------------|----------|----------|------------|
| (none) | Yes | If has `expect` | No |
| `compile_fail` | Yes | No | Yes |

**`compile_fail` example:**

```
/// You cannot add a string and an integer:
///
/// ```camp,compile_fail
/// x = "hello" + 42
/// ```
```

This code block must fail to compile. If it compiles successfully, the doctest
fails. The specific error message is not checked — any compilation error
suffices.

### 3.4 No Escape Mechanism

There is no way to write literal `///` or `//#` inside a `camp` code block.
If you need to display these tokens in documentation, use a non-`camp`
language tag:

```
/// Camp uses `///` for doc comments:
///
/// ```text
/// /// This is a doc comment
/// ```
```

---

## 4. Doctest Runner Design

### 4.1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     camp test                               │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │  Discovery    │     │  Discovery   │                      │
│  │  (doctests)   │     │  (test blocks)│                     │
│  └──────┬───────┘     └──────┬───────┘                      │
│         │                    │                              │
│  ┌──────▼───────┐     ┌──────▼───────┐                      │
│  │  Markdown    │     │   AST        │                      │
│  │  Parser      │     │   Walker     │                      │
│  └──────┬───────┘     └──────┬───────┘                      │
│         │                    │                              │
│  ┌──────▼────────────────────▼───────┐                      │
│  │         Test Collection           │                      │
│  └──────────────┬───────────────────┘                      │
│                 │                                           │
│  ┌──────────────▼───────────────────┐                      │
│  │     Compilation (debug mode)     │                      │
│  │     Each test → standalone file  │                      │
│  └──────────────┬───────────────────┘                      │
│                 │                                           │
│  ┌──────────────▼───────────────────┐                      │
│  │     Execution (if has expect)    │                      │
│  └──────────────┬───────────────────┘                      │
│                 │                                           │
│  ┌──────────────▼───────────────────┐                      │
│  │     Report: PASS / FAIL / SKIP   │                      │
│  └──────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Doctest Extraction Algorithm

For each `.camp` source file:

1. **Lex** the file, identifying `///` doc comment lines and their attachment targets.
2. **Concatenate** consecutive `///` lines into a single Markdown string per declaration.
3. **Parse** the Markdown string to find fenced code blocks.
4. **For each** code block with `camp` or no language tag:
   a. Strip `/// ` and `//# ` prefixes from each line.
   b. Discard `//#` lines for rendering; keep them for compilation.
   c. Extract the code block as a standalone Camp source string.
   d. Record the source file path and line number for error reporting.
   e. Determine the test mode:
      - `compile_fail` annotation → compile only, must fail
      - Contains `expect` → compile and execute
      - No `expect` → typecheck and lint only

### 4.3 Doctest Compilation

Each extracted code block is compiled as a standalone `.camp` file:

1. Write the code block to a temporary file: `/tmp/camp-doctest/<file>/<line>.camp`.
2. Run `camp build` on the temporary file in **debug mode**.
3. For `compile_fail`: if compilation succeeds, the doctest FAILS.
4. For typecheck-only: if compilation succeeds, the doctest PASSES.
5. For execution: if compilation succeeds, proceed to execution.

### 4.4 Doctest Execution

For code blocks that require execution:

1. Compile the code block to `.wasm`.
2. Execute with `wasmtime` (same as the e2e test runner).
3. If the process exits with code 0, the doctest PASSES.
4. If the process exits nonzero or `todo` is reached (panic), the doctest FAILS.
5. Report the failure with the source file and line number.

### 4.5 Named Test Blocks

`test "name" { body }` declarations are also discovered and executed:

1. **Discovery**: Walk the AST of each `.camp` file for `test` declarations.
2. **Compilation**: Test blocks are compiled as part of the module in debug mode.
3. **Execution**: Each test block runs its body. If any `expect` fails, the test fails.
4. **Production mode**: Test blocks are entirely excluded from production builds.

### 4.6 Parallelism

Doctests and named test blocks run concurrently, each in an isolated temporary
directory (same model as the e2e test runner). Use `runtime.cpu_count()` workers.

---

## 5. `expect` Expression Design

### 5.1 Syntax

```
expect <boolean-expression>
```

`expect` is a keyword followed by a boolean expression. The expression is
evaluated; if `False`, the program fails.

### 5.2 Semantics by Build Mode

| Build mode | Behavior |
|------------|----------|
| Debug | Evaluate the expression. If `False`, panic with "expectation failed". |
| Test | Same as debug. |
| Production | Compile to a no-op. The expression is NOT evaluated. No runtime cost. |

### 5.3 Effect Row Interaction

In debug/test mode, `expect` propagates the effect row of its sub-expression:

```
// This expect's sub-expression performs Console!
expect Console.println!("test") == {}

// Therefore the containing function must include Console! in its effect row
```

In production mode, the entire `expect` is removed, so its effects disappear too.
This is the same tradeoff Rust makes with `debug_assert!`.

### 5.4 AST Representation

`expect` is a new expression variant in the surface and canonical AST:

```odin
CExpr_Expect :: struct {
    condition: CExpr,
    span:      Source_Span,
}
```

During typechecking, the condition must have type `Bool`. The `expect`
expression itself has type `{}` (unit).

In debug mode, `expect` compiles to:
1. Evaluate condition.
2. If `False`, call `camp_expect_failed` (runtime panic).
3. Continue.

In production mode, `expect` compiles to nothing — the IR node is dropped
during lowering.

---

## 6. `test` Named Test Block Design

### 6.1 Syntax

```
test "description" {
    // setup code
    expect some_condition
    expect another_condition
}
```

The `test` keyword is followed by a string literal (the test name) and a block
body. The body can contain any Camp expressions, including `expect`.

### 6.2 Semantics

- In **debug/test mode**: Test blocks are compiled and executed by `camp test`.
- In **production mode**: Test blocks are entirely excluded from the compiled
  output. They do not exist in the WASM binary.

### 6.3 AST Representation

```odin
CDecl_Test :: struct {
    name: string,      // the test description string
    body: CExpr,
    span: Source_Span,
}
```

Test blocks are top-level declarations. They are not accessible as regular
bindings — they exist only for the test runner.

---

## 7. `todo` Placeholder Operator Design

### 7.1 Syntax

```
todo                  -- bare, no message
todo("message")       -- with a custom message
```

`todo` is a keyword. The optional message is a string argument in parentheses.

### 7.2 Type and Effect Row

| Property | Value |
|----------|-------|
| Type | `forall a. a` (universally quantified, unifies with any type) |
| Effect row | Empty (pure) |

The universally quantified type means `todo` can appear wherever any type is
expected. The type checker instantiates the type variable to match the expected
type from context.

The empty effect row means a function containing only `todo` is considered pure.
It does NOT require `!` in its name. This is consistent: panics are not tracked
effects (like divide-by-zero).

### 7.3 Build Mode Behavior

| Build mode | Behavior |
|------------|----------|
| Debug | Compiles. At runtime, if reached, panics with "not yet implemented" or the custom message. |
| Test/Doctest | Same as debug. Doctests always compile in debug mode. |
| Production | Compilation error. `todo` is not allowed in production builds. |

### 7.4 Expression Positions

`todo` can appear in any expression position:

```camp
-- Return value
f = || -> Int { todo }

-- Function argument
some_function(todo, 42)

-- Record field
person = { name: todo, age: 30 }

-- Tag payload
Some(todo)

-- Match arm
match result {
    Ok(n) => n
    Err(_) => todo
}

-- Let binding value
x = todo

-- Type-annotated binding
x: Int = todo

-- Dot lambda chain
.map(todo)
```

### 7.5 Type Inference

`todo` introduces a fresh type variable that is unified with the expected type
from context:

```camp
-- Context expects Int, so todo : Int
f = || -> Int { todo }

-- Context expects Str, so todo : Str
g = || -> Str { todo }

-- Context expects the function return type
h = |x: Int| -> Str { todo }
```

If the expected type cannot be determined (ambiguous context), the type checker
reports an error — same as any other ambiguous type variable.

### 7.6 AST Representation

```odin
CExpr_Todo :: struct {
    message: string,   // empty string if no message provided
    span:    Source_Span,
}
```

During typechecking, `todo` creates a fresh type variable and unifies it with
the expected type. The resulting type is the unified type.

During lowering (debug mode), `todo` becomes a runtime panic:
1. If message is empty: `camp_todo_failed("not yet implemented")`.
2. If message is present: `camp_todo_failed(message)`.

During lowering (production mode), the compiler emits an error diagnostic:
`todo is not allowed in production builds`.

### 7.7 Interaction with Effectful Functions

```camp
-- Pure function with todo: no ! required
compute = || -> Int { todo }

-- Effectful function with todo: ! required because of Console!, not todo
compute! = || -[Console!]-> Int {
    Console.println!("debugging")
    todo
}
```

`todo` does not add effects. The `!` suffix rule is determined solely by the
effect row, which `todo` does not modify.

---

## 8. `camp doc` Documentation Generator

### 8.1 Output Format

`camp doc` generates HTML documentation:

1. **Index page**: List of all modules with module doc summaries.
2. **Module pages**: Full documentation for each module, including:
   - Module doc comment
   - All public declarations with their doc comments
   - Type signatures alongside documentation
   - Rendered code examples (with `//#` lines stripped)

### 8.2 Code Example Rendering

In generated HTML, code blocks are:

1. Syntax-highlighted (CSS classes for token types).
2. `//#` lines are stripped — they do not appear.
3. `//` comments within code blocks are shown normally.
4. `expect` expressions are shown (they're part of the example).

### 8.3 Cross-References

Markdown links in doc comments can reference other declarations:

```
/// See [List.map] for mapping over lists.
```

The doc generator resolves these to hyperlinks. Unresolved references produce
a warning.

---

## 9. LSP Integration

### 9.1 Hover Information

When the user hovers over a symbol, the LSP returns:

1. The symbol's fully qualified name.
2. The type signature.
3. The rendered Markdown doc comment (with `//#` lines stripped from code blocks).

### 9.2 Go-to-Definition for Doc References

`[List.map]` style references in doc comments are resolved by the LSP for
go-to-definition support.

---

## 10. Implementation Plan

### Phase 1: Comment Syntax Migration

**Scope**: Lexer + formatter + existing test updates.

1. Change lexer: `//` is a comment, `///` is a doc comment, `//#` is a
   hidden-line doc prefix.
2. Update `format_source.odin`: `collect_comments` detects `//`/`///`/`//#`.
3. Update `Comment_Info` struct: `is_doc` detection based on `///`.
4. Update all e2e snapshot tests: `--` → `//`, `---` → `///`.
5. Update kitchen-sink test.
6. Verify: `just test` passes.

**Estimated scope**: ~30 lines in lexer, ~20 lines in formatter, test updates.

### Phase 2: Doc Comments in AST

**Scope**: Parser + canonical AST + typechecker.

1. Add `doc_comment: string` field to relevant AST declaration nodes.
2. Parse `///` lines and attach to the next declaration during parsing.
3. Handle module doc comment (first `///` in file).
4. Handle parameter doc comments (multiline arg lists).
5. Validate: `//#` outside code blocks is a compiler error.
6. Thread doc comments through canonicalization.

**Estimated scope**: ~50 lines in parser, ~20 lines in AST structs, ~30 lines
in validation.

### Phase 3: `todo` Operator

**Scope**: Lexer + parser + typechecker + lowering + codegen.

1. Add `todo` keyword to lexer.
2. Add `CExpr_Todo` to surface and canonical AST.
3. Typechecker: `todo` creates a fresh type variable, unifies with expected
   type, empty effect row.
4. Lowering (debug): `todo` → runtime panic call.
5. Lowering (production): `todo` → compiler error diagnostic.
6. Add `camp_todo_failed` runtime stub.

**Estimated scope**: ~40 lines across lexer/parser/AST, ~30 lines in
typechecker, ~20 lines in lowering, ~5 lines runtime.

### Phase 4: `expect` Expression

**Scope**: Lexer + parser + typechecker + lowering + codegen.

1. Add `expect` keyword to lexer.
2. Add `CExpr_Expect` to surface and canonical AST.
3. Typechecker: condition must be `Bool`, result type is `{}`.
4. Lowering (debug/test): evaluate condition, panic if `False`.
5. Lowering (production): drop the entire node.
6. Add `camp_expect_failed` runtime stub.

**Estimated scope**: ~30 lines across lexer/parser/AST, ~20 lines in
typechecker, ~15 lines in lowering, ~5 lines runtime.

### Phase 5: `test` Named Test Blocks

**Scope**: Lexer + parser + typechecker + lowering.

1. Add `test` keyword to lexer.
2. Add `CDecl_Test` to surface and canonical AST.
3. Typechecker: typecheck the body like a function body.
4. Lowering (production): skip test blocks entirely.
5. Lowering (debug/test): generate a callable test function.

**Estimated scope**: ~30 lines across lexer/parser/AST, ~20 lines in
typechecker, ~15 lines in lowering.

### Phase 6: Doctest Runner

**Scope**: New `camp test` command + doctest extraction.

1. Extract `///` doc comments from parsed AST.
2. Parse Markdown in doc comments to find fenced code blocks.
3. Extract `camp` (and unannotated) code blocks.
4. Strip `///` and `//#` prefixes from code block lines.
5. Write each code block to a temporary `.camp` file.
6. Compile each file (debug mode) via `camp build`.
7. Execute code blocks with `expect` via wasmtime.
8. Report pass/fail with file+line identification.
9. Discover and run `test` named test blocks.
10. Parallel execution with isolated temp directories.

**Estimated scope**: ~300-400 lines in a new `src/doctest/` package or
extension of `src/e2e/`.

### Phase 7: Documentation Generator

**Scope**: New `camp doc` command.

1. Collect all doc comments from parsed modules.
2. Render Markdown to HTML (use a minimal Markdown→HTML converter).
3. Generate module index and per-module pages.
4. Syntax-highlight code blocks (reuse lexer tokens).
5. Strip `//#` lines from rendered code examples.
6. Resolve cross-references (`[Symbol]` links).

**Estimated scope**: ~500-700 lines in a new `src/doc/` package.

### Phase 8: LSP Hover Integration

**Scope**: LSP server extension.

1. Store doc comments in the symbol index during typechecking.
2. On hover request: look up the symbol's doc comment and type signature.
3. Return both as Markdown content in the LSP hover response.

**Estimated scope**: ~40 lines in the LSP server.

---

## 11. Open Questions and Future Work

### 11.1 Deferred Decisions

| Decision | Status | Notes |
|----------|--------|-------|
| `no_run` annotation | Deferred | Can be added when side-effect-heavy examples become common |
| `ignore` annotation | Deferred | Use ```` ```text ```` for non-tested examples |
| `should_error` annotation | Deferred | Can be added when runtime-failure examples are needed |
| Named code blocks | Deferred | Identified by file+line for now; names can be added later |
| Effect-aware `todo` | Deferred | Pure `todo` is simpler; `Todo!` effect can be added if needed |
| Type-level holes | Deferred | `todo` is expression-only; type holes are future work |
| Cross-module doc resolution | Deferred | `[Symbol]` links resolve within the project; cross-package is future |
| Search in docs | Deferred | `camp doc` generates static HTML; search is a future enhancement |

### 11.2 Future Enhancements

- **Interactive `todo` in LSP**: Show the expected type when hovering over
  `todo` — requires threading the expected type through the typechecker.
- **Doc comment linting**: Warn when a public declaration lacks a doc comment.
- **Doc coverage reporting**: Report what percentage of public API is documented.
- **`todo` count in test output**: Report the number of `todo`s in the codebase
  as a reminder of incomplete work.
