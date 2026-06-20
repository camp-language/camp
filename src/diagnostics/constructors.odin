package diagnostics

import "camp:base"

import "core:fmt"

EXPECTED_GOT_FMT :: "expected {}, got {}"

diag_destroy :: proc(d: ^Diagnostic) {
	delete(d.labels)
	delete(d.hints)
}

diag_init :: proc(
	category: Diagnostic_Category,
	code: string,
	title: string,
	span: base.Source_Span,
	message: string,
) -> Diagnostic {
	d: Diagnostic
	d.category = category
	d.code = code
	d.title = title
	d.span = span
	d.message = message
	d.labels = make([dynamic]Span_Label, 0, 4)
	d.hints = make([dynamic]string, 0, 2)
	return d
}

diag_unexpected_char :: proc(char: u8, span: base.Source_Span) -> Diagnostic {
	display := char_display(char)
	d := diag_init(
		.Error,
		"C0001",
		"UNEXPECTED CHARACTER",
		span,
		fmt.tprintf("I don't recognize the character `{}`.", display),
	)
	return d
}

diag_unterminated_string :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0002",
		"UNTERMINATED STRING",
		span,
		"This string never ends. Try adding a closing `\"`.",
	)
	return d
}

diag_expected_token :: proc(
	expected: base.Token_Kind,
	actual: base.Token,
	span: base.Source_Span,
) -> Diagnostic {
	expected_str := token_kind_display(expected)
	d := diag_init(
		.Error,
		"C0100",
		"SYNTAX ERROR",
		span,
		fmt.tprintf("I expected `{}` here, but I got `{}` instead.", expected_str, actual.text),
	)
	return d
}

diag_unexpected_token :: proc(token: base.Token) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0101",
		"SYNTAX ERROR",
		token.span,
		fmt.tprintf("I was not expecting `{}` here.", token.text),
	)
	#partial switch token.kind {
	case .Pipe:
		append(&d.hints, "Are you trying to write a pattern match?")
	case .Int_Literal,
	     .Float_Literal,
	     .String_Literal,
	     .Interpolated_String_Literal,
	     .Identifier,
	     .Upper_Id,
	     .Kw_If,
	     .Kw_Else,
	     .Kw_Match,
	     .Kw_Is,
	     .Kw_Derives,
	     .Kw_Handle,
	     .Kw_In,
	     .Kw_With,
	     .Kw_Import,
	     .Kw_As,
	     .Kw_For,
	     .Kw_And,
	     .Kw_Or,
	     .Kw_Expect,
	     .Kw_Test,
	     .Kw_Not,
	     .Kw_Pub,
	     .Kw_Self,
	     .Kw_Par,
	     .Kw_Where,
	     .Arrow,
	     .Fat_Arrow,
	     .Eq,
	     .Colon_Eq,
	     .Colon,
	     .Comma,
	     .Dot,
	     .Dot_Dot,
	     .Dollar,
	     .Hash,
	     .At,
	     .Lt,
	     .Gt,
	     .Lt_Eq,
	     .Gt_Eq,
	     .Eq_Eq,
	     .Bang_Eq,
	     .Plus,
	     .Minus,
	     .Star,
	     .Slash,
	     .Percent,
	     .Amp,
	     .Caret,
	     .Tilde,
	     .Backslash,
	     .LParen,
	     .RParen,
	     .LBrack,
	     .RBrack,
	     .LBrace,
	     .RBrace,
	     .Newline,
	     .Eof:
	}
	return d
}

diag_expected_type :: proc(actual: base.Token, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0102",
		"SYNTAX ERROR",
		span,
		fmt.tprintf("I was expecting a type here, but I found `{}` instead.", actual.text),
	)
	return d
}

diag_effectful_naming :: proc(
	name: string,
	effects: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0400",
		"EFFECTFUL FUNCTION NAMING",
		span,
		fmt.tprintf(
			"This function performs effect {}, so its name needs to end with `!`.",
			effects,
		),
	)
	append(&d.hints, fmt.tprintf("Try: `{}!`", name))
	return d
}

diag_undefined_name :: proc(
	name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0200",
		"UNDEFINED NAME",
		span,
		fmt.tprintf("I cannot find `{}`.", name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_use_of_discard :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0210",
		"USE OF DISCARDED VALUE",
		span,
		fmt.tprintf(
			"`{}` begins with `_` and is treated as a discarded value — it cannot be read.",
			name,
		),
	)
	append(&d.hints, "Bind this value to a named binding instead, or use `_` directly to discard.")
	return d
}

diag_unhandled_effect :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0401",
		"UNHANDLED EFFECT",
		span,
		fmt.tprintf(
			"This expression performs effect `{}`, but there is no `handle` block around it.",
			effect_name,
		),
	)
	append(&d.hints, "Try wrapping it with a `handle` block.")
	return d
}

diag_unhandled_effect_entry :: proc(
	effect_name: string,
	effects_str: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0401",
		"UNHANDLED EFFECT",
		span,
		fmt.tprintf(
			"Entry point `main!` has unhandled effect `{}` in its effect row {}.",
			effect_name,
			effects_str,
		),
	)
	append(&d.hints, "Try wrapping the effectful code with a `handle` block, or add a handler.")
	return d
}

diag_type_mismatch :: proc(
	type_a: string,
	type_b: string,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0300",
		"TYPE MISMATCH",
		span,
		fmt.tprintf("`{}` does not match `{}`.", type_a, type_b),
	)
	if span_b != base.Source_Span_ZERO {
		append(
			&d.labels,
			Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", type_b)},
		)
	}
	return d
}

