package camp

format_type :: proc(t: ^Type, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	if t == nil {
		return doc_text("?")
	}

	#partial switch v in t {
	case ^Type_Primitive:
		return doc_text(intern_get(interner, v.name))
	case ^Type_Applied:
		return format_type_applied(v, info, interner)
	case ^Type_Function:
		return format_type_function(v, info, interner)
	case ^Type_Record:
		return format_type_record(v, info, interner)
	case ^Type_Tag_Union:
		return format_type_tag_union(v, info, interner)
	case ^Type_Effect_Row:
		return format_type_effect_row(v, info, interner)
	case ^Type_Variable:
		return doc_text(intern_get(interner, v.name))
	case ^Type_Wildcard:
		return doc_text("_")
	}
	return doc_text("?")
}

format_type_applied :: proc(t: ^Type_Applied, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	name := intern_get(interner, t.name)
	multiline := info.first_separator_break[t.span.start]

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(name))
	append(&parts, doc_text("("))

	if len(t.args) > 0 {
		if multiline {
			args := format_comma_types_multiline(t.args[:], info, interner)
			append(&parts, args)
		} else {
			args := format_comma_types_flat(t.args[:], info, interner)
			append(&parts, args)
		}
	}

	append(&parts, doc_text(")"))
	return doc_concat(parts[:])
}

format_type_function :: proc(t: ^Type_Function, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)

	append(&parts, doc_text("|"))

	if len(t.params) > 0 {
		params := format_comma_types_flat(t.params[:], info, interner)
		append(&parts, params)
	}

	append(&parts, doc_text("| -> "))

	if t.effects != nil {
		append(&parts, doc_text("-["))
		append(&parts, format_type(t.effects, info, interner))
		append(&parts, doc_text("]-> "))
	}

	append(&parts, format_type(&t.return_, info, interner))

	return doc_concat(parts[:])
}

format_type_record :: proc(t: ^Type_Record, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	multiline := info.first_separator_break[t.span.start]

	if multiline {
		return format_record_multiline(t, info, interner)
	}
	return format_record_flat(t, info, interner)
}

format_record_flat :: proc(t: ^Type_Record, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{ "))

	for field, i in t.fields {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(intern_get(interner, field.name)))
		append(&parts, doc_text(": "))
		append(&parts, format_type(&t.fields[i].type, info, interner))
	}

	if t.is_open {
		if len(t.fields) > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, doc_text(".."))
		append(&parts, doc_text(intern_get(interner, t.rest)))
	}

	append(&parts, doc_text(" }"))
	return doc_concat(parts[:])
}

format_record_multiline :: proc(t: ^Type_Record, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	fields_parts: [dynamic]Doc
	defer delete(fields_parts)
	append(&fields_parts, doc_line())

	for field, i in t.fields {
		if i > 0 {
			append(&fields_parts, doc_line())
		}
		append(&fields_parts, doc_text(intern_get(interner, field.name)))
		append(&fields_parts, doc_text(": "))
		append(&fields_parts, format_type(&t.fields[i].type, info, interner))
		append(&fields_parts, doc_text(","))
	}

	if t.is_open {
		if len(t.fields) > 0 {
			append(&fields_parts, doc_text(","))
			append(&fields_parts, doc_line())
		}
		append(&fields_parts, doc_text(".."))
		append(&fields_parts, doc_text(intern_get(interner, t.rest)))
		append(&fields_parts, doc_text(","))
	}

	append(&fields_parts, doc_line())

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("{"))
	append(&parts, doc_nest(4, doc_group(fields_parts[:])))
	append(&parts, doc_text("}"))
	return doc_concat(parts[:])
}

format_type_tag_union :: proc(t: ^Type_Tag_Union, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	multiline := info.first_separator_break[t.span.start]

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text("["))

	if len(t.tags) > 0 {
		if multiline {
			tag_docs := format_tags_multiline(t.tags[:], info, interner)
			append(&parts, tag_docs)
		} else {
			tag_docs := format_tags_flat(t.tags[:], info, interner)
			append(&parts, tag_docs)
		}
	}

	append(&parts, doc_text("]"))
	return doc_concat(parts[:])
}

