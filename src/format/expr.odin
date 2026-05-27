package format

import "camp:base"
import "camp:frontend"
import "core:strconv"

f64_format :: 'g'
float_bit_size :: 64

operator_string :: proc(kind: base.Token_Kind) -> string {
	#partial switch kind {
	case .Plus:
		return "+"
	case .Minus:
		return "-"
	case .Star:
		return "*"
	case .Slash:
		return "/"
	case .Percent:
		return "%"
	case .Amp:
		return "&"
	case .Caret:
		return "^"
	case .Tilde:
		return "~"
	case .Eq_Eq:
		return "=="
	case .Bang_Eq:
		return "!="
	case .Lt:
		return "<"
	case .Gt:
		return ">"
	case .Lt_Eq:
		return "<="
	case .Gt_Eq:
		return ">="
	case .Pipe:
		return "|"
	case .Dot_Dot:
		return ".."
	case .Arrow:
		return "->"
	case .Fat_Arrow:
		return "=>"
	case .Kw_And:
		return "and"
	case .Kw_Or:
		return "or"
	}
	return "?"
}

int_to_string :: proc(value: i64, buf: []u8) -> string {
	return strconv.write_int(buf, value, 10)
}

float_to_string :: proc(value: f64, buf: []u8) -> string {
	return strconv.write_float(buf, value, f64_format, -1, float_bit_size)
}

format_expr :: proc(
	e: frontend.Expr,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	#partial switch v in e {
	case ^frontend.Expr_Int:
		buf: [64]u8
		return doc_text(int_to_string(v.value, buf[:]))
	case ^frontend.Expr_Float:
		buf: [128]u8
		return doc_text(float_to_string(v.value, buf[:]))
	case ^frontend.Expr_String:
		return doc_text(v.value)
	case ^frontend.Expr_Char:
		return format_expr_char(v)
	case ^frontend.Expr_Bool:
		if v.value do return doc_text("True")
		return doc_text("False")
	case ^frontend.Expr_Tag:
		return format_expr_tag(v, info, interner)
	case ^frontend.Expr_Nominal_Construct:
		return format_expr_nominal_construct(v, info, interner)
	case ^frontend.Expr_Record:
		return format_expr_record(v, info, interner)
	case ^frontend.Expr_Tuple:
		return format_expr_tuple(v, info, interner)

	case ^frontend.Expr_List:
		return format_expr_list(v, info, interner)
	case ^frontend.Expr_Identifier:
		return doc_text(base.intern_get(interner, v.name))
	case ^frontend.Expr_Dollar_Identifier:
		return doc_concat([]Doc{doc_text("$"), doc_text(base.intern_get(interner, v.name))})
	case ^frontend.Expr_Call:
		return format_expr_call(v, info, interner)
	case ^frontend.Expr_Method_Call:
		return format_expr_method_call(v, info, interner)
	case ^frontend.Expr_Lambda:
		return format_expr_lambda(v, info, interner)
	case ^frontend.Expr_Block:
		return format_expr_block(v, info, interner)
	case ^frontend.Expr_If:
		return format_expr_if(v, info, interner)
	case ^frontend.Expr_Match:
		return format_expr_match(v, info, interner)
	case ^frontend.Expr_BinOp:
		return format_expr_binop(v, info, interner)
	case ^frontend.Expr_PrefixOp:
		return format_expr_prefixop(v, info, interner)
	case ^frontend.Expr_Field_Access:
		return format_expr_field_access(v, info, interner)
	case ^frontend.Expr_Record_Update:
		return format_expr_record_update(v, info, interner)
	case ^frontend.Expr_Assign:
		return format_expr_assign(v, info, interner)
	case ^frontend.Expr_Return:
		return format_expr_return(v, info, interner)
	case ^frontend.Expr_Crash:
		return format_expr_crash(v, info, interner)
	case ^frontend.Expr_Todo:
		return format_expr_todo(v, info, interner)
	case ^frontend.Expr_Interpolated_String:
		return format_expr_interpolated_string(v, info, interner)
	case ^frontend.Expr_Handle:
		return format_expr_handle(v, info, interner)
	case ^frontend.Expr_Par:
		return format_expr_par(v, info, interner)
	}
	return doc_text("?")
}