diag_primitive_mismatch :: proc(
	name_a: string,
	name_b: string,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0301",
		"TYPE MISMATCH",
		span,
		fmt.tprintf("`{}` does not match `{}`.", name_a, name_b),
	)
	if span_b != base.Source_Span_ZERO {
		append(
			&d.labels,
			Span_Label{span = span_b, label = fmt.tprintf("this has type `{}`", name_b)},
		)
	}
	return d
}

diag_value_row_conflict :: proc(
	kind_a: string,
	kind_b: string,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0302",
		"TYPE MISMATCH",
		span,
		fmt.tprintf("I expected a {} type here, but I found a {} type instead.", kind_a, kind_b),
	)
	if span_b != base.Source_Span_ZERO {
		append(
			&d.labels,
			Span_Label{span = span_b, label = fmt.tprintf("this is a {} type", kind_b)},
		)
	}
	return d
}

diag_infinite_type :: proc(
	type_expr: string,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0303",
		"INFINITE TYPE",
		span,
		fmt.tprintf(
			"This creates an infinite type. `{}` is defined in terms of itself, which would make the type infinitely large.",
			type_expr,
		),
	)
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "also related to this"})
	}
	return d
}

diag_arity_mismatch :: proc(
	expected: int,
	actual: int,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0304",
		"ARITY MISMATCH",
		span,
		fmt.tprintf(
			"This function expects {} argument{}, but it was called with {}.",
			expected,
			plural_s(expected),
			actual,
		),
	)
	if span_b != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = span_b, label = "called here"})
	}
	return d
}

diag_tag_arity_mismatch :: proc(
	tag_name: string,
	expected: int,
	actual: int,
	span: base.Source_Span,
	span_b: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0305",
		"TAG ARITY MISMATCH",
		span,
		fmt.tprintf(
			"Tag `{}` expects {} payload{}, but here it has {}.",
			tag_name,
			expected,
			plural_s(expected),
			actual,
		),
	)
	if span_b != base.Source_Span_ZERO {
		append(
			&d.labels,
			Span_Label {
				span = span_b,
				label = fmt.tprintf(
					"defined with {} payload{} here",
					expected,
					plural_s(expected),
				),
			},
		)
	}
	return d
}

diag_invalid_extension :: proc(path: string, extension: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1200",
		"INVALID FILE EXTENSION",
		base.Source_Span_ZERO,
		fmt.tprintf("I expected a `.camp` file, but you gave me `{}`.", path),
	)
	return d
}

diag_file_not_found :: proc(path: string, os_error: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1201",
		"FILE NOT FOUND",
		base.Source_Span_ZERO,
		fmt.tprintf("I could not read `{}` ({}).", path, os_error),
	)
	return d
}

diag_unknown_command :: proc(command: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1202",
		"UNKNOWN COMMAND",
		base.Source_Span_ZERO,
		fmt.tprintf("I don't know the command `{}`.", command),
	)
	append(&d.hints, "Try `build`, `check`, `test`, or `fmt`.")
	return d
}

diag_module_not_found :: proc(module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0800",
		"MODULE NOT FOUND",
		span,
		fmt.tprintf("module '{}' not found.", module_name),
	)
	return d
}

diag_cyclic_dependency :: proc(cycle_path: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0801",
		"CYCLIC DEPENDENCY",
		span,
		fmt.tprintf("cyclic dependency: {}", cycle_path),
	)
	return d
}

diag_import_not_exported :: proc(
	name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0802",
		"NOT EXPORTED",
		span,
		fmt.tprintf("'{}' is not exported from module '{}'.", name, module_name),
	)
	append(&d.hints, fmt.tprintf("Use qualified access {}.{} or make it pub.", module_name, name))
	return d
}

diag_import_conflicts_binding :: proc(
	name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0803",
		"IMPORT CONFLICT",
		span,
		fmt.tprintf(
			"'{}' imported from {} conflicts with existing binding — use qualified access {}.{}",
			name,
			module_name,
			module_name,
			name,
		),
	)
	return d
}

diag_import_ambiguous :: proc(
	name: string,
	mod_a: string,
	mod_b: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0804",
		"AMBIGUOUS IMPORT",
		span,
		fmt.tprintf(
			"'{}' is ambiguous — imported from both {} and {}; use qualified access.",
			name,
			mod_a,
			mod_b,
		),
	)
	return d
}

diag_file_write_failed :: proc(path: string, reason: string) -> Diagnostic {
	return diag_init(
		.Error,
		"C1203",
		"FILE WRITE FAILED",
		base.Source_Span_ZERO,
		fmt.tprintf("Failed to write output file `{}`: {}", path, reason),
	)
}

diag_entry_point_not_found :: proc() -> Diagnostic {
	d := diag_init(
		.Error,
		"C0805",
		"ENTRY POINT NOT FOUND",
		base.Source_Span_ZERO,
		"entry point not found — expected src/Main.camp with pub main!",
	)
	return d
}

diag_entry_point_no_main :: proc() -> Diagnostic {
	d := diag_init(
		.Error,
		"C0806",
		"NO MAIN FUNCTION",
		base.Source_Span_ZERO,
		"entry point module Main does not define pub main!",
	)
	return d
}

diag_project_no_source :: proc() -> Diagnostic {
	d := diag_init(
		.Error,
		"C0807",
		"NO SOURCE FILES",
		base.Source_Span_ZERO,
		"no Camp source files found — expected a src/ directory",
	)
	return d
}

diag_duplicate_module_name :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0202",
		"DUPLICATE NAME",
		span,
		fmt.tprintf("name '{}' is already defined in this module.", name),
	)
	return d
}

diag_internal :: proc(message: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Internal,
		"C9000",
		"INTERNAL ERROR",
		span,
		fmt.tprintf("Something went wrong inside the compiler: {}", message),
	)
	append(
		&d.hints,
		"This is a bug in Camp. Please report it at https://github.com/smores56/camp/issues",
	)
	return d
}

