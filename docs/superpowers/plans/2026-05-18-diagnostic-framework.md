# Diagnostic Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Camp's flat error system with an Elm-style diagnostic framework that produces friendly, precise error messages with source snippets, underlines, hints, and suggestions.

**Architecture:** Typed error variants with per-error constructor functions that build complete `Diagnostic` structs (message, labels, hints). Dual renderers (CLI with TTY detection, LSP types for future) consume the shared `Diagnostic` type. Pipeline code calls constructors; constructors handle all presentation logic.

**Tech Stack:** Odin, core:fmt, core:os (TTY detection via os.is_terminal)

**Spec:** `docs/superpowers/specs/2026-05-18-diagnostic-framework-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/diagnostic.odin` | Create | `Diagnostic`, `Diagnostic_Category`, `Span_Label`, `Diagnostic_Collector`, all variant structs, title map |
| `src/diag_constructors.odin` | Create | All `diag_*` constructor functions |
| `src/diag_renderer_cli.odin` | Create | CLI renderer, `render_diagnostic`, `render_all`, `span_to_line_col`, snippet extraction, TTY detection |
| `src/diag_renderer_lsp.odin` | Create | `LSP_Rendered` struct and mapping types only |
| `src/diag_token_names.odin` | Create | `token_kind_display` — human-readable names for `Token_Kind` enum values |
| `src/error.odin` | Delete | Replaced by `diagnostic.odin` |
| `src/reporter.odin` | Delete | Replaced by `diag_renderer_cli.odin` |
| `src/context.odin` | Modify | Replace `Error_Collector` with `Diagnostic_Collector` |
| `src/types.odin` | Modify | Replace `Error_Collector` pointer with `Diagnostic_Collector` pointer in `Type_Store` |
| `src/lexer.odin` | Modify | Replace `collector_add` calls with `diag_*` constructors |
| `src/parser.odin` | Modify | Replace `collector_add` calls with `diag_*` constructors |
| `src/typecheck.odin` | Modify | Replace `collector_add` calls with `diag_*` constructors, add Levenshtein for suggestions |
| `src/unify.odin` | Modify | Replace `collector_add`/`make_unify_error` with `diag_*` constructors, fix dual-span bugs |
| `src/cli.odin` | Modify | Replace `report_error` loop with `render_all`, fix type-error-reporting bug, replace CLI `fmt.printfln` errors |
| `src/main.odin` | Modify | Replace CLI `fmt.printfln` errors with diagnostic system |
| `src/test_bootstrap.odin` | Modify | Update tests from `Error_Collector` to `Diagnostic_Collector` |
| `src/test_lexer.odin` | Modify | Update error assertions if needed |
| `src/test_typecheck.odin` | Modify | Update error assertions if needed |
| `src/test_integration.odin` | Modify | Update error assertions if needed |

---

### Task 1: Core Diagnostic Types and Collector

**Files:**
- Create: `src/diagnostic.odin`

- [ ] **Step 1: Create `src/diagnostic.odin` with core types, variant structs, and collector**

```odin
package camp

import "core:fmt"
import "core:mem"

Diagnostic_Category :: enum {
	Warning,
	Error,
	Internal,
}

Span_Label :: struct {
	span:  Source_Span,
	label: string,
}

Diagnostic :: struct {
	category: Diagnostic_Category,
	span:     Source_Span,
	message:  string,
	title:    string,
	labels:   [dynamic]Span_Label,
	hints:    [dynamic]string,
}

Lex_Unexpected_Char :: struct {
	char: u8,
}
Lex_Unterminated_String :: struct {}

Parse_Expected_Token :: struct {
	expected: Token_Kind,
	actual:   Token,
}
Parse_Unexpected_Token :: struct {
	token: Token,
}
Parse_Expected_Type :: struct {
	actual: Token,
}

Type_Effectful_Naming :: struct {
	name:    string,
	effects: string,
}
Type_Undefined_Name :: struct {
	name:          string,
	similar_names: []string,
}
Type_Unhandled_Effect :: struct {
	effect_name: string,
}

Unify_Type_Mismatch :: struct {
	type_a: string,
	type_b: string,
	span_b: Source_Span,
}
Unify_Primitive_Mismatch :: struct {
	name_a: string,
	name_b: string,
	span_b: Source_Span,
}
Unify_Value_Row_Conflict :: struct {
	kind_a: string,
	kind_b: string,
	span_b: Source_Span,
}
Unify_Infinite_Type :: struct {
	type_expr: string,
	span_b:    Source_Span,
}
Unify_Arity_Mismatch :: struct {
	expected: int,
	actual:   int,
	span_b:   Source_Span,
}
Unify_Tag_Arity_Mismatch :: struct {
	tag_name: string,
	expected: int,
	actual:   int,
	span_b:   Source_Span,
}

CLI_Invalid_Extension :: struct {
	path:      string,
	extension: string,
}
CLI_File_Not_Found :: struct {
	path:     string,
	os_error: string,
}
CLI_Unknown_Command :: struct {
	command: string,
}

Diagnostic_Collector :: struct {
	diagnostics:    [dynamic]Diagnostic,
	warning_count:  int,
	error_count:    int,
	internal_count: int,
}

collector_init :: proc(collector: ^Diagnostic_Collector) {
	collector.diagnostics = make([dynamic]Diagnostic, 0, 64)
	collector.warning_count = 0
	collector.error_count = 0
	collector.internal_count = 0
}

collector_destroy :: proc(collector: ^Diagnostic_Collector) {
	for &d in collector.diagnostics {
		delete(d.labels)
		delete(d.hints)
	}
	delete(collector.diagnostics)
}

collector_add_diag :: proc(collector: ^Diagnostic_Collector, d: Diagnostic) {
	append(&collector.diagnostics, d)
	switch d.category {
	case .Warning:  collector.warning_count += 1
	case .Error:    collector.error_count += 1
	case .Internal: collector.internal_count += 1
	}
}

collector_has_errors :: proc(collector: ^Diagnostic_Collector) -> bool {
	return collector.error_count > 0 || collector.internal_count > 0
}
```

- [ ] **Step 2: Commit**

```bash
git add src/diagnostic.odin
git commit -m "feat(diagnostic): add core diagnostic types and collector"
```

---

### Task 2: Token Kind Display Names

**Files:**
- Create: `src/diag_token_names.odin`

- [ ] **Step 1: Create `src/diag_token_names.odin`**

