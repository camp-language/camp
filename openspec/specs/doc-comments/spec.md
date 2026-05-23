# Doc Comments — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's documentation comment system: `///` syntax, markdown content, doc comment attachment, code block testing (doctests), the `camp doc` documentation generator, and LSP hover integration for documentation.

For testing language features (`expect`, `test`, `todo`, `camp test`), see `openspec/specs/testing-language/spec.md`.

## Requirements

### Requirement: Comment Syntax

Camp SHALL support three comment prefixes: `//` for regular comments, `///` for doc comments, and `//#` for hidden lines in doc code blocks.

#### Scenario: Regular comment

- **GIVEN** a line starting with `//` (not `///` or `//#`)
- **WHEN** the compiler processes it
- **THEN** the line SHALL be ignored by the compiler and not attached to any declaration

#### Scenario: Doc comment

- **GIVEN** a line starting with `///` followed by a space and content
- **WHEN** the compiler processes it
- **THEN** the content SHALL be parsed as Markdown and attached to the next declaration

#### Scenario: Hidden line in code block

- **GIVEN** a line starting with `//#` followed by a space and content inside a fenced code block within a doc comment
- **WHEN** the doctest runner processes the code block
- **THEN** the line SHALL be compiled as real Camp code but SHALL NOT appear in rendered documentation

#### Scenario: Hidden line outside code block

- **GIVEN** a line starting with `//#` outside a fenced code block within a doc comment
- **WHEN** the compiler processes it
- **THEN** it SHALL produce a compiler error — `//#` is only valid inside fenced code blocks

### Requirement: Doc Comment Attachment

Doc comments SHALL attach to the declaration that immediately follows them. A `///` doc comment SHALL NOT attach to a preceding declaration.

#### Scenario: Doc comment before function

- **GIVEN** a `///` comment immediately before a function definition
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that function

#### Scenario: Doc comment before nominal type

- **GIVEN** a `///` comment immediately before a nominal type definition
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that nominal type

#### Scenario: Multiple doc comments

- **GIVEN** consecutive `///` lines before a declaration
- **WHEN** the compiler processes the file
- **THEN** all consecutive `///` lines SHALL be combined into a single doc comment for that declaration

#### Scenario: Blank line between doc comment and declaration

- **GIVEN** a `///` comment followed by a blank line, then a declaration
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL NOT attach to the declaration — a blank line breaks the attachment

### Requirement: Module Doc Comment

The first `///` comment in a file, when it appears before any declaration, SHALL be the module doc comment.

#### Scenario: Module doc comment

- **GIVEN** a `///` comment at the top of a file before any declaration
- **WHEN** the compiler processes the file
- **THEN** the comment SHALL be attached to the module itself, not to the first declaration

### Requirement: Doc Comment Targets

Doc comments SHALL be attachable to all top-level declarations, the module itself, type members and fields, tag variants, and function parameters.

#### Scenario: Doc comment on effect operation

- **GIVEN** a `///` comment immediately before an effect operation definition
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that effect operation

#### Scenario: Doc comment on trait method

- **GIVEN** a `///` comment immediately before a trait method signature
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that method

#### Scenario: Doc comment on tag variant

- **GIVEN** a `///` comment immediately before a tag variant in a tag union type definition
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that tag variant

#### Scenario: Doc comment on function parameter

- **GIVEN** a `///` comment on the line immediately before a function parameter in a multiline parameter list
- **WHEN** the compiler processes the file
- **THEN** the doc comment SHALL be attached to that parameter

### Requirement: Markdown Content

The content of a doc comment SHALL be parsed as CommonMark Markdown.

#### Scenario: Paragraphs in doc comments

- **GIVEN** a doc comment with multiple lines of prose
- **WHEN** the doc is rendered
- **THEN** lines SHALL be combined into paragraphs separated by blank `///` lines

#### Scenario: Fenced code blocks in doc comments

- **GIVEN** a doc comment containing a fenced code block with ```` ```camp ````
- **WHEN** the doc is rendered
- **THEN** the code block SHALL be syntax-highlighted and displayable; `//#` lines SHALL NOT appear

#### Scenario: Headers in doc comments

- **GIVEN** a doc comment containing `# Examples` or `## Arguments`
- **WHEN** the doc is rendered
- **THEN** these SHALL be rendered as Markdown section headers

### Requirement: Code Block Testing

All fenced code blocks with the `camp` language tag (or no language tag) in doc comments SHALL be tested by the doctest runner. Code blocks with other language tags SHALL NOT be tested.

#### Scenario: Camp code block is tested

- **GIVEN** a ```` ```camp ```` code block in a doc comment
- **WHEN** `camp test` is run
- **THEN** the code block SHALL be extracted, compiled, and verified

#### Scenario: Unannotated code block defaults to camp

- **GIVEN** a ```` ``` ```` code block (no language tag) in a Camp doc comment
- **WHEN** `camp test` is run
- **THEN** the code block SHALL be treated as Camp code and tested

