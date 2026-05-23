## Why

Camp programs currently build strings through explicit `Str.concat` calls or the `+` operator (which desugars to `Str.concat`). This is verbose and hard to read for the common case of embedding values inside descriptive text: `Str.concat("Hello ", Str.concat(name, "!"))` vs `"Hello ${name}!"`. Every modern language provides string interpolation for this pattern. The language spec already uses `${expr}` syntax in two example snippets, but the compiler doesn't support it yet.

## What Changes

- Add string interpolation syntax `"${expr}"` inside double-quoted strings (auto-detected when `${` appears)
- Add `r"..."` raw interpolated strings (interpolation active, escape sequences literal)
- Add `"""..."""` multiline interpolated strings (newlines literal, interpolation active)
- Add `\$` escape for literal `${` inside strings
- Add `Display` trait to the prelude with implementations for `Str`, `I64`, `I32`, `F64`, `Bool`
- Require interpolated expressions to implement `Display`; compiler inserts `Display.to_str()` calls
- Propagate effect rows from interpolated expressions to the interpolated string's effect row
- Desugar interpolated strings to nested `Str.concat` + `Display.to_str` calls in lowering
- Add `SExpr_Interpolated_String` / `CExpr_Interpolated_String` / `TExpr_Interpolated_String` AST nodes
- Update lexer, parser, canonicalizer, typechecker, lowerer, formatter, tree-sitter, and LSP

## Capabilities

### New Capabilities

- `string-interpolation`: String interpolation syntax, type checking (Display trait constraint), effect row propagation, and desugaring to Str.concat/Display.to_str

### Modified Capabilities

- `language`: New string literal kinds (interpolated, raw+interpolated, multiline+interpolated); new `Display` trait in prelude; `\$` escape sequence
- `compiler`: New AST nodes through all phases; new lexer tokens; new desugaring in lowering; Display trait verification in typechecker
- `tree-sitter`: New grammar rules for interpolated strings, raw strings, multiline strings; likely needs external scanner for brace-depth tracking

## Impact

- **Lexer**: New token kinds (`Interpolated_String_Literal`, `Raw_String_Literal`, `Multiline_String_Literal`); `\$` escape handling
- **Parser**: New `SExpr_Interpolated_String` node; recursive expression parsing inside `${}`; brace-depth tracking
- **Canonicalizer**: New `CExpr_Interpolated_String` node; name resolution for expressions inside interpolation holes
- **Typechecker**: New `TExpr_Interpolated_String` node; Display trait constraint verification; effect row composition from interpolated expressions
- **Lowering**: Desugar `TExpr_Interpolated_String` to nested `Str.concat` + `Display.to_str` calls
- **Formatter**: Format interpolated strings preserving structure; format expressions inside `${}`
- **Tree-sitter**: New `interpolated_string`, `raw_string`, `multiline_string` rules; external scanner for brace tracking; `highlights.scm` updates
- **LSP**: Go-to-definition and hover inside `${expr}`; diagnostics for non-Display types
- **Prelude**: `Display` trait definition; `Str`, `I64`, `I32`, `F64`, `Bool` implementations
- **Trait system dependency**: Display trait verification requires partial trait system implementation (constraint solving, UFCS dispatch, `is` verification)
- **Kitchen sink test**: Update `tests/e2e/language/kitchen-sink/Main.camp` with interpolation examples