format_expr_tag :: proc(
	e: ^frontend.Expr_Tag,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	name := base.intern_get(interner, e.name)

	if len(e.payload) == 0 {
		return doc_text(name)
	}

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(name))
	append(&parts, doc_text("("))

	multiline := info.first_separator_break[e.span.start]

	if multiline {
		format_exprs_comma_multiline(&parts, e.payload[:], info, interner)
	} else {
		format_exprs_comma_flat(&parts, e.payload[:], info, interner)
	}

	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_expr_nominal_construct :: proc(
	e: ^frontend.Expr_Nominal_Construct,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("@"))
	append(&parts, doc_text(base.intern_get(interner, e.type_name)))
	if e.variant != 0 {
		append(&parts, doc_text("."))
		append(&parts, doc_text(base.intern_get(interner, e.variant)))
	}
	if len(e.payload) > 0 {
		append(&parts, doc_text("("))
		for arg, i in e.payload {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, format_expr(arg, info, interner))
		}
		append(&parts, doc_text(")"))
	}
	return doc_concat(parts[:])
}

format_expr_record :: proc(
	e: ^frontend.Expr_Record,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{"))

	all_name_puns := true
	for field in e.fields {
		if !is_name_pun(field, interner) {
			all_name_puns = false
			break
		}
	}

	multiline := info.first_separator_break[e.span.start]

	if multiline {
		append(&parts, doc_line())
		append(
			&parts,
			doc_nest(
				4,
				format_record_fields_multiline(e.fields[:], all_name_puns, info, interner),
			),
		)
	} else if all_name_puns && len(e.fields) > 0 {
		append(&parts, doc_text(" "))
		for field, i in e.fields {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, field.name)))
			if len(e.fields) == 1 {
				append(&parts, doc_text(":"))
			}
		}
	} else {
		for field, i in e.fields {
			if i == 0 {
				append(&parts, doc_text(" "))
			} else {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, field.name)))
			append(&parts, doc_text(": "))
			append(&parts, format_expr(field.value, info, interner))
		}
	}

	append(&parts, doc_text(" }"))
	return doc_concat(parts[:])
}

format_record_fields_multiline :: proc(
	fields: []frontend.Record_Field,
	all_name_puns: bool,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	inner: [dynamic]Doc
	defer delete(inner)

	for field, i in fields {
		if i > 0 {
			append(&inner, doc_text(","))
			append(&inner, doc_line())
		}
		if all_name_puns {
			append(&inner, doc_text(base.intern_get(interner, field.name)))
		} else {
			append(&inner, doc_text(base.intern_get(interner, field.name)))
			append(&inner, doc_text(": "))
			append(&inner, format_expr(field.value, info, interner))
		}
	}

	append(&inner, doc_text(","))
	append(&inner, doc_line())

	return doc_group(inner[:])
}

is_name_pun :: proc(field: frontend.Record_Field, interner: ^base.Intern_Table) -> bool {
	#partial switch val in field.value {
	case ^frontend.Expr_Identifier:
		return val.name == field.name
	}
	return false
}

format_expr_list :: proc(
	e: ^frontend.Expr_List,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("["))

	multiline := info.first_separator_break[e.span.start]

	if multiline {
		format_exprs_comma_multiline(&parts, e.elements[:], info, interner)
	} else {
		format_exprs_comma_flat(&parts, e.elements[:], info, interner)
	}

	append(&parts, doc_text("]"))
	return doc_concat(parts[:])
}

