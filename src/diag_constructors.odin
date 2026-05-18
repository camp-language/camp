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
	#partial switch token.kind {
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
	case:      return fmt.tprintf("{}", rune(ch))
	}
}

plural_s :: proc(n: int) -> string {
	if n == 1 do return ""
	return "s"
}
