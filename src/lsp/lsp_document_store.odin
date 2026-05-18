package lsp

import "core:encoding/json"
import camp ".."

Open_Document :: struct {
	uri:      string,
	version:  int,
	contents: string,
}

Document_Analysis :: struct {
	diagnostics: [dynamic]camp.LSP_Diagnostic,
	symbol_idx:  Symbol_Index,
}

Document_Store :: struct {
	documents:      map[string]Open_Document,
	analyses:       map[string]Document_Analysis,
	allocator:      mem.Allocator,
}

document_store_init :: proc(store: ^Document_Store, allocator: mem.Allocator) {
	store.documents = make(map[string]Open_Document, 16, allocator)
	store.analyses = make(map[string]Document_Analysis, 16, allocator)
	store.allocator = allocator
}

document_store_destroy :: proc(store: ^Document_Store) {
	for uri, analysis in store.analyses {
		delete(analysis.diagnostics)
		symbol_index_destroy(&analysis.symbol_idx)
		delete_key(&store.analyses, uri)
	}
	delete(store.analyses)
	delete(store.documents)
}

handle_did_open :: proc(store: ^Document_Store, params: json.Value) {
	obj, ok := params.(json.Object)
	if !ok do return

	td, ok := obj["textDocument"]
	if !ok do return
	td_obj, ok := td.(json.Object)
	if !ok do return

	uri_val, ok := td_obj["uri"]
	if !ok do return
	uri_str, ok := uri_val.(json.String)
	if !ok do return

	version_val, ok := td_obj["version"]
	if !ok do return
	version_int, ok := version_val.(json.Integer)
	if !ok do return

	text_val, ok := td_obj["text"]
	if !ok do return
	text_str, ok := text_val.(json.String)
	if !ok do return

	doc := Open_Document{
		uri = string(uri_str),
		version = int(version_int),
		contents = string(text_str),
	}
	store.documents[string(uri_str)] = doc
}

handle_did_change :: proc(store: ^Document_Store, params: json.Value) {
	obj, ok := params.(json.Object)
	if !ok do return

	td, ok := obj["textDocument"]
	if !ok do return
	td_obj, ok := td.(json.Object)
	if !ok do return

	uri_val, ok := td_obj["uri"]
	if !ok do return
	uri_str, ok := uri_val.(json.String)
	if !ok do return

	version_val, ok := td_obj["version"]
	if !ok do return
	version_int, ok := version_val.(json.Integer)
	if !ok do return

	changes_val, ok := obj["contentChanges"]
	if !ok do return
	changes_arr, ok := changes_val.(json.Array)
	if !ok do return
	if len(changes_arr) == 0 do return

	last_change, ok := changes_arr[len(changes_arr) - 1].(json.Object)
	if !ok do return

	text_val, ok := last_change["text"]
	if !ok do return
	text_str, ok := text_val.(json.String)
	if !ok do return

	uri := string(uri_str)
	if existing, ok := store.documents[uri]; ok {
		existing.version = int(version_int)
		existing.contents = string(text_str)
		store.documents[uri] = existing
	}
}

handle_did_close :: proc(store: ^Document_Store, params: json.Value) {
	obj, ok := params.(json.Object)
	if !ok do return

	td, ok := obj["textDocument"]
	if !ok do return
	td_obj, ok := td.(json.Object)
	if !ok do return

	uri_val, ok := td_obj["uri"]
	if !ok do return
	uri_str, ok := uri_val.(json.String)
	if !ok do return

	uri := string(uri_str)
	delete_key(&store.documents, uri)

	if analysis, ok := store.analyses[uri]; ok {
		delete(analysis.diagnostics)
		symbol_index_destroy(&analysis.symbol_idx)
		delete_key(&store.analyses, uri)
	}
}

get_document :: proc(store: ^Document_Store, uri: string) -> (Open_Document, bool) {
	if doc, ok := store.documents[uri]; ok {
		return doc, true
	}
	return Open_Document{}, false
}

get_analysis :: proc(store: ^Document_Store, uri: string) -> (Document_Analysis, bool) {
	if a, ok := store.analyses[uri]; ok {
		return a, true
	}
	return Document_Analysis{}, false
}

set_analysis :: proc(store: ^Document_Store, uri: string, analysis: Document_Analysis) {
	if existing, ok := store.analyses[uri]; ok {
		delete(existing.diagnostics)
		symbol_index_destroy(&existing.symbol_idx)
	}
	store.analyses[uri] = analysis
}