This maps `Token_Kind` enum values to human-readable strings for error messages. Read `src/token.odin` to get the complete `Token_Kind` enum before writing this file.

```odin
package camp

token_kind_display :: proc(kind: Token_Kind) -> string {
	switch kind {
	case .Eof:          return "end of file"
	case .Int_Literal:  return "integer"
	case .Float_Literal: return "float"
	case .String_Literal: return "string"
	case .Ident:        return "identifier"
	case .Eq:           return "="
	case .Colon:        return ":"
	case .Comma:        return ","
	case .Dot:          return "."
	case .Arrow:        return "->"
	case .Pipe:         return "|"
	case .LParen:       return "("
	case .RParen:       return ")"
	case .LBrace:       return "{"
	case .RBrace:       return "}"
	case .LBrack:       return "["
	case .RBrack:       return "]"
	case .Plus:         return "+"
	case .Minus:        return "-"
	case .Star:         return "*"
	case .Slash:        return "/"
	case .Percent:      return "%"
	case .EqEq:        return "=="
	case .Neq:          return "!="
	case .Lt:           return "<"
	case .Gt:           return ">"
	case .Le:           return "<="
	case .Ge:           return ">="
	case .And:          return "and"
	case .Or:           return "or"
	case .Not:          return "not"
	case .Kw_If:        return "if"
	case .Kw_Else:      return "else"
	case .Kw_True:      return "true"
	case .Kw_False:     return "false"
	case .Kw_Effect:    return "effect"
	case .Kw_Handle:    return "handle"
	case .Kw_Intercept: return "intercept"
	case .Kw_With:      return "with"
	case .Kw_Resume:    return "resume"
	case .Kw_Match:     return "match"
	case .Kw_Type:      return "type"
	case .Dollar:       return "$"
	case .Bang:         return "!"
	case .DotDot:       return ".."
	case .Underscore:   return "_"
	case:               return "unknown token"
	}
}
```

Note: The implementer must verify against the actual `Token_Kind` enum in `src/token.odin` and add any missing variants.

- [ ] **Step 2: Commit**

```bash
git add src/diag_token_names.odin
git commit -m "feat(diagnostic): add token kind display names"
```

---

### Task 3: Diagnostic Constructor Functions

**Files:**
- Create: `src/diag_constructors.odin`

- [ ] **Step 1: Create `src/diag_constructors.odin`**

```odin
package camp

import "core:fmt"

diag_init :: proc(category: Diagnostic_Category, title: string, span: Source_Span, message: string) -> Diagnostic {
	d: Diagnostic
	d.category = category
	d.title = title
	d.span = span
	d.message = message
	d.labels = make([dynamic]Span_Label, 0, 4)
	d.hints = make([dynamic]string, 0, 2)
	return d
}

diag_unexpected_char :: proc(char: u8, span: Source_Span) -> Diagnostic {
	display := char_display(char)
	d := diag_init(.Error, "UNEXPECTED CHARACTER", span,
		fmt.tprintf("I don't recognize the character `{}`.", display))
	return d
}

diag_unterminated_string :: proc(span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNTERMINATED STRING", span,
		"This string never ends. Try adding a closing `\"`.")
	return d
}

diag_expected_token :: proc(expected: Token_Kind, actual: Token, span: Source_Span) -> Diagnostic {
	expected_str := token_kind_display(expected)
	d := diag_init(.Error, "SYNTAX ERROR", span,
		fmt.tprintf("I expected `{}` here, but I got `{}` instead.", expected_str, actual.text))
	return d
}

diag_unexpected_token :: proc(token: Token) -> Diagnostic {
	d := diag_init(.Error, "SYNTAX ERROR", token.span,
		fmt.tprintf("I was not expecting `{}` here.", token.text))
	switch token.kind {
	case .Pipe:
		append(&d.hints, "Are you trying to write a pattern match?")
	case:
	}
	return d
}

diag_expected_type :: proc(actual: Token, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "SYNTAX ERROR", span,
		fmt.tprintf("I was expecting a type here, but I found `{}` instead.", actual.text))
	return d
}

diag_effectful_naming :: proc(name: string, effects: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "EFFECTFUL FUNCTION NAMING", span,
		fmt.tprintf("This function performs effect {}, so its name needs to end with `!`.", effects))
	append(&d.hints, fmt.tprintf("Try: `{}!`", name))
	return d
}

diag_undefined_name :: proc(name: string, similar: []string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNDEFINED NAME", span,
		fmt.tprintf("I cannot find `{}`.", name))
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_unhandled_effect :: proc(effect_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNHANDLED EFFECT", span,
		fmt.tprintf("This expression performs effect `{}`, but there is no `handle` block around it.", effect_name))
	append(&d.hints, "Try wrapping it with a `handle` block.")
	return d
}

diag_type_mismatch :: proc(type_a: string, type_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("`{}` does not match `{}`.", type_a, type_b))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", type_b)})
	}
	return d
}

diag_primitive_mismatch :: proc(name_a: string, name_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("`{}` does not match `{}`.", name_a, name_b))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", name_b)})
	}
	return d
}

diag_value_row_conflict :: proc(kind_a: string, kind_b: string, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("I expected a {} type here, but I found a {} type instead.", kind_a, kind_b))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this is a {} type", kind_b)})
	}
	return d
}

diag_infinite_type :: proc(type_expr: string, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "INFINITE TYPE", span,
		fmt.tprintf("This creates an infinite type. `{}` is defined in terms of itself, which would make the type infinitely large.", type_expr))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "also related to this"})
	}
	return d
}

diag_arity_mismatch :: proc(expected: int, actual: int, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "ARITY MISMATCH", span,
		fmt.tprintf("This function expects {} argument{}, but it was called with {}.",
			expected, plural_s(expected), actual))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "called here"})
	}
	return d
}

diag_tag_arity_mismatch :: proc(tag_name: string, expected: int, actual: int, span: Source_Span, span_b: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TAG ARITY MISMATCH", span,
		fmt.tprintf("Tag `{}` expects {} payload{}, but here it has {}.",
			tag_name, expected, plural_s(expected), actual))
	if span_b != Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("defined with {} payload{} here", expected, plural_s(expected))})
	}
	return d
}

diag_invalid_extension :: proc(path: string, extension: string) -> Diagnostic {
	d := diag_init(.Error, "INVALID FILE EXTENSION", Source_Span_ZERO,
		fmt.tprintf("I expected a `.camp` file, but you gave me `{}`.", path))
	return d
}

