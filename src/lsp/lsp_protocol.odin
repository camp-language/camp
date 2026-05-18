package lsp

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import camp ".."

JSON_RPC_VERSION :: "2.0"

JSONRPC_Request :: struct {
	jsonrpc: string,
	id:     json.Value,
	method: string,
	params: json.Value,
}

JSONRPC_Response :: struct {
	jsonrpc: string,
	id:     json.Value,
	result: json.Value,
}

JSONRPC_Error_Response :: struct {
	jsonrpc: string,
	id:     json.Value,
	error:  JSONRPC_Error_Body,
}

JSONRPC_Error_Body :: struct {
	code:    int,
	message: string,
	data:    json.Value,
}

JSONRPC_Notification :: struct {
	jsonrpc: string,
	method:  string,
	params:  json.Value,
}

LSP_Initialize_Params :: struct {
	processId:         json.Value,
	rootUri:           json.Value,
	capabilities:      json.Value,
}

LSP_Initialize_Result :: struct {
	capabilities: LSP_Server_Capabilities,
}

LSP_Server_Capabilities :: struct {
	textDocumentSync:             json.Value,
	completionProvider:           json.Value,
	hoverProvider:                bool,
	definitionProvider:           bool,
	documentSymbolProvider:       bool,
	publishDiagnosticsProvider:   json.Value,
}

LSP_TextDocumentIdentifier :: struct {
	uri: string,
}

LSP_Position :: struct {
	line:      uint,
	character: uint,
}

LSP_TextDocumentPositionParams :: struct {
	textDocument: LSP_TextDocumentIdentifier,
	position:     LSP_Position,
}

LSP_Location :: struct {
	uri:   string,
	range: camp.LSP_Range,
}

LSP_Hover :: struct {
	contents: LSP_MarkupContent,
	range:    camp.LSP_Range,
}

LSP_MarkupContent :: struct {
	kind:  string,
	value: string,
}

LSP_Diagnostic_Params :: struct {
	uri:         string,
	diagnostics: json.Array,
}

LSP_DocumentSymbol_Params :: struct {
	textDocument: LSP_TextDocumentIdentifier,
}

make_null :: proc() -> json.Value {
	return json.Value(json.Null(nil))
}

make_int :: proc(v: int) -> json.Value {
	return json.Value(json.Integer(i64(v)))
}

make_string :: proc(v: string) -> json.Value {
	return json.Value(json.String(v))
}

make_bool :: proc(v: bool) -> json.Value {
	return json.Value(json.Boolean(v))
}

make_object :: proc() -> json.Object {
	return make(json.Object, 8)
}

make_array :: proc() -> json.Array {
	return make(json.Array, 0, 8)
}

object_set :: proc(obj: ^json.Object, key: string, val: json.Value) {
	(obj^)[key] = val
}

array_append :: proc(arr: ^json.Array, val: json.Value) {
	append(arr, val)
}

parse_request :: proc(data: string) -> (JSONRPC_Request, bool) {
	parsed, parse_err := json.parse([]byte(data), .JSON, false, context.allocator)
	if parse_err != .None {
		return JSONRPC_Request{}, false
	}

	obj, ok := parsed.(json.Object)
	if !ok {
		return JSONRPC_Request{}, false
	}

	req: JSONRPC_Request
	req.jsonrpc = "2.0"

	if v, ok := obj["id"]; ok {
		req.id = v
	}

	if v, ok := obj["method"]; ok {
		if s, ok := v.(json.String); ok {
			req.method = s
		}
	}

	if v, ok := obj["params"]; ok {
		req.params = v
	} else {
		req.params = make_null()
	}

	return req, true
}

make_response :: proc(id: json.Value, result: json.Value) -> json.Value {
	obj := make_object()
	object_set(&obj, "jsonrpc", make_string(JSON_RPC_VERSION))
	object_set(&obj, "id", id)
	object_set(&obj, "result", result)
	return json.Value(obj)
}

make_error_response :: proc(id: json.Value, code: int, message: string) -> json.Value {
	obj := make_object()
	object_set(&obj, "jsonrpc", make_string(JSON_RPC_VERSION))
	object_set(&obj, "id", id)

	err_obj := make_object()
	object_set(&err_obj, "code", make_int(code))
	object_set(&err_obj, "message", make_string(message))
	object_set(&obj, "error", json.Value(err_obj))

	return json.Value(obj)
}

make_notification :: proc(method: string, params: json.Value) -> json.Value {
	obj := make_object()
	object_set(&obj, "jsonrpc", make_string(JSON_RPC_VERSION))
	object_set(&obj, "method", make_string(method))
	object_set(&obj, "params", params)
	return json.Value(obj)
}

LSP_ERROR_UNKNOWN :: -32001
LSP_ERROR_INVALID_PARAMS :: -32602
LSP_ERROR_INTERNAL :: -32603

lsp_range_to_json :: proc(r: camp.LSP_Range) -> json.Value {
	obj := make_object()

	start_obj := make_object()
	object_set(&start_obj, "line", make_int(int(r.start.line)))
	object_set(&start_obj, "character", make_int(int(r.start.character)))
	object_set(&obj, "start", json.Value(start_obj))

	end_obj := make_object()
	object_set(&end_obj, "line", make_int(int(r.end.line)))
	object_set(&end_obj, "character", make_int(int(r.end.character)))
	object_set(&obj, "end", json.Value(end_obj))

	return json.Value(obj)
}

lsp_diagnostic_to_json :: proc(d: camp.LSP_Diagnostic) -> json.Value {
	obj := make_object()

	range_obj := lsp_range_to_json(d.range)
	object_set(&obj, "range", range_obj)
	object_set(&obj, "severity", make_int(int(d.severity)))
	object_set(&obj, "message", make_string(d.message))
	object_set(&obj, "source", make_string("camp"))

	if len(d.related) > 0 {
		related_arr := make_array()
		for ri in d.related {
			ri_obj := make_object()
			loc_obj := make_object()
			object_set(&loc_obj, "uri", make_string(""))
			object_set(&loc_obj, "range", lsp_range_to_json(ri.location))
			object_set(&ri_obj, "location", json.Value(loc_obj))
			object_set(&ri_obj, "message", make_string(ri.message))
			array_append(&related_arr, json.Value(ri_obj))
		}
		object_set(&obj, "relatedInformation", json.Value(related_arr))
	}

	return json.Value(obj)
}

value_to_string :: proc(v: json.Value) -> string {
	data, err := json.marshal(v)
	if err != nil {
		return "{}"
	}
	result := string(data)
	delete(data)
	return result
}
