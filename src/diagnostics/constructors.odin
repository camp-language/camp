package diagnostics

import "camp:base"

import "core:fmt"

EXPECTED_GOT_FMT :: "expected {}, got {}"

diag_init :: proc(category: Diagnostic_Category, title: string, span: base.Source_Span, message: string) -> Diagnostic {
	d: Diagnostic
	d.category = category
	d.title = title
	d.span = span
	d.message = message
	d.labels = make([dynamic]Span_Label, 0, 4)
	d.hints = make([dynamic]string, 0, 2)
	return d
}

diag_unexpected_char :: proc(char: u8, span: base.Source_Span) -> Diagnostic {
	display := char_display(char)
	d := diag_init(.Error, "UNEXPECTED CHARACTER", span,
		fmt.tprintf("I don't recognize the character `{}`.", display))
	return d
}

diag_unterminated_string :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNTERMINATED STRING", span,
		"This string never ends. Try adding a closing `\"`.")
	return d
}

diag_expected_token :: proc(expected: base.Token_Kind, actual: base.Token, span: base.Source_Span) -> Diagnostic {
	expected_str := token_kind_display(expected)
	d := diag_init(.Error, "SYNTAX ERROR", span,
		fmt.tprintf("I expected `{}` here, but I got `{}` instead.", expected_str, actual.text))
	return d
}

diag_unexpected_token :: proc(token: base.Token) -> Diagnostic {
	d := diag_init(.Error, "SYNTAX ERROR", token.span,
		fmt.tprintf("I was not expecting `{}` here.", token.text))
	#partial switch token.kind {
	case .Pipe:
		append(&d.hints, "Are you trying to write a pattern match?")
	case .Int_Literal, .Float_Literal, .String_Literal, .Interpolated_String_Literal,
	     .Identifier, .Upper_Id,
	     .Kw_If, .Kw_Else, .Kw_Match, .Kw_Is, .Kw_Derives, .Kw_Handle,
	     .Kw_In, .Kw_With, .Kw_Import, .Kw_As, .Kw_For,
	     .Kw_And, .Kw_Or, .Kw_Expect, .Kw_Test, .Kw_Not, .Kw_Pub, .Kw_Self, .Kw_Par,
	     .Kw_Where, .Arrow, .Fat_Arrow, .Eq, .Colon_Eq, .Colon, .Comma, .Dot, .Dot_Dot,
	     .Dollar, .Hash, .At, .Lt, .Gt, .Lt_Eq, .Gt_Eq, .Eq_Eq, .Bang_Eq,
	     .Plus, .Minus, .Star, .Slash, .Percent, .Amp, .Caret, .Tilde, .Backslash,
	     .LParen, .RParen, .LBrack, .RBrack, .LBrace, .RBrace, .Newline, .Eof:
	}
	return d
}

diag_expected_type :: proc(actual: base.Token, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "SYNTAX ERROR", span,
		fmt.tprintf("I was expecting a type here, but I found `{}` instead.", actual.text))
	return d
}

diag_effectful_naming :: proc(name: string, effects: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "EFFECTFUL FUNCTION NAMING", span,
		fmt.tprintf("This function performs effect {}, so its name needs to end with `!`.", effects))
	append(&d.hints, fmt.tprintf("Try: `{}!`", name))
	return d
}

diag_undefined_name :: proc(name: string, similar: []string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNDEFINED NAME", span,
		fmt.tprintf("I cannot find `{}`.", name))
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_unhandled_effect :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNHANDLED EFFECT", span,
		fmt.tprintf("This expression performs effect `{}`, but there is no `handle` block around it.", effect_name))
	append(&d.hints, "Try wrapping it with a `handle` block.")
	return d
}

diag_type_mismatch :: proc(type_a: string, type_b: string, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("`{}` does not match `{}`.", type_a, type_b))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", type_b)})
	}
	return d
}

diag_primitive_mismatch :: proc(name_a: string, name_b: string, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("`{}` does not match `{}`.", name_a, name_b))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", name_b)})
	}
	return d
}

