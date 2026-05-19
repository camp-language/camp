# Tree-sitter Grammar for Camp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a tree-sitter grammar for Camp in `tree-sitter/` with corpus tests, queries, and justfile CI integration.

**Architecture:** Standard tree-sitter project scaffolded via `tree-sitter init` inside `tree-sitter/`. Pure `grammar.js` (no external scanner). Grammar mirrors AST types from `src/ast.odin`. Parse-all-`.camp`-files validation in CI prevents grammar/parser drift.

**Tech Stack:** tree-sitter CLI, JavaScript (grammar DSL), Node.js (for `npm install` devDeps only)

---

### Task 1: Scaffold the tree-sitter project

**Files:**
- Create: `tree-sitter/` directory and all scaffolded files

- [ ] **Step 1: Run tree-sitter init**

```bash
mkdir -p tree-sitter
cd tree-sitter
tree-sitter init
```

Answer the prompts:
- Language name: `Camp`
- Parser name: `tree-sitter-camp`
- Scope: `source.camp`
- File types: `camp`
- License: `MIT`
- Authors: `[your name]`
- Bindings: Node (yes), Rust (yes), Python (yes), Go (yes), C (yes)

- [ ] **Step 2: Install npm dependencies**

```bash
npm install
```

Expected: `node_modules/` created with `tree-sitter-cli` as devDependency. The `tree-sitter` CLI should already be in PATH from home-manager.

- [ ] **Step 3: Verify scaffold works**

```bash
tree-sitter generate
tree-sitter parse --cst - <<< 'hello'
```

Expected: After `tree-sitter generate`, the trivial grammar (matching `hello`) produces a parse tree with no errors.

- [ ] **Step 4: Commit scaffold**

```bash
git add tree-sitter/
git commit -m "feat(tree-sitter): scaffold project with tree-sitter init"
```

---

### Task 2: Configure .gitignore and tree-sitter.json

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add entries to .gitignore**

```bash
cat >> .gitignore << 'EOF'
tree-sitter/node_modules/
tree-sitter/build/
EOF
```

- [ ] **Step 2: Verify tree-sitter.json has correct scope**

Read `tree-sitter/tree-sitter.json` and confirm it has:
```json
{
  "grammars": [
    {
      "name": "tree-sitter-camp",
      "scope": "source.camp",
      "file-types": ["camp"],
      ...
    }
  ]
}
```