diag_file_not_found :: proc(path: string, os_error: string) -> Diagnostic {
	d := diag_init(.Error, "FILE NOT FOUND", Source_Span_ZERO,
		fmt.tprintf("I could not read `{}` ({}).", path, os_error))
	return d
}

diag_unknown_command :: proc(command: string) -> Diagnostic {
	d := diag_init(.Error, "UNKNOWN COMMAND", Source_Span_ZERO,
		fmt.tprintf("I don't know the command `{}`.", command))
	append(&d.hints, "Try `build`, `check`, `test`, or `fmt`.")
	return d
}

diag_internal :: proc(message: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Internal, "INTERNAL ERROR", span,
		fmt.tprintf("Something went wrong inside the compiler: {}", message))
	append(&d.hints, "This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues")
	return d
}

char_display :: proc(ch: u8) -> string {
	switch ch {
	case '\n': return "\\n"
	case '\t': return "\\t"
	case '\r': return "\\r"
	case ' ':  return "space"
	case:      return string([1]u8{ch})
	}
}

plural_s :: proc(n: int) -> string {
	if n == 1 do return ""
	return "s"
}
```

- [ ] **Step 2: Commit**

```bash
git add src/diag_constructors.odin
git commit -m "feat(diagnostic): add all diagnostic constructor functions"
```

---

### Task 4: CLI Renderer

**Files:**
- Create: `src/diag_renderer_cli.odin`

- [ ] **Step 1: Create `src/diag_renderer_cli.odin`**

The renderer produces Elm-style output. Key components:
- `render_all`: Iterates diagnostics and renders each with blank-line separators, then prints summary
- `render_diagnostic`: Renders header, message, source snippet, labels, hints
- `span_to_line_col`: Converts byte offset to 1-based line:col
- `get_source_line`: Extracts a single source line by line number
- `render_snippet`: Renders a source line with line number gutter + underline
- TTY detection via `os.is_terminal` for ANSI color support

```odin
package camp

import "core:fmt"
import "core:os"
import "core:strings"

Color_Scheme :: struct {
	header_title:  string,
	header_dash:   string,
	file_path:     string,
	primary_caret: string,
	secondary_tilde: string,
	hint_text:     string,
	line_number:   string,
	reset:         string,
}

color_scheme_for :: proc(category: Diagnostic_Category) -> Color_Scheme {
	if !os.is_terminal(os.stdout) {
		return Color_Scheme{}
	}
	switch category {
	case .Error:
		return Color_Scheme{
			header_title = "\x1b[1;31m",
			header_dash = "\x1b[2m",
			file_path = "\x1b[4m",
			primary_caret = "\x1b[1;31m",
			secondary_tilde = "\x1b[36m",
			hint_text = "\x1b[32m",
			line_number = "\x1b[2m",
			reset = "\x1b[0m",
		}
	case .Warning:
		return Color_Scheme{
			header_title = "\x1b[1;33m",
			header_dash = "\x1b[2m",
			file_path = "\x1b[4m",
			primary_caret = "\x1b[1;33m",
			secondary_tilde = "\x1b[36m",
			hint_text = "\x1b[32m",
			line_number = "\x1b[2m",
			reset = "\x1b[0m",
		}
	case .Internal:
		return Color_Scheme{
			header_title = "\x1b[1;35m",
			header_dash = "\x1b[2m",
			file_path = "\x1b[4m",
			primary_caret = "\x1b[1;35m",
			secondary_tilde = "\x1b[36m",
			hint_text = "\x1b[32m",
			line_number = "\x1b[2m",
			reset = "\x1b[0m",
		}
	}
	return Color_Scheme{}
}

render_all :: proc(collector: ^Diagnostic_Collector, file_path: string, source: string) {
	for i, d in collector.diagnostics {
		if i > 0 do fmt.println()
		render_diagnostic(d, file_path, source)
	}
	if collector_has_errors(collector) {
		total := collector.error_count + collector.internal_count
		fmt.printfln("compilation failed with {} error(s)", total)
	} else if collector.warning_count > 0 {
		fmt.printfln("{} warning(s) found", collector.warning_count)
	}
}

render_diagnostic :: proc(d: Diagnostic, file_path: string, source: string) {
	colors := color_scheme_for(d.category)

	render_header(d.title, file_path, colors)
	fmt.println()

	message := word_wrap(d.message, 80)
	fmt.println(message)

	if d.span.file_id >= 0 {
		render_snippet(source, d.span, "^", "", colors, colors.primary_caret)
	}

	for label in d.labels {
		if label.span.file_id >= 0 {
			render_snippet(source, label.span, "~", label.label, colors, colors.secondary_tilde)
		}
	}

	for hint in d.hints {
		fmt.print(colors.hint_text)
		fmt.printfln("  {}", hint)
		fmt.print(colors.reset)
	}
}

render_header :: proc(title: string, file_path: string, colors: Color_Scheme) {
	total_width := 60
	prefix := "-- "
	suffix := " --"
	content_len := len(title) + len(suffix) + 1 + len(file_path)
	dash_count := total_width - len(prefix) - len(title) - len(suffix) - 1 - len(file_path)
	if dash_count < 3 do dash_count = 3

	builder: strings.Builder
	strings.init_builder(&builder, 256)
	defer strings.destroy_builder(&builder)

	strings.write_string(&builder, colors.header_dash)
	strings.write_string(&builder, prefix)
	strings.write_string(&builder, colors.header_title)
	strings.write_string(&builder, title)
	strings.write_string(&builder, colors.header_dash)
	strings.write_rune(&builder, ' ')
	for i in 0..<dash_count {
		strings.write_rune(&builder, '-')
	}
	strings.write_string(&builder, suffix)
	strings.write_rune(&builder, ' ')
	strings.write_string(&builder, colors.file_path)
	strings.write_string(&builder, file_path)
	strings.write_string(&builder, colors.reset)

	fmt.println(strings.builder_to_string(&builder))
}

span_to_line_col :: proc(source: string, span: Source_Span) -> (int, int) {
	line := 1
	col := 1
	for i in 0..<span.start {
		if i >= len(source) { break }
		if source[i] == '\n' {
			line += 1
			col = 1
		} else {
			col += 1
		}
	}
	return line, col
}

get_source_line :: proc(source: string, line_num: int) -> string {
	current_line := 1
	line_start := 0
	for i in 0..<len(source) {
		if current_line == line_num {
			line_start = i
			break
		}
		if source[i] == '\n' {
			current_line += 1
		}
	}
	end := line_start
	for end < len(source) && source[end] != '\n' {
		end += 1
	}
	return source[line_start:end]
}

