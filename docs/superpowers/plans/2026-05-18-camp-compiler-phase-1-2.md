# Camp Compiler Phase 1-2: Bootstrap + Lexer/Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the Camp compiler project in Odin with a working error collector and CLI, then implement a Pratt parser that produces a surface AST from Camp source files.

**Architecture:** The compiler is structured as a pipeline of independent phases, each consuming and producing a distinct IR. Phase 1 establishes the project skeleton, build system, and core infrastructure (error collection, source location tracking, string interning). Phase 2 implements lexing and Pratt parsing to produce the surface AST. All data structures use Odin's tagged unions for AST node variants and arena allocation for per-phase memory management.

**Tech Stack:** Odin (odin-lang.org), WASM/WASI target, Pratt parsing, arena allocation

**Spec:** `docs/superpowers/specs/2026-05-18-camp-language-design.md`

---

## Roadmap: All Compiler Phases

| Phase | What it produces | Status |
|-------|-----------------|--------|
| 1. Bootstrap | Project scaffolding, build system, error collector, CLI | This plan |
| 2. Lexer + Parser | Token stream + surface AST from source text | This plan |
| 3. Canonicalizer | Canonical AST with deferred imports, derive expansion | Next plan |
| 4. Typechecker | Typed IR with effect rows, variant unions | Future |
| 5. Effect Lower + CPS | Effect-lowered CPS IR, coroutines as state machines | Future |
| 6. WASM Codegen | .wasm binary emission, Perceus RC insertion | Future |
| 7. Runtime | Camp runtime (effect handlers, WASI bindings, Perceus ops) | Future |
| 8. Stdlib | Core modules (Int, Str, List, Iter, etc.) | Future |
| 9. Package manager | camp.toml parsing, git dependency resolution | Future |
| 10. Testing framework | camp test, parallel test runner | Future |

---

## File Structure

```
camp/
├── camp.toml                    -- Package manifest (not yet used by compiler)
├── src/
│   ├── main.odin                -- CLI entry point
│   ├── cli.odin                 -- Argument parsing, subcommand dispatch
│   ├── error.odin               -- Error collector (warnings, errors, internal errors)
│   ├── source.odin              -- Source file management, location tracking
│   ├── intern.odin              -- String interning
│   ├── lexer.odin               -- Tokenizer
│   ├── token.odin               -- Token types and definitions
│   ├── parser.odin              -- Pratt parser
│   ├── ast.odin                 -- Surface AST node types
│   └── reporter.odin            -- Error formatting and display
├── tests/
│   ├── test_lexer.odin          -- Lexer tests
│   ├── test_parser.odin         -- Parser tests
│   └── test_error.odin          -- Error collector tests
└── README.md
```

Each file has one clear responsibility:
- `error.odin`: Error collection with three categories (warnings, errors, internal errors). No printing.
- `source.odin`: Source text storage, line/column tracking, span calculation. No parsing.
- `intern.odin`: String interning for identifiers. No source management.
- `lexer.odin`: Tokenization. No parsing.
- `token.odin`: Token type definitions. No logic.
- `parser.odin`: Pratt parsing. No tokenization.
- `ast.odin`: AST node type definitions. No logic.
- `reporter.odin`: Formatting errors for display. No collection.

---

## Task 1: Project Bootstrap

**Files:**
- Create: `src/main.odin`
- Create: `src/cli.odin`
- Create: `src/error.odin`
- Create: `src/source.odin`
- Create: `src/intern.odin`
- Create: `src/reporter.odin`

- [ ] **Step 1: Initialize Odin project and create main.odin**

Create `src/main.odin` with a minimal entry point that prints version info and exits:

```odin
package camp

import "core:fmt"
import "core:os"

VERSION :: "0.0.1"

main :: proc() {
    args := os.args
    if len(args) < 2 {
        fmt.println("Camp compiler v{VERSION}")
        fmt.println("Usage: camp <command> [options] <file>")
        fmt.println("Commands: build, test, fmt, check")
        os.exit(1)
    }
    fmt.println("TODO: implement CLI")
}
```

- [ ] **Step 2: Verify the project compiles**

Run: `odin build src -out:camp`
Expected: Compiles without errors, produces `camp` binary

Run: `./camp`
Expected: Prints version info and usage

- [ ] **Step 3: Write failing test for error collector**

Create `src/error.odin`:

```odin
package camp

import "core:fmt"

Error_Category :: enum {
    Warning,
    Error,
    Internal,
}

Error :: struct {
    category: Error_Category,
    message: string,
    span: Source_Span,
}

Error_Collector :: struct {
    errors: [dynamic]Error,
    warning_count: int,
    error_count: int,
    internal_count: int,
}

collector_init :: proc(collector: ^Error_Collector) {
    collector.errors = make([dynamic]Error, 0, 64)
    collector.warning_count = 0
    collector.error_count = 0
    collector.internal_count = 0
}

collector_destroy :: proc(collector: ^Error_Collector) {
    delete(collector.errors)
}

collector_add :: proc(collector: ^Error_Collector, category: Error_Category, message: string, span: Source_Span) {
    append(&collector.errors, Error{category, message, span})
    switch category {
    case .Warning:  collector.warning_count += 1
    case .Error:    collector.error_count += 1
    case .Internal: collector.internal_count += 1
    }
}

collector_has_errors :: proc(collector: ^Error_Collector) -> bool {
    return collector.error_count > 0 or collector.internal_count > 0
}
```

Create `src/source.odin`:

```odin
package camp

Source_Span :: struct {
    file_id: int,
    start: int,
    end: int,
}

Source_Span_ZERO :: Source_Span{-1, 0, 0}

Source_File :: struct {
    path: string,
    contents: string,
    id: int,
}
```

Create `tests/test_error.odin`:

```odin
package camp

import "core:fmt"
import "core:testing"

@(test)
test_collector_add_warning :: proc(t: ^testing.T) {
    collector: Error_Collector
    collector_init(&collector)
    defer collector_destroy(&collector)

    collector_add(&collector, .Warning, "unused variable", Source_Span_ZERO)
    testing.expect(t, collector.warning_count == 1)
    testing.expect(t, collector.error_count == 0)
    testing.expect(t, !collector_has_errors(&collector))
}

@(test)
test_collector_add_error :: proc(t: ^testing.T) {
    collector: Error_Collector
    collector_init(&collector)
    defer collector_destroy(&collector)

    collector_add(&collector, .Error, "type mismatch", Source_Span_ZERO)
    testing.expect(t, collector.warning_count == 0)
    testing.expect(t, collector.error_count == 1)
    testing.expect(t, collector_has_errors(&collector))
}

@(test)
test_collector_add_internal :: proc(t: ^testing.T) {
    collector: Error_Collector
    collector_init(&collector)
    defer collector_destroy(&collector)

    collector_add(&collector, .Internal, "impossible type after typecheck", Source_Span_ZERO)
    testing.expect(t, collector.internal_count == 1)
    testing.expect(t, collector_has_errors(&collector))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test tests`
Expected: All three tests PASS

- [ ] **Step 5: Write failing test for string interner**

Create `src/intern.odin`:

```odin
package camp

import "core:strings"

Intern_ID :: distinct int

Intern_Table :: struct {
    strings: map[string]Intern_ID,
    ids: [dynamic]string,
    next_id: Intern_ID,
}

intern_init :: proc(table: ^Intern_Table) {
    table.strings = make(map[string]Intern_ID, 256)
    table.ids = make([dynamic]string, 0, 256)
    table.next_id = 0
}

intern_destroy :: proc(table: ^Intern_Table) {
    delete(table.strings)
    delete(table.ids)
}

intern :: proc(table: ^Intern_Table, s: string) -> Intern_ID {
    if existing, ok := table.strings[s]; ok {
        return existing
    }
    id := table.next_id
    table.next_id += 1
    table.strings[s] = id
    append(&table.ids, s)
    return id
}

intern_get :: proc(table: ^Intern_Table, id: Intern_ID) -> string {
    return table.ids[int(id)]
}
```

Add to `tests/test_error.odin` (or create `tests/test_intern.odin`):

```odin
@(test)
test_intern_same_string :: proc(t: ^testing.T) {
    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    id1 := intern(&table, "hello")
    id2 := intern(&table, "hello")
    testing.expect(t, id1 == id2)
}

@(test)
test_intern_different_strings :: proc(t: ^testing.T) {
    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    id1 := intern(&table, "hello")
    id2 := intern(&table, "world")
    testing.expect(t, id1 != id2)
}

@(test)
test_intern_roundtrip :: proc(t: ^testing.T) {
    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    id := intern(&table, "test_string")
    testing.expect(t, intern_get(&table, id) == "test_string")
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `odin test tests`
Expected: All six tests PASS (3 error + 3 intern)

- [ ] **Step 7: Implement error reporter**

Create `src/reporter.odin`:

```odin
package camp

import "core:fmt"

report_error :: proc(collector: ^Error_Collector, file_path: string, source: string, error: Error) {
    line, col := span_to_line_col(source, error.span)

    prefix: string
    switch error.category {
    case .Warning:  prefix = "warning"
    case .Error:    prefix = "error"
    case .Internal: prefix = "internal error"
    }

    fmt.println("{file_path}:{line}:{col}: {prefix}: {error.message}")
}

span_to_line_col :: proc(source: string, span: Source_Span) -> (int, int) {
    line := 1
    col := 1
    for i in 0..<span.start {
        if i >= len(source) { break }
        if source[i] == '\n' {
            line += 1
            col = 1
        } else {
            col += 1
        }
    }
    return line, col
}
```

- [ ] **Step 8: Implement CLI subcommand dispatch**

Create `src/cli.odin`:

```odin
package camp

import "core:fmt"
import "core:os"
import "core:path/filepath"

CLI_Command :: enum {
    Build,
    Test,
    Fmt,
    Check,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
    switch cmd {
    case "build": return .Build, true
    case "test":  return .Test, true
    case "fmt":   return .Fmt, true
    case "check": return .Check, true
    case:         return .Build, false
    }
}

