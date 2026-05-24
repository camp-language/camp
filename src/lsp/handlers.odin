package lsp

import "core:encoding/json"
import "core:fmt"
import "camp:diagnostics"

handle_definition :: proc(server: ^LSP_Server, id: int, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing textDocument")
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing uri")
		return
	}
	position, pos_ok := json_get_object(params, "position")
	if !pos_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing position")
		return
	}
	line, line_ok := json_get_int(position, "line")
	if !line_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing line")
		return
	}
	character, char_ok := json_get_int(position, "character")
	if !char_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing character")
		return
	}

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		send_result(server, id, json.Null{})
		return
	}

	offset := position_to_offset(doc.text, line, character)
	if offset < 0 {
		send_result(server, id, json.Null{})
		return
	}

	ident := identifier_at_offset(doc.text, offset)
	if len(ident) == 0 {
		send_result(server, id, json.Null{})
		return
	}

	indices := symbol_index_lookup(&doc.analysis.symbols, ident)
	if len(indices) == 0 {
		send_result(server, id, json.Null{})
		return
	}

	entry := doc.analysis.symbols.entries[indices[0]]

	loc_obj := make(json.Object, 2)
	loc_obj["uri"] = json.String(entry.uri)
	loc_obj["range"] = lsp_range_to_json(entry.range)

	send_result(server, id, loc_obj)
}

handle_hover :: proc(server: ^LSP_Server, id: int, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing textDocument")
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing uri")
		return
	}
	position, pos_ok := json_get_object(params, "position")
	if !pos_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing position")
		return
	}
	line, line_ok := json_get_int(position, "line")
	if !line_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing line")
		return
	}
	character, char_ok := json_get_int(position, "character")
	if !char_ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing character")
		return
	}

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		send_result(server, id, json.Null{})
		return
	}

	offset := position_to_offset(doc.text, line, character)
	if offset < 0 {
		send_result(server, id, json.Null{})
		return
	}

	ident := identifier_at_offset(doc.text, offset)
	if len(ident) == 0 {
		send_result(server, id, json.Null{})
		return
	}

	indices := symbol_index_lookup(&doc.analysis.symbols, ident)
	if len(indices) == 0 {
		send_result(server, id, json.Null{})
		return
	}

	entry := doc.analysis.symbols.entries[indices[0]]

	kind_str := symbol_kind_to_string(entry.kind)
	hover_text := fmt.tprintf("{} {}: {}", kind_str, entry.name, entry.type_str)

	contents_obj := make(json.Object, 2)
	contents_obj["kind"] = json.String("plaintext")
	contents_obj["value"] = json.String(hover_text)

	hover_obj := make(json.Object, 2)
	hover_obj["contents"] = contents_obj
	hover_obj["range"] = lsp_range_to_json(entry.range)

	send_result(server, id, hover_obj)
}

publish_diagnostics :: proc(server: ^LSP_Server, uri: string, diagnostics: [dynamic]diagnostics.LSP_Diagnostic) {
	diag_array := make(json.Array, 0, len(diagnostics))

	for d in diagnostics {
		severity, sev_ok := lsp_severity_to_int(d.severity)
		if !sev_ok {
			continue
		}
		diag_obj := make(json.Object, 4)
		diag_obj["range"] = lsp_range_to_json(d.range)
		diag_obj["severity"] = json.Integer(i64(severity))
		diag_obj["message"] = json.String(d.message)
		diag_obj["source"] = json.String("camp")
		append(&diag_array, diag_obj)
	}

	params_obj := make(json.Object, 2)
	params_obj["uri"] = json.String(uri)
	params_obj["diagnostics"] = diag_array

	send_notification(server, "textDocument/publishDiagnostics", params_obj)
}

position_to_offset :: proc(text: string, line: int, character: int) -> int {
	current_line := 0
	current_col := 0
	for i in 0..<len(text) {
		if current_line == line && current_col == character {
			return i
		}
		if text[i] == '\n' {
			current_line += 1
			current_col = 0
		} else {
			current_col += 1
		}
	}
	if current_line == line && current_col == character {
		return len(text)
	}
	return -1
}

identifier_at_offset :: proc(text: string, offset: int) -> string {
	if offset < 0 || offset >= len(text) {
		return ""
	}
	if !is_ident_char(text[offset]) {
		return ""
	}
	start := offset
	for start > 0 && is_ident_char(text[start - 1]) {
		start -= 1
	}
	end := offset
	for end < len(text) && is_ident_char(text[end]) {
		end += 1
	}
	return text[start:end]
}

is_ident_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') || c == '_' || c == '!'
}

symbol_kind_to_string :: proc(kind: Symbol_Kind) -> string {
	switch kind {
	case .Function:  return "function"
	case .Type:      return "type"
	case .Effect:    return "effect type"
	case .Parameter: return "parameter"
	case .Local:     return "local"
	case:            return "unknown"
	}
}

lsp_severity_to_int :: proc(s: diagnostics.LSP_DiagnosticSeverity) -> (int, bool) {
	switch s {
	case .Error:       return 1, true
	case .Warning:     return 2, true
	case .Information: return 3, true
	case .Hint:        return 4, true
	case:              return 0, false
	}
}

lsp_range_to_json :: proc(r: diagnostics.LSP_Range) -> json.Value {
	start_obj := make(json.Object, 2)
	start_obj["line"] = json.Integer(i64(r.start.line))
	start_obj["character"] = json.Integer(i64(r.start.character))

	end_obj := make(json.Object, 2)
	end_obj["line"] = json.Integer(i64(r.end.line))
	end_obj["character"] = json.Integer(i64(r.end.character))

	obj := make(json.Object, 2)
	obj["start"] = start_obj
	obj["end"] = end_obj

	return obj
}

json_object_get :: proc(v: json.Value, key: string) -> json.Value {
	obj, obj_ok := v.(json.Object)
	if !obj_ok {
		return json.Null{}
	}
	val, val_ok := obj[key]
	if !val_ok {
		return json.Null{}
	}
	return val
}

json_get_object :: proc(v: json.Value, key: string) -> (json.Value, bool) {
	val := json_object_get(v, key)
	_, is_null := val.(json.Null)
	if is_null {
		return json.Null{}, false
	}
	return val, true
}

json_get_string :: proc(v: json.Value, key: string) -> (string, bool) {
	obj, obj_ok := v.(json.Object)
	if !obj_ok {
		return "", false
	}
	val, val_ok := obj[key]
	if !val_ok {
		return "", false
	}
	str_val, str_ok := val.(json.String)
	if !str_ok {
		return "", false
	}
	return string(str_val), true
}

json_get_int :: proc(v: json.Value, key: string) -> (int, bool) {
	obj, obj_ok := v.(json.Object)
	if !obj_ok {
		return 0, false
	}
	val, val_ok := obj[key]
	if !val_ok {
		return 0, false
	}
	int_val, int_ok := val.(json.Integer)
	if !int_ok {
		return 0, false
	}
	return int(int_val), true
}