diag_unqualified_tag :: proc(
	newtype_name: string,
	tag_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0700",
		"UNQUALIFIED TAG",
		span,
		fmt.tprintf(
			"Tag `{}` belongs to newtype `{}` — use `{}.{}` to construct it.",
			tag_name,
			newtype_name,
			newtype_name,
			tag_name,
		),
	)
	return d
}

diag_tag_not_owned :: proc(
	newtype_name: string,
	tag_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0701",
		"TAG NOT OWNED",
		span,
		fmt.tprintf("Tag `{}` does not belong to newtype `{}`.", tag_name, newtype_name),
	)
	return d
}

diag_newtype_coercion :: proc(
	newtype_name: string,
	inner_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0702",
		"NEWTYPE COERCION",
		span,
		fmt.tprintf(
			"Cannot use `{}` where `{}` is expected — newtypes are distinct from their inner type. Use `.inner()` to unwrap.",
			newtype_name,
			inner_name,
		),
	)
	return d
}

diag_orphan_rule_violation :: proc(
	type_name: string,
	trait_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0600",
		"ORPHAN RULE VIOLATION",
		span,
		fmt.tprintf(
			"Cannot implement `{}` for `{}` here — implementations must be in the same module as the type or the trait.",
			trait_name,
			type_name,
		),
	)
	return d
}

diag_overlapping_instance :: proc(
	type_name: string,
	trait_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0601",
		"OVERLAPPING INSTANCE",
		span,
		fmt.tprintf(
			"`{}` already implements `{}` — cannot implement the same trait for the same type twice.",
			type_name,
			trait_name,
		),
	)
	return d
}

diag_constraint_violation :: proc(
	type_name: string,
	constraint_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0602",
		"CONSTRAINT VIOLATION",
		span,
		fmt.tprintf("`{}` does not satisfy constraint `{}`.", type_name, constraint_name),
	)
	return d
}

diag_missing_trait_method :: proc(
	type_name: string,
	trait_name: string,
	method_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0603",
		"MISSING TRAIT METHOD",
		span,
		fmt.tprintf(
			"`{}` does not implement method `{}` required by trait `{}`.",
			type_name,
			method_name,
			trait_name,
		),
	)
	return d
}

diag_trait_method_signature_mismatch :: proc(
	type_name: string,
	trait_name: string,
	method_name: string,
	expected_sig: string,
	actual_sig: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0604",
		"TRAIT METHOD SIGNATURE MISMATCH",
		span,
		fmt.tprintf(
			"`{}`'s `{}` method has wrong signature for trait `{}`.",
			type_name,
			method_name,
			trait_name,
		),
	)
	append(
		&d.labels,
		Span_Label{span = span, label = fmt.tprintf(EXPECTED_GOT_FMT, expected_sig, actual_sig)},
	)
	return d
}

diag_newtype_opaque_violation :: proc(
	type_name: string,
	action: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0703",
		"OPAQUE TYPE",
		span,
		fmt.tprintf(
			"Nominal type `{}` is opaque outside its defining module — cannot {} here.",
			type_name,
			action,
		),
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Perform this operation in the module that defines `{}`, or use `pub` variants.",
			type_name,
		),
	)
	return d
}

diag_unjoined_spawn :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0905",
		"UNJOINED SPAWN",
		span,
		"This spawned handle is not joined on all exit paths. Unjoined handles are cancelled when the handler exits, which may silently discard results.",
	)
	append(&d.hints, "Use `join!` to await the result, or explicitly `cancel!` to discard it.")
	return d
}

diag_unterminated_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0107",
		"UNTERMINATED INTERPOLATION",
		tok.span,
		"This string interpolation expression is missing a closing `}`.",
	)
	return d
}

diag_multiline_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0108",
		"MULTILINE INTERPOLATION",
		tok.span,
		"String interpolation expressions must be on a single line.",
	)
	append(&d.hints, "Try extracting the expression into a variable defined before the string.")
	return d
}

diag_unexpected_tokens_after_interpolation :: proc(tok: base.Token) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0109",
		"UNEXPECTED TOKENS IN INTERPOLATION",
		tok.span,
		"I found extra tokens after the expression in this string interpolation.",
	)
	return d
}

diag_display_not_implemented :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0319",
		"DISPLAY NOT IMPLEMENTED",
		span,
		fmt.tprintf(
			"Type `{}` does not implement `Display`. Only types that implement `Display` can be used in string interpolation.",
			type_name,
		),
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Implement `Display` for `{}`, or convert the value to `Str` before interpolation.",
			type_name,
		),
	)
	return d
}

diag_redundant_pattern :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0503",
		"REDUNDANT PATTERN",
		span,
		"This pattern is redundant — it is already covered by an earlier arm.",
	)
	append(&d.hints, "Remove this arm or reorder patterns so this one comes first.")
	return d
}

diag_non_exhaustive_bool :: proc(missing: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0500",
		"NON-EXHAUSTIVE MATCH",
		span,
		fmt.tprintf("This match on Bool is non-exhaustive: missing branch for `{}`.", missing),
	)
	return d
}

diag_non_exhaustive_int_string :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0501",
		"NON-EXHAUSTIVE MATCH",
		span,
		fmt.tprintf(
			"This match on {} can never be exhaustive without a wildcard pattern.",
			type_name,
		),
	)
	append(&d.hints, "Add a wildcard `_` or variable pattern to handle remaining values.")
	return d
}

diag_shadow :: proc(name_id: base.Intern_ID, name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0201",
		"SHADOWING",
		span,
		fmt.tprintf(
			"`{}` shadows a binding from an enclosing scope. All shadowing is forbidden.",
			name,
		),
	)
	append(&d.hints, "Use a different name for this binding.")
	d.shadowed_name = name_id
	return d
}