diag_value_row_conflict :: proc(kind_a: string, kind_b: string, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TYPE MISMATCH", span,
		fmt.tprintf("I expected a {} type here, but I found a {} type instead.", kind_a, kind_b))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("this is a {} type", kind_b)})
	}
	return d
}

diag_infinite_type :: proc(type_expr: string, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "INFINITE TYPE", span,
		fmt.tprintf("This creates an infinite type. `{}` is defined in terms of itself, which would make the type infinitely large.", type_expr))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "also related to this"})
	}
	return d
}

diag_arity_mismatch :: proc(expected: int, actual: int, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "ARITY MISMATCH", span,
		fmt.tprintf("This function expects {} argument{}, but it was called with {}.",
			expected, plural_s(expected), actual))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "called here"})
	}
	return d
}

diag_tag_arity_mismatch :: proc(tag_name: string, expected: int, actual: int, span: base.Source_Span, span_b: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TAG ARITY MISMATCH", span,
		fmt.tprintf("Tag `{}` expects {} payload{}, but here it has {}.",
			tag_name, expected, plural_s(expected), actual))
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = fmt.tprintf("defined with {} payload{} here", expected, plural_s(expected))})
	}
	return d
}

diag_invalid_extension :: proc(path: string, extension: string) -> Diagnostic {
	d := diag_init(.Error, "INVALID FILE EXTENSION", base.Source_Span_ZERO,
		fmt.tprintf("I expected a `.camp` file, but you gave me `{}`.", path))
	return d
}

diag_file_not_found :: proc(path: string, os_error: string) -> Diagnostic {
	d := diag_init(.Error, "FILE NOT FOUND", base.Source_Span_ZERO,
		fmt.tprintf("I could not read `{}` ({}).", path, os_error))
	return d
}

diag_unknown_command :: proc(command: string) -> Diagnostic {
	d := diag_init(.Error, "UNKNOWN COMMAND", base.Source_Span_ZERO,
		fmt.tprintf("I don't know the command `{}`.", command))
	append(&d.hints, "Try `build`, `check`, `test`, or `fmt`.")
	return d
}

diag_module_not_found :: proc(module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "MODULE NOT FOUND", span,
		fmt.tprintf("module '{}' not found.", module_name))
	return d
}

diag_cyclic_dependency :: proc(cycle_path: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "CYCLIC DEPENDENCY", span,
		fmt.tprintf("cyclic dependency: {}", cycle_path))
	return d
}

diag_import_not_exported :: proc(name: string, module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NOT EXPORTED", span,
		fmt.tprintf("'{}' is not exported from module '{}'.", name, module_name))
	append(&d.hints, fmt.tprintf("Use qualified access {}.{} or make it pub.", module_name, name))
	return d
}

diag_import_conflicts_binding :: proc(name: string, module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "IMPORT CONFLICT", span,
		fmt.tprintf("'{}' imported from {} conflicts with existing binding — use qualified access {}.{}", name, module_name, module_name, name))
	return d
}

diag_import_ambiguous :: proc(name: string, mod_a: string, mod_b: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "AMBIGUOUS IMPORT", span,
		fmt.tprintf("'{}' is ambiguous — imported from both {} and {}; use qualified access.", name, mod_a, mod_b))
	return d
}

diag_file_write_failed :: proc(path: string, reason: string) -> Diagnostic {
	return diag_init(.Error, "FILE WRITE FAILED", base.Source_Span_ZERO,
		fmt.tprintf("Failed to write output file `{}`: {}", path, reason))
}

diag_entry_point_not_found :: proc() -> Diagnostic {
	d := diag_init(.Error, "ENTRY POINT NOT FOUND", base.Source_Span_ZERO,
		"entry point not found — expected src/Main.camp with pub main!")
	return d
}

diag_entry_point_no_main :: proc() -> Diagnostic {
	d := diag_init(.Error, "NO MAIN FUNCTION", base.Source_Span_ZERO,
		"entry point module Main does not define pub main!")
	return d
}