render_snippet :: proc(source: string, span: Source_Span, marker: string, label: string, colors: Color_Scheme, marker_color: string) {
	line, col := span_to_line_col(source, span)
	line_text := get_source_line(source, line)
	gutter_width := 4
	if line >= 1000 do gutter_width = 6
	else if line >= 100 do gutter_width = 5

	gutter := fmt.tprintf("{}{} ", colors.line_number, line)
	for len(gutter) < gutter_width + 1 {
		// Pad to gutter_width + space
	}
	fmt.print(colors.line_number)
	fmt.print(gutter)
	fmt.print("| ")
	fmt.print(colors.reset)
	fmt.println(line_text)

	span_len := span.end - span.start
	if span_len < 1 do span_len = 1

	fmt.write_string(strings_repeat(" ", gutter_width + 2 + col - 1))
	fmt.print(marker_color)
	for i in 0..<span_len {
		fmt.write_string(marker)
	}
	if len(label) > 0 {
		fmt.write_string(" ")
		fmt.write_string(label)
	}
	fmt.println(colors.reset)
}

strings_repeat :: proc(s: string, count: int) -> string {
	if count <= 0 do return ""
	result := make([]u8, count * len(s))
	for i in 0..<count {
		copy(result[i*len(s):(i+1)*len(s)], transmute([]u8)s)
	}
	return string(result)
}

word_wrap :: proc(text: string, width: int) -> string {
	if len(text) <= width do return text
	builder: strings.Builder
	strings.init_builder(&builder, len(text) + 32)
	defer strings.destroy_builder(&builder)

	line_len := 0
	word_start := 0
	for i in 0..<=len(text) {
		if i == len(text) || text[i] == ' ' {
			word := text[word_start:i]
			if line_len + len(word) + 1 > width && line_len > 0 {
				strings.write_rune(&builder, '\n')
				line_len = 0
			} else if line_len > 0 {
				strings.write_rune(&builder, ' ')
				line_len += 1
			}
			strings.write_string(&builder, word)
			line_len += len(word)
			word_start = i + 1
		}
	}

	return strings.builder_to_string(&builder)
}
```

Note: The implementer must verify Odin's `os.is_terminal` API exists and adjust the TTY detection mechanism if needed. If `os.is_terminal` is not available, fall back to checking environment variables (`TERM`, `NO_COLOR`) or always using plain text initially.

- [ ] **Step 2: Commit**

```bash
git add src/diag_renderer_cli.odin
git commit -m "feat(diagnostic): add CLI renderer with Elm-style output"
```

---

### Task 5: LSP Renderer Types

**Files:**
- Create: `src/diag_renderer_lsp.odin`

- [ ] **Step 1: Create `src/diag_renderer_lsp.odin` with LSP mapping types only**

```odin
package camp

LSP_Position :: struct {
	line:      uint,
	character: uint,
}

LSP_Range :: struct {
	start: LSP_Position,
	end:   LSP_Position,
}

LSP_DiagnosticSeverity :: enum int {
	Error   = 1,
	Warning = 2,
	Information = 3,
	Hint    = 4,
}

LSP_DiagnosticRelatedInfo :: struct {
	location: LSP_Range,
	message:  string,
}

LSP_Diagnostic :: struct {
	range:    LSP_Range,
	severity: LSP_DiagnosticSeverity,
	message:  string,
	related:  [dynamic]LSP_DiagnosticRelatedInfo,
}

lsp_from_diagnostic :: proc(d: Diagnostic, source: string) -> LSP_Diagnostic {
	line, col := span_to_line_col(source, d.span)
	end_line, end_col := span_end_to_line_col(source, d.span)
	result: LSP_Diagnostic
	result.range.start = LSP_Position{line = uint(line - 1), character = uint(col - 1)}
	result.range.end = LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)}
	switch d.category {
	case .Error:    result.severity = .Error
	case .Warning:  result.severity = .Warning
	case .Internal: result.severity = .Error
	}
	msg := d.message
	for hint in d.hints {
		msg = fmt.tprintf("{}\n\n{}", msg, hint)
	}
	result.message = msg
	result.related = make([dynamic]LSP_DiagnosticRelatedInfo, 0, len(d.labels))
	for label in d.labels {
		ll, lc := span_to_line_col(source, label.span)
		el, ec := span_end_to_line_col(source, label.span)
		append(&result.related, LSP_DiagnosticRelatedInfo{
			location = LSP_Range{
				start = LSP_Position{line = uint(ll - 1), character = uint(lc - 1)},
				end   = LSP_Position{line = uint(el - 1), character = uint(ec - 1)},
			},
			message = label.label,
		})
	}
	return result
}

