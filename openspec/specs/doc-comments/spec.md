# Doc Comments — Behavioral Specification

## Purpose

Define the behavioral requirements for Camp's documentation comment system, doctests, the `expect` assertion expression, the `test` named-test-block declaration, the `todo` placeholder operator, and the `camp doc` / `camp test` toolchain commands that extract, verify, and render documentation from source code.

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

- **GIVEN** a ```` ```text ```` or ```` ```python ```` code block in a doc comment
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

### Requirement: expect Expression

The `expect` keyword SHALL accept a boolean expression. If the expression evaluates to `False`, the program SHALL fail. In production mode, `expect` SHALL be compiled to a no-op.

#### Scenario: expect with true expression

- **GIVEN** an expression `expect 1 + 1 == 2`
- **WHEN** evaluated in debug or test mode
- **THEN** the expression `1 + 1 == 2` SHALL evaluate to `True` and the program SHALL continue

#### Scenario: expect with false expression

- **GIVEN** an expression `expect 1 + 1 == 3`
- **WHEN** evaluated in debug or test mode
- **THEN** the expression `1 + 1 == 3` SHALL evaluate to `False` and the program SHALL fail with an error

#### Scenario: expect in production mode

- **GIVEN** an expression `expect some_condition`
- **WHEN** compiled in production mode
- **THEN** the `expect` and its expression SHALL be compiled to a no-op — the expression SHALL NOT be evaluated at runtime

#### Scenario: expect effect row

- **GIVEN** an `expect` expression whose boolean sub-expression has effects (e.g., `expect Console.println!("test") == {}`)
- **WHEN** the effect row is computed for the containing function
- **THEN** the effect row SHALL include the sub-expression's effects in debug/test mode; in production mode, the `expect` is removed entirely and its effects are not present

### Requirement: test Named Test Block

The `test` keyword SHALL define a named test block. Test blocks SHALL be discovered and executed by `camp test`.

#### Scenario: Named test block

- **GIVEN** a declaration `test "addition works" { expect 1 + 1 == 2 }`
- **WHEN** `camp test` is run
- **THEN** the test block SHALL be discovered, compiled, and executed; if the `expect` fails, the test SHALL fail with the name "addition works"

#### Scenario: Test block identification

- **GIVEN** a test block `test "addition works" { ... }` in `Math.camp` at line 10
- **WHEN** the test fails
- **THEN** the error message SHALL include the test name "addition works" and the file path `Math.camp:10`

#### Scenario: Test block with setup code

- **GIVEN** a test block containing setup code and multiple expects
- **WHEN** `camp test` is run
- **THEN** all code in the block SHALL execute; if any `expect` fails, the entire test block SHALL fail

#### Scenario: Test blocks in production mode

- **GIVEN** a file containing `test "name" { ... }` declarations
- **WHEN** compiled in production mode
- **THEN** test blocks SHALL be excluded from the compiled output entirely

### Requirement: todo Placeholder Operator

The `todo` keyword SHALL be a placeholder expression that compiles in debug mode and causes a compilation error in production mode. It SHALL have type `forall a. a` and an empty effect row.

#### Scenario: todo as return value

- **GIVEN** a function `f = || -> Int { todo }`
- **WHEN** compiled in debug mode
- **THEN** the function SHALL compile; if called at runtime, it SHALL panic with "not yet implemented"

#### Scenario: todo with message

- **GIVEN** a function `f = || -> Int { todo("implement sorting") }`
- **WHEN** called at runtime in debug mode
- **THEN** it SHALL panic with the message "implement sorting"

#### Scenario: todo in production mode

- **GIVEN** a function `f = || -> Int { todo }`
- **WHEN** compiled in production mode
- **THEN** the compiler SHALL produce an error — `todo` is not allowed in production builds

#### Scenario: todo type is polymorphic

- **GIVEN** a function `f = || -> Str { todo }` and another `g = || -> Bool { todo }`
- **WHEN** compiled in debug mode
- **THEN** both SHALL type-check — `todo` unifies with any expected type

#### Scenario: todo in function argument position

- **GIVEN** an expression `some_function(todo, 42)`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the expected parameter type

#### Scenario: todo in record field position

- **GIVEN** an expression `{ name: todo, age: 30 }`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the expected type of the `name` field

#### Scenario: todo in match arm position

- **GIVEN** a match expression with an arm `_ => todo`
- **WHEN** type-checked
- **THEN** `todo` SHALL unify with the match result type

#### Scenario: todo effect row is empty

- **GIVEN** a function `compute = || -> Int { todo }`
- **WHEN** the compiler infers the effect row
- **THEN** the effect row SHALL be empty — `compute` is pure and does NOT require `!` in its name

#### Scenario: todo in effectful function

- **GIVEN** a function `compute! = || -[Console!]-> Int { Console.println!("debug"); todo }`
- **WHEN** the compiler infers the effect row
- **THEN** the effect row SHALL include `Console!` from the `println!` call — `todo` does not add effects

### Requirement: Unified Test Command

`camp test` SHALL discover and execute both doctests (code blocks in doc comments) and named test blocks.

#### Scenario: Running all tests

- **GIVEN** a project with doc comments containing code blocks and files with `test` declarations
- **WHEN** `camp test` is run
- **THEN** both doctests and named test blocks SHALL be discovered, compiled, and executed

#### Scenario: Test summary

- **GIVEN** `camp test` completes
- **WHEN** results are reported
- **THEN** the runner SHALL display a summary showing the number of doctests and named tests that passed, failed, or were skipped

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
