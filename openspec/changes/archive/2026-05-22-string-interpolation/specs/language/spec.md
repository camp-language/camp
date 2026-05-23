## ADDED Requirements

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

### Requirement: Interpolated String Literal Kinds
The language SHALL support four string literal kinds: plain (`"..."`), interpolated (auto-detected `${` in `"..."`), raw interpolated (`r"..."`), and multiline interpolated (`"""..."""`).

#### Scenario: Plain string
- **GIVEN** the expression `"Hello"`
- **WHEN** the compiler processes it
- **THEN** it SHALL be a plain string literal with escape processing and no interpolation

#### Scenario: Interpolated string
- **GIVEN** the expression `"Hello ${name}"`
- **WHEN** the compiler processes it
- **THEN** it SHALL be an interpolated string with escape processing and `Display.to_str(name)` inserted

#### Scenario: Raw interpolated string
- **GIVEN** the expression `r"C:\${dir}"`
- **WHEN** the compiler processes it
- **THEN** it SHALL be a raw string with no escape processing (except `\$`) and `Display.to_str(dir)` inserted

#### Scenario: Multiline interpolated string
- **GIVEN** the expression `"""Line 1\n${val}"""`
- **WHEN** the compiler processes it
- **THEN** it SHALL be a multiline string with escape processing, newlines allowed in the body, and `Display.to_str(val)` inserted

### Requirement: String Interpolation Escape
The `\$` escape sequence SHALL produce a literal `$` character in all string kinds. A `$` not followed by `{` SHALL be literal without escaping.

#### Scenario: Escaped dollar-brace in interpolated string
- **GIVEN** the expression `"Var: \${HOME}"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"Var: ${HOME}"`

#### Scenario: Dollar without brace is literal
- **GIVEN** the expression `"Price: $5"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"Price: $5"`

#### Scenario: Escaped dollar in raw string
- **GIVEN** the expression `r"Escaped: \${var}"`
- **WHEN** evaluated
- **THEN** the result SHALL be `"Escaped: ${var}"`
