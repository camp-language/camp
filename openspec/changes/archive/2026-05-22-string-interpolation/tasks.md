## 1. Display Trait Foundation

- [ ] 1.1 Implement `is` trait verification in typechecker — when a type declares `is Display`, verify it has a `to_str` method matching `Self -> Str`
- [ ] 1.2 Implement trait constraint solving in function typechecking — when a type parameter has `where a is Display`, verify the constraint at call sites
- [ ] 1.3 Implement UFCS dispatch for `Display.to_str(x)` → call the type's `to_str` function
- [ ] 1.4 Add `Display` trait definition to the prelude: `trait Display { to_str : Self -> Str }`
- [ ] 1.5 Add `Str is Display` to the prelude with `to_str = |s| s` (identity)
- [ ] 1.6 Add `I64 is Display` to the prelude with intrinsic `to_str` (int-to-string conversion)
- [ ] 1.7 Add `I32 is Display` to the prelude with intrinsic `to_str`
- [ ] 1.8 Add `F64 is Display` to the prelude with intrinsic `to_str` (float-to-string conversion)
- [ ] 1.9 Add `Bool is Display` to the prelude with `to_str` matching on `True`/`False`
- [ ] 1.10 Unit tests: Display trait verification, UFCS dispatch, prelude implementations

## 2. Lexer

- [ ] 2.1 Add `Interpolated_String_Literal` token kind (or flag on existing `String_Literal`)
- [ ] 2.2 Detect `${` inside `"..."` — mark the token as interpolated
- [ ] 2.3 Handle `\$` escaping inside strings — don't trigger interpolation for `\$`
- [ ] 2.4 Add `Raw_String_Literal` token kind for `r"..."` strings
- [ ] 2.5 Detect `${` inside `r"..."` — mark the token as interpolated
- [ ] 2.6 Add `Multiline_String_Literal` token kind for `"""..."""` strings
- [ ] 2.7 Detect `${` inside `"""..."""` — mark the token as interpolated
- [ ] 2.8 Unit tests: plain strings, interpolated strings, raw strings, multiline strings, `\$` escaping, `$` without `{`

## 3. Parser

- [ ] 3.1 Add `SExpr_Interpolated_String` and `String_Part`/`String_Segment` to surface AST (`ast.odin`)
- [ ] 3.2 Implement interpolation splitting: parse `"..."` tokens containing `${` into literal segments and expression holes
- [ ] 3.3 Implement recursive expression parsing inside `${...}` holes
- [ ] 3.4 Implement brace-depth tracking for `}` matching in interpolation holes
- [ ] 3.5 Parse `r"..."` raw strings — same interpolation logic, set `is_raw = true`
- [ ] 3.6 Parse `"""..."""` multiline strings — same interpolation logic, set `is_multiline = true`
- [ ] 3.7 Error recovery for unterminated `${` or invalid expressions inside holes
- [ ] 3.8 Unit tests: simple interpolation, adjacent holes, nested braces, escaped `\$`, raw strings, multiline strings, error cases

## 4. Canonicalizer

- [ ] 4.1 Add `CExpr_Interpolated_String` and `CExpr_String_Part` to canonical AST (`canonical.odin`)
- [ ] 4.2 Canonicalize each expression part (name resolution, import resolution)
- [ ] 4.3 Convert literal text segments to `CExpr_String`
- [ ] 4.4 Propagate `is_raw` and `is_multiline` flags
- [ ] 4.5 Unit tests for canonicalization of interpolated strings

## 5. Typechecker

- [ ] 5.1 Add `TExpr_Interpolated_String` and `TExpr_String_Part` to typed AST
- [ ] 5.2 Typecheck each expression part inside interpolation holes
- [ ] 5.3 Verify each expression implements `Display`; produce error for non-Display types
- [ ] 5.4 Compute effect row = union of all expressions' effect rows
- [ ] 5.5 Set overall type = `Str`
- [ ] 5.6 Error message: "Cannot interpolate type `<type>` — it does not implement `Display`"
- [ ] 5.7 Unit tests: Display constraint satisfied, Display constraint violated, effect row propagation, overall Str type

## 6. Lowering (Desugaring)

- [ ] 6.1 Implement `TExpr_Interpolated_String` desugaring in `lower.odin`
- [ ] 6.2 Desugar each expression part to `Display.to_str(lower_texpr(expr))`
- [ ] 6.3 Desugar literal segments to `IR_Literal_String`
- [ ] 6.4 Combine parts with nested `Str.concat` calls
- [ ] 6.5 Handle edge cases: empty literal segments, single interpolation hole, no literal text
- [ ] 6.6 Unit tests: desugaring output matches expected IR structure

## 7. Formatter

- [ ] 7.1 Format interpolated strings preserving original structure in `format_expr.odin`
- [ ] 7.2 Format expressions inside `${}` normally
- [ ] 7.3 Format `r"..."` raw strings with `r` prefix
- [ ] 7.4 Format `"""..."""` multiline strings
- [ ] 7.5 Unit tests for formatted interpolated strings

## 8. Tree-sitter

- [ ] 8.1 Add `interpolated_string` grammar rule to `grammar.js`
- [ ] 8.2 Add `interpolation` node with `${` / `}` delimiters and `@embedded` expression
- [ ] 8.3 Add `raw_string` grammar rule with interpolation support
- [ ] 8.4 Add `multiline_string` grammar rule with interpolation support
- [ ] 8.5 Implement external scanner for brace-depth tracking in interpolation holes
- [ ] 8.6 Update `highlights.scm` for interpolation delimiter and embedded expression highlighting
- [ ] 8.7 Add corpus tests for all string literal kinds
- [ ] 8.8 Verify all e2e `.camp` files parse with `tree-sitter-validate`

## 9. LSP

- [ ] 9.1 Enable go-to-definition inside `${expr}` interpolation holes
- [ ] 9.2 Enable hover inside `${expr}` interpolation holes
- [ ] 9.3 Diagnostics for non-Display types in interpolation holes

## 10. E2E Tests

- [ ] 10.1 Basic interpolation: `"Hello ${name}!"`
- [ ] 10.2 Multiple interpolation holes: `"${a} and ${b}"`
- [ ] 10.3 Expression interpolation: `"${x + y} items"`
- [ ] 10.4 Field access: `"${person.name}"`
- [ ] 10.5 Effectful expression: `"${Console.readln!()}"` — effect row includes `Console!`
- [ ] 10.6 Escaping: `"\${literal}"` produces literal `${literal}`
- [ ] 10.7 Raw string: `r"C:\${dir}\file"` — backslashes literal, interpolation active
- [ ] 10.8 Multiline: `"""Line 1\n${val}"""`
- [ ] 10.9 Type error: non-Display type in `${}` produces compiler error
- [ ] 10.10 Nested strings: `"${\"inner\"}"`
- [ ] 10.11 Update kitchen sink test with interpolation examples