diag_unused_binding :: proc(name: string, hint: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0900",
		"UNUSED BINDING",
		span,
		fmt.tprintf("Binding `{}` is never used. {}", name, hint),
	)
	append(&d.hints, fmt.tprintf("Prefix with `_` to mark as intentionally unused: `_{}`", name))
	return d
}

diag_unused_record_field :: proc(
	field_name: string,
	record_span: base.Source_Span,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0901",
		"UNUSED RECORD FIELD",
		span,
		fmt.tprintf("Record field `{}` is never accessed locally.", field_name),
	)
	if record_span != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = record_span, label = "this record literal"})
	}
	return d
}

diag_unused_import :: proc(
	name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0902",
		"UNUSED IMPORT",
		span,
		fmt.tprintf("`{}` imported from `{}` is never used.", name, module_name),
	)
	return d
}

diag_pointless_evaluation :: proc(kind: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0903",
		"POINTLESS EVALUATION",
		span,
		fmt.tprintf("Pure expression discarded with `_`. {}", kind),
	)
	append(&d.hints, "Remove this binding, or use the result.")
	return d
}

diag_contradictory_prefix :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1000",
		"CONTRADICTORY PREFIX",
		span,
		fmt.tprintf(
			"`{}` combines `_` (ignore) and `$` (each value matters) — these are contradictory.",
			name,
		),
	)
	append(&d.hints, "Reassignable variables cannot be marked as unused. Remove the `_` prefix.")
	return d
}

diag_noop_assignment :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1001",
		"NO-OP ASSIGNMENT",
		span,
		fmt.tprintf("`{}` is assigned to itself — this has no effect.", name),
	)
	return d
}

diag_mutable_capture :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1002",
		"MUTABLE CAPTURE",
		span,
		fmt.tprintf(
			"Mutable variable `{}` cannot be captured by a closure — it is stack-local and cannot escape.",
			name,
		),
	)
	append(&d.hints, "Pass the value as a parameter instead, or use an immutable binding.")
	return d
}

diag_unused_assignment :: proc(
	name: string,
	assign_no: int,
	hint: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0904",
		"UNUSED ASSIGNMENT",
		span,
		fmt.tprintf("Assignment #{} to `${}` is unused. {}", assign_no, name, hint),
	)
	return d
}

char_display :: proc(ch: u8) -> string {
	switch ch {
	case '\n':
		return "\\n"
	case '\t':
		return "\\t"
	case '\r':
		return "\\r"
	case ' ':
		return "space"
	case:
		return fmt.tprintf("{}", rune(ch))
	}
}

plural_s :: proc(n: int) -> string {
	if n == 1 do return ""
	return "s"
}

diag_if_requires_braces :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0103",
		"MISSING BRACES",
		span,
		"`if`/`else` branches require braces. Use `if condition { ... } else { ... }`.",
	)
	append(&d.hints, "For chained conditions, use `else if`.")
	return d
}

diag_ambiguous_type :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0306",
		"AMBIGUOUS TYPE",
		span,
		fmt.tprintf(
			"Cannot determine type for generic parameter `{}`. Provide a type annotation.",
			name,
		),
	)
	return d
}

diag_empty_tag_parens :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0105",
		"EMPTY TAG PARENS",
		span,
		fmt.tprintf("Tag `{}` has no payload — write `{}` without parentheses.", name, name),
	)
	return d
}

diag_empty_effect_row :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0106",
		"EMPTY EFFECT ROW",
		span,
		"An effect row cannot be empty. Use `->` for a pure function instead of `-[ ]->`.",
	)
	return d
}

// --- Lexer ---

diag_invalid_escape :: proc(escape: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0003",
		"INVALID ESCAPE SEQUENCE",
		span,
		fmt.tprintf("\\{} is not a valid escape sequence.", escape),
	)
	append(&d.hints, "Valid escape sequences are: \\n, \\t, \\r, \\\\, \\\", \\0.")
	return d
}

diag_unterminated_per_line_string :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0004",
		"UNTERMINATED PER-LINE STRING",
		span,
		"This per-line string (starting with `\\`) is never closed. The closing `\\` must appear alone on its own line.",
	)
	return d
}

diag_invalid_numeric_literal :: proc(
	text: string,
	hint: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0005",
		"INVALID NUMERIC LITERAL",
		span,
		fmt.tprintf("Invalid numeric literal `{}`.", text),
	)
	if len(hint) > 0 {
		append(&d.hints, hint)
	}
	return d
}

diag_unterminated_block_comment :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0006",
		"UNTERMINATED BLOCK COMMENT",
		span,
		"This block comment was never closed. Add a closing `*/`.",
	)
	return d
}

diag_double_bang_suffix :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0007",
		"DOUBLE BANG SUFFIX",
		span,
		"Only one `!` suffix is allowed on identifiers. Use `not` for logical negation.",
	)
	return d
}

diag_paren_call_syntax :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0008",
		"PAREN CALL SYNTAX",
		span,
		"Paren call syntax `name(args)` is not allowed. Use UFCS: `obj->method(arg)` or effect-qualified: `Effect.op!(arg)`.",
	)
	return d
}

diag_par_entry_must_be_named :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0009",
		"PAR ENTRY MUST BE NAMED",
		span,
		"par block entries must be named: `par { name: expr, ... }`",
	)
	return d
}

// --- Parser ---

diag_duplicate_field_literal :: proc(field_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0110",
		"DUPLICATE FIELD IN RECORD LITERAL",
		span,
		fmt.tprintf("Field `{}` appears more than once in this record literal.", field_name),
	)
	return d
}

diag_duplicate_field_pattern :: proc(field_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0111",
		"DUPLICATE FIELD IN RECORD PATTERN",
		span,
		fmt.tprintf("Field `{}` appears more than once in this record pattern.", field_name),
	)
	return d
}

