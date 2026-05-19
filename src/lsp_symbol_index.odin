package camp


Symbol_Kind :: enum {
	Function,
	Type,
	Effect,
	Parameter,
	Local,
}

Symbol_Entry :: struct {
	name:     string,
	uri:      string,
	range:    LSP_Range,
	kind:     Symbol_Kind,
	type_str: string,
}

Symbol_Index :: struct {
	entries: [dynamic]Symbol_Entry,
	by_name: map[string][]int,
}

symbol_index_init :: proc(idx: ^Symbol_Index) {
	idx.entries = make([dynamic]Symbol_Entry, 0, 64)
	idx.by_name = make(map[string][]int, 16)
}

destroy_symbol_index :: proc(idx: ^Symbol_Index) {
	delete(idx.entries)
	for _, indices in idx.by_name {
		delete(indices)
	}
	delete(idx.by_name)
}

symbol_index_add :: proc(idx: ^Symbol_Index, name: string, uri: string, range: LSP_Range, kind: Symbol_Kind, type_str: string) {
	entry_index := len(idx.entries)
	append(&idx.entries, Symbol_Entry{
		name = name,
		uri = uri,
		range = range,
		kind = kind,
		type_str = type_str,
	})
	indices, ok := idx.by_name[name]
	if !ok {
		v := make([]int, 1)
		v[0] = entry_index
		idx.by_name[name] = v
	} else {
		old_len := len(indices)
		appended := make([]int, old_len + 1)
		copy(appended, indices)
		appended[old_len] = entry_index
		delete(indices)
		idx.by_name[name] = appended
	}
}

symbol_index_lookup :: proc(idx: ^Symbol_Index, name: string) -> []int {
	indices, ok := idx.by_name[name]
	if !ok {
		return nil
	}
	return indices
}

build_symbol_index :: proc(idx: ^Symbol_Index, file: CFile, uri: string, source: string, store: ^Type_Store) {
	for decl in file.decls {
		#partial switch d in decl {
		case ^CDecl_Const:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := format_type_ann(d.type_ann, store)
			symbol_index_add(idx, name_str, uri, range, .Function, type_str)
		case ^CDecl_Effect:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Effect, "effect")
			for op in d.operations {
				op_name := intern_get(store.interner, op.name)
				op_range := span_to_lsp_range(source, op.span)
				symbol_index_add(idx, op_name, uri, op_range, .Function, "operation")
			}
		case ^CDecl_Trait:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Type, "trait")
		case ^CDecl_Alias:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Type, "type alias")
		case:
		}
	}
}

format_type_ann :: proc(type_ann: ^CType, store: ^Type_Store) -> string {
	if type_ann == nil {
		return "?"
	}
	switch t in type_ann^ {
	case ^CType_Primitive:
		return intern_get(store.interner, t.name)
	case ^CType_Function:
		return "function"
	case ^CType_Record:
		return "record"
	case ^CType_Tag_Union:
		return "tag union"
	case ^CType_Effect_Row:
		return "effect row"
	case ^CType_Variable:
		return intern_get(store.interner, t.name)
	case ^CType_Applied:
		return intern_get(store.interner, t.name)
	case ^CType_Wildcard:
		return "_"
	case:
		return "?"
	}
}

span_to_lsp_range :: proc(source: string, span: Source_Span) -> LSP_Range {
	line, col := diag_span_to_line_col(source, span)
	end_line, end_col := span_end_to_line_col(source, span)
	return LSP_Range{
		start = LSP_Position{line = uint(line - 1), character = uint(col - 1)},
		end   = LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)},
	}
}