diag_project_no_source :: proc() -> Diagnostic {
	d := diag_init(.Error, "NO SOURCE FILES", base.Source_Span_ZERO,
		"no Camp source files found — expected a src/ directory")
	return d
}

diag_duplicate_module_name :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "DUPLICATE NAME", span,
		fmt.tprintf("name '{}' is already defined in this module.", name))
	return d
}

diag_internal :: proc(message: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Internal, "INTERNAL ERROR", span,
		fmt.tprintf("Something went wrong inside the compiler: {}", message))
	append(&d.hints, "This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues")
	return d
}

diag_unqualified_tag :: proc(newtype_name: string, tag_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "UNQUALIFIED TAG", span,
		fmt.tprintf("Tag `{}` belongs to newtype `{}` — use `{}.{}` to construct it.", tag_name, newtype_name, newtype_name, tag_name))
	return d
}

diag_tag_not_owned :: proc(newtype_name: string, tag_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TAG NOT OWNED", span,
		fmt.tprintf("Tag `{}` does not belong to newtype `{}`.", tag_name, newtype_name))
	return d
}

diag_newtype_coercion :: proc(newtype_name: string, inner_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NEWTYPE COERCION", span,
		fmt.tprintf("Cannot use `{}` where `{}` is expected — newtypes are distinct from their inner type. Use `.inner()` to unwrap.", newtype_name, inner_name))
	return d
}

diag_orphan_rule_violation :: proc(type_name: string, trait_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "ORPHAN RULE VIOLATION", span,
		fmt.tprintf("Cannot implement `{}` for `{}` here — implementations must be in the same module as the type or the trait.", trait_name, type_name))
	return d
}

diag_overlapping_instance :: proc(type_name: string, trait_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "OVERLAPPING INSTANCE", span,
		fmt.tprintf("`{}` already implements `{}` — cannot implement the same trait for the same type twice.", type_name, trait_name))
	return d
}

diag_constraint_violation :: proc(type_name: string, constraint_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "CONSTRAINT VIOLATION", span,
		fmt.tprintf("`{}` does not satisfy constraint `{}`.", type_name, constraint_name))
	return d
}

diag_missing_trait_method :: proc(type_name: string, trait_name: string, method_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "MISSING TRAIT METHOD", span,
		fmt.tprintf("`{}` does not implement method `{}` required by trait `{}`.", type_name, method_name, trait_name))
	return d
}

diag_trait_method_signature_mismatch :: proc(type_name: string, trait_name: string, method_name: string, expected_sig: string, actual_sig: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "TRAIT METHOD SIGNATURE MISMATCH", span,
		fmt.tprintf("`{}`'s `{}` method has wrong signature for trait `{}`.", type_name, method_name, trait_name))
	append(&d.labels, Span_Label{span = span, label = fmt.tprintf(EXPECTED_GOT_FMT, expected_sig, actual_sig)})
	return d
}

diag_newtype_opaque_violation :: proc(type_name: string, action: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "OPAQUE TYPE", span,
		fmt.tprintf("Nominal type `{}` is opaque outside its defining module — cannot {} here.", type_name, action))
	append(&d.hints, fmt.tprintf("Perform this operation in the module that defines `{}`, or use `pub` variants.", type_name))
	return d
}

diag_unjoined_spawn :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNJOINED SPAWN", span,
		"This spawned handle is not joined on all exit paths. Unjoined handles are cancelled when the handler exits, which may silently discard results.")
	append(&d.hints, "Use `join!` to await the result, or explicitly `cancel!` to discard it.")
	return d
}

diag_unterminated_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(.Error, "UNTERMINATED INTERPOLATION", tok.span,
		"This string interpolation expression is missing a closing `}`.")
	return d
}

diag_multiline_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(.Error, "MULTILINE INTERPOLATION", tok.span,
		"String interpolation expressions must be on a single line.")
	append(&d.hints, "Try extracting the expression into a variable defined before the string.")
	return d
}