diag_duplicate_variant :: proc(variant_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0112",
		"DUPLICATE VARIANT IN TAG UNION",
		span,
		fmt.tprintf("Variant `{}` appears more than once in this tag union type.", variant_name),
	)
	return d
}

diag_duplicate_effect_row :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0113",
		"DUPLICATE EFFECT IN ROW",
		span,
		fmt.tprintf("Effect `{}` appears more than once in this effect row.", effect_name),
	)
	append(&d.hints, "Each effect should appear at most once in an effect row.")
	return d
}

diag_invalid_match_arm :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0114",
		"INVALID MATCH ARM",
		span,
		"This match arm is missing a `=>` and a body.",
	)
	return d
}

diag_missing_arrow_fn_type :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0115",
		"MISSING ARROW IN FUNCTION TYPE",
		span,
		"This function type is missing an arrow. Use `->` for pure functions or `-[effects]->` for effectful ones.",
	)
	return d
}

diag_invalid_visibility :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0116",
		"INVALID VISIBILITY MODIFIER",
		span,
		"`pub` can only be applied to top-level declarations.",
	)
	return d
}

diag_invalid_effect_row_syntax :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0117",
		"INVALID EFFECT ROW SYNTAX",
		span,
		"Effect rows use `|` as a separator, not `,`. Write `-[A! | B!]->` instead of `-[A!, B!]->`.",
	)
	return d
}

// --- Name Resolution ---

diag_undefined_type :: proc(
	type_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0203",
		"UNDEFINED TYPE",
		span,
		fmt.tprintf("Type `{}` is not defined.", type_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_undefined_effect :: proc(
	effect_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0204",
		"UNDEFINED EFFECT",
		span,
		fmt.tprintf("Effect `{}` is not defined.", effect_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_private_access :: proc(
	name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0205",
		"PRIVATE MEMBER ACCESS",
		span,
		fmt.tprintf(
			"`{}` is private to module `{}` and cannot be accessed here.",
			name,
			module_name,
		),
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Use a public member, or access `{}` from within module `{}`.",
			name,
			module_name,
		),
	)
	return d
}

diag_ambiguous_reference :: proc(
	name: string,
	scope_a: string,
	scope_b: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0206",
		"AMBIGUOUS REFERENCE",
		span,
		fmt.tprintf(
			"`{}` is ambiguous — it could refer to the binding from `{}` or the binding from `{}`.",
			name,
			scope_a,
			scope_b,
		),
	)
	append(&d.hints, "Use qualified access to disambiguate.")
	return d
}

diag_not_a_function :: proc(
	name: string,
	type_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0207",
		"NOT A FUNCTION",
		span,
		fmt.tprintf(
			"`{}` has type `{}`, which is not a function. It cannot be called.",
			name,
			type_name,
		),
	)
	return d
}

diag_not_a_type :: proc(name: string, kind: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0208",
		"NOT A TYPE",
		span,
		fmt.tprintf(
			"`{}` has kind `{}`, which is not a type. It cannot be used in a type position.",
			name,
			kind,
		),
	)
	return d
}

diag_raw_id_not_needed :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0209",
		"RAW IDENTIFIER NOT NEEDED",
		span,
		fmt.tprintf(
			"`r#{}` is not a keyword — you can write `{}` without the `r#` prefix.",
			name,
			name,
		),
	)
	return d
}

// --- Type System ---

diag_cannot_infer_return :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0307",
		"CANNOT INFER RETURN TYPE",
		span,
		"Cannot infer the return type of this function. Add a type annotation to the function or its body.",
	)
	return d
}

diag_type_annotation_mismatch :: proc(
	annotated: string,
	inferred: string,
	annotation_span: base.Source_Span,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0308",
		"TYPE ANNOTATION MISMATCH",
		span,
		fmt.tprintf(
			"This expression was annotated with type `{}`, but it has type `{}`.",
			annotated,
			inferred,
		),
	)
	if annotation_span != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = annotation_span, label = "type annotation here"})
	}
	return d
}

diag_missing_field :: proc(
	type_name: string,
	field_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0309",
		"MISSING FIELDS IN RECORD",
		span,
		fmt.tprintf(
			"Record type `{}` requires field `{}`, but it is missing from this literal.",
			type_name,
			field_name,
		),
	)
	append(&d.hints, fmt.tprintf("Add `{}`: <value> to the record literal.", field_name))
	return d
}

diag_unknown_field :: proc(
	field_name: string,
	type_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0310",
		"UNKNOWN FIELD IN RECORD",
		span,
		fmt.tprintf("Field `{}` does not exist on record type `{}`.", field_name, type_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_field_type_mismatch :: proc(
	field_name: string,
	expected: string,
	actual: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0311",
		"FIELD TYPE MISMATCH",
		span,
		fmt.tprintf(
			"Field `{}` has type `{}`, but the provided value has type `{}`.",
			field_name,
			expected,
			actual,
		),
	)
	return d
}

diag_cannot_unify_effect_rows :: proc(
	actual_row: string,
	expected_row: string,
	effect_name: string,
	effect_span: base.Source_Span,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0312",
		"CANNOT UNIFY EFFECT ROWS",
		span,
		fmt.tprintf(
			"Effect row `{}` does not match expected row `{}`. The extra effect `{}` is not handled.",
			actual_row,
			expected_row,
			effect_name,
		),
	)
	if effect_span != base.Source_Span_ZERO {
		append(
			&d.labels,
			Span_Label {
				span = effect_span,
				label = fmt.tprintf("this expression introduces effect `{}`", effect_name),
			},
		)
	}
	append(
		&d.hints,
		fmt.tprintf(
			"Add `{}` to the function's effect row, or handle it with a `handle` block.",
			effect_name,
		),
	)
	return d
}

