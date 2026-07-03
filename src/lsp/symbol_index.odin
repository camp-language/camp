package lsp

import "camp:base"
import "camp:diagnostics"
import "camp:semantics"
import "core:strings"

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
	range:    diagnostics.LSP_Range,
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

symbol_index_add :: proc(
	idx: ^Symbol_Index,
	name: string,
	uri: string,
	range: diagnostics.LSP_Range,
	kind: Symbol_Kind,
	type_str: string,
) {
	entry_index := len(idx.entries)
	append(
		&idx.entries,
		Symbol_Entry {
			name = clone_string(name, context.allocator),
			uri = clone_string(uri, context.allocator),
			range = range,
			kind = kind,
			type_str = clone_string(type_str, context.allocator),
		},
	)

	// Clone the name for the map key — the original is a borrowed reference
	// (e.g., from an interner) that may be freed before the map is destroyed.
	key_name := clone_string(name, context.allocator)

	indices, ok := idx.by_name[key_name]
	if !ok {
		v := make([]int, 1)
		v[0] = entry_index
		idx.by_name[key_name] = v
	} else {
		old_len := len(indices)
		appended := make([]int, old_len + 1)
		copy(appended, indices)
		appended[old_len] = entry_index
		delete(indices)
		idx.by_name[key_name] = appended
	}
}

symbol_index_lookup :: proc(idx: ^Symbol_Index, name: string) -> []int {
	indices, ok := idx.by_name[name]
	if !ok {
		return nil
	}
	return indices
}

build_symbol_index :: proc(
	idx: ^Symbol_Index,
	file: semantics.CFile,
	uri: string,
	source: string,
	store: ^semantics.Type_Store,
) {
	for decl in file.decls {
		#partial switch d in decl {
		case ^semantics.CDecl_Const:
			name_str := base.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else if d.type_ann != nil {
				type_str = format_type_ann(d.type_ann, store)
			}
			symbol_index_add(idx, name_str, uri, range, .Function, type_str)
		case ^semantics.CDecl_Effect:
			name_str := base.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(
				idx,
				strings.concatenate({name_str, "!"}, context.allocator),
				uri,
				range,
				.Effect,
				"effect type",
			)
			for op in d.operations {
				op_name := base.intern_get(store.interner, op.name)
				op_range := span_to_lsp_range(source, op.span)
				symbol_index_add(idx, op_name, uri, op_range, .Function, "operation")
			}
		case ^semantics.CDecl_Trait:
			name_str := base.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else {
				type_str = "trait"
			}
			symbol_index_add(idx, name_str, uri, range, .Type, type_str)
		case ^semantics.CDecl_Alias:
			name_str := base.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else if d.target != nil {
				type_str = format_type_ann(d.target, store)
			}
			symbol_index_add(idx, name_str, uri, range, .Type, type_str)
		case ^semantics.CDecl_Newtype,
		     ^semantics.CDecl_Import,
		     ^semantics.CDecl_Test,
		     ^semantics.CDecl_Expect:
		}
	}
}

format_type_ann :: proc(type_ann: ^semantics.CType, store: ^semantics.Type_Store) -> string {
	if type_ann == nil {
		return "?"
	}
	switch t in type_ann^ {
	case ^semantics.CType_Primitive:
		return base.intern_get(store.interner, t.name)
	case ^semantics.CType_Function:
		return "function"
	case ^semantics.CType_Record:
		return "record"
	case ^semantics.CType_Tuple:
		return "tuple"
	case ^semantics.CType_Tag_Union:
		return "tag union"
	case ^semantics.CType_Effect_Row:
		return "effect row"
	case ^semantics.CType_Variable:
		return base.intern_get(store.interner, t.name)
	case ^semantics.CType_Applied:
		return base.intern_get(store.interner, t.name)
	case ^semantics.CType_Self:
		return "Self"
	}
	return "?"
}

format_resolved_type :: proc(store: ^semantics.Type_Store, var_id: base.Type_Var_ID) -> string {
	resolved := semantics.resolve_var(store, var_id)
	v := &store.vars[int(resolved)]
	inf, is_inf := v.link.(semantics.Inferred_Type)
	if !is_inf {
		return "?"
	}
	switch v in inf {
	case semantics.Inferred_Primitive:
		return base.intern_get(store.interner, v.primitive_name)
	case semantics.Inferred_Function:
		b: strings.Builder
		strings.builder_init_len_cap(&b, 0, 64)
		for i in 0 ..< len(v.param_ids) {
			if i > 0 do strings.write_string(&b, ", ")
			strings.write_string(&b, format_resolved_type(store, v.param_ids[i]))
		}
		strings.write_string(&b, " -> ")
		strings.write_string(&b, format_resolved_type(store, v.return_id))
		result := strings.to_string(b)
		cloned := strings.clone(result, context.allocator)
		strings.builder_destroy(&b)
		return cloned
	case semantics.Inferred_Constructor:
		return base.intern_get(store.interner, v.primitive_name)
	case semantics.Inferred_Newtype:
		return base.intern_get(store.interner, v.primitive_name)
	case semantics.Inferred_Handle:
		return "Handle"
	case semantics.Inferred_Record_Row:
		return "{ ... }"
	case semantics.Inferred_Tag_Union_Row:
		return "[ ... ]"
	case semantics.Inferred_Effect_Row:
		return "{}"
	case semantics.Inferred_Tuple:
		return "(...)"
	}
	return "?"
}

span_to_lsp_range :: proc(source: string, span: base.Source_Span) -> diagnostics.LSP_Range {
	line, col := diagnostics.diag_span_to_line_col(source, span)
	end_line, end_col := diagnostics.span_end_to_line_col(source, span)
	return diagnostics.LSP_Range {
		start = diagnostics.LSP_Position{line = uint(line - 1), character = uint(col - 1)},
		end = diagnostics.LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)},
	}
}

