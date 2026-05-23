## MODIFIED Requirements

### Requirement: No External Scanner
The grammar SHALL use an external C scanner for handling string interpolation brace-depth tracking. The previous requirement that the grammar be implemented entirely in `grammar.js` without an external scanner SHALL be modified to allow an external scanner for interpolated string support.

#### Scenario: External scanner for interpolation
- **GIVEN** Camp source containing an interpolated string `"${record.{name}}"`
- **WHEN** tree-sitter parses it
- **THEN** the external scanner SHALL track brace depth to correctly match the interpolation-closing `}`

## ADDED Requirements

### Requirement: Interpolated String Grammar
The tree-sitter grammar SHALL include rules for interpolated strings, raw strings, and multiline strings with interpolation support.

#### Scenario: Interpolated string parse tree
- **GIVEN** Camp source `"Hello ${name}!"`
- **WHEN** tree-sitter parses it
- **THEN** it SHALL produce an `interpolated_string` node containing `string_content` and `interpolation` child nodes

#### Scenario: Interpolation node structure
- **GIVEN** Camp source `"${expr}"`
- **WHEN** tree-sitter parses it
- **THEN** it SHALL produce an `interpolation` node containing `${`, the expression, and `}`

#### Scenario: Raw string parse tree
- **GIVEN** Camp source `r"C:\${dir}"`
- **WHEN** tree-sitter parses it
- **THEN** it SHALL produce a `raw_string` node with interpolation support

#### Scenario: Multiline string parse tree
- **GIVEN** Camp source `"""Line 1\n${x}"""`
- **WHEN** tree-sitter parses it
- **THEN** it SHALL produce a `multiline_string` node with interpolation support

### Requirement: Interpolation Highlighting
The tree-sitter highlights query SHALL provide distinct highlighting for interpolation delimiters (`${` and `}`) and the embedded expression.

#### Scenario: Highlighting interpolation delimiters
- **GIVEN** Camp source `"Hello ${name}!"`
- **WHEN** `highlights.scm` is applied
- **THEN** `${` and `}` SHALL be captured as `@punctuation.special` and the expression SHALL be captured as `@embedded`