diag_row_label_mismatch :: proc(
	actual_row: string,
	expected_row: string,
	missing_label: string,
	extra_label: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0313",
		"ROW LABEL MISMATCH",
		span,
		fmt.tprintf(
			"Record row `{}` does not match expected row `{}`. Missing label `{}`, extra label `{}`.",
			actual_row,
			expected_row,
			missing_label,
			extra_label,
		),
	)
	return d
}

diag_type_param_kind_mismatch :: proc(
	param_name: string,
	expected_kind: string,
	actual_name: string,
	actual_kind: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0314",
		"TYPE PARAMETER KIND MISMATCH",
		span,
		fmt.tprintf(
			"Type parameter `{}` expects a {} type, but `{}` is a {} type.",
			param_name,
			expected_kind,
			actual_name,
			actual_kind,
		),
	)
	return d
}

diag_recursive_type_alias :: proc(alias_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0315",
		"RECURSIVE TYPE ALIAS",
		span,
		fmt.tprintf(
			"Type alias `{}` is directly recursive, which would expand infinitely. Use a tag union or newtype to introduce indirection.",
			alias_name,
		),
	)
	return d
}

diag_invalid_main_signature :: proc(actual_type: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0316",
		"INVALID MAIN SIGNATURE",
		span,
		fmt.tprintf(
			"`main!` has type `{}`, but it must have type `() -[effects]-> I64`.",
			actual_type,
		),
	)
	append(&d.hints, "`main!` must return `I64`. Use `0` for a successful exit.")
	return d
}

diag_duplicate_type_param :: proc(param_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0317",
		"DUPLICATE TYPE PARAMETER",
		span,
		fmt.tprintf(
			"Type parameter `{}` appears more than once in this type's parameter list.",
			param_name,
		),
	)
	return d
}

diag_empty_tag_union :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0318",
		"EMPTY TAG UNION",
		span,
		fmt.tprintf(
			"Tag union `{}` has no variants. A tag union must have at least one variant.",
			type_name,
		),
	)
	return d
}

// --- Effect System ---

diag_effect_row_mismatch :: proc(
	actual_row: string,
	expected_row: string,
	ctx: string,
	missing_effect: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0402",
		"EFFECT ROW MISMATCH",
		span,
		fmt.tprintf(
			"This function's effect row `-[{}]->` does not match the expected `-[{}]->`.",
			actual_row,
			expected_row,
		),
	)
	append(
		&d.labels,
		Span_Label{span = span, label = fmt.tprintf("expected effect row from {}", ctx)},
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Add `{}` to the function's effect row, or handle it before this point.",
			missing_effect,
		),
	)
	return d
}

diag_unnecessary_effect_in_signature :: proc(
	effect_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0403",
		"UNNECESSARY EFFECT IN SIGNATURE",
		span,
		fmt.tprintf(
			"Effect `{}` is listed in this function's effect row, but the function never performs it.",
			effect_name,
		),
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Remove `{}` from the effect row, or the function may need to perform this effect.",
			effect_name,
		),
	)
	return d
}

diag_effect_not_in_scope :: proc(
	effect_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0404",
		"EFFECT NOT IN SCOPE",
		span,
		fmt.tprintf("Effect `{}` is not defined. Did you mean to import it?", effect_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_handler_signature_mismatch :: proc(
	effect_name: string,
	expected: int,
	actual: int,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0405",
		"HANDLER SIGNATURE MISMATCH",
		span,
		fmt.tprintf(
			"Handler arm for `{}` expects {} parameter{}, but the effect operation provides {}.",
			effect_name,
			expected,
			plural_s(expected),
			actual,
		),
	)
	return d
}

diag_missing_resume :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0406",
		"MISSING RESUME IN HANDLER",
		span,
		fmt.tprintf(
			"Handler arm for `{}` does not call `resume`. The computation is stuck.",
			effect_name,
		),
	)
	append(
		&d.hints,
		"Call `resume(value)` to continue the computation, or `resume` with a different value to alter the result.",
	)
	return d
}

diag_double_resume :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0407",
		"DOUBLE RESUME IN HANDLER",
		span,
		fmt.tprintf(
			"`resume` was called more than once in this handler arm for `{}`. Each handler arm may call `resume` at most once.",
			effect_name,
		),
	)
	return d
}

diag_invalid_resume :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0408",
		"INVALID RESUME OUTSIDE HANDLER",
		span,
		"`resume` can only be used inside a `handle` block.",
	)
	return d
}

diag_redundant_handler :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0409",
		"REDUNDANT HANDLER",
		span,
		fmt.tprintf(
			"This `handle` block handles `{}`, but that effect is never performed in the handled computation.",
			effect_name,
		),
	)
	append(
		&d.hints,
		fmt.tprintf(
			"Remove the handler arm for `{}`, or the computation may need to perform this effect.",
			effect_name,
		),
	)
	return d
}

diag_effect_row_subtype :: proc(
	actual_row: string,
	declared_row: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0410",
		"EFFECT ROW SUBTYPE WARNING",
		span,
		fmt.tprintf(
			"This function's effect row `-[{}]->` is a subtype of the declared `-[{}]->`. The extra declared effects are unnecessary.",
			actual_row,
			declared_row,
		),
	)
	append(&d.hints, fmt.tprintf("Consider tightening the effect row to `-[{}]->`.", actual_row))
	return d
}

// --- Pattern Matching ---

diag_non_exhaustive_tag :: proc(
	type_name: string,
	missing_variant: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0502",
		"NON-EXHAUSTIVE MATCH",
		span,
		fmt.tprintf(
			"This match on `{}` is non-exhaustive: missing branch for `{}`.",
			type_name,
			missing_variant,
		),
	)
	append(
		&d.hints,
		fmt.tprintf("Add a branch for `{}`, or add a wildcard pattern.", missing_variant),
	)
	return d
}