If not, fix it to match.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add tree-sitter entries to .gitignore"
```

---

### Task 3: Write lexer rules — tokens, whitespace, comments

**Files:**
- Modify: `tree-sitter/grammar.js`

Replace the entire contents of `grammar.js` with the base skeleton including extras (whitespace, comments) and keyword/operator token definitions.

- [ ] **Step 1: Write skeleton with extras, word, and token rules**

Write `tree-sitter/grammar.js`:

```js
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: "camp",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

  rules: {
    source_file: ($) => repeat($._declaration),

    comment: ($) => token(seq("--", /.*/)),

    _declaration: ($) => choice(
      $.const_declaration,
    ),

    const_declaration: ($) => seq(
      $.identifier,
      "=",
      $._expression,
    ),

    _expression: ($) => $._primary_expression,

    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.identifier,
    ),

    // --- Literals ---
    integer: ($) => /[0-9][0-9_]*/,

    float: ($) => /[0-9][0-9_]*\.[0-9][0-9_]*/,

    string: ($) => seq(
      '"',
      repeat(choice(/[^\\"\n]+/, $.escape_sequence)),
      '"',
    ),

    escape_sequence: ($) => token(seq("\\", /[nrt"\\]/)),

    boolean: ($) => choice("true", "false"),

    // --- Identifiers ---
    identifier: ($) => /[_a-z][_a-zA-Z0-9]*/,

    // --- Keywords ---
    _if: ($) => "if",
    _else: ($) => "else",
    _match: ($) => "match",
    _effect: ($) => "effect",
    _trait: ($) => "trait",
    _is: ($) => "is",
    _alias: ($) => "alias",
    _handle: ($) => "handle",
    _intercept: ($) => "intercept",
    _in: ($) => "in",
    _with: ($) => "with",
    _import: ($) => "import",
    _exposing: ($) => "exposing",
    _as: ($) => "as",
    _unsafe: ($) => "unsafe",
    _for: ($) => "for",
    _and: ($) => "and",
    _or: ($) => "or",
    _not: ($) => "not",
    _expect: ($) => "expect",
    _test: ($) => "test",
  },
});
```

- [ ] **Step 2: Generate and test the skeleton**

```bash
cd tree-sitter && tree-sitter generate
```

Expected: No errors from `tree-sitter generate`.

- [ ] **Step 3: Write a simple corpus test**

Create `tree-sitter/test/corpus/literals.txt`:

```
========
Integer literal
========
42
---
(source_file
  (const_declaration
    (integer)))
```

- [ ] **Step 4: Run corpus tests**

```bash
cd tree-sitter && tree-sitter test
```

Expected: Test passes.

- [ ] **Step 5: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/literals.txt
git commit -m "feat(tree-sitter): add lexer rules, skeleton grammar, first corpus test"
```

---

### Task 4: Write expression rules — literals, identifiers, basic primaries

**Files:**
- Modify: `tree-sitter/grammar.js`

Extend `_primary_expression` to cover all primary forms except lambdas, blocks, records (which have disambiguation challenges handled in Task 5).

- [ ] **Step 1: Add type_identifier, dollar_identifier, and tag_expression**

In `grammar.js`, add to `rules`:

```js
    // --- Identifiers (continued) ---
    type_identifier: ($) => /[A-Z][a-zA-Z0-9]*/,

    dollar_identifier: ($) => seq("$", $.identifier),

    // --- Literals (continued) ---

    // --- Primary expressions ---
    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.dollar_identifier,
      $.identifier,
      $.type_identifier,
      $.tag_expression,
      $.list_expression,
      $.parenthesized_expression,
    ),

    tag_expression: ($) => seq(
      field("name", $.type_identifier),
      optional(field("arguments", $.arguments)),
    ),

    arguments: ($) => seq(
      "(",
      optional(seq($._expression, repeat(seq(",", $._expression)))),
      ")",
    ),

    list_expression: ($) => seq(
      "[",
      optional(seq($._expression, repeat(seq(",", $._expression)))),
      "]",
    ),

    parenthesized_expression: ($) => seq(
      "(",
      $._expression,
      ")",
    ),
```

- [ ] **Step 2: Add corpus tests**

Append to `tree-sitter/test/corpus/literals.txt`:

```
========
Float literal
========
3.14
---
(source_file
  (const_declaration
    (float)))

========
String literal
========
"hello world"
---
(source_file
  (const_declaration
    (string)))

========
Boolean literal
========
true
---
(source_file
  (const_declaration
    (boolean)))

========
Identifier
========
x
---
(source_file
  (const_declaration
    (identifier)))

========
Dollar identifier
========
$x
---
(source_file
  (const_declaration
    (dollar_identifier)))

========
Type identifier
========
Ok
---
(source_file
  (const_declaration
    (type_identifier)))

========
Tag expression
========
Ok(42)
---
(source_file
  (const_declaration
    (tag_expression
      (type_identifier)
      (arguments
        (integer)))))

========
List expression empty
========
[]
---
(source_file
  (const_declaration
    (list_expression)))

========
List expression
========
[1, 2, 3]
---
(source_file
  (const_declaration
    (list_expression
      (integer)
      (integer)
      (integer))))
```

- [ ] **Step 3: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/literals.txt
git commit -m "feat(tree-sitter): add literals, identifiers, tag/list/paren expressions"
```

---

### Task 5: Write expression rules — lambdas, blocks, records, if, match

**Files:**
- Modify: `tree-sitter/grammar.js`

Add the remaining primary expressions. Lambda uses `|` and `(` syntaxes. Block vs record disambiguation uses GLR. If/match follow expression-body syntax.

- [ ] **Step 1: Add disambiguation rules for `{` (block vs record)**

The key insight: after `{`, if the next token is an identifier followed by `:` (or `..` for spread), it's a record. Otherwise it's a block. In tree-sitter, we use `conflicts` and let GLR handle it.

Add to the `conflicts` array in `grammar.js` (before `rules`):
```js
  conflicts: ($) => [
    [$.block, $.record_expression],
  ],
```

- [ ] **Step 2: Add lambda, block, record, if, match, handle expressions**

Add these rules to the `rules` object:

```js
    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.dollar_identifier,
      $.identifier,
      $.type_identifier,
      $.tag_expression,
      $.list_expression,
      $.parenthesized_expression,
      $.lambda_expression,
      $.block,
      $.record_expression,
      $.if_expression,
      $.match_expression,
      $.handle_expression,
      $.return_expression,
      $.crash_expression,
    ),

    // --- Lambda ---
    lambda_expression: ($) => choice(
      $.pipe_lambda,
      $.paren_lambda,
    ),

    pipe_lambda: ($) => seq(
      "|",
      optional(seq(
        optional($.type_parameters),
        optional(seq(
          field("parameters", $.lambda_parameters),
        )),
      )),
      "|",
      optional(seq("->", field("return_type", $._type))),
      field("body", $._expression),
    ),

    lambda_parameters: ($) => seq(
      $.lambda_parameter,
      repeat(seq(",", $.lambda_parameter)),
    ),

    lambda_parameter: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("type", $._type))),
    ),

    type_parameters: ($) => seq(
      "<",
      $.type_parameter,
      repeat(seq(",", $.type_parameter)),
      ">",
    ),

    type_parameter: ($) => $.identifier,

    paren_lambda: ($) => seq(
      "(",
      optional(field("parameters", $.lambda_parameters)),
      ")",
      optional(seq(
        "->",
        optional($.effect_annotation),
        field("return_type", $._type),
      )),
      field("body", $._expression),
    ),

    effect_annotation: ($) => seq(
      "{",
      optional(seq($.type_identifier, repeat(seq(",", $.type_identifier)))),
      "}",
    ),

    // --- Block ---
    block: ($) => seq(
      "{",
      repeat($._statement),
      optional($._expression),
      "}",
    ),

    _statement: ($) => seq(
      $._expression,
    ),

    // --- Record ---
    record_expression: ($) => seq(
      "{",
      optional(seq("..", field("spread", $._expression), ",")),
      field("fields", $.record_fields),
      "}",
    ),

    record_fields: ($) => seq(
      $.record_field,
      repeat(seq(",", $.record_field)),
      optional(","),
    ),

    record_field: ($) => seq(
      field("name", $.identifier),
      ":",
      field("value", $._expression),
    ),

    // --- If ---
    if_expression: ($) => prec.right(seq(
      "if",
      field("condition", $._expression),
      field("consequence", $._expression),
      optional(seq("else", field("alternative", $._expression))),
    )),

    // --- Match ---
    match_expression: ($) => seq(
      "match",
      field("scrutinee", $._expression),
      "{",
      field("arms", $.match_arms),
      "}",
    ),

    match_arms: ($) => seq(
      $.match_arm,
      repeat(seq("|", $.match_arm)),
    ),

    match_arm: ($) => seq(
      field("pattern", $._pattern),
      "->",
      field("body", $._expression),
    ),

    // --- Handle ---
    handle_expression: ($) => seq(
      choice("handle", "intercept"),
      field("body", $._expression),
      "with",
      "{",
      field("arms", $.handler_arms),
      "}",
    ),

    handler_arms: ($) => repeat1($.handler_arm),

    handler_arm: ($) => seq(
      field("operation", $.type_identifier),
      ".",
      field("name", $.identifier),
      "(",
      field("resume_param", $.identifier),
      ")",
      "->",
      field("body", $._expression),
    ),

    // --- Return/Crash ---
    return_expression: ($) => seq("return", $._expression),

    crash_expression: ($) => seq("crash", $._expression),
```

- [ ] **Step 3: Update pattern rules (placeholder for later tasks)**

For now, add a minimal pattern rule so match arms work:
```js
    _pattern: ($) => choice(
      $.identifier,
      $.type_identifier,
      $.integer,
      $.string,
      $.boolean,
      $.wildcard_pattern,
      $.or_pattern,
    ),

    wildcard_pattern: ($) => "_",

    or_pattern: ($) => seq(
      $._pattern,
      "|",
      $._pattern,
    ),
```

- [ ] **Step 4: Add type rules (placeholder for later tasks)**

```js
    _type: ($) => choice(
      $.type_identifier,
      $.function_type,
    ),

    function_type: ($) => seq(
      optional(seq("(", optional(seq($._type, repeat(seq(",", $._type)))), ")")),
      "->",
      $._type,
    ),
```

- [ ] **Step 5: Generate and fix conflicts**

```bash
cd tree-sitter && tree-sitter generate
```

If there are conflicts, inspect them and add entries to the `conflicts` array. Common conflicts: block vs record (`{`); lambda vs binary expression (`|`).

- [ ] **Step 6: Write corpus tests**

Create `tree-sitter/test/corpus/expressions.txt`:

```
========
Pipe lambda no params
========
|| 42
---
(source_file
  (const_declaration
    (lambda_expression
      (pipe_lambda
        (integer)))))

========
Pipe lambda with params
========
|x| x
---
(source_file
  (const_declaration
    (lambda_expression
      (pipe_lambda
        (lambda_parameters
          (lambda_parameter
            (identifier)))
        (identifier)))))

========
Pipe lambda with return type
========
|| -> I64 { 42 }
---
(source_file
  (const_declaration
    (lambda_expression
      (pipe_lambda
        (return_type
          (type_identifier))
        (block
          (integer))))))

========
Paren lambda
========
(x: I64) -> I64 { x + 1 }
---
(source_file
  (const_declaration
    (lambda_expression
      (paren_lambda
        (lambda_parameters
          (lambda_parameter
            (identifier)
            (type_identifier)))
        (return_type
          (type_identifier))
        (block)))))

========
Block expression
========
{ 1 2 3 }
---
(source_file
  (const_declaration
    (block
      (integer)
      (integer)
      (integer))))

========
Record expression
========
{ x: 1, y: 2 }
---
(source_file
  (const_declaration
    (record_expression
      (record_fields
        (record_field
          (identifier)
          (integer))
        (record_field
          (identifier)
          (integer))))))

========
Record spread
========
{ x: 10 ..p }
---
(source_file
  (const_declaration
    (record_expression
      (spread
        (identifier))
      (record_fields
        (record_field
          (identifier)
          (integer))))))

========
If expression
========
if true 1 else 0
---
(source_file
  (const_declaration
    (if_expression
      (boolean)
      (integer)
      (integer))))

========
If without else
========
if true { 1 }
---
(source_file
  (const_declaration
    (if_expression
      (boolean)
      (block
        (integer)))))

========
Match expression
========
match x { 1 -> 0 | _ -> 1 }
---
(source_file
  (const_declaration
    (match_expression
      (identifier)
      (match_arms
        (match_arm
          (integer)
          (integer))
        (match_arm
          (wildcard_pattern)
          (integer))))))

========
Handle expression
========
handle body with { E.op(r) -> r }
---
(source_file
  (const_declaration
    (handle_expression
      (identifier)
      (handler_arms
        (handler_arm
          (type_identifier)
          (identifier)
          (identifier)
          (identifier))))))

========
Return expression
========
return 42
---
(source_file
  (const_declaration
    (return_expression
      (integer))))

========
Crash expression
========
crash "oops"
---
(source_file
  (const_declaration
    (crash_expression
      (string))))
```

- [ ] **Step 7: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass. If any fail, use `tree-sitter test -u` to update expected outputs and inspect diffs to understand the actual parse tree shape.

- [ ] **Step 8: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/expressions.txt
git commit -m "feat(tree-sitter): add lambda, block, record, if, match, handle expressions"
```

---

### Task 6: Write operator precedence rules

**Files:**
- Modify: `tree-sitter/grammar.js`

Add binary and prefix operators with correct precedence and associativity.

- [ ] **Step 1: Add operator expression rules**

Replace the `_expression` rule and add operator rules in `grammar.js`:

```js
    _expression: ($) => choice(
      $.binary_expression,
      $.unary_expression,
      $.call_expression,
      $.field_access_expression,
      $.method_call_expression,
      $._primary_expression,
    ),

    binary_expression: ($) => choice(
      ...[
        ["or", 1],
        ["and", 2],
        ["==", 3],
        ["!=", 3],
        ["<", 4],
        [">", 4],
        ["<=", 4],
        [">=", 4],
        ["+", 5],
        ["-", 5],
        ["*", 6],
        ["/", 6],
        ["%", 6],
      ].map(([op, prec]) =>
        prec.left(prec, seq(
          field("left", $._expression),
          field("operator", op),
          field("right", $._expression),
        ))
      ),
    ),

    unary_expression: ($) => choice(
      prec.left(7, seq(
        field("operator", "-"),
        field("argument", $._expression),
      )),
      prec.left(7, seq(
        field("operator", "not"),
        field("argument", $._expression),
      )),
    ),

    call_expression: ($) => prec.left(8, seq(
      field("function", $._expression),
      field("arguments", $.arguments),
    )),

    method_call_expression: ($) => prec.left(8, seq(
      field("receiver", $._expression),
      ".",
      field("method", $.identifier),
      field("arguments", $.arguments),
    )),

    field_access_expression: ($) => prec.left(8, seq(
      field("record", $._expression),
      ".",
      field("field", $.identifier),
    )),
```

- [ ] **Step 2: Write corpus tests**

Create `tree-sitter/test/corpus/operators.txt`:

```
========
Binary arithmetic
========
1 + 2
---
(source_file
  (const_declaration
    (binary_expression
      (integer)
      (integer))))

========
Binary precedence
========
1 + 2 * 3
---
(source_file
  (const_declaration
    (binary_expression
      (integer)
      (binary_expression
        (integer)
        (integer)))))

========
Binary comparison
========
x == y
---
(source_file
  (const_declaration
    (binary_expression
      (identifier)
      (identifier))))

========
Binary logical
========
true and false
---
(source_file
  (const_declaration
    (binary_expression
      (boolean)
      (boolean))))

========
Unary negation
========
-42
---
(source_file
  (const_declaration
    (unary_expression
      (integer))))

========
Unary not
========
not true
---
(source_file
  (const_declaration
    (unary_expression
      (boolean))))

========
Function call
========
f(x)
---
(source_file
  (const_declaration
    (call_expression
      (identifier)
      (arguments
        (identifier)))))

========
Method call
========
x.foo()
---
(source_file
  (const_declaration
    (method_call_expression
      (identifier)
      (identifier)
      (arguments))))

========
Field access
========
r.x
---
(source_file
  (const_declaration
    (field_access_expression
      (identifier)
      (identifier))))
```

- [ ] **Step 3: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass. Use `tree-sitter test -u` if needed to update expected outputs.

- [ ] **Step 4: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/operators.txt
git commit -m "feat(tree-sitter): add operator precedence rules"
```

---

### Task 7: Write pattern rules

**Files:**
- Modify: `tree-sitter/grammar.js`

Replace the placeholder `_pattern` rule with full pattern support.

- [ ] **Step 1: Add full pattern rules**

Replace the `_pattern` rule and add sub-patterns:

```js
    _pattern: ($) => choice(
      $.wildcard_pattern,
      $.or_pattern,
      $.tag_pattern,
      $.record_pattern,
      $.list_pattern,
      $.integer,
      $.string,
      $.boolean,
      $.type_identifier,
      $.identifier,
    ),

    wildcard_pattern: ($) => "_",

    or_pattern: ($) => prec.right(seq(
      field("left", $._pattern),
      "|",
      field("right", $._pattern),
    )),

    tag_pattern: ($) => seq(
      field("name", $.type_identifier),
      optional(field("arguments", $.pattern_arguments)),
    ),

    pattern_arguments: ($) => seq(
      "(",
      optional(seq($._pattern, repeat(seq(",", $._pattern)))),
      ")",
    ),

    record_pattern: ($) => seq(
      "{",
      optional(seq(
        field("fields", $.record_pattern_fields),
        optional(","),
      )),
      "}",
    ),

    record_pattern_fields: ($) => seq(
      $.record_pattern_field,
      repeat(seq(",", $.record_pattern_field)),
    ),

    record_pattern_field: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("pattern", $._pattern))),
    ),

    list_pattern: ($) => seq(
      "[",
      optional(seq($._pattern, repeat(seq(",", $._pattern)))),
      "]",
    ),
