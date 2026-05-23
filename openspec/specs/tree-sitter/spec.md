# Domain Specification: Tree-sitter

## Purpose

Provide a tree-sitter grammar for Camp that enables syntax highlighting, scope tracking, and symbol tagging for editors, with corpus tests preventing parser/grammar drift.

## Requirements

### Requirement: Grammar Coverage

The tree-sitter grammar SHALL cover all Camp syntactic constructs including declarations, expressions, patterns, and types.

#### Scenario: Declaration parsing

- Given a Camp source file containing const declarations, effect declarations, trait declarations, alias declarations, import declarations, test declarations, and expect declarations
- When parsed by tree-sitter
- Then each declaration SHALL produce a named node matching its construct type

#### Scenario: Expression parsing

- Given Camp source containing binary expressions, prefix expressions, call expressions, lambdas, blocks, if expressions, match expressions, record expressions, list expressions, tag expressions, handle expressions, return expressions, and crash expressions
- When parsed by tree-sitter
- Then each expression SHALL produce a named node with correct precedence

#### Scenario: Pattern parsing

- Given Camp source containing tag patterns, record patterns, list patterns, literal patterns, identifier patterns, wildcard patterns, and destructure patterns
- When parsed by tree-sitter
- Then each pattern SHALL produce a named node

#### Scenario: Type parsing

- Given Camp source containing function types, tag union types, record types, effect rows, applied types, primitive types, type variables, and wildcard types
- When parsed by tree-sitter
- Then each type SHALL produce a named node

### Requirement: Operator Precedence

The grammar SHALL encode correct operator precedence.

#### Scenario: Precedence ordering

- Given Camp source with mixed operators
- When parsed by tree-sitter
- Then the parse tree SHALL reflect precedence from lowest to highest: `or` (1), `and` (2), `==`/`!=` (3), comparison (4), `+`/`-` (5), `*`/`/`/`%` (6), prefix (7), call/field_access (8), anonymous_method (9)

### Requirement: Disambiguation of Ambiguous Syntax

The grammar SHALL correctly disambiguate ambiguous Camp constructs.

#### Scenario: Block vs record

- Given `{` followed by an identifier then `:`
- When parsed by tree-sitter
- Then it SHALL be parsed as a record expression (not a block)

#### Scenario: Lambda params vs tag union separator

- Given `|` in expression position at statement start
- When parsed by tree-sitter
- Then it SHALL start a lambda parameter list

#### Scenario: `|` inside brackets after a type

- Given `|` inside `[...]` after a type
- When parsed by tree-sitter
- Then it SHALL separate union tags

#### Scenario: Effectful function name

- Given `f!` as a binding name
- When parsed by tree-sitter
- Then it SHALL be a const_declaration with `is_effectful = true`

### Requirement: External Scanner for Interpolation

The grammar SHALL use an external C scanner for handling string interpolation brace-depth tracking. The previous requirement that the grammar be implemented entirely in `grammar.js` without an external scanner SHALL be modified to allow an external scanner for interpolated string support.

#### Scenario: External scanner for interpolation

- Given Camp source containing an interpolated string `"${record.{name}}"`
- When tree-sitter parses it
- Then the external scanner SHALL track brace depth to correctly match the interpolation-closing `}`

### Requirement: Corpus Tests

The grammar SHALL include tree-sitter corpus tests for all syntactic constructs.

#### Scenario: Corpus test coverage

- Given each Camp syntactic construct
- When corpus tests are run
- Then each construct SHALL have a test in `tree-sitter/test/corpus/` validating its S-expression parse tree

### Requirement: E2E Validation

All e2e `.camp` test files SHALL parse successfully with tree-sitter.

#### Scenario: Validate against e2e files

- Given all `.camp` files under `tests/e2e/`
- When `tree-sitter parse` is run on each file
- Then no file SHALL produce an `ERROR` node

### Requirement: Syntax Highlighting Queries

The grammar SHALL provide syntax highlighting captures.

#### Scenario: Highlighting captures

- Given Camp source with keywords, types, constructors, variables, strings, numbers, comments, and operators
- When `highlights.scm` is applied
- Then each syntactic class SHALL be captured with an appropriate highlight class

### Requirement: Scope Tracking Queries

The grammar SHALL provide scope/locals tracking for const declarations.

#### Scenario: Locals tracking

- Given Camp source with const declarations
- When `locals.scm` is applied
- Then const_declaration bindings SHALL be tracked for scope

### Requirement: Symbol Tagging Queries

The grammar SHALL provide symbol tagging for goto-definition and outline.

#### Scenario: Symbol tags

- Given Camp source with const declarations, effect declarations, and trait declarations
- When `tags.scm` is applied
- Then these declarations SHALL be tagged for symbol navigation

### Requirement: Grammar-Parser Synchronization

The tree-sitter grammar SHALL stay synchronized with Camp's compiler parser.

#### Scenario: CI synchronization check

- Given a commit changes Camp's syntax
- When CI runs
- Then `tree-sitter test` and `odin test src` SHALL both pass, ensuring grammar and parser stay in sync

#### Scenario: E2E validation check

- Given new syntax is added to Camp
- When e2e `.camp` files use the new syntax
- Then `tree-sitter-validate` SHALL fail if tree-sitter cannot parse the new syntax

### Requirement: Interpolated String Grammar

The tree-sitter grammar SHALL include rules for interpolated strings, raw strings, and multiline strings with interpolation support.

#### Scenario: Interpolated string parse tree

- Given Camp source `"Hello ${name}!"`
- When tree-sitter parses it
- Then it SHALL produce an `interpolated_string` node containing `string_content` and `interpolation` child nodes

#### Scenario: Interpolation node structure

- Given Camp source `"${expr}"`
- When tree-sitter parses it
- Then it SHALL produce an `interpolation` node containing `${`, the expression, and `}`

#### Scenario: Raw string parse tree

- Given Camp source `r"C:\${dir}"`
- When tree-sitter parses it
- Then it SHALL produce a `raw_string` node with interpolation support

#### Scenario: Multiline string parse tree

- Given Camp source `"""Line 1\n${x}"""`
- When tree-sitter parses it
- Then it SHALL produce a `multiline_string` node with interpolation support

### Requirement: Interpolation Highlighting

The tree-sitter highlights query SHALL provide distinct highlighting for interpolation delimiters (`${` and `}`) and the embedded expression.

#### Scenario: Highlighting interpolation delimiters

- Given Camp source `"Hello ${name}!"`
- When `highlights.scm` is applied
- Then `${` and `}` SHALL be captured as `@punctuation.special` and the expression SHALL be captured as `@embedded`
