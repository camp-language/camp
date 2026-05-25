package format

import "core:strings"
import "camp:base"
import "camp:frontend"

format_decl :: proc(d: frontend.Decl, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	#partial switch v in d {
	case ^frontend.Decl_Const:
		return format_decl_const(v, info, interner)
	case ^frontend.Decl_Effect:
		return format_decl_effect(v, info, interner)
	case ^frontend.Decl_Trait:
		return format_decl_trait(v, info, interner)
	case ^frontend.Decl_Alias:
		return format_decl_alias(v, info, interner)
	case ^frontend.Decl_Newtype:
		return format_decl_newtype(v, info, interner)
	case ^frontend.Decl_Import:
		return format_decl_import(v, info, interner)
	case ^frontend.Decl_Test:
		return format_decl_test(v, info, interner)
	case ^frontend.Decl_Expect:
		return format_decl_expect(v, info, interner)
	}
	return doc_text("?")
}

format_decl_const :: proc(v: ^frontend.Decl_Const, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	if v.is_pub {
		append(&parts, doc_text("pub "))
	}
	name_str := base.intern_get(interner, v.name)
	append(&parts, doc_text(name_str))
	if v.is_effectful && !strings.has_suffix(name_str, "!") {
		append(&parts, doc_text("!"))
	}
	if v.type_ann != nil {
		append(&parts, doc_text(": "))
		append(&parts, format_type(v.type_ann, info, interner))
	}
	if len(v.where_clauses) > 0 {
		append(&parts, doc_text(" where "))
		for wc, i in v.where_clauses {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, wc.type_param)))
			append(&parts, doc_text(" is "))
			append(&parts, doc_text(base.intern_get(interner, wc.trait_name)))
		}
	}
	append(&parts, doc_text(" = "))
	append(&parts, format_expr(v.body, info, interner))
	return doc_concat(parts[:])
}

format_decl_effect :: proc(v: ^frontend.Decl_Effect, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(base.intern_get(interner, v.name)))
	if len(v.type_params) > 0 {
		append(&parts, doc_text("<"))
		for tp, i in v.type_params {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, tp.name)))
		}
		append(&parts, doc_text(">"))
	}
	append(&parts, doc_text("! :"))

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

format_effect_ops :: proc(ops: []frontend.Effect_Op, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	op_parts: [dynamic]Doc
	defer delete(op_parts)
	append(&op_parts, doc_line())
	for op, i in ops {
		if i > 0 {
			append(&op_parts, doc_line())
		}
		op_name := base.intern_get(interner, op.name)
		append(&op_parts, doc_text(op_name))
		if op.is_effectful && !strings.has_suffix(op_name, "!") {
			append(&op_parts, doc_text("!"))
		}
		if len(op.params) > 0 {
			append(&op_parts, doc_text("("))
			for param, j in op.params {
				if j > 0 {
					append(&op_parts, doc_text(", "))
				}
				append(&op_parts, doc_text(base.intern_get(interner, param.name)))
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

format_decl_trait :: proc(v: ^frontend.Decl_Trait, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(base.intern_get(interner, v.name)))
	if v.parent != 0 {
		append(&parts, doc_text(" is "))
		append(&parts, doc_text(base.intern_get(interner, v.parent)))
	}

	if len(v.methods) == 0 {
		append(&parts, doc_text(" : {}"))
		return doc_concat(parts[:])
	}

	append(&parts, doc_text(" : {"))
	append(&parts, doc_nest(4, format_trait_methods(v.methods[:], info, interner)))
	append(&parts, doc_line())
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_trait_methods :: proc(methods: []frontend.Trait_Method, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	m_parts: [dynamic]Doc
	defer delete(m_parts)
	append(&m_parts, doc_line())
	for m, i in methods {
		if i > 0 {
			append(&m_parts, doc_line())
		}
		append(&m_parts, doc_text(base.intern_get(interner, m.name)))
		append(&m_parts, doc_text(": "))
		append(&m_parts, doc_text("|"))
		for param, j in m.params {
			if j > 0 {
				append(&m_parts, doc_text(", "))
			}
			append(&m_parts, doc_text(base.intern_get(interner, param.name)))
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

format_decl_alias :: proc(v: ^frontend.Decl_Alias, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(base.intern_get(interner, v.name)))
	append(&parts, doc_text(" : "))
	append(&parts, format_type(v.target, info, interner))
	return doc_concat(parts[:])
}

format_decl_newtype :: proc(v: ^frontend.Decl_Newtype, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	if v.is_pub {
		append(&parts, doc_text("pub "))
	}
	append(&parts, doc_text("@"))
	append(&parts, doc_text(base.intern_get(interner, v.name)))
	if len(v.type_params) > 0 {
		append(&parts, doc_text("("))
		for tp, i in v.type_params {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, tp)))
		}
		append(&parts, doc_text(")"))
	}
	if len(v.derive_targets) > 0 {
		append(&parts, doc_text(" derives "))
		for dt, i in v.derive_targets {
			if i > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, dt)))
		}
	}
	append(&parts, doc_text(" : "))
	if v.pub_variants {
		append(&parts, doc_text("pub "))
	}
	append(&parts, format_type(v.inner_type, info, interner))
	return doc_concat(parts[:])
}