```

- [ ] **Step 2: Write corpus tests**

Create `tree-sitter/test/corpus/patterns.txt`:

```
========
Wildcard pattern
========
x = _ 0
---
(source_file
  (const_declaration
    (identifier)
    (wildcard_pattern))
  (const_declaration
    (integer)))

========
Int literal pattern
========
x = 1 0
---
(source_file
  (const_declaration
    (identifier)
    (integer))
  (const_declaration
    (integer)))

========
Or pattern
========
x = 1 | 2 0
---
(source_file
  (const_declaration
    (identifier)
    (or_pattern
      (integer)
      (integer)))
  (const_declaration
    (integer)))

========
Tag pattern
========
x = Ok(v) 0
---
(source_file
  (const_declaration
    (identifier)
    (tag_pattern
      (type_identifier)
      (pattern_arguments
        (identifier))))
  (const_declaration
    (integer)))

========
Record pattern
========
x = { x: 1, y } 0
---
(source_file
  (const_declaration
    (identifier)
    (record_pattern
      (record_pattern_fields
        (record_pattern_field
          (identifier)
          (integer))
        (record_pattern_field
          (identifier)))))
  (const_declaration
    (integer)))

========
List pattern
========
x = [1, 2] 0
---
(source_file
  (const_declaration
    (identifier)
    (list_pattern
      (integer)
      (integer)))
  (const_declaration
    (integer)))