diag_unexpected_tokens_after_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(.Error, "UNEXPECTED TOKENS IN INTERPOLATION", tok.span,
		"I found extra tokens after the expression in this string interpolation.")
	return d
}

diag_display_not_implemented :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "DISPLAY NOT IMPLEMENTED", span,
		fmt.tprintf("Type `{}` does not implement `Display`. Only types that implement `Display` can be used in string interpolation.", type_name))
	append(&d.hints, fmt.tprintf("Implement `Display` for `{}`, or convert the value to `Str` before interpolation.", type_name))
	return d
}

diag_redundant_pattern :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "REDUNDANT PATTERN", span,
		"This pattern is redundant — it is already covered by an earlier arm.")
	append(&d.hints, "Remove this arm or reorder patterns so this one comes first.")
	return d
}

diag_non_exhaustive_bool :: proc(missing: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NON-EXHAUSTIVE MATCH", span,
		fmt.tprintf("This match on Bool is non-exhaustive: missing branch for `{}`.", missing))
	return d
}

diag_non_exhaustive_int_string :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "NON-EXHAUSTIVE MATCH", span,
		fmt.tprintf("This match on {} can never be exhaustive without a wildcard pattern.", type_name))
	append(&d.hints, "Add a wildcard `_` or variable pattern to handle remaining values.")
	return d
}

diag_shadow :: proc(name_id: base.Intern_ID, name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "SHADOWING", span,
		fmt.tprintf("`{}` shadows a binding from an enclosing scope. All shadowing is forbidden.", name))
	append(&d.hints, "Use a different name for this binding.")
	d.shadowed_name = name_id
	return d
}

diag_unused_binding :: proc(name: string, hint: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNUSED BINDING", span,
		fmt.tprintf("Binding `{}` is never used. {}", name, hint))
	append(&d.hints, fmt.tprintf("Prefix with `_` to mark as intentionally unused: `_{}`", name))
	return d
}

diag_unused_record_field :: proc(field_name: string, record_span: base.Source_Span, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNUSED RECORD FIELD", span,
		fmt.tprintf("Record field `{}` is never accessed locally.", field_name))
	if record_span != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = record_span, label = "this record literal"})
	}
	return d
}

diag_unused_import :: proc(name: string, module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNUSED IMPORT", span,
		fmt.tprintf("`{}` imported from `{}` is never used.", name, module_name))
	return d
}

diag_pointless_evaluation :: proc(kind: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "POINTLESS EVALUATION", span,
		fmt.tprintf("Pure expression discarded with `_`. {}", kind))
	append(&d.hints, "Remove this binding, or use the result.")
	return d
}

diag_contradictory_prefix :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "CONTRADICTORY PREFIX", span,
		fmt.tprintf("`{}` combines `_` (ignore) and `$` (each value matters) — these are contradictory.", name))
	append(&d.hints, "Reassignable variables cannot be marked as unused. Remove the `_` prefix.")
	return d
}

diag_noop_assignment :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "NO-OP ASSIGNMENT", span,
		fmt.tprintf("`{}` is assigned to itself — this has no effect.", name))
	return d
}

diag_unused_assignment :: proc(name: string, assign_no: int, hint: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Warning, "UNUSED ASSIGNMENT", span,
		fmt.tprintf("Assignment #{} to `${}` is unused. {}", assign_no, name, hint))
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

diag_if_requires_braces :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "MISSING BRACES", span,
		"`if`/`else` branches require braces. Use `if condition { ... } else { ... }`.")
	append(&d.hints, "For chained conditions, use `else if`.")
	return d
}

diag_lambda_multi_param :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "LAMBDA MULTI PARAM", span,
		"Lambdas must take a single parameter. Use a record to pass multiple values.")
	return d
}

diag_ambiguous_type :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(.Error, "AMBIGUOUS TYPE", span,
		fmt.tprintf("Cannot determine type for generic parameter `{}`. Provide a type annotation.", name))
	return d
}
