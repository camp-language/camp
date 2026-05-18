package lsp

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"

import camp ".."

LSP_Server :: struct {
	store:            Document_Store,
	initialized:      bool,
	shutdown:         bool,
	logger:           log.Logger,
}

server_init :: proc(server: ^LSP_Server, allocator: mem.Allocator) {
	document_store_init(&server.store, allocator)
	server.initialized = false
	server.shutdown = false
	log.logger_init(&server.logger, os.stderr, log.Level.Debug, log.Level.Debug, "camp-lsp")
}

server_destroy :: proc(server: ^LSP_Server) {
	document_store_destroy(&server.store)
}

lsp_main :: proc() -> int {
	server: LSP_Server
	server_init(&server, context.allocator)
	defer server_destroy(&server)

	return server_loop(&server)
}

server_loop :: proc(server: ^LSP_Server) -> int {
	for {
		msg_data, ok := read_message()
		if !ok {
			log.debug(&server.logger, "Failed to read message or stdin closed")
			break
		}

		req, parsed := parse_request(msg_data)
		if !parsed {
			log.debug(&server.logger, "Failed to parse JSON-RPC message")
			continue
		}

		has_id := true
		_, is_null := req.id.(json.Null)
		if is_null {
			has_id = false
		}

		if has_id {
			dispatch_request(server, req)
		} else {
			dispatch_notification(server, req)
		}

		if server.shutdown {
			break
		}
	}

	return 0
}

dispatch_request :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	switch req.method {
	case "initialize":
		handle_initialize(server, req)
	case "initialized":
		server.initialized = true
	case "shutdown":
		response := make_object()
		send_response(req.id, json.Value(response))
		server.shutdown = true
	case "textDocument/definition":
		handle_text_document_definition(server, req)
	case "textDocument/hover":
		handle_text_document_hover(server, req)
	case "textDocument/documentSymbol":
		handle_text_document_symbol(server, req)
	case:
		send_error_response(req.id, LSP_ERROR_UNKNOWN, fmt.tprintf("Unknown method: {}", req.method))
	}
}

dispatch_notification :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	switch req.method {
	case "textDocument/didOpen":
		handle_did_open(&server.store, req.params)
		uri := extract_uri_from_did_open(req.params)
		if uri != "" {
			reanalyze_and_publish(server, uri)
		}
	case "textDocument/didChange":
		handle_did_change(&server.store, req.params)
		uri := extract_uri_from_did(req.params)
		if uri != "" {
			reanalyze_and_publish(server, uri)
		}
	case "textDocument/didClose":
		handle_did_close(&server.store, req.params)
		uri := extract_uri_from_did(req.params)
		if uri != "" {
			notification := publish_diagnostics(&server.store, uri)
			send_notification_message(notification)
		}
	case "exit":
		server.shutdown = true
	case:
	}
}

handle_initialize :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	caps := make_object()

	sync := make_object()
	object_set(&sync, "openClose", make_bool(true))
	object_set(&sync, "change", make_int(1))
	object_set(&sync, "save", make_bool(true))
	object_set(&caps, "textDocumentSync", json.Value(sync))

	object_set(&caps, "hoverProvider", make_bool(true))
	object_set(&caps, "definitionProvider", make_bool(true))
	object_set(&caps, "documentSymbolProvider", make_bool(true))

	result := make_object()
	object_set(&result, "capabilities", json.Value(caps))

	send_response(req.id, json.Value(result))
}

handle_text_document_definition :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	result := handle_definition(&server.store, req.params)
	send_response(req.id, result)
}

handle_text_document_hover :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	result := handle_hover(&server.store, req.params)
	send_response(req.id, result)
}

handle_text_document_symbol :: proc(server: ^LSP_Server, req: JSONRPC_Request) {
	params_obj, ok := req.params.(json.Object)
	if !ok {
		send_response(req.id, json.Value(make_array()))
		return
	}

	td_val, ok := params_obj["textDocument"]
	if !ok {
		send_response(req.id, json.Value(make_array()))
		return
	}
	td_obj, ok := td_val.(json.Object)
	if !ok {
		send_response(req.id, json.Value(make_array()))
		return
	}

	uri_val, ok := td_obj["uri"]
	if !ok {
		send_response(req.id, json.Value(make_array()))
		return
	}
	uri_str, ok := uri_val.(json.String)
	if !ok {
		send_response(req.id, json.Value(make_array()))
		return
	}

	uri := string(uri_str)
	analysis, has_analysis := get_analysis(&server.store, uri)
	if !has_analysis {
		send_response(req.id, json.Value(make_array()))
		return
	}

	symbols_arr := make_array()
	for entry in analysis.symbol_idx.entries {
		sym := make_object()
		object_set(&sym, "name", make_string(entry.name))
		object_set(&sym, "kind", make_int(int(entry.kind)))

		loc := make_object()
		object_set(&loc, "uri", make_string(uri))
		object_set(&loc, "range", lsp_range_to_json(entry.range))
		object_set(&sym, "location", json.Value(loc))

		array_append(&symbols_arr, json.Value(sym))
	}

	send_response(req.id, json.Value(symbols_arr))
}

reanalyze_and_publish :: proc(server: ^LSP_Server, uri: string) {
	doc, ok := get_document(&server.store, uri)
	if !ok {
		return
	}

	analysis := analyze_document(doc, server.store.allocator)
	set_analysis(&server.store, uri, analysis)

	notification := publish_diagnostics(&server.store, uri)
	send_notification_message(notification)
}

send_response :: proc(id: json.Value, result: json.Value) {
	msg := make_response(id, result)
	send_json(msg)
}

send_error_response :: proc(id: json.Value, code: int, message: string) {
	msg := make_error_response(id, code, message)
	send_json(msg)
}

send_notification_message :: proc(notification: json.Value) {
	send_json(notification)
}

send_json :: proc(v: json.Value) {
	str := value_to_string(v)
	write_message(str)
}

extract_uri_from_did_open :: proc(params: json.Value) -> string {
	obj, ok := params.(json.Object)
	if !ok do return ""
	td_val, ok := obj["textDocument"]
	if !ok do return ""
	td_obj, ok := td_val.(json.Object)
	if !ok do return ""
	uri_val, ok := td_obj["uri"]
	if !ok do return ""
	uri_str, ok := uri_val.(json.String)
	if !ok do return ""
	return string(uri_str)
}

extract_uri_from_did :: proc(params: json.Value) -> string {
	obj, ok := params.(json.Object)
	if !ok do return ""
	td_val, ok := obj["textDocument"]
	if !ok do return ""
	td_obj, ok := td_val.(json.Object)
	if !ok do return ""
	uri_val, ok := td_obj["uri"]
	if !ok do return ""
	uri_str, ok := uri_val.(json.String)
	if !ok do return ""
	return string(uri_str)
}
