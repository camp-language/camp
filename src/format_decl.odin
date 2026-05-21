package camp

format_decl :: proc(d: Decl, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	#partial switch v in d {
	case ^Decl_Const:
		return format_decl_const(v, info, interner)
	case ^Decl_Effect:
		return format_decl_effect(v, info, interner)
	case ^Decl_Trait:
		return format_decl_trait(v, info, interner)
	case ^Decl_Alias:
		return format_decl_alias(v, info, interner)
	case ^Decl_Newtype:
		return format_decl_newtype(v, info, interner)
	case ^Decl_Import:
		return format_decl_import(v, info, interner)
	case ^Decl_Test:
		return format_decl_test(v, info, interner)
	case ^Decl_Expect:
		return format_decl_expect(v, info, interner)
	}
	return doc_text("?")
}

format_decl_const :: proc(v: ^Decl_Const, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	if v.is_pub {
		append(&parts, doc_text("pub "))
	}
	append(&parts, doc_text(intern_get(interner, v.name)))
	if v.is_effectful {
		append(&parts, doc_text("!"))
	}
	if v.type_ann != nil {
		append(&parts, doc_text(": "))
		append(&parts, format_type(v.type_ann, info, interner))
	}
	append(&parts, doc_text(" = "))
	append(&parts, format_expr(v.body, info, interner))
	return doc_concat(parts[:])
}

