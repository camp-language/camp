package lsp

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "camp:diagnostics"

LSP_Server :: struct {
	transport: Transport,
	doc_store: Document_Store,
	shutdown:  bool,
	running:   bool,
	allocator: mem.Allocator,
}

lsp_main :: proc() {
	server: LSP_Server
	server.allocator = context.allocator
	transport_init(&server.transport, server.allocator)
	store_init(&server.doc_store, server.allocator)
	server.shutdown = false
	server.running = true

	server_loop(&server)
}

server_loop :: proc(server: ^LSP_Server) {
	for server.running {
		msg_raw, ok := read_message(&server.transport)
		if !ok {
			break
		}

		parsed, parse_err := json.parse(msg_raw, .JSON, true, server.allocator)
		delete(msg_raw, server.transport.allocator)
		if parse_err != .None {
			send_error(server, 0, int(JSON_RPC_Error_Code.ParseError), "parse error")
			continue
		}
		// NOTE: json.parse allocates a value tree that is never freed.
		// There is no json.value_destroy in this Odin version, so this leaks.
		// To fix: iterate parsed.Object and free nested values manually.

		method_val, has_method := json_get_string(parsed, "method")
		if !has_method {
			send_error(server, 0, int(JSON_RPC_Error_Code.InvalidRequest), "missing method")
			continue
		}

		id_val, has_id := json_get_int(parsed, "id")
		params_val := json_object_get(parsed, "params")

		if has_id {
			dispatch_request(server, id_val, method_val, params_val)
		} else {
			dispatch_notification(server, method_val, params_val)
		}

		analyze_dirty_documents(server)
	}
}

dispatch_request :: proc(server: ^LSP_Server, id: int, method: string, params: json.Value) {
	switch method {
	case "initialize":
		handle_initialize(server, id, params)
	case "shutdown":
		server.shutdown = true
		send_result(server, id, json.Null{})
	case "textDocument/definition":
		handle_definition(server, id, params)
	case "textDocument/hover":
		handle_hover(server, id, params)
	case:
		send_error(server, id, int(JSON_RPC_Error_Code.MethodNotFound),
			fmt.tprintf("method not found: {}", method))
	}
}

dispatch_notification :: proc(server: ^LSP_Server, method: string, params: json.Value) {
	switch method {
	case "initialized":
		return
	case "textDocument/didOpen":
		handle_did_open(server, params)
	case "textDocument/didChange":
		handle_did_change(server, params)
	case "textDocument/didClose":
		handle_did_close(server, params)
	case "textDocument/didSave":
		handle_did_save(server, params)
	case "exit":
		server.running = false
		if server.shutdown {
			os.exit(0)
		} else {
			os.exit(1)
		}
	case:
		return
	}
}

handle_initialize :: proc(server: ^LSP_Server, id: int, params: json.Value) {
	caps := make(json.Object, 4)
	caps["textDocumentSync"] = json.Integer(1)
	caps["definitionProvider"] = json.Boolean(true)
	caps["hoverProvider"] = json.Boolean(true)

	result_obj := make(json.Object, 1)
	result_obj["capabilities"] = caps

	send_result(server, id, result_obj)
}

handle_did_open :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		return
	}
	text, text_ok := json_get_string(text_doc, "text")
	if !text_ok {
		return
	}
	version, _ := json_get_int(text_doc, "version")

	store_open(&server.doc_store, uri, text, version)
}

handle_did_change :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		return
	}
	version, _ := json_get_int(text_doc, "version")

	changes_val := json_object_get(params, "contentChanges")
	_, is_null := changes_val.(json.Null)
	if is_null {
		return
	}
	changes, changes_ok := changes_val.(json.Array)
	if !changes_ok {
		return
	}

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		return
	}

	new_text := doc.text
	if len(changes) > 0 {
		last_change := changes[len(changes) - 1]
		change_text, ct_ok := json_get_string(last_change, "text")
		if ct_ok {
			new_text = change_text
		}
	}

	store_update(&server.doc_store, uri, new_text, version)
}

handle_did_close :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		return
	}

	publish_diagnostics(server, uri, make([dynamic]diagnostics.LSP_Diagnostic, 0))
	store_close(&server.doc_store, uri)
}

handle_did_save :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, td_ok := json_get_object(params, "textDocument")
	if !td_ok {
		return
	}
	uri, uri_ok := json_get_string(text_doc, "uri")
	if !uri_ok {
		return
	}

	text, has_text := json_get_string(params, "text")
	if has_text {
		store_update(&server.doc_store, uri, text, 0)
	}
}

analyze_dirty_documents :: proc(server: ^LSP_Server) {
	for uri, doc in server.doc_store.documents {
		if !doc.dirty {
			continue
		}
		doc.dirty = false

		file_path := uri_to_file_path(uri)
		analysis := analyze_document(doc.text, file_path, uri, server.allocator)

		destroy_analysis(&doc.analysis)
		doc.analysis = analysis

		publish_diagnostics(server, uri, doc.analysis.diagnostics)
	}
}

uri_to_file_path :: proc(uri: string) -> string {
	path := uri
	if strings.has_prefix(path, "file:///") {
		path = path[7:]
	} else if strings.has_prefix(path, "file://") {
		path = path[7:]
	}
	return url_decode(path)
}

url_decode :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init_none(&b, context.allocator)
	i := 0
	for i < len(s) {
		if s[i] == '%' && i + 2 < len(s) {
			hi := hex_val(s[i + 1])
			lo := hex_val(s[i + 2])
			if hi >= 0 && lo >= 0 {
				strings.write_byte(&b, u8(hi << 4 | lo))
				i += 3
				continue
			}
		}
		strings.write_byte(&b, s[i])
		i += 1
	}
	return strings.to_string(b)
}

hex_val :: proc(ch: u8) -> int {
	switch ch {
	case '0'..='9': return int(ch - '0')
	case 'a'..='f': return int(ch - 'a' + 10)
	case 'A'..='F': return int(ch - 'A' + 10)
	}
	return -1
}

send_response :: proc(server: ^LSP_Server, id: int, result: json.Value, err: ^JSON_RPC_Error) {
	resp := make(json.Object, 3)
	resp["jsonrpc"] = json.String(JSON_RPC_Version)
	resp["id"] = json.Integer(i64(id))
	if result != nil {
		resp["result"] = result
	}
	if err != nil {
		err_obj := make(json.Object, 2)
		err_obj["code"] = json.Integer(i64(err.code))
		err_obj["message"] = json.String(err.message)
		resp["error"] = err_obj
	}
	msg_bytes, marshal_err := json.marshal(resp, allocator = server.allocator)
	if marshal_err != nil {
		fmt.eprintln("lsp: failed to marshal response")
		return
	}
	write_message(&server.transport, string(msg_bytes))
}

send_error :: proc(server: ^LSP_Server, id: int, code: int, message: string) {
	err := new(JSON_RPC_Error)
	err.code = code
	err.message = message
	send_response(server, id, nil, err)
}

send_result :: proc(server: ^LSP_Server, id: int, result: json.Value) {
	send_response(server, id, result, nil)
}

send_notification :: proc(server: ^LSP_Server, method: string, params: json.Value) {
	notif := make(json.Object, 3)
	notif["jsonrpc"] = json.String(JSON_RPC_Version)
	notif["method"] = json.String(method)
	notif["params"] = params
	msg_bytes, err := json.marshal(notif, allocator = server.allocator)
	if err != nil {
		fmt.eprintln("lsp: failed to marshal notification")
		return
	}
	write_message(&server.transport, string(msg_bytes))
}