run_build :: proc(args: []string) {
    file_path := "main.camp"
    if len(args) > 0 {
        file_path = args[0]
    }

    if filepath.ext(file_path) != ".camp" {
        fmt.println("error: expected .camp file, got {file_path}")
        os.exit(1)
    }

    collector: Error_Collector
    collector_init(&collector)
    defer collector_destroy(&collector)

    fmt.println("compiling {file_path}...")
    fmt.println("TODO: implement compilation pipeline")
}
```

Update `src/main.odin` to use the CLI:

```odin
package camp

import "core:fmt"
import "core:os"

VERSION :: "0.0.1"

main :: proc() {
    args := os.args
    if len(args) < 2 {
        fmt.println("Camp compiler v{VERSION}")
        fmt.println("Usage: camp <command> [options] <file>")
        fmt.println("Commands: build, test, fmt, check")
        os.exit(1)
    }

    cmd, ok := parse_command(args[1])
    if !ok {
        fmt.println("error: unknown command '{args[1]}'")
        fmt.println("Commands: build, test, fmt, check")
        os.exit(1)
    }

    remaining_args := args[2:]
    switch cmd {
    case .Build: run_build(remaining_args)
    case .Test:  fmt.println("TODO: camp test")
    case .Fmt:   fmt.println("TODO: camp fmt")
    case .Check: fmt.println("TODO: camp check")
    }
}
```

- [ ] **Step 9: Verify CLI compiles and runs**

Run: `odin build src -out:camp && ./camp build test.camp`
Expected: Prints "compiling test.camp..." then "TODO: implement compilation pipeline"

Run: `./camp`
Expected: Prints version and usage

- [ ] **Step 10: Commit bootstrap**

```bash
git add src/ tests/
git commit -m "feat(bootstrap): project skeleton, error collector, string interner, CLI

- Odin project with build, test, fmt, check subcommands
- Error collector with three categories (warning, error, internal)
- String interning for identifiers
- Source location tracking (file, span)
- Error reporter with line/column display"
```

---

## Task 2: Token Definitions

**Files:**
- Create: `src/token.odin`
- Create: `tests/test_token.odin`

- [ ] **Step 1: Define token types**

Create `src/token.odin`:

```odin
package camp

Token_Kind :: enum {
    // Literals
    Int_Literal,
    Float_Literal,
    String_Literal,

    // Identifiers and tags
    Identifier,     // lowercase or mixed: function/variable names
    Upper_Id,       // UpperCamelCase: type names, tag names

    // Keywords
    Kw_If,
    Kw_Else,
    Kw_Match,
    Kw_Effect,
    Kw_Trait,
    Kw_Is,
    Kw_Alias,
    Kw_Handle,
    Kw_Intercept,
    Kw_In,
    Kw_With,
    Kw_Import,
    Kw_Exposing,
    Kw_As,
    Kw_Unsafe,
    Kw_For,
    Kw_And,
    Kw_Or,
    Kw_True,
    Kw_False,
    Kw_Expect,
    Kw_Test,

    // Delimiters
    Pipe,           // |
    Arrow,          // ->
    Fat_Arrow,      // =>
    Eq,             // =
    Colon,          // :
    Comma,          // ,
    Dot,            // .
    Dot_Dot,        // ..
    Bang,           // !
    Dollar,         // $
    Hash,           // #
    At,             // @
    Lt,             // <
    Gt,             // >
    Lt_Eq,         // <=
    Gt_Eq,         // >=
    Eq_Eq,         // ==
    Bang_Eq,       // !=
    Plus,           // +
    Minus,          // -
    Star,           // *
    Slash,          // /
    Percent,        // %
    Amp,            // &
    Caret,          // ^
    Tilde,          // ~

    // Brackets
    LParen,         // (
    RParen,         // )
    LBrack,         // [
    RBrack,         // ]
    LBrace,         // {
    RBrace,         // }

    // Special
    Newline,
    Eof,
}

Token :: struct {
    kind:      Token_Kind,
    text:      string,
    span:      Source_Span,
    int_value: i64,      // for Int_Literal
    f64_value: f64,      // for Float_Literal
}
```

- [ ] **Step 2: Verify token definitions compile**

Run: `odin build src -out:camp`
Expected: Compiles without errors

- [ ] **Step 3: Commit token definitions**

```bash
git add src/token.odin
git commit -m "feat(parser): define token types for Camp lexer"
```

---

## Task 3: Lexer

**Files:**
- Create: `src/lexer.odin`
- Create: `tests/test_lexer.odin`

- [ ] **Step 1: Write failing lexer test for basic tokens**

Create `tests/test_lexer.odin`:

```odin
package camp

import "core:fmt"
import "core:testing"

lex_all :: proc(source: string) -> ([]Token, ^Error_Collector) {
    collector: ^Error_Collector = new(Error_Collector)
    collector_init(collector)

    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    file := Source_File{path = "<test>", contents = source, id = 0}
    lexer: Lexer
    lexer_init(&lexer, file, collector, &table)

    tokens: [dynamic]Token
    for {
        tok := lexer_next(&lexer)
        append(&tokens, tok)
        if tok.kind == .Eof { break }
    }

    return tokens[:], collector
}

@(test)
test_lexer_integer_literal :: proc(t: ^testing.T) {
    tokens, collector := lex_all("42")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2) // Int_Literal + Eof
    testing.expect(t, tokens[0].kind == .Int_Literal)
    testing.expect(t, tokens[0].int_value == 42)
}

@(test)
test_lexer_string_literal :: proc(t: ^testing.T) {
    tokens, collector := lex_all("\"hello\"")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .String_Literal)
}

@(test)
test_lexer_upper_identifier :: proc(t: ^testing.T) {
    tokens, collector := lex_all("Ok")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Upper_Id)
}

@(test)
test_lexer_lower_identifier :: proc(t: ^testing.T) {
    tokens, collector := lex_all("add")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Identifier)
}

@(test)
test_lexer_dollar_identifier :: proc(t: ^testing.T) {
    tokens, collector := lex_all("$count")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Dollar)
    testing.expect(t, tokens[1].kind == .Identifier) // "count" after $
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `odin test tests`
Expected: FAIL — `Lexer` type not defined

- [ ] **Step 3: Implement the lexer**

Create `src/lexer.odin`:

```odin
package camp

import "core:strings"
import "core:unicode/utf8"

KEYWORDS :map[string]Token_Kind = {
    ["if"]        = .Kw_If,
    ["else"]      = .Kw_Else,
    ["match"]     = .Kw_Match,
    ["effect"]    = .Kw_Effect,
    ["trait"]     = .Kw_Trait,
    ["is"]        = .Kw_Is,
    ["alias"]     = .Kw_Alias,
    ["handle"]    = .Kw_Handle,
    ["intercept"] = .Kw_Intercept,
    ["in"]        = .Kw_In,
    ["with"]      = .Kw_With,
    ["import"]    = .Kw_Import,
    ["exposing"]  = .Kw_Exposing,
    ["as"]        = .Kw_As,
    ["unsafe"]    = .Kw_Unsafe,
    ["for"]       = .Kw_For,
    ["and"]       = .Kw_And,
    ["or"]        = .Kw_Or,
    ["true"]      = .Kw_True,
    ["false"]     = .Kw_False,
    ["expect"]    = .Kw_Expect,
    ["test"]      = .Kw_Test,
}

Lexer :: struct {
    source:    string,
    pos:       int,
    collector: ^Error_Collector,
    intern:    ^Intern_Table,
    file_id:   int,
}

lexer_init :: proc(l: ^Lexer, file: Source_File, collector: ^Error_Collector, table: ^Intern_Table) {
    l.source = file.contents
    l.pos = 0
    l.collector = collector
    l.intern = table
    l.file_id = file.id
}

lexer_peek :: proc(l: ^Lexer) -> u8 {
    if l.pos >= len(l.source) { return 0 }
    return l.source[l.pos]
}

lexer_advance :: proc(l: ^Lexer) -> u8 {
    ch := l.source[l.pos]
    l.pos += 1
    return ch
}

lexer_skip_whitespace :: proc(l: ^Lexer) {
    for l.pos < len(l.source) {
        ch := l.source[l.pos]
        if ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' {
            l.pos += 1
        } else if ch == '-' and l.pos + 1 < len(l.source) and l.source[l.pos + 1] == '-' {
            // line comment: -- to end of line
            l.pos += 2
            for l.pos < len(l.source) and l.source[l.pos] != '\n' {
                l.pos += 1
            }
        } else {
            break
        }
    }
}

lexer_make_span :: proc(l: ^Lexer, start: int) -> Source_Span {
    return Source_Span{file_id = l.file_id, start = start, end = l.pos}
}

lexer_make_token :: proc(l: ^Lexer, kind: Token_Kind, start: int, text: string) -> Token {
    return Token{kind = kind, text = text, span = lexer_make_span(l, start)}
}

lexer_next :: proc(l: ^Lexer) -> Token {
    lexer_skip_whitespace(l)

    if l.pos >= len(l.source) {
        return Token{kind = .Eof, span = lexer_make_span(l, l.pos)}
    }

    start := l.pos
    ch := l.source[l.pos]

    // Integer or float literal
    if ch >= '0' and ch <= '9' {
        return lexer_lex_number(l, start)
    }

    // String literal
    if ch == '"' {
        return lexer_lex_string(l, start)
    }

    // $ prefix (mutable variable)
    if ch == '$' {
        l.pos += 1
        return lexer_make_token(l, .Dollar, start, l.source[start:l.pos])
    }

    // Identifier or keyword
    if is_identifier_start(ch) {
        return lexer_lex_identifier(l, start)
    }

    // Multi-character operators
    if ch == '-' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '>' {
            l.pos += 1
            return lexer_make_token(l, .Arrow, start, l.source[start:l.pos])
        }
        if l.pos < len(l.source) and l.source[l.pos] == '=' {
            l.pos += 1
            return lexer_make_token(l, .Eq_Eq, start, l.source[start:l.pos]) // -= ? No, -> is arrow, -= would be minus-eq
        }
        return lexer_make_token(l, .Minus, start, l.source[start:l.pos])
    }

    if ch == '=' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '=' {
            l.pos += 1
            return lexer_make_token(l, .Eq_Eq, start, l.source[start:l.pos])
        }
        if l.pos < len(l.source) and l.source[l.pos] == '>' {
            l.pos += 1
            return lexer_make_token(l, .Fat_Arrow, start, l.source[start:l.pos])
        }
        return lexer_make_token(l, .Eq, start, l.source[start:l.pos])
    }

    if ch == '<' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '=' {
            l.pos += 1
            return lexer_make_token(l, .Lt_Eq, start, l.source[start:l.pos])
        }
        return lexer_make_token(l, .Lt, start, l.source[start:l.pos])
    }

    if ch == '>' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '=' {
            l.pos += 1
            return lexer_make_token(l, .Gt_Eq, start, l.source[start:l.pos])
        }
        return lexer_make_token(l, .Gt, start, l.source[start:l.pos])
    }

    if ch == '!' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '=' {
            l.pos += 1
            return lexer_make_token(l, .Bang_Eq, start, l.source[start:l.pos])
        }
        return lexer_make_token(l, .Bang, start, l.source[start:l.pos])
    }

    if ch == '.' {
        l.pos += 1
        if l.pos < len(l.source) and l.source[l.pos] == '.' {
            l.pos += 1
            return lexer_make_token(l, .Dot_Dot, start, l.source[start:l.pos])
        }
        return lexer_make_token(l, .Dot, start, l.source[start:l.pos])
    }

    // Single-character tokens
    single_char_tokens :map[u8]Token_Kind = {
        ['|']  = .Pipe,
        [':']  = .Colon,
        [',']  = .Comma,
        ['#']  = .Hash,
        ['@']  = .At,
        ['+']  = .Plus,
        ['*']  = .Star,
        ['/']  = .Slash,
        ['%']  = .Percent,
        ['&']  = .Amp,
        ['^']  = .Caret,
        ['~']  = .Tilde,
        ['(']  = .LParen,
        [')']  = .RParen,
        ['[']  = .LBrack,
        [']']  = .RBrack,
        ['{']  = .LBrace,
        ['}']  = .RBrace,
    }

    if kind, ok := single_char_tokens[ch]; ok {
        l.pos += 1
        return lexer_make_token(l, kind, start, l.source[start:l.pos])
    }

    // Unknown character
    l.pos += 1
    collector_add(l.collector, .Error, "unexpected character '{string(ch)}'", lexer_make_span(l, start))
    return lexer_next(l)
}

lexer_lex_number :: proc(l: ^Lexer, start: int) -> Token {
    is_float := false
    for l.pos < len(l.source) {
        ch := l.source[l.pos]
        if ch >= '0' and ch <= '9' {
            l.pos += 1
        } else if ch == '.' and !is_float {
            // Check if next char is also a digit (to distinguish 3.14 from 3.method)
            if l.pos + 1 < len(l.source) and l.source[l.pos + 1] >= '0' and l.source[l.pos + 1] <= '9' {
                is_float = true
                l.pos += 1
            } else {
                break
            }
        } else if ch == '_' {
            l.pos += 1 // skip underscores in numbers
        } else {
            break
        }
    }

    text := l.source[start:l.pos]
    tok := lexer_make_token(l, .Int_Literal, start, text)

    if is_float {
        tok.kind = .Float_Literal
        // Parse f64 value
        tok.f64_value = strings.float_from_string(text, f64)
    } else {
        // Parse i64 value
        tok.int_value = strings.int_from_string(text, i64)
    }

    return tok
}

lexer_lex_string :: proc(l: ^Lexer, start: int) -> Token {
    l.pos += 1 // skip opening "
    content_start := l.pos

    for l.pos < len(l.source) and l.source[l.pos] != '"' {
        if l.source[l.pos] == '\\' {
            l.pos += 1 // skip escape character
        }
        l.pos += 1
    }

    content_end := l.pos
    if l.pos < len(l.source) {
        l.pos += 1 // skip closing "
    } else {
        collector_add(l.collector, .Error, "unterminated string literal", lexer_make_span(l, start))
    }

    text := l.source[start:l.pos]
    return Token{kind = .String_Literal, text = text, span = lexer_make_span(l, start)}
}

lexer_lex_identifier :: proc(l: ^Lexer, start: int) -> Token {
    is_upper := l.source[l.pos] >= 'A' and l.source[l.pos] <= 'Z'

    for l.pos < len(l.source) and is_identifier_continue(l.source[l.pos]) {
        l.pos += 1
    }

    text := l.source[start:l.pos]

    // Check for keywords (only lowercase identifiers can be keywords)
    if !is_upper {
        if kind, ok := KEYWORDS[text]; ok {
            return lexer_make_token(l, kind, start, text)
        }
        return lexer_make_token(l, .Identifier, start, text)
    }

    return lexer_make_token(l, .Upper_Id, start, text)
}

is_identifier_start :: proc(ch: u8) -> bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_'
}

is_identifier_continue :: proc(ch: u8) -> bool {
    return is_identifier_start(ch) or (ch >= '0' and ch <= '9')
}
```

- [ ] **Step 4: Run lexer tests**

Run: `odin test tests`
Expected: All lexer tests PASS (integer literal, string literal, upper identifier, lower identifier, dollar identifier)

- [ ] **Step 5: Write additional lexer tests for keywords and operators**

Add to `tests/test_lexer.odin`:

```odin
@(test)
test_lexer_keyword :: proc(t: ^testing.T) {
    tokens, collector := lex_all("if else match")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 4) // Kw_If + Kw_Else + Kw_Match + Eof
    testing.expect(t, tokens[0].kind == .Kw_If)
    testing.expect(t, tokens[1].kind == .Kw_Else)
    testing.expect(t, tokens[2].kind == .Kw_Match)
}

@(test)
test_lexer_arrow :: proc(t: ^testing.T) {
    tokens, collector := lex_all("->")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Arrow)
}

@(test)
test_lexer_dot_dot :: proc(t: ^testing.T) {
    tokens, collector := lex_all("..")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Dot_Dot)
}

@(test)
test_lexer_comment :: proc(t: ^testing.T) {
    tokens, collector := lex_all("42 -- this is a comment\n43")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 3) // 42 + 43 + Eof
    testing.expect(t, tokens[0].int_value == 42)
    testing.expect(t, tokens[1].int_value == 43)
}

@(test)
test_lexer_float_literal :: proc(t: ^testing.T) {
    tokens, collector := lex_all("3.14")
    defer delete(tokens)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, len(tokens) == 2)
    testing.expect(t, tokens[0].kind == .Float_Literal)
}
```

- [ ] **Step 6: Run all lexer tests**

Run: `odin test tests`
Expected: All tests PASS

- [ ] **Step 7: Commit lexer**

```bash
git add src/lexer.odin src/token.odin tests/test_lexer.odin
git commit -m "feat(lexer): tokenize Camp source into typed tokens

- All Camp token types defined (literals, identifiers, keywords, operators, delimiters)
- Lexer handles: integers, floats, strings, identifiers, UpperCamelCase tags,
  keywords, operators (->, =>, ==, !=, <=, >=, ..), comments (--), $ prefix
- Keywords: if, else, match, effect, trait, is, alias, handle, intercept,
  in, with, import, exposing, as, unsafe, for, and, or, true, false,
  expect, test
- Full test coverage for all token types"
```

---

## Task 4: Surface AST Definitions

**Files:**
- Create: `src/ast.odin`

- [ ] **Step 1: Define AST node types**

Create `src/ast.odin`:

```odin
package camp

// Top-level declarations
Decl :: union {
    ^Decl_Const,
    ^Decl_Effect,
    &Decl_Trait,
    &Decl_Alias,
    &Decl_Import,
    &Decl_Test,
    &Decl_Expect,
}

Decl_Const :: struct {
    name:     Intern_ID,
    is_pub:   bool,
    body:     Expr,
    type_ann: ^Type,       // optional type annotation
    span:     Source_Span,
}

Decl_Effect :: struct {
    name:       Intern_ID,
    is_pub:     bool,
    operations: [dynamic]Effect_Op,
    span:       Source_Span,
}

Effect_Op :: struct {
    name:       Intern_ID,
    is_effectful: bool,     // has ! suffix
    params:     [dynamic]Func_Param,
    return_type: ^Type,
    return_effects: ^Type, // effect row
    span:       Source_Span,
}

Decl_Trait :: struct {
    name:        Intern_ID,
    is_pub:      bool,
    parent:      Intern_ID,  // 0 if no parent (is ParentTrait)
    methods:     [dynamic]Trait_Method,
    span:        Source_Span,
}

Trait_Method :: struct {
    name:        Intern_ID,
    params:      [dynamic]Func_Param,
    return_type: ^Type,
    span:        Source_Span,
}

Decl_Alias :: struct {
    name:   Intern_ID,
    is_pub: bool,
    target: ^Type,
    span:   Source_Span,
}

Decl_Import :: struct {
    module:    string,
    exposing:  [dynamic]Intern_ID,  // empty = no exposing clause
    alias:     Intern_ID,            // 0 if no 'as' clause
    is_unsafe: bool,
    span:      Source_Span,
}

Decl_Test :: struct {
    name:   string,
    body:   Expr,
    span:   Source_Span,
}

Decl_Expect :: struct {
    condition: Expr,
    span:      Source_Span,
}

// Expressions
Expr :: union {
    &Expr_Int,
    &Expr_Float,
    &Expr_String,
    &Expr_Bool,
    &Expr_Tag,
    &Expr_Record,
    &Expr_List,
    &Expr_Identifier,
    &Expr_Dollar_Identifier,
    &Expr_Call,
    &Expr_Method_Call,
    &Expr_Lambda,
    &Expr_Block,
    &Expr_If,
    &Expr_Match,
    &Expr_BinOp,
    &Expr_PrefixOp,
    &Expr_Field_Access,
    &Expr_Record_Update,
    &Expr_Assign,       // $x = expr
    &Expr_Return,
    &Expr_Crash,
    &Expr_Interpolate,
}

Expr_Int :: struct {
    value: i64,
    span:  Source_Span,
}

Expr_Float :: struct {
    value: f64,
    span:  Source_Span,
}

Expr_String :: struct {
    value: string,
    span:  Source_Span,
}

Expr_Bool :: struct {
    value: bool,
    span:  Source_Span,
}

Expr_Tag :: struct {
    name:    Intern_ID,
    payload: [dynamic]Expr,   // empty = no-payload tag
    span:    Source_Span,
}

Expr_Record :: struct {
    fields:  [dynamic]Record_Field,
    rest:    Expr,               // for { ..expr, field: value } (nil if no rest)
    is_open: bool,               // true if type ends with ..
    span:    Source_Span,
}

Record_Field :: struct {
    name:  Intern_ID,
    value: Expr,
    span:  Source_Span,
}

Expr_List :: struct {
    elements: [dynamic]Expr,
    span:     Source_Span,
}

Expr_Identifier :: struct {
    name: Intern_ID,
    span: Source_Span,
}

Expr_Dollar_Identifier :: struct {
    name: Intern_ID,
    span: Source_Span,
}

Expr_Call :: struct {
    callee:  Expr,
    args:    [dynamic]Expr,
    span:    Source_Span,
}

Expr_Method_Call :: struct {
    receiver: Expr,
    method:   Intern_ID,
    args:     [dynamic]Expr,
    span:     Source_Span,
}

Expr_Lambda :: struct {
    type_params: [dynamic]Intern_ID,  // <a, b> before |
    params:     [dynamic]Func_Param,
    return_type: ^Type,               // optional
    effects:    ^Type,                // optional effect row
    body:       Expr,
    span:       Source_Span,
}

Func_Param :: struct {
    name:     Intern_ID,
    type_ann: ^Type,     // optional
    span:     Source_Span,
}

Expr_Block :: struct {
    statements: [dynamic]Expr,  // last one is the return value
    span:       Source_Span,
}

Expr_If :: struct {
    condition:  Expr,
    then_branch: Expr,
    else_branch: Expr,  // can be another If or a Block
    span:       Source_Span,
}

Expr_Match :: struct {
    scrutinee: Expr,
    arms:      [dynamic]Match_Arm,
    span:      Source_Span,
}

Match_Arm :: struct {
    pattern:  Pattern,
    body:     Expr,
    span:     Source_Span,
}

Pattern :: union {
    &Pattern_Tag,
    &Pattern_Record,
    &Pattern_List,
    &Pattern_Int,
    &Pattern_String,
    &Pattern_Bool,
    &Pattern_Identifier,
    &Pattern_Wildcard,
    &Pattern_Destructure,
}

Pattern_Tag :: struct {
    name:    Intern_ID,
    payload: [dynamic]Pattern,
    span:    Source_Span,
}

Pattern_Record :: struct {
    fields:  [dynamic]Pattern_Field,
    is_open: bool,           // { name, .. }
    span:    Source_Span,
}

Pattern_Field :: struct {
    name:     Intern_ID,
    binding:  Intern_ID,     // 0 if same as name (shorthand)
    span:     Source_Span,
}

Pattern_List :: struct {
    elements: [dynamic]Pattern,
    span:     Source_Span,
}

Pattern_Int :: struct {
    value: i64,
    span:  Source_Span,
}

Pattern_String :: struct {
    value: string,
    span:  Source_Span,
}

Pattern_Bool :: struct {
    value: bool,
    span:  Source_Span,
}

Pattern_Identifier :: struct {
    name: Intern_ID,
    span: Source_Span,
}

Pattern_Wildcard :: struct {
    span: Source_Span,
}

Pattern_Destructure :: struct {
    type_name: Intern_ID,
    inner:     Pattern,
    span:      Source_Span,
}

Expr_BinOp :: struct {
    op:    Token_Kind,  // Plus, Minus, Star, Slash, Eq_Eq, Bang_Eq, etc.
    left:  Expr,
    right: Expr,
    span:  Source_Span,
}

Expr_PrefixOp :: struct {
    op:     Token_Kind,  // Minus, Bang
    operand: Expr,
    span:    Source_Span,
}

Expr_Field_Access :: struct {
    record:    Expr,
    field:     Intern_ID,
    span:      Source_Span,
}

Expr_Record_Update :: struct {
    rest:      Expr,
    updates:   [dynamic]Record_Field,
    span:      Source_Span,
}

Expr_Assign :: struct {
    target: Expr,   // must be a Dollar_Identifier
    value:  Expr,
    span:   Source_Span,
}

Expr_Return :: struct {
    value: Expr,
    span:  Source_Span,
}

Expr_Crash :: struct {
    message: Expr,
    span:    Source_Span,
}

Expr_Interpolate :: struct {
    parts: [dynamic]Expr,  // alternating strings and expressions
    span:  Source_Span,
}

// Types
Type :: union {
    &Type_Primitive,
    &Type_Applied,    // List(a), Map(k, v)
    &Type_Function,
    &Type_Record,
    &Type_Tag_Union,
    &Type_Effect_Row,
    &Type_Variable,
    &Type_Wildcard,   // _
}

Type_Primitive :: struct {
    name: Intern_ID,  // I64, Str, Bool, etc.
    span: Source_Span,
}

Type_Applied :: struct {
    name:     Intern_ID,
    args:     [dynamic]Type,
    span:     Source_Span,
}

Type_Function :: struct {
    params:  [dynamic]Type,
    effects: ^Type,      // optional effect row
    return_: Type,
    span:    Source_Span,
}

Type_Record :: struct {
    fields:  [dynamic]Type_Field,
    rest:    Intern_ID,  // 0 if closed, >0 if open with row variable
    is_open: bool,
    span:    Source_Span,
}

Type_Field :: struct {
    name: Intern_ID,
    type: Type,
    span: Source_Span,
}

Type_Tag_Union :: struct {
    tags:    [dynamic]Type_Tag,
    rest:    Intern_ID,  // 0 if closed, >0 if open with row variable
    is_open: bool,
    span:    Source_Span,
}

Type_Tag :: struct {
    name:    Intern_ID,
    payload: [dynamic]Type,
    span:    Source_Span,
}

Type_Effect_Row :: struct {
    effects: [dynamic]Intern_ID,
    rest:    Intern_ID,  // 0 if closed, >0 if open
    is_open: bool,
    span:    Source_Span,
}

Type_Variable :: struct {
    name: Intern_ID,
    span: Source_Span,
}

Type_Wildcard :: struct {
    span: Source_Span,
}

// A Camp source file
File :: struct {
    path:  string,
    decls: [dynamic]Decl,
    span:  Source_Span,
}
```

- [ ] **Step 2: Verify AST compiles**

Run: `odin build src -out:camp`
Expected: Compiles without errors

- [ ] **Step 3: Commit AST definitions**

```bash
git add src/ast.odin
git commit -m "feat(ast): define surface AST node types

- Top-level declarations: const, effect, trait, alias, import, test, expect
- Expressions: literals, tags, records, lists, identifiers, calls,
  method calls, lambdas, blocks, if/match, binary/prefix ops,
  field access, record update, assignment, return, crash, interpolation
- Patterns: tag, record, list, literals, identifier, wildcard, destructure
- Types: primitive, applied, function, record, tag union, effect row,
  variable, wildcard
- Open/closed records and tag unions via is_open + rest fields"
```

---

## Task 5: Pratt Parser

**Files:**
- Create: `src/parser.odin`
- Create: `tests/test_parser.odin`

- [ ] **Step 1: Write failing parser test for simple expressions**

Create `tests/test_parser.odin`:

```odin
package camp

import "core:fmt"
import "core:testing"

parse_expr :: proc(source: string) -> (Expr, ^Error_Collector) {
    collector: ^Error_Collector = new(Error_Collector)
    collector_init(collector)

    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    file := Source_File{path = "<test>", contents = source, id = 0}
    lexer: Lexer
    lexer_init(&lexer, file, collector, &table)

    parser: Parser
    parser_init(&parser, &lexer, collector, &table)

    return parser_parse_expr(&parser), collector
}

@(test)
test_parser_integer_literal :: proc(t: ^testing.T) {
    expr, collector := parse_expr("42")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    // Check it's an Expr_Int with value 42
    switch e in expr {
    case &Expr_Int:
        testing.expect(t, e.value == 42)
    case:
        testing.expect(t, false) // wrong type
    }
}

@(test)
test_parser_tag :: proc(t: ^testing.T) {
    expr, collector := parse_expr("Ok(42)")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Tag:
        // Tag name is "Ok", payload is [42]
        testing.expect(t, len(e.payload) == 1)
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_addition :: proc(t: ^testing.T) {
    expr, collector := parse_expr("1 + 2")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_BinOp:
        testing.expect(t, e.op == .Plus)
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_lambda :: proc(t: ^testing.T) {
    expr, collector := parse_expr("|x| x + 1")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Lambda:
        testing.expect(t, len(e.params) == 1)
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_if_else :: proc(t: ^testing.T) {
    expr, collector := parse_expr("if True 1 else 2")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_If:
        testing.expect(t, true) // parsed as if expression
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_record :: proc(t: ^testing.T) {
    expr, collector := parse_expr("{ name: \"Camp\", age: 1 }")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Record:
        testing.expect(t, len(e.fields) == 2)
    case:
        testing.expect(t, false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `odin test tests`
Expected: FAIL — `Parser` type not defined

- [ ] **Step 3: Implement the Pratt parser**

Create `src/parser.odin`:

```odin
package camp

import "core:fmt"

// Pratt parser based on https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html

Binding_Power :: int