format_tags_flat :: proc(tags: []Type_Tag, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	for tag, i in tags {
		if i > 0 {
			append(&parts, doc_text(" | "))
		}
		append(&parts, format_tag(&tags[i], info, interner))
	}
	return doc_concat(parts[:])
}

format_tags_multiline :: proc(tags: []Type_Tag, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	inner_parts: [dynamic]Doc
	defer delete(inner_parts)
	append(&inner_parts, doc_line())

	for tag, i in tags {
		if i > 0 {
			append(&inner_parts, doc_line())
			append(&inner_parts, doc_text("| "))
		}
		append(&inner_parts, format_tag(&tags[i], info, interner))
	}

	append(&inner_parts, doc_line())

	return doc_nest(4, doc_group(inner_parts[:]))
}

format_tag :: proc(tag: ^Type_Tag, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	name := intern_get(interner, tag.name)

	if len(tag.payload) == 0 {
		return doc_text(name)
	}

	parts: [dynamic]Doc
	defer delete(parts)
	append(&parts, doc_text(name))
	append(&parts, doc_text("("))
	for payload, i in tag.payload {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_type(&tag.payload[i], info, interner))
	}
	append(&parts, doc_text(")"))

	return doc_concat(parts[:])
}

format_type_effect_row :: proc(t: ^Type_Effect_Row, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	multiline := info.first_separator_break[t.span.start]

	if multiline {
		return format_effect_row_multiline(t, info, interner)
	}
	return format_effect_row_flat(t, info, interner)
}

format_effect_row_flat :: proc(t: ^Type_Effect_Row, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	for entry, i in t.effects {
		if i > 0 {
			append(&parts, doc_text(" | "))
		}
		name := intern_get(interner, entry.name)
		if len(entry.type_args) > 0 {
			append(&parts, doc_text(name))
			append(&parts, doc_text("!("))
			for j in 0..<len(entry.type_args) {
				if j > 0 {
					append(&parts, doc_text(", "))
				}
				append(&parts, format_type(&entry.type_args[j], info, interner))
			}
			append(&parts, doc_text(")"))
		} else {
			append(&parts, doc_text(name))
		}
	}

	if t.is_open {
		if len(t.effects) > 0 {
			append(&parts, doc_text(" | "))
		}
		append(&parts, doc_text(".."))
		append(&parts, doc_text(intern_get(interner, t.rest)))
	}

	return doc_concat(parts[:])
}

format_effect_row_multiline :: proc(t: ^Type_Effect_Row, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	inner: [dynamic]Doc
	defer delete(inner)
	append(&inner, doc_line())

	for entry, i in t.effects {
		if i > 0 {
			append(&inner, doc_line())
			append(&inner, doc_text("| "))
		}
		name := intern_get(interner, entry.name)
		if len(entry.type_args) > 0 {
			append(&inner, doc_text(name))
			append(&inner, doc_text("!("))
			for j in 0..<len(entry.type_args) {
				if j > 0 {
					append(&inner, doc_text(", "))
				}
				append(&inner, format_type(&entry.type_args[j], info, interner))
			}
			append(&inner, doc_text(")"))
		} else {
			append(&inner, doc_text(name))
		}
	}

	if t.is_open {
		if len(t.effects) > 0 {
			append(&inner, doc_line())
			append(&inner, doc_text("| "))
		}
		append(&inner, doc_text(".."))
		append(&inner, doc_text(intern_get(interner, t.rest)))
	}

	append(&inner, doc_line())

	return doc_nest(4, doc_group(inner[:]))
}

format_comma_types_flat :: proc(types: []Type, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	parts: [dynamic]Doc
	defer delete(parts)
	for type, i in types {
		if i > 0 {
			append(&parts, doc_text(", "))
		}
		append(&parts, format_type(&types[i], info, interner))
	}
	return doc_concat(parts[:])
}

format_comma_types_multiline :: proc(types: []Type, info: ^Format_Source_Info, interner: ^Intern_Table) -> Doc {
	inner: [dynamic]Doc
	defer delete(inner)
	append(&inner, doc_line())

	for type, i in types {
		if i > 0 {
			append(&inner, doc_line())
		}
		append(&inner, format_type(&types[i], info, interner))
		append(&inner, doc_text(","))
	}

	append(&inner, doc_line())

	return doc_nest(4, doc_group(inner[:]))
}
