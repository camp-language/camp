package lsp

import "core:fmt"
import "core:strings"

import camp ".."

Symbol_Kind :: enum int {
	File = 1,
	Module = 2,
	Namespace = 3,
	Package = 4,
	Class = 5,
	Method = 6,
	Property = 7,
	Field = 8,
	Constructor = 9,
	Enum = 10,
	Interface = 11,
	Function = 12,
	Variable = 13,
	Constant = 14,
}

Symbol_Entry :: struct {
	name:      string,
	kind:      Symbol_Kind,
	range:     camp.LSP_Range,
	type_str:  string,
}

Symbol_Index :: struct {
	entries: [dynamic]Symbol_Entry,
}

symbol_index_init :: proc(idx: ^Symbol_Index) {
	idx.entries = make([dynamic]Symbol_Entry, 0, 64)
}

symbol_index_destroy :: proc(idx: ^Symbol_Index) {
	delete(idx.entries)
}

build_symbol_index :: proc(cfile: camp.CFile, source: string, interner: ^camp.Intern_Table) -> Symbol_Index {
	idx: Symbol_Index
	symbol_index_init(&idx)

	for decl in cfile.decls {
		#partial switch d in decl {
		case ^camp.CDecl_Const:
			name_str := camp.intern_get(interner, d.name.name)
			rng := span_to_lsp_range(source, d.span)
			type_str := format_type_ann(d.type_ann, interner)
			append(&idx.entries, Symbol_Entry{
				name = name_str,
				kind = .Constant,
				range = rng,
				type_str = type_str,
			})

		case ^camp.CDecl_Effect:
			name_str := camp.intern_get(interner, d.name.name)
			rng := span_to_lsp_range(source, d.span)
			append(&idx.entries, Symbol_Entry{
				name = name_str,
				kind = .Interface,
				range = rng,
				type_str = "effect",
			})

		case ^camp.CDecl_Trait:
			name_str := camp.intern_get(interner, d.name.name)
			rng := span_to_lsp_range(source, d.span)
			append(&idx.entries, Symbol_Entry{
				name = name_str,
				kind = .Interface,
				range = rng,
				type_str = "trait",
			})

		case ^camp.CDecl_Alias:
			name_str := camp.intern_get(interner, d.name.name)
			rng := span_to_lsp_range(source, d.span)
			type_str := format_type_ann(d.target, interner)
			append(&idx.entries, Symbol_Entry{
				name = name_str,
				kind = .Constant,
				range = rng,
				type_str = type_str,
			})
		case:
		}
	}

	return idx
}

span_to_lsp_range :: proc(source: string, span: camp.Source_Span) -> camp.LSP_Range {
	start_line, start_col := camp.diag_span_to_line_col(source, span)
	end_line, end_col := camp.span_end_to_line_col(source, span)
	return camp.LSP_Range{
		start = camp.LSP_Position{line = uint(start_line - 1), character = uint(start_col - 1)},
		end   = camp.LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)},
	}
}

format_type_ann :: proc(t: ^camp.CType, interner: ^camp.Intern_Table) -> string {
	if t == nil {
		return "?"
	}
	return format_ctype(t^, interner)
}

format_ctype :: proc(t: camp.CType, interner: ^camp.Intern_Table) -> string {
	switch ty in t {
	case ^camp.CType_Primitive:
		return camp.intern_get(interner, ty.name)
	case ^camp.CType_Applied:
		name := camp.intern_get(interner, ty.name)
		if len(ty.args) == 0 {
			return name
		}
		builder: strings.Builder
		strings.builder_init(&builder, 64)
		strings.write_string(&builder, name)
		strings.write_rune(&builder, '(')
		for i, arg in ty.args {
			if i > 0 {
				strings.write_string(&builder, ", ")
			}
			strings.write_string(&builder, format_ctype(arg, interner))
		}
		strings.write_rune(&builder, ')')
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	case ^camp.CType_Function:
		builder: strings.Builder
		strings.builder_init(&builder, 128)
		for i, p in ty.params {
			if i > 0 {
				strings.write_string(&builder, ", ")
			}
			strings.write_string(&builder, format_ctype(p, interner))
		}
		strings.write_string(&builder, " -> ")
		strings.write_string(&builder, format_ctype(ty.return_, interner))
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	case ^camp.CType_Variable:
		return camp.intern_get(interner, ty.name)
	case ^camp.CType_Wildcard:
		return "_"
	case ^camp.CType_Record:
		return "{ ... }"
	case ^camp.CType_Tag_Union:
		return "[ ... ]"
	case ^camp.CType_Effect_Row:
		return "{}"
	}
	return "?"
}

format_resolved_type :: proc(store: ^camp.Type_Store, var_id: camp.Type_Var_ID) -> string {
	resolved := camp.resolve_var(store, var_id)
	v := camp.get_var(store, resolved)

	inf, is_inf := v.link.(camp.Inferred_Type)
	if !is_inf {
		return "?"
	}

	switch inf.tag {
	case .Primitive:
		return camp.intern_get(store.interner, inf.primitive_name)
	case .Function:
		builder: strings.Builder
		strings.builder_init(&builder, 128)
		for i, pid in inf.param_ids {
			if i > 0 {
				strings.write_string(&builder, ", ")
			}
			strings.write_string(&builder, format_resolved_type(store, pid))
		}
		strings.write_string(&builder, " -> ")
		strings.write_string(&builder, format_resolved_type(store, inf.return_id))
		result := strings.to_string(builder)
		strings.builder_destroy(&builder)
		return result
	case .Constructor:
		return camp.intern_get(store.interner, inf.primitive_name)
	case .Record_Row:
		return "{ ... }"
	case .Tag_Union_Row:
		return "[ ... ]"
	case .Effect_Row:
		return "{}"
	}
	return "?"
}

find_symbol_at :: proc(idx: ^Symbol_Index, line: uint, character: uint) -> int {
	for i, entry in idx.entries {
		if line >= entry.range.start.line && line <= entry.range.end.line {
			if line == entry.range.start.line && character < entry.range.start.character {
				continue
			}
			if line == entry.range.end.line && character > entry.range.end.character {
				continue
			}
			return i
		}
	}
	return -1
}