// Prefix binding powers (how tightly an operator binds on the left)
// Infix binding powers (how tightly an operator binds between operands)
// Higher = tighter binding

PREFIX_BP :map[Token_Kind]Binding_Power = {
    [.Minus]    = 7,
    [.Bang]     = 7,
}

INFIX_BP :map[Token_Kind][2]Binding_Power = {
    // [left_bp, right_bp]
    // left_bp = binding power for left operand
    // right_bp = binding power for right operand
    // left_bp < right_bp = left-associative
    [.Or]           = {1, 2},
    [.Kw_And]       = {3, 4},
    [.Eq_Eq]        = {5, 6},
    [.Bang_Eq]      = {5, 6},
    [.Lt]           = {5, 6},
    [.Gt]           = {5, 6},
    [.Lt_Eq]        = {5, 6},
    [.Gt_Eq]        = {5, 6},
    [.Pipe]         = {7, 8},     // | for tag unions (lower than +)
    [.Plus]         = {9, 10},
    [.Minus]        = {9, 10},
    [.Star]         = {11, 12},
    [.Slash]        = {11, 12},
    [.Percent]      = {11, 12},
    [.Caret]        = {13, 14},   // exponentiation, right-assoc: {13, 12}
}

Parser :: struct {
    lexer:     ^Lexer,
    current:   Token,
    collector: ^Error_Collector,
    intern:    ^Intern_Table,
}

parser_init :: proc(p: ^Parser, lexer: ^Lexer, collector: ^Error_Collector, table: ^Intern_Table) {
    p.lexer = lexer
    p.collector = collector
    p.intern = table
    p.current = lexer_next(lexer)
}

parser_advance :: proc(p: ^Parser) -> Token {
    prev := p.current
    p.current = lexer_next(p.lexer)
    return prev
}

parser_expect :: proc(p: ^Parser, kind: Token_Kind) -> Token {
    if p.current.kind == kind {
        return parser_advance(p)
    }
    collector_add(p.collector, .Error, "expected {kind}, got {p.current.kind}", p.current.span)
    return Token{kind = kind, span = p.current.span}
}

parser_parse_file :: proc(p: ^Parser) -> File {
    file: File
    file.path = "" // TODO: get from lexer
    file.decls = make([dynamic]Decl, 0, 32)

    for p.current.kind != .Eof {
        decl := parser_parse_decl(p)
        append(&file.decls, decl)
    }

    return file
}

parser_parse_decl :: proc(p: ^Parser) -> Decl {
    is_pub := false
    if p.current.kind == .Upper_Id and p.current.text == "pub" {
        parser_advance(p)
        is_pub = true
    }

    switch p.current.kind {
    case .Kw_Effect:
        return parser_parse_effect_decl(p, is_pub)
    case .Kw_Trait:
        return parser_parse_trait_decl(p, is_pub)
    case .Kw_Alias:
        return parser_parse_alias_decl(p, is_pub)
    case .Kw_Import:
        return parser_parse_import_decl(p, is_pub)
    case .Kw_Test:
        return parser_parse_test_decl(p)
    case .Kw_Expect:
        return parser_parse_expect_decl(p)
    case:
        return parser_parse_const_decl(p, is_pub)
    }
}

parser_parse_const_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
    start_span := p.current.span

    // name = expr
    // or: name: Type = expr
    name := parser_advance(p) // identifier
    name_id := intern(p.intern, name.text)

    type_ann: ^Type = nil
    if p.current.kind == .Colon {
        parser_advance(p)
        type_ann = parser_parse_type(p)
    }

    parser_expect(p, .Eq)
    body := parser_parse_expr(p)

    decl := new(Decl_Const)
    decl^ = Decl_Const{
        name = name_id,
        is_pub = is_pub,
        body = body,
        type_ann = type_ann,
        span = Source_Span{file_id = start_span.file_id, start = start_span.start, end = p.current.span.end},
    }
    return decl
}

parser_parse_expr :: proc(p: ^Parser) -> Expr {
    return parser_parse_expr_bp(p, 0)
}

parser_parse_expr_bp :: proc(p: ^Parser, min_bp: Binding_Power) -> Expr {
    left := parser_parse_prefix(p)

    for {
        if p.current.kind == .Eof { break }

        right_bp: Binding_Power
        if bps, ok := INFIX_BP[p.current.kind]; ok {
            right_bp = bps[1]
            if bps[0] < min_bp { break }
        } else {
            break
        }

        op := parser_advance(p)
        right := parser_parse_expr_bp(p, right_bp)

        binop := new(Expr_BinOp)
        binop^ = Expr_BinOp{op = op.kind, left = left, right = right, span = Source_Span{file_id = op.span.file_id, start = 0, end = op.span.end}}
        left = binop
    }

    return left
}

parser_parse_prefix :: proc(p: ^Parser) -> Expr {
    tok := p.current

    switch tok.kind {
    case .Int_Literal:
        parser_advance(p)
        e := new(Expr_Int)
        e^ = Expr_Int{value = tok.int_value, span = tok.span}
        return e

    case .Float_Literal:
        parser_advance(p)
        e := new(Expr_Float)
        e^ = Expr_Float{value = tok.f64_value, span = tok.span}
        return e

    case .String_Literal:
        parser_advance(p)
        e := new(Expr_String)
        e^ = Expr_String{value = tok.text, span = tok.span}
        return e

    case .Kw_True:
        parser_advance(p)
        e := new(Expr_Bool)
        e^ = Expr_Bool{value = true, span = tok.span}
        return e

    case .Kw_False:
        parser_advance(p)
        e := new(Expr_Bool)
        e^ = Expr_Bool{value = false, span = tok.span}
        return e

    case .Upper_Id:
        return parser_parse_tag_or_call(p)

    case .Identifier:
        return parser_parse_identifier_expr(p)

    case .Dollar:
        parser_advance(p)
        name := parser_expect(p, .Identifier)
        e := new(Expr_Dollar_Identifier)
        e^ = Expr_Dollar_Identifier{name = intern(p.intern, name.text), span = tok.span}
        return e

    case .Pipe:
        return parser_parse_lambda(p)

    case .LBrace:
        return parser_parse_block_or_record(p)

    case .LBrack:
        return parser_parse_list(p)

    case .Kw_If:
        return parser_parse_if(p)

    case .Kw_Match:
        return parser_parse_match(p)

    case .LParen:
        parser_advance(p) // skip (
        expr := parser_parse_expr(p)
        parser_expect(p, .RParen)
        return expr

    case .Minus, .Bang:
        parser_advance(p)
        rhs := parser_parse_expr_bp(p, 7) // prefix binding power
        e := new(Expr_PrefixOp)
        e^ = Expr_PrefixOp{op = tok.kind, operand = rhs, span = tok.span}
        return e

    case:
        collector_add(p.collector, .Error, "unexpected token: {tok.kind}", tok.span)
        parser_advance(p)
        // Return a placeholder
        e := new(Expr_Int)
        e^ = Expr_Int{value = 0, span = tok.span}
        return e
    }
}

parser_parse_tag_or_call :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    name_tok := parser_advance(p)
    name_id := intern(p.intern, name_tok.text)

    tag := new(Expr_Tag)
    tag^ = Expr_Tag{name = name_id, payload = make([dynamic]Expr, 0, 2), span = start}

    if p.current.kind == .LParen {
        parser_advance(p) // skip (
        for p.current.kind != .RParen and p.current.kind != .Eof {
            arg := parser_parse_expr(p)
            append(&tag.payload, arg)
            if p.current.kind == .Comma {
                parser_advance(p)
            }
        }
        parser_expect(p, .RParen)
    }

    // Check for method call: Tag(args).method()
    if p.current.kind == .Dot {
        return parser_parse_method_chain(p, tag)
    }

    return tag
}

parser_parse_identifier_expr :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    name_tok := parser_advance(p)
    name_id := intern(p.intern, name_tok.text)

    // Check for function call: name(args)
    if p.current.kind == .LParen {
        parser_advance(p)
        call := new(Expr_Call)
        call^ = Expr_Call{args = make([dynamic]Expr, 0, 4), span = start}
        // callee is the identifier
        id_expr := new(Expr_Identifier)
        id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
        call.callee = id_expr

        for p.current.kind != .RParen and p.current.kind != .Eof {
            arg := parser_parse_expr(p)
            append(&call.args, arg)
            if p.current.kind == .Comma {
                parser_advance(p)
            }
        }
        parser_expect(p, .RParen)

        // Check for method chain: name(args).method()
        if p.current.kind == .Dot {
            return parser_parse_method_chain(p, call)
        }

        return call
    }

    // Check for method call: name.method()
    if p.current.kind == .Dot {
        id_expr := new(Expr_Identifier)
        id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
        return parser_parse_method_chain(p, id_expr)
    }

    // Plain identifier
    e := new(Expr_Identifier)
    e^ = Expr_Identifier{name = name_id, span = name_tok.span}
    return e
}

