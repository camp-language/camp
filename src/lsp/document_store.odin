package lsp

import "camp:diagnostics"
import "core:mem"

Document_Analysis :: struct {
	diagnostics:  [dynamic]diagnostics.LSP_Diagnostic,
	symbols:      Symbol_Index,
	parse_ok:     bool,
	typecheck_ok: bool,
}

Open_Document :: struct {
	uri:      string,
	text:     string,
	version:  int,
	analysis: Document_Analysis,
	dirty:    bool,
}

Document_Store :: struct {
	documents: map[string]^Open_Document,
	allocator: mem.Allocator,
}

store_init :: proc(store: ^Document_Store, allocator: mem.Allocator) {
	store.documents = make(map[string]^Open_Document, 16, allocator)
	store.allocator = allocator
}

store_destroy :: proc(store: ^Document_Store) {
	for uri, doc in store.documents {
		destroy_analysis(&doc.analysis)
		delete(doc.text, store.allocator)
		delete(doc.uri, store.allocator)
		free(doc, store.allocator)
	}
	delete(store.documents)
}

store_open :: proc(store: ^Document_Store, uri: string, text: string, version: int) {
	store_close(store, uri)

	doc := new(Open_Document, store.allocator)
	doc.uri = clone_string(uri, store.allocator)
	doc.text = clone_string(text, store.allocator)
	doc.version = version
	doc.dirty = true
	doc.analysis = Document_Analysis{}
	store.documents[uri] = doc
}

store_update :: proc(store: ^Document_Store, uri: string, text: string, version: int) -> bool {
	doc, ok := store.documents[uri]
	if !ok {
		return false
	}
	delete(doc.text, store.allocator)
	doc.text = clone_string(text, store.allocator)
	doc.version = version
	doc.dirty = true
	return true
}

store_close :: proc(store: ^Document_Store, uri: string) {
	doc, ok := store.documents[uri]
	if !ok {
		return
	}
	destroy_analysis(&doc.analysis)
	delete(doc.text, store.allocator)
	delete(doc.uri, store.allocator)
	free(doc, store.allocator)
	delete_key(&store.documents, uri)
}

store_get :: proc(store: ^Document_Store, uri: string) -> ^Open_Document {
	doc, ok := store.documents[uri]
	if !ok {
		return nil
	}
	return doc
}

destroy_analysis :: proc(a: ^Document_Analysis) {
	delete(a.diagnostics)
	destroy_symbol_index(&a.symbols)
}

clone_string :: proc(s: string, allocator: mem.Allocator) -> string {
	if len(s) == 0 {
		return ""
	}
	buf := make([]u8, len(s), allocator)
	copy(buf, transmute([]u8)s)
	return string(buf)
}