```

- [ ] **Step 3: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/patterns.txt
git commit -m "feat(tree-sitter): add full pattern rules"
```

---

### Task 8: Write type rules

**Files:**
- Modify: `tree-sitter/grammar.js`

Replace the placeholder `_type` rule with full type support.

- [ ] **Step 1: Add full type rules**

Replace the `_type` rule and add sub-types:

```js
    _type: ($) => choice(
      $.type_identifier,
      $.function_type,
      $.tag_union_type,
      $.record_type,
      $.applied_type,
      $.wildcard_type,
      $.type_variable,
    ),

    function_type: ($) => seq(
      optional(seq(
        "(",
        optional(seq($._type, repeat(seq(",", $._type)))),
        ")",
      )),
      "->",
      optional($.effect_annotation),
      $._type,
    ),

    tag_union_type: ($) => seq(
      "[",
      $.tag_union_variant,
      repeat(seq("|", $.tag_union_variant)),
      optional(seq("|", $.wildcard_type)),
      "]",
    ),

    tag_union_variant: ($) => seq(
      field("name", $.type_identifier),
      optional(field("arguments", $.type_arguments)),
    ),

    record_type: ($) => seq(
      "{",
      optional(seq(
        $.record_type_field,
        repeat(seq(",", $.record_type_field)),
        optional(","),
      )),
      "}",
    ),

    record_type_field: ($) => seq(
      field("name", $.identifier),
      ":",
      field("type", $._type),
    ),

    applied_type: ($) => seq(
      field("name", $.type_identifier),
      field("arguments", $.type_arguments),
    ),

    type_arguments: ($) => seq(
      "(",
      optional(seq($._type, repeat(seq(",", $._type)))),
      ")",
    ),

    wildcard_type: ($) => "_",

    type_variable: ($) => $.identifier,
```

