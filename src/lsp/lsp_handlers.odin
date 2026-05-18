package lsp

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import camp ".."

handle_definition :: proc(store: ^Document_Store, params: json.Value) -> json.Value {
	pos_params, ok := parse_text_document_position(params)
	if !ok {
		return make_null()
	}

	analysis, has_analysis := get_analysis(store, pos_params.uri)
	if !has_analysis {
		return make_null()
	}

	idx := find_symbol_at(&analysis.symbol_idx, pos_params.position.line, pos_params.position.character)
	if idx < 0 {
		return make_null()
	}

	entry := analysis.symbol_idx.entries[idx]

	loc := make_object()
	object_set(&loc, "uri", make_string(pos_params.uri))
	object_set(&loc, "range", lsp_range_to_json(entry.range))

	return json.Value(loc)
}

handle_hover :: proc(store: ^Document_Store, params: json.Value) -> json.Value {
	pos_params, ok := parse_text_document_position(params)
	if !ok {
		return make_null()
	}

	analysis, has_analysis := get_analysis(store, pos_params.uri)
	if !has_analysis {
		return make_null()
	}

	idx := find_symbol_at(&analysis.symbol_idx, pos_params.position.line, pos_params.position.character)
	if idx < 0 {
		return make_null()
	}

	entry := analysis.symbol_idx.entries[idx]

	builder: strings.Builder
	strings.builder_init(&builder, 128)

	kind_str := symbol_kind_to_string(entry.kind)
	fmt.sbprintf(&builder, "```camp\n{} : {}\n```", entry.name, entry.type_str)

	hover := make_object()

	contents := make_object()
	object_set(&contents, "kind", make_string("markdown"))
	object_set(&contents, "value", make_string(strings.to_string(builder)))
	strings.builder_destroy(&builder)
	object_set(&hover, "contents", json.Value(contents))

	object_set(&hover, "range", lsp_range_to_json(entry.range))

	return json.Value(hover)
}

publish_diagnostics :: proc(store: ^Document_Store, uri: string) -> json.Value {
	analysis, has_analysis := get_analysis(store, uri)
	if !has_analysis {
		params := make_object()
		object_set(&params, "uri", make_string(uri))
		object_set(&params, "diagnostics", json.Value(make_array()))
		return make_notification("textDocument/publishDiagnostics", json.Value(params))
	}

	diagnostics_arr := make_array()
	for d in analysis.diagnostics {
		array_append(&diagnostics_arr, lsp_diagnostic_to_json(d))
	}

	params := make_object()
	object_set(&params, "uri", make_string(uri))
	object_set(&params, "diagnostics", json.Value(diagnostics_arr))

	return make_notification("textDocument/publishDiagnostics", json.Value(params))
}

Text_Document_Position :: struct {
	uri:      string,
	position: camp.LSP_Position,
}

parse_text_document_position :: proc(params: json.Value) -> (Text_Document_Position, bool) {
	obj, ok := params.(json.Object)
	if !ok {
		return Text_Document_Position{}, false
	}

	td_val, ok := obj["textDocument"]
	if !ok {
		return Text_Document_Position{}, false
	}
	td_obj, ok := td_val.(json.Object)
	if !ok {
		return Text_Document_Position{}, false
	}

	uri_val, ok := td_obj["uri"]
	if !ok {
		return Text_Document_Position{}, false
	}
	uri_str, ok := uri_val.(json.String)
	if !ok {
		return Text_Document_Position{}, false
	}

	pos_val, ok := obj["position"]
	if !ok {
		return Text_Document_Position{}, false
	}
	pos_obj, ok := pos_val.(json.Object)
	if !ok {
		return Text_Document_Position{}, false
	}

	line_val, ok := pos_obj["line"]
	if !ok {
		return Text_Document_Position{}, false
	}
	line_int, ok := line_val.(json.Integer)
	if !ok {
		return Text_Document_Position{}, false
	}

	char_val, ok := pos_obj["character"]
	if !ok {
		return Text_Document_Position{}, false
	}
	char_int, ok := char_val.(json.Integer)
	if !ok {
		return Text_Document_Position{}, false
	}

	return Text_Document_Position{
		uri = string(uri_str),
		position = camp.LSP_Position{line = uint(line_int), character = uint(char_int)},
	}, true
}

position_to_offset :: proc(source: string, line: uint, character: uint) -> int {
	current_line := uint(0)
	offset := 0
	for offset < len(source) {
		if current_line == line {
			return offset + int(character)
		}
		if source[offset] == '\n' {
			current_line += 1
		}
		offset += 1
	}
	return offset
}

identifier_at_offset :: proc(source: string, offset: int) -> string {
	if offset < 0 || offset >= len(source) {
		return ""
	}

	start := offset
	for start > 0 && is_identifier_char(source[start-1]) {
		start -= 1
	}

	end := offset
	for end < len(source) && is_identifier_char(source[end]) {
		end += 1
	}

	if start == end {
		return ""
	}
	return source[start:end]
}

is_identifier_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '!'
}

symbol_kind_to_string :: proc(kind: Symbol_Kind) -> string {
	switch kind {
	case .Constant:   return "constant"
	case .Function:   return "function"
	case .Interface:  return "interface"
	case .Variable:   return "variable"
	case .Class:      return "class"
	case .Method:     return "method"
	case .Property:   return "property"
	case .Field:      return "field"
	case .Enum:       return "enum"
	case .Namespace:  return "namespace"
	case .Module:     return "module"
	case .Package:    return "package"
	case .Constructor: return "constructor"
	case .File:        return "file"
	}
	return "unknown"
}