span_end_to_line_col :: proc(source: string, span: Source_Span) -> (int, int) {
	line := 1
	col := 1
	for i in 0..<span.end {
		if i >= len(source) { break }
		if source[i] == '\n' {
			line += 1
			col = 1
		} else {
			col += 1
		}
	}
	return line, col
}
```

- [ ] **Step 2: Commit**

```bash
git add src/diag_renderer_lsp.odin
git commit -m "feat(diagnostic): add LSP renderer types and mapping"
```

---

### Task 6: Migrate Context and Type_Store

**Files:**
- Modify: `src/context.odin`
- Modify: `src/types.odin`

- [ ] **Step 1: Update `src/context.odin` — replace `Error_Collector` with `Diagnostic_Collector`**

Change `Compilation_Context` to use `Diagnostic_Collector`:

```odin
Compilation_Context :: struct {
	arena:     virtual.Arena,
	allocator: mem.Allocator,
	interner:   Intern_Table,
	collector:  Diagnostic_Collector,
}
```

Change `context_init` to call `collector_init` on `Diagnostic_Collector` (same name, already works).

Change `context_destroy` to call `collector_destroy` on `Diagnostic_Collector` (same name, already works).

- [ ] **Step 2: Update `src/types.odin` — replace `Error_Collector` pointer with `Diagnostic_Collector` pointer**

In `Type_Store`, change the `collector` field type:

```odin
collector: ^Diagnostic_Collector,
```

Also update `type_store_init` parameter type:

```odin
type_store_init :: proc(store: ^Type_Store, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
```

- [ ] **Step 3: Verify it compiles (expect errors in files that still reference old types)**

Run: `odin build src 2>&1 | head -30`

Expected: Compilation errors in lexer.odin, parser.odin, typecheck.odin, unify.odin, cli.odin, main.odin, and test files that still reference `Error_Collector` / `collector_add`. This is expected — those files are migrated in subsequent tasks.

- [ ] **Step 4: Commit**

```bash
git add src/context.odin src/types.odin
git commit -m "refactor(diagnostic): migrate context and type_store to Diagnostic_Collector"
```

---

### Task 7: Migrate Lexer

**Files:**
- Modify: `src/lexer.odin`

- [ ] **Step 1: Update lexer error emissions**

In `src/lexer.odin`, the `Lexer` struct has a `collector: ^Error_Collector` field. Change it to `collector: ^Diagnostic_Collector`.

Update `lexer_init` parameter accordingly.

Replace the two `collector_add` calls:

Line 196 — unexpected character:
```odin
// OLD:
collector_add(l.collector, .Error, "unexpected character", lexer_make_span(l, start))
// NEW:
collector_add_diag(l.collector, diag_unexpected_char(ch, lexer_make_span(l, start)))
```

Line 246 — unterminated string:
```odin
// OLD:
collector_add(l.collector, .Error, "unterminated string literal", lexer_make_span(l, start))
// NEW:
collector_add_diag(l.collector, diag_unterminated_string(lexer_make_span(l, start)))
```

- [ ] **Step 2: Verify it compiles**

Run: `odin build src 2>&1 | head -10`

- [ ] **Step 3: Commit**

```bash
git add src/lexer.odin
git commit -m "refactor(diagnostic): migrate lexer to diagnostic constructors"
```

---

### Task 8: Migrate Parser

**Files:**
- Modify: `src/parser.odin`

- [ ] **Step 1: Update parser error emissions**

In `src/parser.odin`, the `Parser` struct has a `collector: ^Error_Collector` field. Change it to `collector: ^Diagnostic_Collector`.

Update `parser_init` parameter accordingly.

Replace the three `collector_add` calls:

Line 54 — expected token:
```odin
// OLD:
collector_add(p.collector, .Error, fmt.tprintf("expected {}, got {}", kind, p.current.kind), p.current.span)
// NEW:
collector_add_diag(p.collector, diag_expected_token(kind, p.current, p.current.span))
```

Line 242 — unexpected token:
```odin
// OLD:
collector_add(p.collector, .Error, fmt.tprintf("unexpected token: {}", tok.kind), tok.span)
// NEW:
collector_add_diag(p.collector, diag_unexpected_token(tok))
```

Line 801 — expected type:
```odin
// OLD:
collector_add(p.collector, .Error, fmt.tprintf("expected type, got {}", p.current.kind), p.current.span)
// NEW:
collector_add_diag(p.collector, diag_expected_type(p.current, p.current.span))
```

- [ ] **Step 2: Verify it compiles**

Run: `odin build src 2>&1 | head -10`

- [ ] **Step 3: Commit**

```bash
git add src/parser.odin
git commit -m "refactor(diagnostic): migrate parser to diagnostic constructors"
```

---

### Task 9: Migrate Typecheck (including Levenshtein)

**Files:**
- Modify: `src/typecheck.odin`

- [ ] **Step 1: Add Levenshtein distance function to `src/typecheck.odin`**

This enables "Did you mean?" suggestions for undefined names:

```odin
levenshtein_distance :: proc(a: string, b: string) -> int {
	if len(a) == 0 do return len(b)
	if len(b) == 0 do return len(a)

	matrix: [dynamic][dynamic]int
	matrix = make([dynamic][dynamic]int, len(a) + 1)
	for i in 0..<=len(a) {
		matrix[i] = make([dynamic]int, len(b) + 1)
		matrix[i][0] = i
	}
	for j in 0..<=len(b) {
		matrix[0][j] = j
	}
	defer {
		for i in 0..<=len(a) {
			delete(matrix[i])
		}
		delete(matrix)
	}

	for i in 1..<=len(a) {
		for j in 1..<=len(b) {
			cost := 1
			if a[i-1] == b[j-1] do cost = 0
			matrix[i][j] = min(
				matrix[i-1][j] + 1,
				matrix[i][j-1] + 1,
				matrix[i-1][j-1] + cost,
			)
		}
	}

	return matrix[len(a)][len(b)]
}

find_similar_names :: proc(name: string, env: ^Type_Env) -> []string {
	best_name: string
	best_dist := 999
	for k, _ in env.bindings {
		candidate := intern_get(env.store.interner, k)
		dist := levenshtein_distance(name, candidate)
		if dist < best_dist && dist <= 3 && dist < len(name) / 2 + 1 {
			best_dist = dist
			best_name = candidate
		}
	}
	if best_dist < 999 {
		return []string{best_name}
	}
	return nil
}
```

Note: The implementer must verify that `env.bindings` iteration provides access to the interner, and adjust if `Type_Env` doesn't store a reference to the `Type_Store`/`Intern_Table`. If the interner is not accessible from `env`, pass `store.interner` as an additional parameter.

- [ ] **Step 2: Update typecheck error emissions**

Replace the three `collector_add` calls in `src/typecheck.odin`:

Lines 42-44 — effectful naming:
```odin
// OLD:
name_str := intern_get(store.interner, d.name.name)
collector_add(store.collector, .Error,
	fmt.tprintf("function with non-empty effect row must have '!' in name: '{}'", name_str),
	d.span)
// NEW:
name_str := intern_get(store.interner, d.name.name)
effects_str := format_effect_row(store, result.effects)
collector_add_diag(store.collector, diag_effectful_naming(name_str, effects_str, d.span))
```

`format_effect_row` is a new helper that resolves the effect row to a human-readable string like `{IO}`:
```odin
format_effect_row :: proc(store: ^Type_Store, effects: Type_Var_ID) -> string {
	rid := resolve_var(store, effects)
	rv := get_var(store, rid)
	if rv.kind == .Effect_Row {
		if len(rv.effect_names) == 0 do return "{}"
		builder: strings.Builder
		strings.init_builder(&builder, 64)
		strings.write_rune(&builder, '{')
		for i, name in rv.effect_names {
			if i > 0 do strings.write_string(&builder, ", ")
			strings.write_string(&builder, intern_get(store.interner, name))
		}
		strings.write_rune(&builder, '}')
		result := strings.builder_to_string(&builder)
		strings.destroy_builder(&builder)
		return result
	}
	return "{}"
}
```

Note: The implementer must verify the exact field names on `Type_Var` for effect rows by reading `src/types.odin`. The field may be named differently (e.g., `row_entries` instead of `effect_names`).

Lines 123-125 — undefined name:
```odin
// OLD:
collector_add(store.collector, .Error,
	fmt.tprintf("undefined name: {}", e.name.name),
	e.span)
// NEW:
name_str := intern_get(store.interner, e.name.name)
similar := find_similar_names(name_str, env, store.interner)
collector_add_diag(store.collector, diag_undefined_name(name_str, similar, e.span))
```

Lines 482-484 — unhandled effect:
```odin
// OLD:
effect_str := intern_get(store.interner, effect_name)
collector_add(store.collector, .Error,
	fmt.tprintf("unhandled effect: {}", effect_str),
	e.span)
// NEW:
effect_str := intern_get(store.interner, effect_name)
collector_add_diag(store.collector, diag_unhandled_effect(effect_str, e.span))
```

- [ ] **Step 3: Verify it compiles**

Run: `odin build src 2>&1 | head -10`

- [ ] **Step 4: Commit**

```bash
git add src/typecheck.odin
git commit -m "refactor(diagnostic): migrate typecheck to diagnostic constructors with Levenshtein suggestions"
```

---

### Task 10: Migrate Unify (fix dual-span bugs)

**Files:**
- Modify: `src/unify.odin`

- [ ] **Step 1: Remove `Unify_Error` struct and replace `make_unify_error`**

The `Unify_Error` struct is no longer needed — diagnostics carry both spans via `Span_Label`. Remove the struct entirely.

Replace `make_unify_error` and all unify error emissions:

```odin
// Remove Unify_Error struct entirely
// Remove make_unify_error entirely

// Change unify return type from ^Unify_Error to bool
unify :: proc(store: ^Type_Store, a: Type_Var_ID, b: Type_Var_ID) -> bool {
	ra := resolve_var(store, a)
	rb := resolve_var(store, b)

	if ra == rb {
		return true
	}

	va := get_var(store, ra)
	vb := get_var(store, rb)

	if va.kind != vb.kind {
		if va.kind == .Value && vb.kind != .Value {
			collector_add_diag(store.collector,
				diag_value_row_conflict("value", "row", va.span, vb.span))
			return false
		}
		if va.kind != .Value && vb.kind == .Value {
			collector_add_diag(store.collector,
				diag_value_row_conflict("row", "value", va.span, vb.span))
			return false
		}
	}

	if occurs_check(store, ra, rb) {
		collector_add_diag(store.collector,
			diag_infinite_type("this type", va.span, vb.span))
		return false
	}
	// ... rest of unify continues, returning true on success, false on error
```

Lines 78-89 — type mismatch (tag mismatch):
```odin
// OLD:
span := get_var(store, context_var).span
collector_add(store.collector, .Error,
	fmt.tprintf("type mismatch: {} vs {}", a.tag, b.tag),
	span)
err := new(Unify_Error)
err^ = Unify_Error{...}
return err
// NEW:
va := get_var(store, resolve_var(store, a_id))
vb := get_var(store, resolve_var(store, b_id))
type_a_str := format_inferred_type(store, a)
type_b_str := format_inferred_type(store, b)
collector_add_diag(store.collector,
	diag_type_mismatch(type_a_str, type_b_str, va.span, vb.span))
return false
```

Note: `a_id` and `b_id` are the `Type_Var_ID` values passed into `unify_inferred`. The current code uses `context_var` for the span, but we need the original `a` and `b` var IDs. The implementer must check the full `unify_inferred` signature to ensure these are available. If `unify_inferred` doesn't have access to the original var IDs, add them as parameters.

Lines 92-103 — primitive mismatch:
```odin
// OLD:
span := get_var(store, context_var).span
collector_add(store.collector, .Error,
	fmt.tprintf("primitive mismatch: {} vs {}", a.primitive_name, b.primitive_name),
	span)
// NEW:
name_a := intern_get(store.interner, a.primitive_name)
name_b := intern_get(store.interner, b.primitive_name)
va := get_var(store, resolve_var(store, a_id))
vb := get_var(store, resolve_var(store, b_id))
collector_add_diag(store.collector,
	diag_primitive_mismatch(name_a, name_b, va.span, vb.span))
return false
```

Lines 109-110 — function arity mismatch (BUG FIX — currently passes `context_var` for both):
```odin
// OLD:
return make_unify_error(store, context_var, context_var,
	fmt.tprintf("function arity mismatch: {} vs {}", len(a.param_ids), len(b.param_ids)))
// NEW:
va := get_var(store, resolve_var(store, a_id))
vb := get_var(store, resolve_var(store, b_id))
collector_add_diag(store.collector,
	diag_arity_mismatch(len(a.param_ids), len(b.param_ids), va.span, vb.span))
return false
```

Lines 350-351 — tag payload arity mismatch (BUG FIX — currently passes `context_var` for both, and `at.name` is Intern_ID):
```odin
// OLD:
return make_unify_error(store, context_var, context_var,
	fmt.tprintf("tag payload arity mismatch for {}: {} vs {}", at.name, len(at.payload), len(bt.payload)))
// NEW:
tag_name := intern_get(store.interner, at.name)
va := get_var(store, resolve_var(store, a_id))
vb := get_var(store, resolve_var(store, b_id))
collector_add_diag(store.collector,
	diag_tag_arity_mismatch(tag_name, len(at.payload), len(bt.payload), va.span, vb.span))
return false
```

- [ ] **Step 2: Add `format_inferred_type` helper**

This resolves an `Inferred_Type` to a human-readable string for error messages:

```odin
format_inferred_type :: proc(store: ^Type_Store, t: Inferred_Type) -> string {
	switch t.tag {
	case .Primitive:
		return intern_get(store.interner, t.primitive_name)
	case .Function:
		return fmt.tprintf("({} params) -> {}", len(t.param_ids), format_type_var(store, t.return_id))
	case .Record_Row:
		return "record"
	case .Tag_Union_Row:
		return "tag union"
	case .Effect_Row:
		return "effect row"
	}
	return "unknown"
}

format_type_var :: proc(store: ^Type_Store, id: Type_Var_ID) -> string {
	rid := resolve_var(store, id)
	rv := get_var(store, rid)
	if rv.kind == .Value && rv.bound.tag != .Unbound {
		return format_inferred_type(store, rv.bound)
	}
	return "?"
}
```

Note: The implementer must verify the exact field names on `Type_Var` and `Inferred_Type` by reading `src/types.odin`. The bound type field may be named differently.

- [ ] **Step 3: Update all callers of `unify`**

Since `unify` now returns `bool` instead of `^Unify_Error`, update all call sites that check `err != nil` to check `!result` instead. Search for `err := unify(` and `if err != nil` patterns throughout `src/unify.odin` and replace:

```odin
// OLD:
err := unify(store, a, b)
if err != nil {
	return err
}
// NEW:
if !unify(store, a, b) {
	return false
}
```

- [ ] **Step 4: Verify it compiles**

Run: `odin build src 2>&1 | head -20`

- [ ] **Step 5: Commit**

```bash
git add src/unify.odin
git commit -m "refactor(diagnostic): migrate unify to diagnostic constructors, fix dual-span bugs"
```

---

### Task 11: Migrate CLI and Main

**Files:**
- Modify: `src/cli.odin`
- Modify: `src/main.odin`

- [ ] **Step 1: Update `src/cli.odin`**

Replace `Error_Collector` references with `Diagnostic_Collector`.

Replace CLI-level `fmt.printfln` error calls:

Line 31 — invalid extension:
```odin
// OLD:
fmt.printfln("error: expected .camp file, got {}", file_path)
os.exit(1)
// NEW:
ext := filepath.ext(file_path)
collector_add_diag(&ctx.collector, diag_invalid_extension(file_path, ext))
render_all(&ctx.collector, file_path, "")
os.exit(1)
```

Note: The `ctx` isn't initialized yet at line 31 in the current code. Move the `context_init` call earlier, before the extension check, OR keep the direct `fmt.printfln` for pre-context errors but format them in the new style. The implementer should choose the simpler approach: initialize context before the extension check.

Line 40 — file not found:
```odin
// OLD:
fmt.printfln("error: could not read file {}", file_path)
// NEW:
collector_add_diag(&ctx.collector, diag_file_not_found(file_path, fmt.tprintf("{}", err)))
```

Lines 56-62 — parse error reporting (replace `report_error` loop with `render_all`):
```odin
// OLD:
if collector_has_errors(&ctx.collector) {
	for e in ctx.collector.errors {
		report_error(&ctx.collector, file_path, source, e)
	}
	fmt.printfln("compilation failed with {} error(s)", ctx.collector.error_count)
	os.exit(1)
}
// NEW:
if collector_has_errors(&ctx.collector) {
	render_all(&ctx.collector, file_path, source)
	os.exit(1)
}
```

Lines 76-79 — typecheck error reporting (BUG FIX — currently doesn't show individual errors):
```odin
// OLD:
if collector_has_errors(&ctx.collector) {
	fmt.println("type errors found, stopping.")
	os.exit(1)
}
// NEW:
if collector_has_errors(&ctx.collector) {
	render_all(&ctx.collector, file_path, source)
	os.exit(1)
}
```

Remove the `import` of the old reporter module if it was imported separately.

- [ ] **Step 2: Update `src/main.odin`**

Replace CLI-level error calls:

Lines 8-15 — no arguments:
```odin
// OLD:
if len(args) < 2 {
	fmt.printfln("Camp compiler v{}", VERSION)
	fmt.println("Usage: camp <command> [options] <file>")
	fmt.println("Commands: build, test, fmt, check")
	os.exit(1)
}
// NEW:
if len(args) < 2 {
	fmt.printfln("Camp compiler v{}", VERSION)
	fmt.println("Usage: camp <command> [options] <file>")
	fmt.println("Commands: build, test, fmt, check")
	os.exit(1)
}
```
(This is a usage message, not a diagnostic — keep it as-is.)

Lines 18-21 — unknown command:
```odin
// OLD:
if !ok {
	fmt.printfln("error: unknown command '{}'", args[1])
	fmt.println("Commands: build, test, fmt, check")
	os.exit(1)
}
// NEW:
if !ok {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)
	collector_add_diag(&collector, diag_unknown_command(args[1]))
	render_all(&collector, "", "")
	os.exit(1)
}
```

- [ ] **Step 3: Verify it compiles**

Run: `odin build src 2>&1 | head -20`

- [ ] **Step 4: Commit**

```bash
git add src/cli.odin src/main.odin
git commit -m "refactor(diagnostic): migrate CLI and main to diagnostic system, fix type error reporting bug"
```

---

### Task 12: Delete Old Error/Reporter Files

**Files:**
- Delete: `src/error.odin`
- Delete: `src/reporter.odin`

- [ ] **Step 1: Delete old files**

```bash
rm src/error.odin src/reporter.odin
```

- [ ] **Step 2: Verify it compiles**

Run: `odin build src 2>&1 | head -20`

Expected: No errors (all references should already be migrated)

- [ ] **Step 3: Commit**

```bash
git add -A src/error.odin src/reporter.odin
git commit -m "chore(diagnostic): remove old error.odin and reporter.odin"
```

---

### Task 13: Migrate Tests

**Files:**
- Modify: `src/test_bootstrap.odin`
- Modify: `src/test_lexer.odin` (if it references `Error_Collector`)
- Modify: `src/test_typecheck.odin` (if it references `Error_Collector`)
- Modify: `src/test_integration.odin` (if it references `Error_Collector`)

- [ ] **Step 1: Update `src/test_bootstrap.odin`**

Replace all `Error_Collector` with `Diagnostic_Collector`, `collector_add` with `collector_add_diag`, and update test assertions.

The three collector tests become:

```odin
package camp

import "core:testing"

@(test)
test_collector_add_warning :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	d := diag_init(.Warning, "TEST", Source_Span_ZERO, "unused variable")
	collector_add_diag(&collector, d)
	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, collector.error_count == 0)
	testing.expect(t, !collector_has_errors(&collector))
}