- [ ] **Step 2: Write corpus tests**

Create `tree-sitter/test/corpus/types.txt`:

```
========
Primitive type
========
I64
---
(source_file
  (const_declaration
    (type_identifier)))

========
Function type
========
() -> I64
---
(source_file
  (const_declaration
    (function_type
      (type_identifier))))

========
Function type with params
========
(I64, I64) -> I64
---
(source_file
  (const_declaration
    (function_type
      (type_identifier)
      (type_identifier)
      (type_identifier))))

========
Tag union type
========
[Ok | Err]
---
(source_file
  (const_declaration
    (tag_union_type
      (tag_union_variant
        (type_identifier))
      (tag_union_variant
        (type_identifier)))))

========
Tag union type with payloads
========
[Ok(I64) | Err(String)]
---
(source_file
  (const_declaration
    (tag_union_type
      (tag_union_variant
        (type_identifier)
        (type_arguments
          (type_identifier)))
      (tag_union_variant
        (type_identifier)
        (type_arguments
          (type_identifier))))))

========
Record type
========
{ x: I64, y: I64 }
---
(source_file
  (const_declaration
    (record_type
      (record_type_field
        (identifier)
        (type_identifier))
      (record_type_field
        (identifier)
        (type_identifier)))))

========
Applied type
========
List(I64)
---
(source_file
  (const_declaration
    (applied_type
      (type_identifier)
      (type_arguments
        (type_identifier)))))
```