#### Scenario: Non-camp code block is not tested

- **GIVEN** a ```` ```text ```` or ```` ```python ```` code block in a Camp doc comment
- **WHEN** `camp test` is run
- **THEN** the code block SHALL NOT be extracted or tested

### Requirement: Code Block Compilation Mode

Code blocks SHALL compile as isolated standalone `.camp` files. Each code block SHALL NOT inherit imports or definitions from the surrounding module.

#### Scenario: Isolated compilation

- **GIVEN** a code block that uses `List.map`
- **WHEN** the doctest runner compiles it
- **THEN** the code block SHALL fail to compile unless it includes the necessary `//# import` lines

#### Scenario: Hidden import line

- **GIVEN** a code block containing `//# import List`
- **WHEN** the doctest runner processes it
- **THEN** the import line SHALL be compiled as real Camp code but SHALL NOT appear in rendered documentation

### Requirement: Code Block Execution

Code blocks that contain `expect` expressions SHALL be compiled and executed. Code blocks without `expect` SHALL be typechecked and linted only.

#### Scenario: Code block with expect is executed

- **GIVEN** a code block containing `expect 1 + 1 == 2`
- **WHEN** `camp test` is run
- **THEN** the code block SHALL be compiled and executed; all `expect` expressions MUST evaluate to `True`

#### Scenario: Code block without expect is typechecked only

- **GIVEN** a code block with no `expect` expressions
- **WHEN** `camp test` is run
- **THEN** the code block SHALL be typechecked and linted but not executed

#### Scenario: Typecheck failure is a hard failure

- **GIVEN** a code block (without `compile_fail`) that fails to typecheck
- **WHEN** `camp test` is run
- **THEN** the doctest SHALL fail

### Requirement: Code Block Annotations

Code blocks SHALL support comma-separated annotations after the language tag to control testing behavior.

#### Scenario: compile_fail annotation

- **GIVEN** a ```` ```camp,compile_fail ```` code block
- **WHEN** `camp test` is run
- **THEN** the code block MUST fail to compile; if it compiles successfully, the doctest SHALL fail

#### Scenario: Any error suffices for compile_fail

- **GIVEN** a ```` ```camp,compile_fail ```` code block
- **WHEN** the code block produces any compilation error
- **THEN** the doctest SHALL pass — the specific error message is not checked

#### Scenario: No annotations

- **GIVEN** a ```` ```camp ```` code block with no annotations
- **WHEN** `camp test` is run
- **THEN** the code block SHALL be compiled (and executed if it contains `expect`)

### Requirement: Doctest Compilation Mode

Doctests SHALL always compile in debug mode, enabling the `todo` operator.

#### Scenario: todo allowed in doctests

- **GIVEN** a doc code block containing `todo`
- **WHEN** `camp test` compiles the code block
- **THEN** the code block SHALL compile successfully (debug mode allows `todo`)

#### Scenario: todo panics if reached in doctest

- **GIVEN** a doc code block containing a `todo` that is reached during execution
- **WHEN** the doctest runner executes the code block
- **THEN** the `todo` SHALL panic and the doctest SHALL fail

### Requirement: Doctest Identification

Failed doctests SHALL be identified by file path and line number of the code block.

#### Scenario: Doctest failure location

- **GIVEN** a code block in `Foo.camp` starting at line 42 that fails
- **WHEN** the doctest runner reports the failure
- **THEN** the error message SHALL include `Foo.camp:42`

### Requirement: Documentation Generation

`camp doc` SHALL generate HTML documentation from doc comments. Hidden lines (`//#`) SHALL be stripped from rendered code examples.

#### Scenario: Generating documentation

- **GIVEN** a project with `///` doc comments
- **WHEN** `camp doc` is run
- **THEN** HTML documentation SHALL be generated with rendered Markdown, syntax-highlighted code examples, and type signatures

#### Scenario: Hidden lines in generated docs

- **GIVEN** a doc code block containing `//#` lines
- **WHEN** `camp doc` renders the code block
- **THEN** the `//#` lines SHALL NOT appear in the rendered output

### Requirement: LSP Hover Documentation

The LSP SHALL show rendered Markdown doc comments alongside type signatures when hovering over a documented symbol.

#### Scenario: Hover over documented function

- **GIVEN** a function with a `///` doc comment
- **WHEN** the user hovers over the function name in the editor
- **THEN** the LSP SHALL display the rendered Markdown documentation plus the function's type signature

#### Scenario: Hover over symbol with code examples

- **GIVEN** a doc comment containing a fenced code block
- **WHEN** the LSP displays hover information
- **THEN** the code block SHALL be rendered with syntax highlighting and `//#` lines SHALL be hidden