@(test)
test_collector_add_error :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	d := diag_init(.Error, "TEST", Source_Span_ZERO, "type mismatch")
	collector_add_diag(&collector, d)
	testing.expect(t, collector.warning_count == 0)
	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector_has_errors(&collector))
}

@(test)
test_collector_add_internal :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	d := diag_init(.Internal, "TEST", Source_Span_ZERO, "impossible type after typecheck")
	collector_add_diag(&collector, d)
	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, collector_has_errors(&collector))
}
```

The intern tests remain unchanged.

- [ ] **Step 2: Search for remaining `Error_Collector` references in test files**

Run: `rg "Error_Collector" src/test_`

If any references remain, update them to `Diagnostic_Collector` and update any `collector_add` calls to `collector_add_diag`.

- [ ] **Step 3: Run unit tests**

Run: `odin test src`

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add src/test_bootstrap.odin src/test_lexer.odin src/test_typecheck.odin src/test_integration.odin
git commit -m "test(diagnostic): migrate tests to Diagnostic_Collector"
```

---

### Task 14: Integration Test — Verify Error Output

**Files:**
- None (manual verification)

- [ ] **Step 1: Build the compiler**

Run: `odin build src -out:camp`

- [ ] **Step 2: Test a lexer error**

Create a test file with an invalid character and verify the output:

