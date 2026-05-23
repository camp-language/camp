## ADDED Requirements

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
The compiler SHALL emit token kinds for interpolated, raw, and multiline string literals. A `"..."` string containing `${` SHALL be emitted as an interpolated string token. An `r"..."` string SHALL be emitted as a raw string token. A `"""..."""` string SHALL be emitted as a multiline string token.

#### Scenario: Interpolated string token
- **GIVEN** source text `"Hello ${name}!"`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a single interpolated string token containing the full text

#### Scenario: Plain string token
- **GIVEN** source text `"Hello, world!"`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a plain string literal token (no interpolation)

#### Scenario: Raw string token
- **GIVEN** source text `r"C:\Users"`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a raw string token

#### Scenario: Multiline string token
- **GIVEN** source text `"""Line 1\nLine 2"""`
- **WHEN** the lexer tokenizes it
- **THEN** it SHALL emit a multiline string token

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