- [ ] **Step 3: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/types.txt
git commit -m "feat(tree-sitter): add full type rules"
```

---

### Task 9: Write declaration rules

**Files:**
- Modify: `tree-sitter/grammar.js`

Replace the placeholder `_declaration` rule with all declaration forms.

- [ ] **Step 1: Add all declaration rules**

Replace `_declaration` and `const_declaration`:

```js
    _declaration: ($) => choice(
      $.const_declaration,
      $.effect_declaration,
      $.trait_declaration,
      $.alias_declaration,
      $.import_declaration,
      $.test_declaration,
      $.expect_declaration,
    ),

    const_declaration: ($) => seq(
      field("name", $.identifier),
      optional("!"),
      optional(seq(":", field("type_annotation", $._type))),
      "=",
      field("body", $._expression),
    ),

    effect_declaration: ($) => seq(
      "effect",
      field("name", $.type_identifier),
      "{",
      field("operations", repeat($.effect_operation)),
      "}",
    ),

    effect_operation: ($) => seq(
      field("name", $.identifier),
      optional(seq(
        "(",
        optional(field("parameters", $.effect_parameters)),
        ")",
      )),
      optional(seq("->", field("return_type", $._type))),
    ),

    effect_parameters: ($) => seq(
      $.effect_parameter,
      repeat(seq(",", $.effect_parameter)),
    ),

    effect_parameter: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("type", $._type))),
    ),

    trait_declaration: ($) => seq(
      "trait",
      field("name", $.type_identifier),
      optional(seq("is", field("parent", $.type_identifier))),
      "{",
      repeat($.trait_method),
      "}",
    ),

    trait_method: ($) => seq(
      field("name", $.identifier),
      ":",
      field("type", $._type),
    ),

    alias_declaration: ($) => seq(
      "alias",
      field("name", $.type_identifier),
      "=",
      field("target", $._type),
    ),

    import_declaration: ($) => seq(
      "import",
      field("module", $.string),
      optional(seq(
        "exposing",
        "(",
        optional(field("exposed", $.exposed_names)),
        ")",
      )),
      optional(seq("as", field("alias", $.identifier))),
    ),

    exposed_names: ($) => seq(
      $.identifier,
      repeat(seq(",", $.identifier)),
    ),

    test_declaration: ($) => seq(
      "test",
      field("name", $.string),
      field("body", $._expression),
    ),

    expect_declaration: ($) => seq(
      "expect",
      field("condition", $._expression),
    ),