```bash
echo 'x = @' > /tmp/test-err.camp && ./camp build /tmp/test-err.camp
```

Expected output should look like:
```
-- UNEXPECTED CHARACTER ----------------------------------------- /tmp/test-err.camp

1 | x = @
        ^
I don't recognize the character `@`.

compilation failed with 1 error(s)
```

- [ ] **Step 3: Test a type error**

Create a test file with a type mismatch:

```bash
echo 'x = 42 y = x + true' > /tmp/test-typeerr.camp && ./camp build /tmp/test-typeerr.camp
```

Expected: Elm-style TYPE MISMATCH output with source snippets

- [ ] **Step 4: Test an undefined name with suggestion**

```bash
echo 'x = foo' > /tmp/test-undef.camp && ./camp build /tmp/test-undef.camp
```

Expected: UNDEFINED NAME output (without suggestion since no similar names exist in scope)

- [ ] **Step 5: Test the effectful naming error**

```bash
echo 'effect IO { println } main = || -> {IO} I64 { 0 }' > /tmp/test-effect.camp && ./camp build /tmp/test-effect.camp
```

Expected: EFFECTFUL FUNCTION NAMING output with "Try: `main!`" hint

- [ ] **Step 6: Test a CLI error**

```bash
./camp build /tmp/test.txt
```