format_import_item :: proc(item: frontend.Import_Item, interner: ^base.Intern_Table) -> Doc {
	switch it in item {
	case base.Intern_ID:
		return doc_text(base.intern_get(interner, it))
	case ^frontend.Import_Variant_Group:
		parts: [dynamic]Doc
		defer delete(parts)
		append(&parts, doc_text("["))
		for variant, j in it.variants {
			if j > 0 {
				append(&parts, doc_text(", "))
			}
			append(&parts, doc_text(base.intern_get(interner, variant)))
		}
		append(&parts, doc_text("]"))
		return doc_concat(parts[:])
	}
	return doc_text("?")
}

format_decl_import :: proc(v: ^frontend.Decl_Import, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("import "))
	append(&parts, doc_text(v.module))

	if v.alias != 0 {
		append(&parts, doc_text(" as "))
		append(&parts, doc_text(base.intern_get(interner, v.alias)))
	}

	if len(v.names) > 0 {
		multiline := info.first_separator_break[v.span.start]
		if multiline {
			append(&parts, doc_text(" {"))
			append(&parts, doc_nest(4, format_import_names_multiline(v.names[:], interner)))
			append(&parts, doc_line())
			append(&parts, doc_text("}"))
		} else {
			append(&parts, doc_text(" { "))
			for item, i in v.names {
				if i > 0 {
					append(&parts, doc_text(", "))
				}
				append(&parts, format_import_item(item, interner))
			}
			append(&parts, doc_text(" }"))
		}
	}

	return doc_concat(parts[:])
}

format_import_names_multiline :: proc(names: []frontend.Import_Item, interner: ^base.Intern_Table) -> Doc {
	inner: [dynamic]Doc
	defer delete(inner)
	append(&inner, doc_line())
	for item, i in names {
		if i > 0 {
			append(&inner, doc_line())
		}
		append(&inner, format_import_item(item, interner))
		append(&inner, doc_text(","))
	}
	append(&inner, doc_line())
	return doc_group(inner[:])
}

format_decl_test :: proc(v: ^frontend.Decl_Test, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("test "))
	append(&parts, doc_text(v.name))
	append(&parts, doc_text(" = "))
	append(&parts, format_expr(v.body, info, interner))
	return doc_concat(parts[:])
}

format_decl_expect :: proc(v: ^frontend.Decl_Expect, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("expect "))
	append(&parts, format_expr(v.condition, info, interner))
	return doc_concat(parts[:])
}

format_file :: proc(f: frontend.File, info: ^Format_Source_Info, interner: ^base.Intern_Table) -> Doc {
	if len(f.decls) == 0 {
		return doc_empty()
	}

	parts: [dynamic]Doc
	defer delete(parts)
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

has_blank_line_between_decls :: proc(prev: frontend.Decl, next: frontend.Decl, info: ^Format_Source_Info) -> bool {
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

decl_span_start :: proc(d: frontend.Decl) -> int {
	#partial switch v in d {
	case ^frontend.Decl_Const:
		return v.span.start
	case ^frontend.Decl_Effect:
		return v.span.start
	case ^frontend.Decl_Trait:
		return v.span.start
	case ^frontend.Decl_Alias:
		return v.span.start
	case ^frontend.Decl_Newtype:
		return v.span.start
	case ^frontend.Decl_Import:
		return v.span.start
	case ^frontend.Decl_Test:
		return v.span.start
	case ^frontend.Decl_Expect:
		return v.span.start
	}
	return 0
}