format_expr_tuple :: proc(
	e: ^frontend.Expr_Tuple,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("("))
	for el, i in e.elements {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_expr(el, info, interner))
	}
	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_expr_call :: proc(
	e: ^frontend.Expr_Call,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, format_expr(e.callee, info, interner))
	append(&parts, doc_text("("))

	multiline := info.first_separator_break[e.span.start]

	if multiline {
		format_exprs_comma_multiline(&parts, e.args[:], info, interner)
	} else {
		format_exprs_comma_flat(&parts, e.args[:], info, interner)
	}

	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_expr_method_call :: proc(
	e: ^frontend.Expr_Method_Call,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	multiline := info.first_separator_break[e.span.start]

	if multiline {
		parts: [dynamic]Doc
		defer delete(parts)
		append(&parts, format_expr(e.receiver, info, interner))
		append(&parts, doc_line())
		append(&parts, doc_text("."))
		append(&parts, doc_text(base.intern_get(interner, e.method)))
		append(&parts, doc_text("("))
		format_exprs_comma_multiline(&parts, e.args[:], info, interner)
		append(&parts, doc_text(")"))
		return doc_concat(parts[:])
	}

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, format_expr(e.receiver, info, interner))
	append(&parts, doc_text("."))
	append(&parts, doc_text(base.intern_get(interner, e.method)))
	append(&parts, doc_text("("))
	format_exprs_comma_flat(&parts, e.args[:], info, interner)
	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_expr_lambda :: proc(
	e: ^frontend.Expr_Lambda,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("|"))

	for param, i in e.params {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(base.intern_get(interner, param.name)))
		if param.type_ann != nil {
			append(&parts, doc_text(": "))
			append(&parts, format_type(param.type_ann, info, interner))
		}
	}

	append(&parts, doc_text("|"))

	if e.return_type != nil {
		append(&parts, doc_text(" -> "))
		append(&parts, format_type(e.return_type, info, interner))
	}

	_, body_is_block := e.body.(^frontend.Expr_Block)

	if body_is_block {
		append(&parts, doc_space())
		append(&parts, format_expr(e.body, info, interner))
	} else {
		append(&parts, doc_text(" "))
		append(&parts, format_expr(e.body, info, interner))
	}

	return doc_concat(parts[:])
}