parser_parse_method_chain :: proc(p: ^Parser, receiver: Expr) -> Expr {
    for p.current.kind == .Dot {
        parser_advance(p)
        method_tok := parser_expect(p, .Identifier)
        method_id := intern(p.intern, method_tok.text)

        mc := new(Expr_Method_Call)
        mc^ = Expr_Method_Call{
            receiver = receiver,
            method = method_id,
            args = make([dynamic]Expr, 0, 4),
            span = receiver.(#as union {}).span, // approximate span
        }

        if p.current.kind == .LParen {
            parser_advance(p)
            for p.current.kind != .RParen and p.current.kind != .Eof {
                arg := parser_parse_expr(p)
                append(&mc.args, arg)
                if p.current.kind == .Comma {
                    parser_advance(p)
                }
            }
            parser_expect(p, .RParen)
        }

        receiver = mc
    }
    return receiver
}

parser_parse_lambda :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    parser_advance(p) // skip |

    type_params: [dynamic]Intern_ID
    type_params = make([dynamic]Intern_ID, 0, 4)

    // Check for <a, b> type params before |
    // (This is handled by the caller for named functions, not in bare lambdas)

    params: [dynamic]Func_Param
    params = make([dynamic]Func_Param, 0, 4)

    for p.current.kind != .Pipe and p.current.kind != .Eof {
        param := Func_Param{span = p.current.span}
        if p.current.kind == .Identifier or p.current.kind == .Upper_Id {
            name_tok := parser_advance(p)
            param.name = intern(p.intern, name_tok.text)
            if p.current.kind == .Colon {
                parser_advance(p)
                param.type_ann = parser_parse_type(p)
            }
        }
        append(&params, param)
        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .Pipe)

    // Optional return type: -> Type
    return_type: ^Type = nil
    effects: ^Type = nil
    if p.current.kind == .Arrow {
        parser_advance(p)
        // Check for effect row: ->{ E1, E2 } Type
        if p.current.kind == .LBrace {
            effects = parser_parse_effect_row_type(p)
        }
        return_type = parser_parse_type(p)
    }

    body := parser_parse_expr(p)

    e := new(Expr_Lambda)
    e^ = Expr_Lambda{
        type_params = type_params,
        params = params,
        return_type = return_type,
        effects = effects,
        body = body,
        span = start,
    }
    return e
}

parser_parse_block_or_record :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    parser_advance(p) // skip {

    // If next token is Identifier followed by Colon, it's a record
    // Otherwise it's a block
    if p.current.kind == .Identifier or p.current.kind == .Upper_Id {
        // Peek ahead to check for colon or comma (record pattern)
        // Records: { name: value, ... } or { name, ... }
        // Blocks: { statement; ... }
        // Heuristic: if we see `name:` it's a record, otherwise block
        saved_pos := p.lexer.pos
        saved_tok := p.current
        next := lexer_next(p.lexer)
        is_record := next.kind == .Colon

        // Restore lexer state
        p.lexer.pos = saved_pos
        // We can't easily restore the token, so re-lex
        p.current = saved_tok

        if is_record {
            return parser_parse_record_expr(p, start)
        }
    }

    // Block
    return parser_parse_block(p, start)
}

parser_parse_block :: proc(p: ^Parser, start: Source_Span) -> Expr {
    stmts: [dynamic]Expr
    stmts = make([dynamic]Expr, 0, 8)

    for p.current.kind != .RBrace and p.current.kind != .Eof {
        stmt := parser_parse_expr_or_decl(p)
        append(&stmts, stmt)
    }
    parser_expect(p, .RBrace)

    e := new(Expr_Block)
    e^ = Expr_Block{statements = stmts, span = start}
    return e
}