```

- [ ] **Step 2: Write corpus tests**

Create `tree-sitter/test/corpus/declarations.txt`:

```
========
Const declaration
========
x = 42
---
(source_file
  (const_declaration
    (identifier)
    (integer)))

========
Const with type annotation
========
x: I64 = 42
---
(source_file
  (const_declaration
    (identifier)
    (type_annotation
      (type_identifier))
    (integer)))

========
Effectful const
========
main! = || 42
---
(source_file
  (const_declaration
    (identifier)
    (lambda_expression
      (pipe_lambda
        (integer)))))

========
Effect declaration
========
effect IO { println }
---
(source_file
  (effect_declaration
    (type_identifier)
    (effect_operation
      (identifier))))

========
Effect with typed operation
========
effect IO { println(s: String) -> () }
---
(source_file
  (effect_declaration
    (type_identifier)
    (effect_operation
      (identifier)
      (effect_parameters
        (effect_parameter
          (identifier)
          (type_identifier)))
      (return_type
        (type_identifier)))))

========
Trait declaration
========
trait Display { display: Self -> String }
---
(source_file
  (trait_declaration
    (type_identifier)
    (trait_method
      (identifier)
      (function_type
        (type_identifier)
        (type_identifier)))))

========
Alias declaration
========
alias UserId = I64
---
(source_file
  (alias_declaration
    (type_identifier)
    (type_identifier)))

========
Import declaration
========
import "std/io" exposing (println, read) as io
---
(source_file
  (import_declaration
    (string)
    (exposed_names
      (identifier)
      (identifier))
    (identifier)))

========
Test declaration
========
test "it works" { 42 }
---
(source_file
  (test_declaration
    (string)
    (block
      (integer))))

========
Expect declaration
========
expect 1 + 1 == 2
---
(source_file
  (expect_declaration
    (binary_expression
      (integer)
      (integer))))
```

- [ ] **Step 3: Generate and test**

```bash
cd tree-sitter && tree-sitter generate && tree-sitter test
```

Expected: All tests pass. The `!` after identifier in const_declaration may need adjustment — if so, run `tree-sitter test -u` to see actual tree shape and adjust.

- [ ] **Step 4: Commit**

```bash
git add tree-sitter/grammar.js tree-sitter/test/corpus/declarations.txt
git commit -m "feat(tree-sitter): add all declaration rules"
```

---

### Task 10: Add justfile recipes

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Add tree-sitter recipes to justfile**

Append to `justfile`:

```makefile
tree-sitter-generate:
    cd tree-sitter && tree-sitter generate

tree-sitter-test: tree-sitter-generate
    cd tree-sitter && tree-sitter test

tree-sitter-validate: tree-sitter-generate
    #!/bin/bash
    for f in tests/e2e/**/*.camp; do
      if tree-sitter parse "$$f" 2>&1 | grep -q 'ERROR'; then
        echo "FAIL: $$f has parse errors" && exit 1
      fi
    done
    echo "All .camp files parse successfully"

lint-tree-sitter: tree-sitter-test tree-sitter-validate

test: test-unit test-e2e lint-tree-sitter
```

- [ ] **Step 2: Run tree-sitter-test**

```bash
just tree-sitter-test
```

Expected: All corpus tests pass.

- [ ] **Step 3: Run tree-sitter-validate**

```bash
just tree-sitter-validate
```

Expected: All e2e `.camp` files parse without ERROR nodes. If some fail, inspect which files and why (likely missing syntax features) — fix the grammar or note them as known gaps.

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "feat(just): add tree-sitter generate, test, validate, and lint recipes"
```

---

### Task 11: Write query files (highlights, locals, tags)

**Files:**
- Modify: `tree-sitter/queries/highlights.scm`
- Modify: `tree-sitter/queries/locals.scm`
- Modify: `tree-sitter/queries/tags.scm`

- [ ] **Step 1: Write highlights.scm**

```scm
; Keywords
[
  "if"
  "else"
  "match"
  "effect"
  "trait"
  "is"
  "alias"
  "handle"
  "intercept"
  "in"
  "with"
  "import"
  "exposing"
  "as"
  "unsafe"
  "for"
  "and"
  "or"
  "not"
  "expect"
  "test"
  "return"
  "crash"
] @keyword

; Types
(type_identifier) @type

; Constructors (type_identifier in tag_expression)
(tag_expression name: (type_identifier) @constructor)

; Variables
(identifier) @variable

; String
(string) @string

; Number
(integer) @number
(float) @float

; Boolean
(boolean) @boolean

; Operators
[
  "+"
  "-"
  "*"
  "/"
  "%"
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "="
  "->"
  "=>"
  "|"
] @operator

; Comments
(comment) @comment

; Punctuation
[
  "(" ")"
  "[" "]"
  "{" "}"
  ":"
  ","
  "."
  ".."
  "$"
  "!"
] @punctuation
```

