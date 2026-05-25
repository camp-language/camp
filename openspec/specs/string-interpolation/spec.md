# Domain Specification: String Interpolation

## Purpose

Define the behavioral requirements for string interpolation in Camp — the syntax, Display trait constraint, effect row propagation, per-line prefix multiline strings, nested brace handling, and the compiler's compilation strategy for interpolated strings.

## Requirements

### Requirement: String Interpolation Syntax
A double-quoted string containing `${` SHALL be an interpolated string. Each `${expr}` hole SHALL contain a single-line Camp expression. The `${` SHALL be the interpolation start delimiter and the matching `}` SHALL be the interpolation end delimiter. A `$` not followed by `{` SHALL be a literal dollar sign.

#### Scenario: Simple variable interpolation
- **GIVEN** a binding `name = "Camp"`
- **WHEN** the expression `"Hello, ${name}!"` is evaluated
- **THEN** the result SHALL be the string `"Hello, Camp!"`

#### Scenario: Expression interpolation
- **GIVEN** bindings `x = 3` and `y = 4`
- **WHEN** the expression `"${x + y} items"` is evaluated
- **THEN** the result SHALL be the string `"7 items"`

#### Scenario: Field access interpolation
- **GIVEN** a record `person = { name: "Alice", age: 30 }`
- **WHEN** the expression `"${person.name} is ${person.age}"` is evaluated
- **THEN** the result SHALL be the string `"Alice is 30"`

#### Scenario: Adjacent interpolation holes
- **GIVEN** bindings `a = "hello"` and `b = "world"`
- **WHEN** the expression `"${a}${b}"` is evaluated
- **THEN** the result SHALL be the string `"helloworld"`

#### Scenario: Literal dollar sign without brace
- **GIVEN** the expression `"Price: $5.00"`
- **WHEN** evaluated
- **THEN** the result SHALL be the string `"Price: $5.00"` — no interpolation because `$` is not followed by `{`

#### Scenario: Escaped interpolation delimiter
- **GIVEN** the expression `"Variable: \${HOME}"`
- **WHEN** evaluated
- **THEN** the result SHALL be the string `"Variable: ${HOME}"` — the `\$` escapes the interpolation

#### Scenario: Plain string without interpolation
- **GIVEN** the expression `"Hello, world!"`
- **WHEN** evaluated
- **THEN** it SHALL be a plain string literal with no interpolation processing

### Requirement: Display Trait Constraint
Each expression inside an interpolation hole `${expr}` SHALL implement the `Display` trait. The compiler SHALL insert a `Display.to_str(expr)` call for each interpolated expression. If the expression's type does not implement `Display`, the compiler SHALL produce an error.

#### Scenario: Str value interpolation
- **GIVEN** a binding `name: Str = "Camp"`
- **WHEN** the expression `"Hello, ${name}!"` is type-checked
- **THEN** it SHALL succeed because `Str is Display`

#### Scenario: I64 value interpolation
- **GIVEN** a binding `count: I64 = 42`
- **WHEN** the expression `"Count: ${count}"` is type-checked
- **THEN** it SHALL succeed because `I64 is Display`, and the compiler SHALL insert `Display.to_str(count)`

#### Scenario: Non-Display type produces error
- **GIVEN** a nominal type `@UserId : U64` that does NOT implement `Display`
- **WHEN** the expression `"User: ${uid}"` where `uid: UserId` is type-checked
- **THEN** the compiler SHALL produce an error stating that `UserId` does not implement `Display`

#### Scenario: Display trait in prelude
- **GIVEN** any Camp module
- **WHEN** the compiler processes the module
- **THEN** the `Display` trait SHALL be available with `Str`, `I64`, `I32`, `F64`, and `Bool` as implementing types

### Requirement: Interpolation Effect Row Propagation
The effect row of an interpolated string SHALL be the union of the effect rows of all interpolated expressions. An interpolated string containing an effectful expression SHALL itself be effectful.

#### Scenario: Pure interpolation
- **GIVEN** a binding `name: Str = "Camp"` (pure)
- **WHEN** the expression `"Hello, ${name}!"` is type-checked
- **THEN** the effect row SHALL be empty

#### Scenario: Effectful interpolation
- **GIVEN** a function `Console.readln! : || -[Console!]-> Str`
- **WHEN** the expression `"You said: ${Console.readln!()}"` is type-checked
- **THEN** the effect row SHALL include `Console!`

#### Scenario: Multiple effectful expressions
- **GIVEN** a function `Console.readln! : || -[Console!]-> Str` and `File.read! : Handle -[File!]-> Str`
- **WHEN** the expression `"${Console.readln!()}: ${File.read!(h)}"` is type-checked
- **THEN** the effect row SHALL include both `Console!` and `File!`

### Requirement: Interpolated String Type
An interpolated string SHALL have type `Str`.

#### Scenario: Interpolated string type inference
- **GIVEN** the expression `"Hello, ${name}!"`
- **WHEN** the compiler infers its type
- **THEN** the type SHALL be `Str`


