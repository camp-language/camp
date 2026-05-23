## ADDED Requirements

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

### Requirement: Raw Interpolated Strings
An `r"..."` string SHALL NOT process backslash escape sequences (the backslash SHALL be a literal character), EXCEPT for `\$` which SHALL escape the interpolation delimiter. The `r` prefix SHALL indicate raw mode. Interpolation `${expr}` SHALL be active in raw strings.

#### Scenario: Raw string with interpolation
- **GIVEN** a binding `dir = "home"`
- **WHEN** the expression `r"C:\${dir}\file.txt"` is evaluated
- **THEN** the result SHALL be the string `"C:\\home\\file.txt"` — backslashes are literal, `${dir}` interpolates

#### Scenario: Raw string escape is literal
- **GIVEN** the expression `r"line1\nline2"`
- **WHEN** evaluated
- **THEN** the result SHALL be the string `"line1\\nline2"` — `\n` is literal, not a newline

#### Scenario: Raw string interpolation escaping
- **GIVEN** the expression `r"var: \${HOME}"`
- **WHEN** evaluated
- **THEN** the result SHALL be the string `"var: ${HOME}"` — `\$` escapes interpolation even in raw strings

#### Scenario: Plain raw string without interpolation
- **GIVEN** the expression `r"C:\Users"`
- **WHEN** evaluated
- **THEN** the result SHALL be the string `"C:\\Users"` — no interpolation, no escape processing

### Requirement: Multiline Interpolated Strings
A `"""..."""` string SHALL allow newlines in the string body. Interpolation `${expr}` SHALL be active. Backslash escape sequences SHALL be processed. Expressions inside `${...}` SHALL be single-line.

#### Scenario: Multiline with interpolation
- **GIVEN** a binding `name = "Camp"`
- **WHEN** the expression `"""Hello, ${name}!\nWelcome."""` is evaluated
- **THEN** the result SHALL contain the interpolated name, a newline, and "Welcome."

#### Scenario: Multiline with literal newline
- **GIVEN** a binding `name = "Camp"`
- **WHEN** the expression `"""Hello, ${name}!
Welcome."""` is evaluated
- **THEN** the result SHALL contain "Hello, Camp!", a newline, and "Welcome."

#### Scenario: Expression must be single-line in multiline string
- **GIVEN** a multiline string `"""Result: ${1 +\n2}"""`
- **WHEN** the compiler parses it
- **THEN** it SHALL produce an error because the interpolation expression spans multiple lines

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