- [ ] **Step 2: Write locals.scm**

```scm
; Variable definitions
(const_declaration
  name: (identifier) @definition.variable)

; Type parameter definitions
(type_parameter
  (identifier) @definition.type_parameter)

; References
(identifier) @reference
```

- [ ] **Step 3: Write tags.scm**

```scm
; Function/const definitions
(const_declaration
  name: (identifier) @name) @definition.function

; Effect definitions
(effect_declaration
  name: (type_identifier) @name) @definition.type

; Trait definitions
(trait_declaration
  name: (type_identifier) @name) @definition.type

; Alias definitions
(alias_declaration
  name: (type_identifier) @name) @definition.type
```

- [ ] **Step 4: Verify query syntax**

```bash
cd tree-sitter && tree-sitter highlight -H highlights.scm - <<< 'x = 42'
```

Expected: Output with ANSI color codes (no errors loading query file).

- [ ] **Step 5: Commit**

```bash
git add tree-sitter/queries/highlights.scm tree-sitter/queries/locals.scm tree-sitter/queries/tags.scm
git commit -m "feat(tree-sitter): add highlight, locals, and tags queries"
```

---

### Task 12: Parse all e2e .camp files and fix remaining issues

**Files:**
- Modify: `tree-sitter/grammar.js` (as needed)

- [ ] **Step 1: Run tree-sitter-validate**

```bash
just tree-sitter-validate
```

- [ ] **Step 2: For each failing file, inspect the parse tree**

```bash
tree-sitter parse tests/e2e/path/to/failing.camp
```

- [ ] **Step 3: Fix grammar rules to handle missing syntax**

Common issues likely:
- String interpolation `"{x}"` — the lexer currently treats `{x}` as literal text. Add support or mark as known limitation.
- `{ ..base, x: 10 }` record update syntax (spread + new fields in `{ }`)
- `$` assignment: `$x = 42` vs $x usage
- Nested `if` without braces: `if true 1 else 0`
- Effect annotation `{IO}` in function types
- `..` in record/update patterns/spreads

Fix each issue iteratively:
1. Inspect the failing parse tree
2. Modify `grammar.js`
3. Run `tree-sitter generate`
4. Re-test that file
5. Update corpus tests with `tree-sitter test -u` for any affected existing tests

- [ ] **Step 4: Add corpus tests for edge cases found during validation**

Add new test cases to appropriate corpus files for any syntax patterns discovered during validation.

- [ ] **Step 5: Run full just test suite**

```bash
just test
```

Expected: unit tests pass, e2e tests pass, tree-sitter tests pass, tree-sitter-validate passes.

- [ ] **Step 6: Commit**

```bash
git add -A tree-sitter/
git commit -m "fix(tree-sitter): resolve parse issues found during e2e validation"
```

---

### Task 13: Add tree-sitter README with sync strategy

**Files:**
- Create: `tree-sitter/README.md`

- [ ] **Step 1: Write README**

```markdown
# tree-sitter-camp

Tree-sitter grammar for the [Camp](https://github.com/camp-language/camp) programming language.

## Usage

```sh
just tree-sitter-test      # run corpus tests
just tree-sitter-validate  # parse all e2e .camp files
just lint-tree-sitter      # both (pre-commit)
```

## Development

1. Edit `grammar.js`
2. Run `tree-sitter generate`
3. Run `tree-sitter test`
4. Add tests to `test/corpus/`

## Keeping in Sync with the Compiler

When the compiler's parser changes:

1. Run `just tree-sitter-validate` — any syntax changes will produce ERROR nodes
2. Update `grammar.js` to match
3. Run `tree-sitter test -u` to update corpus expected outputs
4. Review the diff of test changes to confirm they match the new syntax

## TODO

- [ ] Heavy sync mechanism: snapshot-based drift detection — regenerate all corpus expected outputs from real `.camp` files and commit them. Any change to either side produces a diff.
- [ ] String interpolation `"{x} is the answer"` — currently lexed as a plain string; needs external scanner for proper `{expr}` inside string support
```

- [ ] **Step 2: Commit**

```bash
git add tree-sitter/README.md
git commit -m "docs(tree-sitter): add README with sync strategy and TODOs"
```