format_decl_effect :: proc(v: ^Decl_Effect, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("effect "))
	append(&parts, doc_text(intern_get(interner, v.name)))

	if len(v.operations) == 0 {
		append(&parts, doc_text(" {}"))
		return doc_concat(parts[:])
	}

	append(&parts, doc_text(" {"))
	append(&parts, doc_nest(4, format_effect_ops(v.operations[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_effect_ops :: proc(ops: []Effect_Op, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	op_parts: [dynamic]Doc
	append(&op_parts, doc_line())
	for op, i in ops {
		if i > 0 {
			append(&op_parts, doc_line())
		}
		append(&op_parts, doc_text(intern_get(interner, op.name)))
		if op.is_effectful {
			append(&op_parts, doc_text("!"))
		}
		if len(op.params) > 0 {
			append(&op_parts, doc_text("("))
			for param, j in op.params {
				if j > 0 {
					append(&op_parts, doc_text(", "))
				}
				append(&op_parts, doc_text(intern_get(interner, param.name)))
				if param.type_ann != nil {
					append(&op_parts, doc_text(": "))
					append(&op_parts, format_type(param.type_ann, info, interner))
				}
			}
			append(&op_parts, doc_text(")"))
		}
		if op.return_type != nil {
			append(&op_parts, doc_text(": "))
			append(&op_parts, format_type(op.return_type, info, interner))
		}
	}
	return doc_group(op_parts[:])
}

format_decl_trait :: proc(v: ^Decl_Trait, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("trait "))
	append(&parts, doc_text(intern_get(interner, v.name)))
	if v.parent != 0 {
		append(&parts, doc_text(" is "))
		append(&parts, doc_text(intern_get(interner, v.parent)))
	}

	if len(v.methods) == 0 {
		append(&parts, doc_text(" {}"))
		return doc_concat(parts[:])
	}

	append(&parts, doc_text(" {"))
	append(&parts, doc_nest(4, format_trait_methods(v.methods[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_trait_methods :: proc(methods: []Trait_Method, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	m_parts: [dynamic]Doc
	append(&m_parts, doc_line())
	for m, i in methods {
		if i > 0 {
			append(&m_parts, doc_line())
		}
		append(&m_parts, doc_text(intern_get(interner, m.name)))
		append(&m_parts, doc_text(": "))
		append(&m_parts, doc_text("|"))
		for param, j in m.params {
			if j > 0 {
				append(&m_parts, doc_text(", "))
			}
			append(&m_parts, doc_text(intern_get(interner, param.name)))
			if param.type_ann != nil {
				append(&m_parts, doc_text(": "))
				append(&m_parts, format_type(param.type_ann, info, interner))
			}
		}
		append(&m_parts, doc_text("| -> "))
		if m.return_type != nil {
			append(&m_parts, format_type(m.return_type, info, interner))
		}
	}
	return doc_group(m_parts[:])
}

format_decl_alias :: proc(v: ^Decl_Alias, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("alias "))
	append(&parts, doc_text(intern_get(interner, v.name)))
	append(&parts, doc_text(" = "))
	append(&parts, format_type(v.target, info, interner))
	return doc_concat(parts[:])
}

format_decl_newtype :: proc(v: ^Decl_Newtype, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	if v.is_pub {
		append(&parts, doc_text("pub "))
	}
	append(&parts, doc_text(intern_get(interner, v.name)))
	if len(v.type_params) > 0 {
		append(&parts, doc_text("("))
		for tp, i in v.type_params {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(intern_get(interner, tp)))
		}
		append(&parts, doc_text(")"))
	}
	if len(v.trait_conforms) > 0 {
		append(&parts, doc_text(" is "))
		for tc, i in v.trait_conforms {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(intern_get(interner, tc)))
		}
	}
	append(&parts, doc_text(" := "))
	append(&parts, format_type(v.inner_type, info, interner))
	return doc_concat(parts[:])
}

format_decl_import :: proc(v: ^Decl_Import, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("import "))
	append(&parts, doc_text(v.module))

	if len(v.exposing) > 0 {
		multiline := info.first_separator_break[v.span.start]
		if multiline {
			append(&parts, doc_text(" exposing ["))
			append(&parts, doc_nest(4, format_exposing_list_multiline(v.exposing[:], interner)))
			append(&parts, doc_line())
			append(&parts, doc_text("]"))
		} else {
			append(&parts, doc_text(" exposing ["))
			for name, i in v.exposing {
				if i > 0 {
					append(&parts, doc_text(", "))
				}
				append(&parts, doc_text(intern_get(interner, name)))
			}
			append(&parts, doc_text("]"))
		}
	}

	if v.alias != 0 {
		append(&parts, doc_text(" as "))
		append(&parts, doc_text(intern_get(interner, v.alias)))
	}

	return doc_concat(parts[:])
}

format_exposing_list_multiline :: proc(names: []Intern_ID, interner: ^Intern_Table) -> Doc {
	inner: [dynamic]Doc
	append(&inner, doc_line())
	for name, i in names {
		if i > 0 {
			append(&inner, doc_line())
		}
		append(&inner, doc_text(intern_get(interner, name)))
		append(&inner, doc_text(","))
	}
	append(&inner, doc_line())
	return doc_group(inner[:])
}

format_decl_test :: proc(v: ^Decl_Test, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("test "))
	append(&parts, doc_text(v.name))
	append(&parts, doc_text(" = "))
	append(&parts, format_expr(v.body, info, interner))
	return doc_concat(parts[:])
}

format_decl_expect :: proc(v: ^Decl_Expect, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	append(&parts, doc_text("expect "))
	append(&parts, format_expr(v.condition, info, interner))
	return doc_concat(parts[:])
}

format_file :: proc(f: File, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	if len(f.decls) == 0 {
		return doc_empty()
	}

	parts: [dynamic]Doc
	for decl, i in f.decls {
		if i > 0 {
			append(&parts, doc_line())
			if has_blank_line_between_decls(f.decls[i - 1], decl, info) {
				append(&parts, doc_line())
			}
		}
		append(&parts, format_decl(decl, info, interner))
	}
	return doc_concat(parts[:])
}

has_blank_line_between_decls :: proc(prev: Decl, next: Decl, info: ^Format_Source_Info) -> bool {
	prev_start := decl_span_start(prev)
	next_start := decl_span_start(next)
	if info.blank_line_after[prev_start] {
		return true
	}
	if prev_start >= next_start || next_start > len(info.source) {
		return false
	}
	for pos, val in info.blank_line_after {
		if pos > prev_start && pos < next_start && val {
			return true
		}
	}
	return false
}

decl_span_start :: proc(d: Decl) -> int {
	#partial switch v in d {
	case ^Decl_Const:
		return v.span.start
	case ^Decl_Effect:
		return v.span.start
	case ^Decl_Trait:
		return v.span.start
	case ^Decl_Alias:
		return v.span.start
	case ^Decl_Newtype:
		return v.span.start
	case ^Decl_Import:
		return v.span.start
	case ^Decl_Test:
		return v.span.start
	case ^Decl_Expect:
		return v.span.start
	}
	return 0
}