### Requirement: Per-Line Prefix Multiline Strings
A `\` at the start of a line SHALL indicate that line is part of a multiline string literal. Per-line prefix strings are raw — no `\n`, `\t`, or other backslash escape sequences are processed. Interpolation `${expr}` SHALL be active. Expressions inside `${...}` SHALL be single-line (for SIMD-friendly lexing). The newline between consecutive `\` lines SHALL be appended to the string content. Non-empty lines that do not start with `\` within a multiline string block SHALL produce an error with a suggestion to add the `\` prefix.

#### Scenario: Multiline with interpolation
- **GIVEN** a binding `name = "Camp"`
- **WHEN** the expression `\Hello, ${name}!
\Welcome.` is evaluated
- **THEN** the result SHALL contain "Hello, Camp!" followed by a newline and "Welcome."

#### Scenario: Raw backslash is literal
- **GIVEN** the expression `\C:\Users\${dir}` where `dir = "camp"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"C:\\Users\\camp"` — backslashes are literal characters, `${dir}` interpolates

#### Scenario: Expression must be single-line
- **GIVEN** a per-line string `\Result: ${1 +
2}`
- **WHEN** the compiler parses it
- **THEN** it SHALL produce an error because the interpolation expression spans multiple lines

#### Scenario: Missing prefix error
- **GIVEN** the following lines:
  `\Hello`
  `world`
  `\!`
- **WHEN** the compiler parses them
- **THEN** it SHALL produce an error for the line `world` suggesting to add a `\` prefix

### Requirement: Nested Braces in Interpolation
An expression inside `${...}` SHALL support nested `{}` pairs for records, blocks, and other brace-delimited constructs. The matching `}` SHALL be determined by brace-depth tracking.

#### Scenario: Record expression in interpolation
- **GIVEN** a function `format_record : |{ name: Str }| -> Str`
- **WHEN** the expression `"${format_record({ name: "Alice" })}"` is parsed
- **THEN** the inner `}` of the record SHALL NOT terminate the interpolation; the outer `}` SHALL terminate it

#### Scenario: Block expression in interpolation
- **GIVEN** an if expression inside interpolation `"${if True { 1 } else { 2 }}"`
- **WHEN** parsed
- **THEN** the brace-depth tracking SHALL correctly match the interpolation-closing `}`

### Requirement: Interpolated String Literal Kinds
The language SHALL support two string literal kinds: plain (`"..."`) and per-line prefix (`\`). A `"..."` string without `${` SHALL be a plain string literal. A `"..."` string containing `${` SHALL be automatically detected as an interpolated string. Lines starting with `\` SHALL be per-line prefix multiline strings with interpolation support.

#### Scenario: Plain string
- **GIVEN** the expression `"Hello"`
- **WHEN** the compiler processes it
- **THEN** it SHALL be a plain string literal with escape processing and no interpolation

#### Scenario: Interpolated string
- **GIVEN** the expression `"Hello ${name}"`
- **WHEN** the compiler processes it
- **THEN** it SHALL be an interpolated string with escape processing and `Display.to_str(name)` inserted

#### Scenario: Per-line prefix multiline string
- **GIVEN** the expression `\Line 1
\${val}
\Line 3`
- **WHEN** the compiler processes it
- **THEN** it SHALL be a multiline raw string with no escape processing, interpolation active, and `Display.to_str(val)` inserted

### Requirement: String Interpolation Escape
The `\$` escape sequence SHALL produce a literal `$` character in plain `"..."` strings. In `\` per-line strings, which are raw, `\$` SHALL be the literal characters `\$` (no escape processing). A `$` not followed by `{` SHALL be literal without escaping in all string kinds.

#### Scenario: Escaped dollar-brace in interpolated string
- **GIVEN** the expression `"Var: \${HOME}"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"Var: ${HOME}"`

#### Scenario: Dollar without brace is literal
- **GIVEN** the expression `"Price: $5"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"Price: $5"`

### Requirement: Display Trait
The language SHALL provide a `Display` trait in the prelude defining a `to_str : Self -> Str` method. Types that implement `Display` SHALL be usable inside string interpolation holes without explicit conversion.

#### Scenario: Display trait definition
- **GIVEN** any Camp module
- **WHEN** the compiler processes the module
- **THEN** the `Display` trait SHALL be available with signature `to_str : Self -> Str`

#### Scenario: Str implements Display
- **GIVEN** the `Display` trait in the prelude
- **WHEN** a value of type `Str` is used in an interpolation hole
- **THEN** it SHALL be accepted without explicit `to_str` call; `Display.to_str` on `Str` SHALL be the identity function

#### Scenario: I64 implements Display
- **GIVEN** the `Display` trait in the prelude
- **WHEN** a value of type `I64` is used in an interpolation hole
- **THEN** it SHALL be accepted; `Display.to_str` SHALL produce the decimal string representation

#### Scenario: F64 implements Display
- **GIVEN** the `Display` trait in the prelude
- **WHEN** a value of type `F64` is used in an interpolation hole
- **THEN** it SHALL be accepted; `Display.to_str` SHALL produce the decimal string representation

#### Scenario: Bool implements Display
- **GIVEN** the `Display` trait in the prelude
- **WHEN** a value of type `Bool` is used in an interpolation hole
- **THEN** it SHALL be accepted; `Display.to_str(True)` SHALL produce `"True"` and `Display.to_str(False)` SHALL produce `"False"`

### Requirement: Interpolated String AST Nodes
The compiler SHALL support interpolated string nodes through the surface AST, canonical AST, and typed AST. The nodes SHALL preserve the interpolation structure (literal segments and expression holes) for quality error messages.

#### Scenario: Surface AST interpolated string
- **GIVEN** Camp source `"Hello ${name}!"`
- **WHEN** the parser produces the surface AST
- **THEN** it SHALL produce an `SExpr_Interpolated_String` with parts: literal `"Hello "`, expression `name`, literal `"!"`

#### Scenario: Canonical AST interpolated string
- **GIVEN** an `SExpr_Interpolated_String`
- **WHEN** canonicalization runs
- **THEN** it SHALL produce a `CExpr_Interpolated_String` with name resolution applied to expression parts

#### Scenario: Typed AST interpolated string
- **GIVEN** a `CExpr_Interpolated_String`
- **WHEN** typechecking runs
- **THEN** it SHALL produce a `TExpr_Interpolated_String` with type information, effect rows, and Display constraint verification

### Requirement: Interpolated String Typechecking
The compiler SHALL typecheck each expression inside an interpolation hole. Each expression SHALL be verified to implement the `Display` trait. The overall type SHALL be `Str`. The effect row SHALL be the union of all expressions' effect rows.

#### Scenario: Type check with Display constraint satisfied
- **GIVEN** an interpolated string `"Count: ${n}"` where `n: I64`
- **WHEN** the compiler type-checks it
- **THEN** it SHALL succeed with type `Str` and empty effect row, because `I64 is Display`

#### Scenario: Type error for non-Display type
- **GIVEN** an interpolated string `"Value: ${v}"` where `v` does NOT implement `Display`
- **WHEN** the compiler type-checks it
- **THEN** it SHALL produce an error: "Cannot interpolate type `<type>` — it does not implement `Display`"

#### Scenario: Effect row propagation
- **GIVEN** an interpolated string `"${Console.readln!()}"` where `readln!` has effect row `{ Console! }`
- **WHEN** the compiler type-checks it
- **THEN** the interpolated string's effect row SHALL include `Console!`

### Requirement: Interpolated String Desugaring
The compiler SHALL desugar `TExpr_Interpolated_String` to nested `Str.concat` and `Display.to_str` calls in the lowering phase. No new IR node SHALL be introduced.

#### Scenario: Simple interpolation desugaring
- **GIVEN** a typed interpolated string with parts: literal `"Hello "`, expression `name`, literal `"!"`
- **WHEN** lowering runs
- **THEN** it SHALL produce `Str.concat("Hello ", Str.concat(Display.to_str(name), "!"))` using `IR_Call` and `IR_Literal_String` nodes

#### Scenario: Empty literal segment
- **GIVEN** a typed interpolated string `"${a}${b}"` with no literal text between holes
- **WHEN** lowering runs
- **THEN** it SHALL produce `Str.concat(Display.to_str(a), Display.to_str(b))` with no empty string literals

### Requirement: Interpolated String Lexer Tokens
The compiler SHALL emit token kinds for plain, interpolated, and per-line prefix string literals. A `"..."` string without `${` SHALL be emitted as a plain string token. A `"..."` string containing `${` SHALL be emitted as an interpolated string token. Lines starting with `\` SHALL be emitted as per-line string tokens.

#### Scenario: Plain string token
- **GIVEN** source text `"Hello, world!"`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a plain string literal token

#### Scenario: Interpolated string token
- **GIVEN** source text `"Hello ${name}!"`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a single interpolated string token containing the full text

#### Scenario: Per-line string token
- **GIVEN** source text `\Hello
\${name}
\!`
- **WHEN** the lexer tokenizes each line
- **THEN** it SHALL emit per-line string tokens for each `\`-prefixed line

### Requirement: Interpolated String Parsing
The parser SHALL split interpolated string tokens into literal text segments and expression holes. Each expression hole SHALL be parsed by recursively invoking the expression parser. Brace-depth tracking SHALL determine the matching `}` for each interpolation hole.

#### Scenario: Parse simple interpolation
- **GIVEN** an interpolated string token `"Hello ${name}!"`
- **WHEN** the parser processes it
- **THEN** it SHALL produce an `SExpr_Interpolated_String` with three parts: text `"Hello "`, expression `name`, text `"!"`

#### Scenario: Parse nested braces
- **GIVEN** an interpolated string token `"${f({ x: 1 })}"`
- **WHEN** the parser processes it
- **THEN** the brace-depth tracking SHALL correctly match the outer `}` as the interpolation terminator

#### Scenario: Error on unterminated interpolation
- **GIVEN** an interpolated string token `"${name"` with no closing `}`
- **WHEN** the parser processes it
- **THEN** it SHALL produce a parse error for the unterminated interpolation hole

For the complete syntax reference, see `docs/syntax-recipe.md`.