format_expr_block :: proc(
	e: ^frontend.Expr_Block,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{"))
	append(&parts, doc_nest(4, format_block_statements(e.statements[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_block_statements :: proc(
	statements: []frontend.Expr,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_line())
	for stmt, i in statements {
		if i > 0 {
			append(&parts, doc_line())
		}
		append(&parts, format_expr(stmt, info, interner))
	}
	return doc_group(parts[:])
}

format_expr_if :: proc(
	e: ^frontend.Expr_If,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	_, then_is_block := e.then_branch.(^frontend.Expr_Block)
	_, else_is_block := e.else_branch.(^frontend.Expr_Block)

	has_braces := then_is_block || else_is_block
	multiline := info.first_separator_break[e.span.start]

	if multiline || has_braces {
		parts: [dynamic]Doc
		defer delete(parts)
		append(&parts, doc_text("if "))
		append(&parts, format_expr(e.condition, info, interner))
		append(&parts, doc_text(" {"))
		append(&parts, doc_line())
		append(&parts, doc_nest(4, format_expr(e.then_branch, info, interner)))
		append(&parts, doc_line())
		append(&parts, doc_text("}"))

		if else_is_block {
			append(&parts, doc_text(" else {"))
			append(&parts, doc_line())
			append(&parts, doc_nest(4, format_expr(e.else_branch, info, interner)))
			append(&parts, doc_line())
			append(&parts, doc_text("}"))
		} else {
			append(&parts, doc_text(" else "))
			append(&parts, format_expr(e.else_branch, info, interner))
		}

		return doc_concat(parts[:])
	}

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("if "))
	append(&parts, format_expr(e.condition, info, interner))
	append(&parts, doc_text(" "))
	append(&parts, format_expr(e.then_branch, info, interner))
	append(&parts, doc_text(" else "))
	append(&parts, format_expr(e.else_branch, info, interner))
	return doc_concat(parts[:])
}

format_expr_match :: proc(
	e: ^frontend.Expr_Match,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("match "))
	append(&parts, format_expr(e.scrutinee, info, interner))
	append(&parts, doc_text(" {"))
	append(&parts, doc_line())
	append(&parts, doc_nest(4, format_match_arms(e.arms[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_match_arms :: proc(
	arms: []frontend.Match_Arm,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	arm_parts: [dynamic]Doc
	defer delete(arm_parts)
	for arm, i in arms {
		if i > 0 {
			append(&arm_parts, doc_line())
		}
		append(&arm_parts, doc_text("| "))
		append(&arm_parts, format_pattern(arm.pattern, info, interner))
		if arm.guard != nil {
			append(&arm_parts, doc_text(" if "))
			append(&arm_parts, format_expr(arm.guard, info, interner))
		}
		append(&arm_parts, doc_text(" -> "))
		append(&arm_parts, format_expr(arm.body, info, interner))
	}
	return doc_group(arm_parts[:])
}

format_pattern :: proc(
	p: frontend.Pattern,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	#partial switch v in p {
	case ^frontend.Pattern_Tag:
		return format_pattern_tag(v, info, interner)
	case ^frontend.Pattern_Record:
		return format_pattern_record(v, info, interner)
	case ^frontend.Pattern_Tuple:
		return format_pattern_tuple(v, info, interner)

	case ^frontend.Pattern_List:
		return format_pattern_list(v, info, interner)
	case ^frontend.Pattern_Int:
		buf: [64]u8
		return doc_text(int_to_string(v.value, buf[:]))
	case ^frontend.Pattern_String:
		return doc_text(v.value)
	case ^frontend.Pattern_Char:
		return format_pattern_char(v)
	case ^frontend.Pattern_Bool:
		if v.value do return doc_text("True")
		return doc_text("False")
	case ^frontend.Pattern_Identifier:
		return doc_text(base.intern_get(interner, v.name))
	case ^frontend.Pattern_Wildcard:
		return doc_text("_")
	case ^frontend.Pattern_Destructure:
		return format_pattern_destructure(v, info, interner)
	case ^frontend.Pattern_Or:
		parts: [dynamic]Doc
		defer delete(parts)
		for alt, i in v.alternatives {
			if i > 0 {
				append(&parts, doc_text(" | "))
			}
			append(&parts, format_pattern(alt, info, interner))
		}
		return doc_group(parts[:])
	}
	return doc_text("?")
}

format_pattern_tag :: proc(
	p: ^frontend.Pattern_Tag,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	name := base.intern_get(interner, p.name)
	if len(p.payload) == 0 {
		return doc_text(name)
	}

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(name))
	append(&parts, doc_text("("))
	for payload, i in p.payload {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_pattern(payload, info, interner))
	}
	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_pattern_record :: proc(
	p: ^frontend.Pattern_Record,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{ "))
	for field, i in p.fields {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(base.intern_get(interner, field.name)))
		if field.binding != 0 {
			append(&parts, doc_text(": "))
			append(&parts, doc_text(base.intern_get(interner, field.binding)))
		}
	}
	if p.is_open {
		if len(p.fields) > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(".."))
	}
	append(&parts, doc_text(" }"))
	return doc_concat(parts[:])
}

format_pattern_tuple :: proc(
	p: ^frontend.Pattern_Tuple,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("("))
	for el, i in p.elements {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_pattern(el, info, interner))
	}
	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_pattern_list :: proc(
	p: ^frontend.Pattern_List,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("["))
	for element, i in p.elements {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_pattern(element, info, interner))
	}
	append(&parts, doc_text("]"))
	return doc_concat(parts[:])
}

format_pattern_destructure :: proc(
	p: ^frontend.Pattern_Destructure,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("@"))
	append(&parts, doc_text(base.intern_get(interner, p.type_name)))
	append(&parts, format_pattern(p.inner, info, interner))
	return doc_concat(parts[:])
}

format_expr_binop :: proc(
	e: ^frontend.Expr_BinOp,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	op_str := operator_string(e.op)
	multiline := info.first_separator_break[e.span.start]

	if multiline {
		parts: [dynamic]Doc
		defer delete(parts)
		append(&parts, format_expr(e.left, info, interner))
		append(&parts, doc_line())
		append(&parts, doc_text(op_str))
		append(&parts, doc_text(" "))
		append(&parts, format_expr(e.right, info, interner))
		return doc_concat(parts[:])
	}

	return doc_concat(
		[]Doc {
			format_expr(e.left, info, interner),
			doc_text(" "),
			doc_text(op_str),
			doc_text(" "),
			format_expr(e.right, info, interner),
		},
	)
}

format_expr_prefixop :: proc(
	e: ^frontend.Expr_PrefixOp,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	op_str := operator_string(e.op)
	return doc_concat([]Doc{doc_text(op_str), format_expr(e.operand, info, interner)})
}

format_expr_field_access :: proc(
	e: ^frontend.Expr_Field_Access,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	return doc_concat(
		[]Doc {
			format_expr(e.record, info, interner),
			doc_text("."),
			doc_text(base.intern_get(interner, e.field)),
		},
	)
}

format_expr_record_update :: proc(
	e: ^frontend.Expr_Record_Update,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{ "))
	append(&parts, doc_text(".."))
	append(&parts, format_expr(e.rest, info, interner))

	multiline := info.first_separator_break[e.span.start]

	if len(e.updates) > 0 {
		if multiline {
			append(&parts, doc_text(","))
			append(&parts, doc_line())
			append(
				&parts,
				doc_nest(4, format_update_fields_multiline(e.updates[:], info, interner)),
			)
		} else {
			for update, i in e.updates {
				append(&parts, doc_text(", "))
				append(&parts, doc_text(base.intern_get(interner, update.name)))
				append(&parts, doc_text(": "))
				append(&parts, format_expr(update.value, info, interner))
			}
		}
	}

	append(&parts, doc_text(" }"))
	return doc_concat(parts[:])
}

format_update_fields_multiline :: proc(
	fields: []frontend.Record_Field,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	inner: [dynamic]Doc
	defer delete(inner)
	for field, i in fields {
		if i > 0 {
			append(&inner, doc_text(","))
			append(&inner, doc_line())
		}
		append(&inner, doc_text(base.intern_get(interner, field.name)))
		append(&inner, doc_text(": "))
		append(&inner, format_expr(field.value, info, interner))
	}
	append(&inner, doc_text(","))
	return doc_group(inner[:])
}

format_expr_assign :: proc(
	e: ^frontend.Expr_Assign,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	if e.type_ann != nil {
		return doc_concat(
			[]Doc {
				format_expr(e.target, info, interner),
				doc_text(": "),
				format_type(e.type_ann, info, interner),
				doc_text(" = "),
				format_expr(e.value, info, interner),
			},
		)
	}
	return doc_concat(
		[]Doc {
			format_expr(e.target, info, interner),
			doc_text(" = "),
			format_expr(e.value, info, interner),
		},
	)
}

format_expr_return :: proc(
	e: ^frontend.Expr_Return,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	return doc_concat([]Doc{doc_text("return "), format_expr(e.value, info, interner)})
}

format_expr_crash :: proc(
	e: ^frontend.Expr_Crash,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	return doc_concat([]Doc{doc_text("panic "), format_expr(e.message, info, interner)})
}

format_expr_interpolated_string :: proc(
	e: ^frontend.Expr_Interpolated_String,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)

	open_delim := "\""
	close_delim := "\""
	append(&parts, doc_text(open_delim))

	for part in e.parts {
		switch p in part {
		case ^frontend.String_Segment:
			append(&parts, doc_text(p.text))
		case frontend.Expr:
			append(&parts, doc_text("${"))
			append(&parts, format_expr(p, info, interner))
			append(&parts, doc_text("}"))
		}
	}

	append(&parts, doc_text(close_delim))
	return doc_concat(parts[:])
}

format_expr_handle :: proc(
	e: ^frontend.Expr_Handle,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)

	append(&parts, doc_text("handle "))
	for effect, i in e.effects {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(base.intern_get(interner, effect)))
	}
	append(&parts, doc_text(" in "))
	append(&parts, format_expr(e.body, info, interner))
	append(&parts, doc_text(" with {"))
	append(&parts, doc_line())
	append(&parts, doc_nest(4, format_handler_arms(e.arms[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))

	return doc_concat(parts[:])
}

format_handler_arms :: proc(
	arms: []frontend.Handler_Arm,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	arm_parts: [dynamic]Doc
	defer delete(arm_parts)
	for arm, i in arms {
		if i > 0 {
			append(&arm_parts, doc_line())
		}
		append(&arm_parts, doc_text(base.intern_get(interner, arm.op)))
		append(&arm_parts, doc_text(" "))
		if len(arm.params) > 0 {
			append(&arm_parts, doc_text(base.intern_get(interner, arm.params[0])))
		}
		if len(arm.params) > 1 {
			for i in 1 ..< len(arm.params) {
				append(&arm_parts, doc_text(", "))
				append(&arm_parts, doc_text(base.intern_get(interner, arm.params[i])))
			}
		}
		append(&arm_parts, doc_text(" -> "))
		append(&arm_parts, format_expr(arm.body, info, interner))
	}
	return doc_group(arm_parts[:])
}

format_expr_par :: proc(
	e: ^frontend.Expr_Par,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)

	if e.for_var != base.Intern_ID(0) {
		// par for x in xs { body }
		append(&parts, doc_text("par for "))
		append(&parts, doc_text(base.intern_get(interner, e.for_var)))
		append(&parts, doc_text(" in "))
		append(&parts, format_expr(e.for_iter, info, interner))
		append(&parts, doc_text(" {"))
		append(&parts, doc_line())
		append(&parts, doc_nest(4, format_expr(e.for_body, info, interner)))
		append(&parts, doc_line())
		append(&parts, doc_text("}"))
	} else if len(e.names) > 0 {
		// par { name: expr, name2: expr2 }
		append(&parts, doc_text("par {"))
		append(&parts, doc_line())
		entry_parts: [dynamic]Doc
		for idx in 0 ..< len(e.names) {
			if idx > 0 {
				append(&entry_parts, doc_text(","))
				append(&entry_parts, doc_line())
			}
			append(&entry_parts, doc_text(base.intern_get(interner, e.names[idx])))
			append(&entry_parts, doc_text(": "))
			append(&entry_parts, format_expr(e.expressions[idx], info, interner))
		}
		append(&parts, doc_nest(4, doc_concat(entry_parts[:])))
		append(&parts, doc_line())
		append(&parts, doc_text("}"))
	} else {
		// par { e1, e2, e3 } (unnamed, legacy)
		append(&parts, doc_text("par {"))
		append(&parts, doc_line())
		append(
			&parts,
			doc_nest(4, format_exprs_comma_multiline_inner(e.expressions[:], info, interner)),
		)
		append(&parts, doc_line())
		append(&parts, doc_text("}"))
	}

	return doc_concat(parts[:])
}