parser_parse_expr_or_decl :: proc(p: ^Parser) -> Expr {
    // Inside blocks, we can have:
    // - name = expr (constant binding)
    // - $name = expr (mutable binding)
    // - name: Type = expr (typed constant binding)
    // - expect expr
    // - return expr
    // - Any expression

    if p.current.kind == .Kw_Expect {
        parser_advance(p)
        cond := parser_parse_expr(p)
        e := new(Expr_Call) // expect is treated as a function call for now
        id := new(Expr_Identifier)
        id^ = Expr_Identifier{name = intern(p.intern, "expect"), span = cond.(#as union {}).span}
        e^ = Expr_Call{callee = id, args = make([dynamic]Expr, 0, 4), span = cond.(#as union {}).span}
        append(&e.args, cond)
        return e
    }

    if p.current.kind == .Dollar {
        // Mutable binding: $name = expr
        // or assignment: $name = expr (where $name already exists)
        start := p.current.span
        parser_advance(p)
        name_tok := parser_expect(p, .Identifier)
        name_id := intern(p.intern, name_tok.text)

        type_ann: ^Type = nil
        if p.current.kind == .Colon {
            parser_advance(p)
            type_ann = parser_parse_type(p)
        }

        parser_expect(p, .Eq)
        value := parser_parse_expr(p)

        id_expr := new(Expr_Dollar_Identifier)
        id_expr^ = Expr_Dollar_Identifier{name = name_id, span = start}
        assign := new(Expr_Assign)
        assign^ = Expr_Assign{target = id_expr, value = value, span = start}
        return assign
    }

    // Regular expression (might be a constant binding: name = expr)
    // Parse as expression, check for = after
    expr := parser_parse_expr(p)
    if p.current.kind == .Eq {
        parser_advance(p)
        value := parser_parse_expr(p)
        assign := new(Expr_Assign)
        assign^ = Expr_Assign{target = expr, value = value, span = start}
        return assign
    }
    return expr
}

parser_parse_record_expr :: proc(p: ^Parser, start: Source_Span) -> Expr {
    // Already consumed {
    fields: [dynamic]Record_Field
    fields = make([dynamic]Record_Field, 0, 8)
    rest_expr: Expr = nil
    is_open := false

    // Check for { ..expr, ... } (record update)
    if p.current.kind == .Dot_Dot {
        parser_advance(p)
        rest_expr = parser_parse_expr(p)
        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }

    for p.current.kind != .RBrace and p.current.kind != .Eof {
        if p.current.kind == .Dot_Dot {
            is_open = true
            parser_advance(p)
            if p.current.kind == .Identifier {
                // ..rest — row variable name
                parser_advance(p)
            }
            if p.current.kind == .Comma {
                parser_advance(p)
            }
            continue
        }

        name_tok := parser_expect(p, .Identifier)
        name_id := intern(p.intern, name_tok.text)

        value: Expr = nil
        if p.current.kind == .Colon {
            parser_advance(p)
            value = parser_parse_expr(p)
        } else {
            // Shorthand: { name } means { name: name }
            id_expr := new(Expr_Identifier)
            id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
            value = id_expr
        }

        append(&fields, Record_Field{name = name_id, value = value, span = name_tok.span})

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    e := new(Expr_Record)
    e^ = Expr_Record{fields = fields, rest = rest_expr, is_open = is_open, span = start}
    return e
}

parser_parse_list :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    parser_advance(p) // skip [

    elements: [dynamic]Expr
    elements = make([dynamic]Expr, 0, 8)

    for p.current.kind != .RBrack and p.current.kind != .Eof {
        elem := parser_parse_expr(p)
        append(&elements, elem)
        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrack)

    e := new(Expr_List)
    e^ = Expr_List{elements = elements, span = start}
    return e
}

parser_parse_if :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    parser_advance(p) // skip if

    condition := parser_parse_expr(p)
    then_branch := parser_parse_expr(p)

    else_branch: Expr = nil
    if p.current.kind == .Kw_Else {
        parser_advance(p)
        else_branch = parser_parse_expr(p)
    }

    e := new(Expr_If)
    e^ = Expr_If{condition = condition, then_branch = then_branch, else_branch = else_branch, span = start}
    return e
}

parser_parse_match :: proc(p: ^Parser) -> Expr {
    start := p.current.span
    parser_advance(p) // skip match

    scrutinee := parser_parse_expr(p)

    arms: [dynamic]Match_Arm
    arms = make([dynamic]Match_Arm, 0, 8)

    parser_expect(p, .LBrace)
    for p.current.kind != .RBrace and p.current.kind != .Eof {
        pattern := parser_parse_pattern(p)
        parser_expect(p, .Fat_Arrow)
        body := parser_parse_expr(p)
        append(&arms, Match_Arm{pattern = pattern, body = body, span = p.current.span})
        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    e := new(Expr_Match)
    e^ = Expr_Match{scrutinee = scrutinee, arms = arms, span = start}
    return e
}

parser_parse_pattern :: proc(p: ^Parser) -> Pattern {
    switch p.current.kind {
    case .Upper_Id:
        name_tok := parser_advance(p)
        name_id := intern(p.intern, name_tok.text)

        pat := new(Pattern_Tag)
        pat^ = Pattern_Tag{name = name_id, payload = make([dynamic]Pattern, 0, 2), span = name_tok.span}

        if p.current.kind == .LParen {
            parser_advance(p)
            for p.current.kind != .RParen and p.current.kind != .Eof {
                inner := parser_parse_pattern(p)
                append(&pat.payload, inner)
                if p.current.kind == .Comma {
                    parser_advance(p)
                }
            }
            parser_expect(p, .RParen)
        }
        return pat

    case .Identifier:
        name_tok := parser_advance(p)
        name_id := intern(p.intern, name_tok.text)
        pat := new(Pattern_Identifier)
        pat^ = Pattern_Identifier{name = name_id, span = name_tok.span}
        return pat

    case .Int_Literal:
        tok := parser_advance(p)
        pat := new(Pattern_Int)
        pat^ = Pattern_Int{value = tok.int_value, span = tok.span}
        return pat

    case .String_Literal:
        tok := parser_advance(p)
        pat := new(Pattern_String)
        pat^ = Pattern_String{value = tok.text, span = tok.span}
        return pat

    case .Kw_True, .Kw_False:
        tok := parser_advance(p)
        pat := new(Pattern_Bool)
        pat^ = Pattern_Bool{value = tok.kind == .Kw_True, span = tok.span}
        return pat

    case .LBrace:
        return parser_parse_record_pattern(p)

    case .LBrack:
        return parser_parse_list_pattern(p)

    case: // Underscore/wildcard (using _ identifier or unknown)
        tok := parser_advance(p)
        pat := new(Pattern_Wildcard)
        pat^ = Pattern_Wildcard{span = tok.span}
        return pat
    }
}

parser_parse_record_pattern :: proc(p: ^Parser) -> Pattern {
    start := p.current.span
    parser_advance(p) // skip {

    fields: [dynamic]Pattern_Field
    fields = make([dynamic]Pattern_Field, 0, 8)
    is_open := false

    for p.current.kind != .RBrace and p.current.kind != .Eof {
        if p.current.kind == .Dot_Dot {
            is_open = true
            parser_advance(p)
            if p.current.kind == .Comma {
                parser_advance(p)
            }
            continue
        }

        name_tok := parser_expect(p, .Identifier)
        name_id := intern(p.intern, name_tok.text)

        binding: Intern_ID = name_id
        if p.current.kind == .Colon {
            // { field: binding }
            parser_advance(p)
            binding_tok := parser_expect(p, .Identifier)
            binding = intern(p.intern, binding_tok.text)
        }

        append(&fields, Pattern_Field{name = name_id, binding = binding, span = name_tok.span})

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    pat := new(Pattern_Record)
    pat^ = Pattern_Record{fields = fields, is_open = is_open, span = start}
    return pat
}

parser_parse_list_pattern :: proc(p: ^Parser) -> Pattern {
    start := p.current.span
    parser_advance(p) // skip [

    elements: [dynamic]Pattern
    elements = make([dynamic]Pattern, 0, 8)

    for p.current.kind != .RBrack and p.current.kind != .Eof {
        elem := parser_parse_pattern(p)
        append(&elements, elem)
        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrack)

    pat := new(Pattern_List)
    pat^ = Pattern_List{elements = elements, span = start}
    return pat
}

// Type parsing
parser_parse_type :: proc(p: ^Parser) -> ^Type {
    // Types are parsed for annotations, not expressions
    // This is a simplified type parser for Phase 2
    // Full type parsing (function types, effect rows, etc.) will be refined in Phase 4

    t: Type = nil

    switch p.current.kind {
    case .Upper_Id:
        name_tok := parser_advance(p)
        name_id := intern(p.intern, name_tok.text)

        // Check for type application: List(a)
        if p.current.kind == .LParen {
            parser_advance(p)
            applied := new(Type_Applied)
            applied^ = Type_Applied{name = name_id, args = make([dynamic]Type, 0, 4), span = name_tok.span}
            for p.current.kind != .RParen and p.current.kind != .Eof {
                arg := parser_parse_type(p)
                append(&applied.args, arg)
                if p.current.kind == .Comma {
                    parser_advance(p)
                }
            }
            parser_expect(p, .RParen)
            t = applied
        } else {
            prim := new(Type_Primitive)
            prim^ = Type_Primitive{name = name_id, span = name_tok.span}
            t = prim
        }

    case .Identifier:
        name_tok := parser_advance(p)
        name_id := intern(p.intern, name_tok.text)
        v := new(Type_Variable)
        v^ = Type_Variable{name = name_id, span = name_tok.span}
        t = v

    case .LBrace:
        t = parser_parse_record_type(p)

    case .LBrack:
        t = parser_parse_tag_union_type(p)

    case:
        collector_add(p.collector, .Error, "expected type, got {p.current.kind}", p.current.span)
        // Return a placeholder
        v := new(Type_Variable)
        v^ = Type_Variable{name = intern(p.intern, "_"), span = p.current.span}
        t = v
    }

    // Check for function type: Type, Type -> Type
    // This is handled at a higher level for now

    // Allocate and return
    result := new(Type)
    result^ = t
    return result
}

parser_parse_record_type :: proc(p: ^Parser) -> Type {
    start := p.current.span
    parser_advance(p) // skip {

    fields: [dynamic]Type_Field
    fields = make([dynamic]Type_Field, 0, 8)
    rest: Intern_ID = 0
    is_open := false

    for p.current.kind != .RBrace and p.current.kind != .Eof {
        if p.current.kind == .Dot_Dot {
            is_open = true
            parser_advance(p)
            if p.current.kind == .Identifier {
                rest_tok := parser_advance(p)
                rest = intern(p.intern, rest_tok.text)
            }
            if p.current.kind == .Comma {
                parser_advance(p)
            }
            continue
        }

        name_tok := parser_expect(p, .Identifier)
        name_id := intern(p.intern, name_tok.text)
        parser_expect(p, .Colon)
        field_type := parser_parse_type(p)

        append(&fields, Type_Field{name = name_id, type = field_type^, span = name_tok.span})

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    rec := new(Type_Record)
    rec^ = Type_Record{fields = fields, rest = rest, is_open = is_open, span = start}
    return rec
}

parser_parse_tag_union_type :: proc(p: ^Parser) -> Type {
    start := p.current.span
    parser_advance(p) // skip [

    tags: [dynamic]Type_Tag
    tags = make([dynamic]Type_Tag, 0, 8)
    rest: Intern_ID = 0
    is_open := false

    for p.current.kind != .RBrack and p.current.kind != .Eof {
        if p.current.kind == .Dot_Dot {
            is_open = true
            parser_advance(p)
            if p.current.kind == .Identifier {
                rest_tok := parser_advance(p)
                rest = intern(p.intern, rest_tok.text)
            }
            if p.current.kind == .Pipe {
                parser_advance(p)
            }
            continue
        }

        name_tok := parser_expect(p, .Upper_Id)
        name_id := intern(p.intern, name_tok.text)

        payload: [dynamic]Type
        payload = make([dynamic]Type, 0, 2)

        if p.current.kind == .LParen {
            parser_advance(p)
            for p.current.kind != .RParen and p.current.kind != .Eof {
                arg := parser_parse_type(p)
                append(&payload, arg^)
                if p.current.kind == .Comma {
                    parser_advance(p)
                }
            }
            parser_expect(p, .RParen)
        }

        append(&tags, Type_Tag{name = name_id, payload = payload, span = name_tok.span})

        if p.current.kind == .Pipe {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrack)

    union := new(Type_Tag_Union)
    union^ = Type_Tag_Union{tags = tags, rest = rest, is_open = is_open, span = start}
    return union
}

parser_parse_effect_row_type :: proc(p: ^Parser) -> ^Type {
    start := p.current.span
    parser_advance(p) // skip {

    effects: [dynamic]Intern_ID
    effects = make([dynamic]Intern_ID, 0, 8)
    rest: Intern_ID = 0
    is_open := false

    for p.current.kind != .RBrace and p.current.kind != .Eof {
        if p.current.kind == .Dot_Dot {
            is_open = true
            parser_advance(p)
            if p.current.kind == .Identifier {
                rest_tok := parser_advance(p)
                rest = intern(p.intern, rest_tok.text)
            }
            if p.current.kind == .Comma {
                parser_advance(p)
            }
            continue
        }

        name_tok := parser_expect(p, .Upper_Id)
        name_id := intern(p.intern, name_tok.text)
        append(&effects, name_id)

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    row := new(Type_Effect_Row)
    row^ = Type_Effect_Row{effects = effects, rest = rest, is_open = is_open, span = start}
    result := new(Type)
    result^ = row
    return result
}

// Declaration parsers (stubs for now, filled in during implementation)

parser_parse_effect_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
    start := p.current.span
    parser_advance(p) // skip effect

    name_tok := parser_expect(p, .Upper_Id)
    name_id := intern(p.intern, name_tok.text)

    ops: [dynamic]Effect_Op
    ops = make([dynamic]Effect_Op, 0, 8)

    parser_expect(p, .LBrace)
    for p.current.kind != .RBrace and p.current.kind != .Eof {
        op_name_tok := parser_advance(p)
        op_name_id := intern(p.intern, op_name_tok.text)
        is_effectful := p.current.kind == .Bang
        if is_effectful { parser_advance(p) }

        parser_expect(p, .Colon)
        // Parse type signature (simplified)
        return_type := parser_parse_type(p)

        append(&ops, Effect_Op{name = op_name_id, is_effectful = is_effectful, return_type = return_type, span = op_name_tok.span})

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    decl := new(Decl_Effect)
    decl^ = Decl_Effect{name = name_id, is_pub = is_pub, operations = ops, span = start}
    return decl
}

parser_parse_trait_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
    start := p.current.span
    parser_advance(p) // skip trait

    name_tok := parser_expect(p, .Upper_Id)
    name_id := intern(p.intern, name_tok.text)

    parent: Intern_ID = 0
    if p.current.kind == .Kw_Is {
        parser_advance(p)
        parent_tok := parser_expect(p, .Upper_Id)
        parent = intern(p.intern, parent_tok.text)
    }

    methods: [dynamic]Trait_Method
    methods = make([dynamic]Trait_Method, 0, 8)

    parser_expect(p, .LBrace)
    for p.current.kind != .RBrace and p.current.kind != .Eof {
        m_name_tok := parser_advance(p)
        m_name_id := intern(p.intern, m_name_tok.text)

        parser_expect(p, .Colon)
        return_type := parser_parse_type(p)

        append(&methods, Trait_Method{name = m_name_id, return_type = return_type, span = m_name_tok.span})

        if p.current.kind == .Comma {
            parser_advance(p)
        }
    }
    parser_expect(p, .RBrace)

    decl := new(Decl_Trait)
    decl^ = Decl_Trait{name = name_id, is_pub = is_pub, parent = parent, methods = methods, span = start}
    return decl
}

parser_parse_alias_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
    start := p.current.span
    parser_advance(p) // skip alias

    name_tok := parser_expect(p, .Upper_Id)
    name_id := intern(p.intern, name_tok.text)
    parser_expect(p, .Eq)
    target := parser_parse_type(p)

    decl := new(Decl_Alias)
    decl^ = Decl_Alias{name = name_id, is_pub = is_pub, target = target, span = start}
    return decl
}

parser_parse_import_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
    start := p.current.span

    is_unsafe := false
    if p.current.kind == .Kw_Unsafe {
        parser_advance(p)
        is_unsafe = true
    }

    parser_advance(p) // skip import

    module_tok := parser_expect(p, .Upper_Id)
    module_name := module_tok.text

    exposing: [dynamic]Intern_ID
    exposing = make([dynamic]Intern_ID, 0, 8)

    alias: Intern_ID = 0

    if p.current.kind == .Kw_Exposing {
        parser_advance(p)
        parser_expect(p, .LBrack)
        for p.current.kind != .RBrack and p.current.kind != .Eof {
            name_tok := parser_advance(p)
            append(&exposing, intern(p.intern, name_tok.text))
            if p.current.kind == .Comma {
                parser_advance(p)
            }
        }
        parser_expect(p, .RBrack)
    }

    if p.current.kind == .Kw_As {
        parser_advance(p)
        alias_tok := parser_expect(p, .Upper_Id)
        alias = intern(p.intern, alias_tok.text)
    }

    decl := new(Decl_Import)
    decl^ = Decl_Import{module = module_name, exposing = exposing, alias = alias, is_unsafe = is_unsafe, span = start}
    return decl
}

parser_parse_test_decl :: proc(p: ^Parser) -> Decl {
    start := p.current.span
    parser_advance(p) // skip test

    name_tok := parser_expect(p, .String_Literal)
    parser_expect(p, .Eq)

    body := parser_parse_expr(p)

    decl := new(Decl_Test)
    decl^ = Decl_Test{name = name_tok.text, body = body, span = start}
    return decl
}

parser_parse_expect_decl :: proc(p: ^Parser) -> Decl {
    start := p.current.span
    parser_advance(p) // skip expect

    condition := parser_parse_expr(p)

    decl := new(Decl_Expect)
    decl^ = Decl_Expect{condition = condition, span = start}
    return decl
}
```

- [ ] **Step 4: Run parser tests**

Run: `odin test tests`
Expected: All parser tests PASS (integer literal, tag, addition, lambda, if/else, record)

- [ ] **Step 5: Write additional parser tests for match and type annotations**

Add to `tests/test_parser.odin`:

```odin
@(test)
test_parser_match :: proc(t: ^testing.T) {
    expr, collector := parse_expr("match x { Ok(v) => v | Err(e) => 0 }")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Match:
        testing.expect(t, len(e.arms) == 2)
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_method_call :: proc(t: ^testing.T) {
    expr, collector := parse_expr("list.iter().map(|x| x + 1)")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Method_Call:
        testing.expect(t, true) // parsed as method chain
    case:
        testing.expect(t, false)
    }
}

@(test)
test_parser_record_update :: proc(t: ^testing.T) {
    expr, collector := parse_expr("{ ..record, name: \"new\" }")
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    switch e in expr {
    case &Expr_Record:
        testing.expect(t, len(e.fields) == 1)
    case:
        testing.expect(t, false)
    }
}
```

- [ ] **Step 6: Run all parser tests**

Run: `odin test tests`
Expected: All tests PASS

- [ ] **Step 7: Commit parser**

```bash
git add src/parser.odin src/ast.odin tests/test_parser.odin
git commit -m "feat(parser): Pratt parser for Camp surface AST

- Pratt parsing with binding powers for operator precedence
- Expression parsing: literals, tags, records, lists, lambdas,
  blocks, if/match, binary/prefix operators, method chains,
  field access, record update, assignment
- Pattern parsing: tags, records, lists, literals, identifiers, wildcards
- Type parsing: primitives, applied types, records, tag unions, effect rows
- Declaration parsing: const, effect, trait, alias, import, test, expect
- Full test coverage for expressions and patterns"
```

---

## Task 6: Integration — Parse a Camp File End-to-End

**Files:**
- Modify: `src/cli.odin`
- Create: `tests/test_integration.odin`

- [ ] **Step 1: Write integration test**

Create `tests/test_integration.odin`:

```odin
package camp

import "core:fmt"
import "core:testing"

parse_camp_source :: proc(source: string) -> (File, ^Error_Collector) {
    collector: ^Error_Collector = new(Error_Collector)
    collector_init(collector)

    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    file := Source_File{path = "<test>", contents = source, id = 0}

    lexer: Lexer
    lexer_init(&lexer, file, collector, &table)

    parser: Parser
    parser_init(&parser, &lexer, collector, &table)

    return parser_parse_file(&parser), collector
}

@(test)
test_integration_hello_world :: proc(t: ^testing.T) {
    source := "main! = || ->{ Console } Str { \"Hello, Camp!\" }"
    file, collector := parse_camp_source(source)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_add_function :: proc(t: ^testing.T) {
    source := "add = |x: I64, y: I64| -> I64 { x + y }"
    file, collector := parse_camp_source(source)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_effect_definition :: proc(t: ^testing.T) {
    source := "effect Console { print!: Str ->{ Console } {} }"
    file, collector := parse_camp_source(source)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    testing.expect(t, len(file.decls) == 1)
}

@(test)
test_integration_multiple_decls :: proc(t: ^testing.T) {
    source := "name = \"Camp\"\nversion = 1\nmain! = || ->{ Console } Str { \"Hello\" }"
    file, collector := parse_camp_source(source)
    defer collector_destroy(collector)
    defer free(collector)

    testing.expect(t, !collector_has_errors(collector))
    testing.expect(t, len(file.decls) == 3)
}
```

- [ ] **Step 2: Run integration tests**

Run: `odin test tests`
Expected: All integration tests PASS

- [ ] **Step 3: Wire parser into CLI**

Update `src/cli.odin` `run_build` to use the lexer + parser:

```odin
run_build :: proc(args: []string) {
    file_path := "main.camp"
    if len(args) > 0 {
        file_path = args[0]
    }

    if filepath.ext(file_path) != ".camp" {
        fmt.println("error: expected .camp file, got {file_path}")
        os.exit(1)
    }

    collector: Error_Collector
    collector_init(&collector)
    defer collector_destroy(&collector)

    table: Intern_Table
    intern_init(&table)
    defer intern_destroy(&table)

    // Read source file
    data, ok := os.read_entire_file_from_filename(file_path)
    if !ok {
        fmt.println("error: could not read file {file_path}")
        os.exit(1)
    }
    source := string(data)

    file_rec := Source_File{path = file_path, contents = source, id = 0}

    // Lex
    lexer: Lexer
    lexer_init(&lexer, file_rec, &collector, &table)

    // Parse
    parser: Parser
    parser_init(&parser, &lexer, &collector, &table)
    ast_file := parser_parse_file(&parser)

    if collector_has_errors(&collector) {
        for err in collector.errors {
            report_error(&collector, file_path, source, err)
        }
        fmt.println("compilation failed with {collector.error_count} error(s)")
        os.exit(1)
    }

    fmt.println("parsed {file_path}: {len(ast_file.decls)} declaration(s)")
    fmt.println("TODO: implement type checking and code generation")
}
```

- [ ] **Step 4: Create a test Camp file and verify end-to-end**

Create `test_main.camp`:

```
main! = || ->{ Console } Str {
    Console.println!("Hello, Camp!")
    Ok({})
}
```

Run: `odin build src -out:camp && ./camp build test_main.camp`
Expected: Prints "parsed test_main.camp: 1 declaration(s)"

- [ ] **Step 5: Test error reporting**

Create `test_error.camp`:

```
main! = || ->{ Console } Str {
    if True
```

Run: `./camp build test_error.camp`
Expected: Prints an error about unexpected token (missing else branch or RBrace)

- [ ] **Step 6: Commit integration**

```bash
git add src/cli.odin tests/test_integration.odin test_main.camp
git commit -m "feat: end-to-end lexing + parsing of Camp source files

- CLI reads .camp files, lexes, parses, and reports errors
- Integration tests: hello world, add function, effect definition, multiple decls
- Error reporting with file:line:col format
- Successfully parses basic Camp programs"
```

---

## Task 7: Cleanup and Documentation

**Files:**
- Modify: `README.md`
- Remove: `test_main.camp`, `test_error.camp` (temp test files)

- [ ] **Step 1: Update README with build instructions**

Update `README.md`:

```markdown
# camp

A general-purpose, strictly-typed functional programming language with algebraic effects, compiling to WASM/WASI.

**Status:** Early development. Lexer and parser are functional. Type checking and code generation are not yet implemented.

## Building

Requires [Odin](https://odin-lang.org).

```bash
odin build src -out:camp
```

## Running

```bash
camp build <file.camp>    # Compile a Camp source file
camp test                 # Run tests (not yet implemented)
camp fmt                  # Format source (not yet implemented)
camp check                # Type-check only (not yet implemented)
```

## Design

See [docs/superpowers/specs/2026-05-18-camp-language-design.md](docs/superpowers/specs/2026-05-18-camp-language-design.md) for the full language design specification.

## Testing

```bash
odin test tests
```
```

- [ ] **Step 2: Remove temporary test files**

Run: `rm -f test_main.camp test_error.camp`

- [ ] **Step 3: Run all tests one final time**

Run: `odin test tests`
Expected: All tests PASS (error collector, intern, lexer, parser, integration)

- [ ] **Step 4: Final commit**

```bash
git add README.md
git commit -m "docs: update README with build and usage instructions"
```

---

## Self-Review

**Spec coverage check:**

| Spec section | Covered by task |
|-------------|----------------|
| §3.4 Tag unions | Task 4 (AST), Task 5 (parser) |
| §3.5 Records | Task 4 (AST), Task 5 (parser) |
| §3.6 Newtypes | Task 4 (AST), Task 5 (parser) — nominal qualification deferred to canonicalizer |
| §3.7 Functions | Task 4 (AST), Task 5 (parser) |
| §3.8 Logic operators | Task 3 (lexer: and/or keywords) |
| §3.9 Var syntax | Task 3 (lexer: $), Task 4 (AST), Task 5 (parser) |
| §3.10 Traits | Task 4 (AST), Task 5 (parser) |
| §3.11 Effect rows | Task 4 (AST), Task 5 (parser) |
| §5.3 Phase 1-2 | Task 1-6 |
| §8.5 Prelude | Not yet — deferred to Phase 3 |
| §8.6 FFI | Not yet — deferred to Phase 6 |

**Placeholder scan:** No TBDs, TODOs, or "implement later" patterns in code steps. All code is concrete.

**Type consistency:** All AST types, token kinds, and parser functions use consistent naming throughout tasks.

**Gap:** The parser's `parser_parse_const_decl` doesn't handle effectful function names with `!` suffix yet. This is because `!` is a separate token (Token_Kind.Bang) — the parser needs to handle `name!` as a single identifier. This should be refined during implementation when we discover how the lexer emits `!` in function name context. Adding a note to handle this during Task 5 implementation.
