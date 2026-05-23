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

diag_module_not_found :: proc(module_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "MODULE NOT FOUND", span,
		fmt.tprintf("module '{}' not found.", module_name))
	return d
}

diag_cyclic_dependency :: proc(cycle_path: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "CYCLIC DEPENDENCY", span,
		fmt.tprintf("cyclic dependency: {}", cycle_path))
	return d
}

diag_import_not_exported :: proc(name: string, module_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NOT EXPORTED", span,
		fmt.tprintf("'{}' is not exported from module '{}'.", name, module_name))
	append(&d.hints, fmt.tprintf("Use qualified access {}.{} or make it pub.", module_name, name))
	return d
}

diag_import_conflicts_binding :: proc(name: string, module_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "IMPORT CONFLICT", span,
		fmt.tprintf("'{}' imported from {} conflicts with existing binding — use qualified access {}.{}", name, module_name, module_name, name))
	return d
}

diag_import_ambiguous :: proc(name: string, mod_a: string, mod_b: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "AMBIGUOUS IMPORT", span,
		fmt.tprintf("'{}' is ambiguous — imported from both {} and {}; use qualified access.", name, mod_a, mod_b))
	return d
}

diag_entry_point_not_found :: proc() -> Diagnostic {
	d := diag_init(.Error, "ENTRY POINT NOT FOUND", Source_Span_ZERO,
		"entry point not found — expected src/Main.camp with pub main!")
	return d
}

diag_entry_point_no_main :: proc() -> Diagnostic {
	d := diag_init(.Error, "NO MAIN FUNCTION", Source_Span_ZERO,
		"entry point module Main does not define pub main!")
	return d
}

diag_project_no_source :: proc() -> Diagnostic {
	d := diag_init(.Error, "NO SOURCE FILES", Source_Span_ZERO,
		"no Camp source files found — expected a src/ directory")
	return d
}

diag_duplicate_module_name :: proc(name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "DUPLICATE NAME", span,
		fmt.tprintf("name '{}' is already defined in this module.", name))
	return d
}

diag_internal :: proc(message: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Internal, "INTERNAL ERROR", span,
		fmt.tprintf("Something went wrong inside the compiler: {}", message))
	append(&d.hints, "This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues")
	return d
}

diag_unqualified_tag :: proc(newtype_name: string, tag_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNQUALIFIED TAG", span,
		fmt.tprintf("Tag `{}` belongs to newtype `{}` — use `{}.{}` to construct it.", tag_name, newtype_name, newtype_name, tag_name))
	return d
}

diag_tag_not_owned :: proc(newtype_name: string, tag_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TAG NOT OWNED", span,
		fmt.tprintf("Tag `{}` does not belong to newtype `{}`.", tag_name, newtype_name))
	return d
}

diag_newtype_coercion :: proc(newtype_name: string, inner_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NEWTYPE COERCION", span,
		fmt.tprintf("Cannot use `{}` where `{}` is expected — newtypes are distinct from their inner type. Use `.inner()` to unwrap.", newtype_name, inner_name))
	return d
}

diag_orphan_rule_violation :: proc(type_name: string, trait_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "ORPHAN RULE VIOLATION", span,
		fmt.tprintf("Cannot implement `{}` for `{}` here — implementations must be in the same module as the type or the trait.", trait_name, type_name))
	return d
}

diag_overlapping_instance :: proc(type_name: string, trait_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "OVERLAPPING INSTANCE", span,
		fmt.tprintf("`{}` already implements `{}` — cannot implement the same trait for the same type twice.", type_name, trait_name))
	return d
}

diag_constraint_violation :: proc(type_name: string, constraint_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "CONSTRAINT VIOLATION", span,
		fmt.tprintf("`{}` does not satisfy constraint `{}`.", type_name, constraint_name))
	return d
}

diag_missing_trait_method :: proc(type_name: string, trait_name: string, method_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "MISSING TRAIT METHOD", span,
		fmt.tprintf("`{}` does not implement method `{}` required by trait `{}`.", type_name, method_name, trait_name))
	return d
}

diag_trait_method_signature_mismatch :: proc(type_name: string, trait_name: string, method_name: string, expected_sig: string, actual_sig: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TRAIT METHOD SIGNATURE MISMATCH", span,
		fmt.tprintf("`{}`'s `{}` method has wrong signature for trait `{}`.", type_name, method_name, trait_name))
	append(&d.labels, Span_Label{span = span, label = fmt.tprintf("expected `{}`, got `{}`", expected_sig, actual_sig)})
	return d
}

diag_newtype_opaque_violation :: proc(type_name: string, action: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "OPAQUE TYPE", span,
		fmt.tprintf("Nominal type `{}` is opaque outside its defining module — cannot {} here.", type_name, action))
	append(&d.hints, fmt.tprintf("Perform this operation in the module that defines `{}`, or use `pub` variants.", type_name))
	return d
}

diag_unjoined_spawn :: proc(span: Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNJOINED SPAWN", span,
		"This spawned handle is not joined on all exit paths. Unjoined handles are cancelled when the handler exits, which may silently discard results.")
	append(&d.hints, "Use `join!` to await the result, or explicitly `cancel!` to discard it.")
	return d
}

diag_redundant_pattern :: proc(span: Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "REDUNDANT PATTERN", span,
		"This pattern is redundant — it is already covered by an earlier arm.")
	append(&d.hints, "Remove this arm or reorder patterns so this one comes first.")
	return d
}

diag_non_exhaustive_bool :: proc(missing: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NON-EXHAUSTIVE MATCH", span,
		fmt.tprintf("This match on Bool is non-exhaustive: missing branch for `{}`.", missing))
	return d
}

diag_non_exhaustive_int_string :: proc(type_name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "NON-EXHAUSTIVE MATCH", span,
		fmt.tprintf("This match on {} can never be exhaustive without a wildcard pattern.", type_name))
	append(&d.hints, "Add a wildcard `_` or variable pattern to handle remaining values.")
	return d
}

diag_shadow :: proc(name: string, span: Source_Span) -> Diagnostic {
	d := diag_init(.Error, "SHADOWING", span,
		fmt.tprintf("`{}` shadows a binding from an enclosing scope. All shadowing is forbidden.", name))
	append(&d.hints, "Use a different name for this binding.")
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
