# Tree-sitter Grammar for Camp

## Overview

Add a [tree-sitter](https://tree-sitter.github.io/) grammar for the Camp programming language, hosted in-repo under `tree-sitter/`. Provides syntax highlighting, scope tracking, and symbol tagging for editors; corpus tests prevent parser/grammar drift.

## Directory Structure

```
camp/
├── tree-sitter/
│   ├── tree-sitter.json          # scope: source.camp, file-types: ["camp"]
│   ├── package.json              # npm manifest (devDeps: tree-sitter-cli)
│   ├── grammar.js                # Main grammar definition
│   ├── src/
│   │   └── parser.c              # Generated parser
│   ├── queries/
│   │   ├── highlights.scm        # Syntax highlighting
│   │   ├── locals.scm            # Scope/locals tracking
│   │   └── tags.scm              # Symbol tagging (goto-def, outline)
│   ├── bindings/                 # Auto-generated (node, rust, python)
│   └── test/
│       └── corpus/
│           ├── literals.txt
│           ├── declarations.txt
│           ├── expressions.txt
│           ├── operators.txt
│           ├── patterns.txt
│           ├── types.txt
│           └── effects.txt
├── justfile                      # + tree-sitter-generate, tree-sitter-test,
│                                 #   tree-sitter-validate, lint-tree-sitter
└── .gitignore                    # + tree-sitter/node_modules/, tree-sitter/build/
```

## Grammar Rules

Mirrors the Camp AST (src/ast.odin). Named rules match recognisable language constructs.

```
source_file
  -> repeat(_declaration)

_declaration
  -> const_declaration     # x = expr, f = |params| -> ret { body }
  -> effect_declaration    # effect Name { ops }
  -> trait_declaration     # trait Name { methods }
  -> alias_declaration     # alias Name = Type
  -> import_declaration    # import "module" exposing (..)
  -> test_declaration      # test name { body }
  -> expect_declaration    # expect expr

_expression
  -> binary_expression     # or, and, ==, !=, <, >, +, -, *, / (operator precedence)
  -> prefix_expression     # -, not
  -> call_expression       # f(args), x.method(args)
  -> _primary_expression
    -> literals (int, float, string, bool)
    -> identifier, dollar_identifier
    -> lambda              # |<A> params| -> ret_type { body }
    -> block               # { stmt; stmt; expr }
    -> if_expression       # if cond { then } else { else }
    -> match_expression    # match scrutinee { pattern => body }
    -> record_expression   # { x: 1, y: 2 }  or  { ..base, x: new }
    -> list_expression     # [1, 2, 3]
    -> tag_expression      # UpperId(args)
    -> handle_expression   # handle body with { op(resume) => body }
    -> return_expression   # return expr
    -> crash_expression    # crash expr
    -> interpolate         # future: string interpolation

_pattern
  -> tag_pattern, record_pattern, list_pattern
  -> literal patterns (int, string, bool)
  -> identifier, wildcard (_)
  -> destructure pattern

_type
  -> function_type         # (Type) -> Type
  -> tag_union_type        # [Ok(a) | Err(e) | ..]
  -> record_type           # { x: Type, y: Type }
  -> effect_row            # [Effect1, Effect2]
  -> applied_type          # List(Int)
  -> primitive_type        # UpperId
  -> type_variable         # lower_id
  -> wildcard_type         # _
```

### Precedence

```
or                              prec.left(1)
and                             prec.left(2)
==, !=                          prec.left(3)
<, >, <=, >=                    prec.left(4)
+, -                            prec.left(5)
*, /, %                         prec.left(6)
prefix (-, not)                 prec.left(7)
call, method_call, field_access prec.left(8)
```

### Disambiguation

- `{` as block vs record: `{` followed by identifier then `:` (with optional whitespace) is a record; otherwise a block. Handled via GLR with dynamic precedence.
- `|` as lambda param delimiter vs tag union separator: position-dependent. In expression position at statement start, `|...|` starts a lambda. Inside `[...]` after a type, `|` separates union tags.
- `!` suffix on binding names: `f!` is a const_declaration with is_effectful = true.
- `$` prefix: `$x` is a dollar_identifier (mutable reference).

## No External Scanner

Camp's lexer is simple enough for pure grammar.js:
- `--` line comments (til EOL)
- Basic `"..."` strings with escape sequences
- No indentation sensitivity
- Identifiers: `[a-z_][a-zA-Z0-9_]*` (lowercase/underscore) and `[A-Z][a-zA-Z0-9_]*` (uppercase for constructors/types)

## Testing & CI

### Corpus Tests

Standard tree-sitter S-expression tests in `tree-sitter/test/corpus/`. Each construct gets its own file. Example:

```
==================
Integer literal
==================
42
---
(source_file
  (expression_statement
    (integer)))
```

### justfile Recipes

```makefile
tree-sitter-generate:
    tree-sitter generate

tree-sitter-test: tree-sitter-generate
    tree-sitter test

tree-sitter-validate: tree-sitter-generate
    #!/bin/bash
    for f in tests/e2e/**/*.camp; do
      if tree-sitter parse "$$f" | grep -q 'ERROR'; then
        echo "FAIL: $$f has parse errors" && exit 1
      fi
    done
    echo "All .camp files parse successfully"

lint-tree-sitter: tree-sitter-test tree-sitter-validate

test: test-unit test-e2e lint-tree-sitter
```

`lint-tree-sitter` is the pre-commit hook target. `test` includes it in the full suite.

### Grammar-Parser Sync Strategy

- **Lightweight**: CI runs `tree-sitter test` + `odin test src` on every commit. Corpus tests break when grammar falls behind the compiler's parser.
- **Medium**: `tree-sitter-validate` parses all e2e `.camp` files and fails on any `ERROR` node. Catches new syntax tree-sitter doesn't know about.
- **Heavy** (future): Snapshot-based drift detection. Regenerate all corpus expected outputs from real `.camp` files and commit them. Any change produces a diff. Tracked as a TODO in `tree-sitter/README.md`.

## Queries

Initial scope, iterated after grammar stabilises:

- **highlights.scm**: keyword, type, constructor, variable, string, number, comment, operator captures
- **locals.scm**: scope tracking for const_declaration bindings
- **tags.scm**: const_declaration for goto-def; effect_declaration and trait_declaration for outline/symbols

## Setup

```sh
tree-sitter init  # scaffold tree-sitter/ (prompts for name, scope, etc.)
# -> name: tree-sitter-camp
# -> scope: source.camp
# -> file-types: ["camp"]
npm install       # install tree-sitter-cli (dev dependency)
```

## References

- [Tree-sitter Creating Parsers](https://tree-sitter.github.io/tree-sitter/creating-parsers/overview)
- [tree-sitter-gleam](https://github.com/gleam-lang/tree-sitter-gleam) -- similar functional language grammar
- [tree-sitter-gren](https://github.com/MaeBrooks/tree-sitter-gren) -- similar functional language grammar
- [Writing a tree-sitter grammar in an afternoon](https://siraben.dev/2022/03/01/tree-sitter.html)