format_exprs_comma_multiline_inner :: proc(
	exprs: []frontend.Expr,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	for expr, i in exprs {
		if i > 0 {
			append(&parts, doc_text(","))
			append(&parts, doc_line())
		}
		append(&parts, format_expr(expr, info, interner))
	}
	return doc_concat(parts[:])
}

// Comma-separated formatting helpers

format_exprs_comma_flat :: proc(
	parts: ^[dynamic]Doc,
	exprs: []frontend.Expr,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) {
	for expr, i in exprs {
		if i > 0 {
			append(parts, doc_text(", "))
		}
		append(parts, format_expr(expr, info, interner))
	}
}

format_exprs_comma_multiline :: proc(
	parts: ^[dynamic]Doc,
	exprs: []frontend.Expr,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) {
	inner: [dynamic]Doc
	defer delete(inner)
	append(&inner, doc_line())
	for expr, i in exprs {
		if i > 0 {
			span_start := frontend.expr_span(expr, .Start)
			if info.has_backslash[span_start] {
				append(&inner, doc_backslash_break())
			}
			append(&inner, doc_line())
		}
		append(&inner, format_expr(expr, info, interner))
		append(&inner, doc_text(","))
	}
	append(&inner, doc_line())

	append(parts, doc_nest(4, doc_group(inner[:])))
}

format_expr_char :: proc(e: ^frontend.Expr_Char) -> Doc {
	return format_char_literal(e.value)
}

format_expr_todo :: proc(
	e: ^frontend.Expr_Todo,
	info: ^Format_Source_Info,
	interner: ^base.Intern_Table,
) -> Doc {
	if e.message == nil {
		return doc_text("todo")
	}
	return doc_concat([]Doc{doc_text("todo "), format_expr(e.message, info, interner)})
}

format_char_literal :: proc(value: u8) -> Doc {
	switch value {
	case '\n':
		return doc_text("'\\n'")
	case '\t':
		return doc_text("'\\t'")
	case '\\':
		return doc_text("'\\\\'")
	case '\'':
		return doc_text("'\\''")
	case 32 ..= 126:
		return doc_concat([]Doc{doc_text("'"), doc_text(string([]u8{value})), doc_text("'")})
	}
	return doc_text("'?'")
}

format_pattern_char :: proc(p: ^frontend.Pattern_Char) -> Doc {
	return format_char_literal(p.value)
}