diag_fragile_match :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0504",
		"FRAGILE MATCH",
		span,
		fmt.tprintf(
			"This match on `{}` is exhaustive now, but adding a new variant to `{}` would make it non-exhaustive.",
			type_name,
			type_name,
		),
	)
	append(&d.hints, "Add a wildcard pattern to make this match robust against future changes.")
	return d
}

diag_invalid_irrefutable_pattern :: proc(pattern: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0505",
		"INVALID IRREFUTABLE PATTERN",
		span,
		fmt.tprintf(
			"Pattern `{}` is refutable and cannot be used in a `let` binding. Only irrefutable patterns (wildcards, variables, records with all fields) are allowed here.",
			pattern,
		),
	)
	append(&d.hints, "Use a `match` expression instead.")
	return d
}

diag_missing_field_pattern :: proc(field_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0506",
		"MISSING FIELDS IN RECORD PATTERN",
		span,
		fmt.tprintf(
			"Record pattern is missing field `{}`. Use `_` to ignore a field, or `{..}` to ignore remaining fields.",
			field_name,
		),
	)
	return d
}

diag_unknown_field_pattern :: proc(
	field_name: string,
	type_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0507",
		"UNKNOWN FIELD IN RECORD PATTERN",
		span,
		fmt.tprintf("Field `{}` does not exist on record type `{}`.", field_name, type_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_duplicate_binding_pattern :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0508",
		"DUPLICATE BINDING IN PATTERN",
		span,
		fmt.tprintf(
			"Variable `{}` appears more than once in this pattern. In Camp, each variable in a pattern must be unique.",
			name,
		),
	)
	return d
}

diag_wildcard_after_catch_all :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0509",
		"WILDCARD AFTER CATCH-ALL",
		span,
		"This wildcard pattern is unreachable — a previous wildcard or variable pattern already matches everything.",
	)
	return d
}

// --- Traits/Generics ---

diag_missing_trait_constraint :: proc(
	param_name: string,
	constraint: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0605",
		"MISSING TRAIT CONSTRAINT",
		span,
		fmt.tprintf(
			"Type parameter `{}` requires constraint `{}`, but it is not in scope here.",
			param_name,
			constraint,
		),
	)
	append(&d.hints, fmt.tprintf("Add `{}` to the type parameter's constraint list.", constraint))
	return d
}

diag_conflicting_implementations :: proc(
	trait_name: string,
	type_name: string,
	other_trait: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0606",
		"CONFLICTING IMPLEMENTATIONS",
		span,
		fmt.tprintf(
			"Implementing `{}` for `{}` would conflict with the existing implementation via `{}`.",
			trait_name,
			type_name,
			other_trait,
		),
	)
	return d
}

diag_trait_not_found :: proc(
	trait_name: string,
	similar: []string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0607",
		"TRAIT NOT FOUND",
		span,
		fmt.tprintf("Trait `{}` is not defined.", trait_name),
	)
	if len(similar) > 0 {
		append(&d.hints, fmt.tprintf("Did you mean `{}`?", similar[0]))
	}
	return d
}

diag_supertrait_not_satisfied :: proc(
	trait_name: string,
	supertrait: string,
	type_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0608",
		"SUPERTRAIT NOT SATISFIED",
		span,
		fmt.tprintf(
			"Trait `{}` requires supertrait `{}`, but `{}` does not implement it.",
			trait_name,
			supertrait,
			type_name,
		),
	)
	append(&d.hints, fmt.tprintf("Implement `{}` for `{}` first.", supertrait, type_name))
	return d
}

diag_cyclic_trait_dependency :: proc(
	trait_name: string,
	cycle: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0609",
		"CYCLIC TRAIT DEPENDENCY",
		span,
		fmt.tprintf("Trait `{}` has a cyclic dependency: {}.", trait_name, cycle),
	)
	return d
}

diag_ambiguous_trait_resolution :: proc(
	trait_name: string,
	type_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0610",
		"AMBIGUOUS TRAIT RESOLUTION",
		span,
		fmt.tprintf(
			"Multiple implementations of `{}` for `{}` are available. Use a qualified call to disambiguate.",
			trait_name,
			type_name,
		),
	)
	return d
}

// --- Newtype ---

diag_newtype_field_access :: proc(
	field_name: string,
	type_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0704",
		"NEWTYPE FIELD ACCESS",
		span,
		fmt.tprintf(
			"Cannot access field `{}` on newtype `{}` — newtypes are opaque. Use a method or accessor defined in the defining module.",
			field_name,
			type_name,
		),
	)
	return d
}

// --- Module/Import ---

diag_duplicate_import :: proc(
	name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0808",
		"DUPLICATE IMPORT",
		span,
		fmt.tprintf("`{}` is imported more than once from module `{}`.", name, module_name),
	)
	return d
}

diag_import_shadows_binding :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0809",
		"IMPORT SHADOWS BINDING",
		span,
		fmt.tprintf(
			"Imported name `{}` shadows a local binding. Use qualified access to disambiguate.",
			name,
		),
	)
	return d
}

diag_self_import :: proc(module_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0810",
		"SELF IMPORT",
		span,
		fmt.tprintf("Module `{}` cannot import itself.", module_name),
	)
	return d
}

diag_suggest_import :: proc(
	type_name: string,
	module_name: string,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0811",
		"MISSING IMPORT FOR TYPE",
		span,
		fmt.tprintf(
			"Type `{}` is defined in module `{}`. Consider adding `import {} {{ {} }}`.",
			type_name,
			module_name,
			module_name,
			type_name,
		),
	)
	return d
}

// --- Unused Analysis ---