Expected: INVALID FILE EXTENSION output

- [ ] **Step 7: Run full unit test suite**

Run: `odin test src`

Expected: All tests pass

- [ ] **Step 8: Commit any fixes**

If any issues were found and fixed during integration testing:

```bash
git add -A src/ && git commit -m "fix(diagnostic): integration test fixes"
```

---

### Task 15: Add Renderer Unit Tests

**Files:**
- Create: `src/test_diagnostic.odin`

- [ ] **Step 1: Create `src/test_diagnostic.odin` with renderer tests**

```odin
package camp

import "core:testing"
import "core:strings"

@(test)
test_render_simple_error :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	source := "x = @"
	span := Source_Span{file_id = 0, start = 4, end = 5}
	collector_add_diag(&collector, diag_unexpected_char('@', span))

	testing.expect(t, collector.error_count == 1)
	testing.expect(t, collector_has_errors(&collector))

	d := collector.diagnostics[0]
	testing.expect(t, d.category == .Error)
	testing.expect(t, d.title == "UNEXPECTED CHARACTER")
	testing.expect(t, len(d.hints) == 0)
}

@(test)
test_render_error_with_hint :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	span := Source_Span{file_id = 0, start = 0, end = 3}
	collector_add_diag(&collector, diag_undefined_name("foo", []string{"bar"}, span))

	testing.expect(t, collector.error_count == 1)

	d := collector.diagnostics[0]
	testing.expect(t, d.title == "UNDEFINED NAME")
	testing.expect(t, len(d.hints) == 1)
	testing.expect(t, d.hints[0] == "Did you mean `bar`?")
}

@(test)
test_render_multi_span :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	span_a := Source_Span{file_id = 0, start = 0, end = 3}
	span_b := Source_Span{file_id = 0, start = 10, end = 13}
	collector_add_diag(&collector, diag_type_mismatch("I64", "String", span_a, span_b))

	testing.expect(t, collector.error_count == 1)

	d := collector.diagnostics[0]
	testing.expect(t, d.title == "TYPE MISMATCH")
	testing.expect(t, len(d.labels) == 1)
	testing.expect(t, d.labels[0].span == span_b)
}

@(test)
test_render_warning :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	d := diag_init(.Warning, "UNUSED VARIABLE", Source_Span_ZERO, "x is unused")
	collector_add_diag(&collector, d)

	testing.expect(t, collector.warning_count == 1)
	testing.expect(t, !collector_has_errors(&collector))
}

@(test)
test_render_internal :: proc(t: ^testing.T) {
	collector: Diagnostic_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	span := Source_Span{file_id = 0, start = 0, end = 1}
	collector_add_diag(&collector, diag_internal("impossible type", span))

	testing.expect(t, collector.internal_count == 1)
	testing.expect(t, collector_has_errors(&collector))

	d := collector.diagnostics[0]
	testing.expect(t, d.category == .Internal)
	testing.expect(t, len(d.hints) == 1)
}

@(test)
test_span_to_line_col :: proc(t: ^testing.T) {
	source := "abc\ndef\nghi"
	span := Source_Span{file_id = 0, start = 4, end = 7}
	line, col := span_to_line_col(source, span)
	testing.expect(t, line == 2)
	testing.expect(t, col == 1)
}

@(test)
test_char_display :: proc(t: ^testing.T) {
	testing.expect(t, char_display('\n') == "\\n")
	testing.expect(t, char_display(' ') == "space")
	testing.expect(t, char_display('a') == "a")
}

@(test)
test_plural_s :: proc(t: ^testing.T) {
	testing.expect(t, plural_s(1) == "")
	testing.expect(t, plural_s(0) == "s")
	testing.expect(t, plural_s(2) == "s")
}
```

- [ ] **Step 2: Run the tests**

Run: `odin test src`

Expected: All tests pass including the new ones

- [ ] **Step 3: Commit**

```bash
git add src/test_diagnostic.odin
git commit -m "test(diagnostic): add diagnostic renderer unit tests"
```

---

### Task 16: Final Verification and Push

**Files:**
- None

- [ ] **Step 1: Run full unit test suite**

Run: `odin test src`

Expected: All tests pass

- [ ] **Step 2: Build the compiler**

Run: `odin build src -out:camp`

Expected: Successful build with no warnings

- [ ] **Step 3: Manual smoke test with a real Camp file**

Create a valid Camp file and verify it still compiles:

```bash
echo 'main! = || -> I64 { 42 }' > /tmp/test-valid.camp && ./camp build /tmp/test-valid.camp
```

Expected: Successful compilation output (no diagnostic errors)

- [ ] **Step 4: Push**

```bash
git push
```