diag_unused_function :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0906",
		"UNUSED FUNCTION",
		span,
		fmt.tprintf("Private function `{}` is never called.", name),
	)
	append(&d.hints, "If this is intentional, consider making it `pub` or prefixing with `_`.")
	return d
}

diag_unused_type_definition :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0907",
		"UNUSED TYPE DEFINITION",
		span,
		fmt.tprintf("Type `{}` is defined but never referenced.", type_name),
	)
	return d
}

diag_unused_type_parameter :: proc(param_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0908",
		"UNUSED TYPE PARAMETER",
		span,
		fmt.tprintf(
			"Type parameter `{}` is declared but never used in the type definition.",
			param_name,
		),
	)
	return d
}

diag_unused_effect_handler :: proc(effect_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0909",
		"UNUSED EFFECT HANDLER",
		span,
		fmt.tprintf(
			"Handler arm for `{}` never intercepts any operations. The effect is not performed in the handled computation.",
			effect_name,
		),
	)
	return d
}

diag_unreachable_code :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0910",
		"UNREACHABLE CODE",
		span,
		"This code is unreachable — it follows a `return`, `match` with all branches returning, or similar construct.",
	)
	return d
}

diag_must_use_discarded :: proc(function_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0911",
		"MUST_USE DISCARDED",
		span,
		fmt.tprintf(
			"Result of `{}` is discarded. This type is marked as `@must_use` — its result should not be ignored.",
			function_name,
		),
	)
	append(&d.hints, "Use the result, or explicitly discard with `_ =` if intentional.")
	return d
}

diag_redundant_else :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0912",
		"REDUNDANT ELSE",
		span,
		"This `else` branch is redundant — the `if` condition is always true (or the preceding `match` is exhaustive).",
	)
	return d
}

diag_unnecessary_mutability :: proc(name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C0913",
		"UNNECESSARY MUTABILITY",
		span,
		fmt.tprintf(
			"Variable `{}` is declared with `$` but is never reassigned. Use an immutable binding instead.",
			name,
		),
	)
	append(&d.hints, fmt.tprintf("Replace `${}` with `{}`.", name, name))
	return d
}

// --- Perceus/RC ---

diag_reference_leak :: proc(type_name: string, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C1100",
		"REFERENCE LEAK",
		span,
		fmt.tprintf(
			"Value of type `{}` is created but never consumed. This may indicate a reference counting leak.",
			type_name,
		),
	)
	append(&d.hints, "Ensure the value is used, returned, or explicitly dropped.")
	return d
}

diag_unnecessary_copy :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Warning,
		"C1101",
		"UNNECESSARY COPY",
		span,
		"This value is copied when it could be moved. Use `move` or restructure to avoid the copy.",
	)
	return d
}

diag_consume_after_use :: proc(
	name: string,
	consume_span: base.Source_Span,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1102",
		"CONSUME AFTER USE",
		span,
		fmt.tprintf(
			"Value `{}` is consumed (used after it has been moved/consumed). Each value can only be used once under Perceus semantics.",
			name,
		),
	)
	if consume_span != base.Source_Span_ZERO {
		append(&d.labels, Span_Label{span = consume_span, label = "value consumed here"})
	}
	return d
}

// --- CLI/Build ---

diag_output_dir_not_found :: proc(path: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1204",
		"OUTPUT DIRECTORY NOT FOUND",
		base.Source_Span_ZERO,
		fmt.tprintf("Output directory `{}` does not exist and could not be created.", path),
	)
	return d
}

diag_invalid_option :: proc(option: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1205",
		"INVALID OPTION",
		base.Source_Span_ZERO,
		fmt.tprintf("Unknown option `{}`.", option),
	)
	append(&d.hints, "Run `camp --help` for available options.")
	return d
}

diag_conflicting_options :: proc(option_a: string, option_b: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1206",
		"CONFLICTING OPTIONS",
		base.Source_Span_ZERO,
		fmt.tprintf(
			"Options `{}` and `{}` conflict — they cannot be used together.",
			option_a,
			option_b,
		),
	)
	return d
}

diag_compilation_limit :: proc(limit: string) -> Diagnostic {
	d := diag_init(
		.Error,
		"C1207",
		"COMPILATION LIMIT EXCEEDED",
		base.Source_Span_ZERO,
		fmt.tprintf(
			"Compilation limit exceeded: {}. This may indicate an infinite loop in the compiler.",
			limit,
		),
	)
	append(
		&d.hints,
		"This is likely a compiler bug. Please report it at https://github.com/smores56/camp/issues",
	)
	return d
}

diag_tuple_size :: proc(count: int, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0118",
		"TUPLE SIZE",
		span,
		fmt.tprintf("Tuple must have 2 or 3 elements, got {}", count),
	)
	return d
}

diag_tuple_empty :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0119",
		"EMPTY TUPLE",
		span,
		"Empty tuple `()` is not valid; use `{}` for unit",
	)
	return d
}

diag_tuple_type_size :: proc(count: int, span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0120",
		"TUPLE TYPE SIZE",
		span,
		fmt.tprintf("Tuple type must have 2 or 3 elements, got {}", count),
	)
	return d
}

diag_tuple_single_element :: proc(span: base.Source_Span) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0121",
		"SINGLE-ELEMENT TUPLE",
		span,
		"Single-element tuple is not valid; use the type directly or add a return type for a function: `(T) -> R`",
	)
	return d
}

diag_tuple_pattern_count :: proc(
	expected: int,
	actual: int,
	span: base.Source_Span,
) -> Diagnostic {
	d := diag_init(
		.Error,
		"C0320",
		"TUPLE PATTERN COUNT MISMATCH",
		span,
		fmt.tprintf("Tuple pattern has {} elements but expected {}", actual, expected),
	)
	return d
}

