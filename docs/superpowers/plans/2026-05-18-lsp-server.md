# LSP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Language Server Protocol server for Camp, available via `camp lsp`, providing diagnostics, go-to-definition, and hover. The server embeds Camp's compiler pipeline in-process.

**Architecture:** Four-layer design — transport (stdio JSON-RPC), protocol (LSP message types), server state (document store + event loop), analysis (reuses Camp pipeline). Builds on the diagnostic framework's `LSP_Diagnostic` type and `lsp_from_diagnostic` mapping. Full re-parse on change, multi-file document store, table-based symbol index.

**Tech Stack:** Odin, `core:encoding/json`, `core:os`, `core:fmt`, `core:strings`, `core:mem`

**Prerequisite:** Diagnostic framework must be fully implemented first (provides `LSP_Diagnostic`, `lsp_from_diagnostic`, `span_to_line_col`, `span_end_to_line_col`).

**Spec:** `docs/superpowers/specs/2026-05-18-lsp-server-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/lsp/lsp_transport.odin` | Create | JSON-RPC reader/writer over stdio, `Content-Length` framing |
| `src/lsp/lsp_protocol.odin` | Create | JSON-RPC 2.0 types, LSP message types, unmarshal/marshal helpers |
| `src/lsp/lsp_document_store.odin` | Create | `Document_Store`, `Open_Document`, document lifecycle |
| `src/lsp/lsp_symbol_index.odin` | Create | `Symbol_Index`, `Symbol_Entry`, `Symbol_Kind`, index building |
| `src/lsp/lsp_analysis.odin` | Create | `analyze_document`, `Document_Analysis`, runs compiler pipeline |
| `src/lsp/lsp_handlers.odin` | Create | Feature handlers: definition, hover, diagnostics publishing |
| `src/lsp/lsp.odin` | Create | `LSP_Server`, event loop, `lsp_main`, init/shutdown |
| `src/main.odin` | Modify | Add `Lsp` to `CLI_Command`, dispatch to `lsp_main` |
| `src/cli.odin` | Modify | Add `"lsp"` to `parse_command` |

---

### Task 1: JSON-RPC Transport

**Files:**
- Create: `src/lsp/lsp_transport.odin`

- [ ] **Step 1: Create `src/lsp/` directory and `src/lsp/lsp_transport.odin`**

```odin
package lsp

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

Transport :: struct {
	allocator: mem.Allocator,
}

transport_init :: proc(t: ^Transport, allocator: mem.Allocator) {
	t.allocator = allocator
}

read_message :: proc(t: ^Transport) -> (string, bool) {
	header_buf: [256]u8
	header_len := 0
	content_length := -1

	for {
		b: u8
		n, err := os.read(os.stdin, []u8{b})[:1]
		if n == 0 || err != nil {
			return "", false
		}
		header_buf[header_len] = b
		header_len += 1

		if header_len >= 4 &&
			header_buf[header_len-4] == '\r' &&
			header_buf[header_len-3] == '\n' &&
			header_buf[header_len-2] == '\r' &&
			header_buf[header_len-1] == '\n' {
			break
		}

		if header_len >= len(header_buf) - 1 {
			fmt.eprintln("lsp: header too long")
			return "", false
		}
	}

	header_str := string(header_buf[:header_len])
	prefix := "Content-Length: "
	start := -1
	for i in 0..<=len(header_str) - len(prefix) {
		match: for j in 0..<len(prefix) {
			if header_str[i+j] != prefix[j] {
				continue match
			}
		}
		start = i + len(prefix)
		break
	}

	if start == -1 {
		fmt.eprintln("lsp: missing Content-Length header")
		return "", false
	}

	num_start := start
	num_end := num_start
	for num_end < len(header_str) && header_str[num_end] != '\r' {
		num_end += 1
	}
	num_str := header_str[num_start:num_end]
	ok: bool
	content_length, ok = strconv_parse_int(num_str)
	if !ok || content_length <= 0 {
		fmt.eprintln("lsp: invalid Content-Length")
		return "", false
	}

	body_buf := make([]u8, content_length, t.allocator)
	defer delete(body_buf, t.allocator)

	total_read := 0
	for total_read < content_length {
		n, err := os.read(os.stdin, body_buf[total_read:])
		if n == 0 || err != nil {
			return "", false
		}
		total_read += n
	}

	return string(body_buf[:total_read]), true
}

write_message :: proc(t: ^Transport, message: string) -> bool {
	header := fmt.tprintf("Content-Length: {}\r\n\r\n", len(message))
	n, err := os.write(os.stdout, transmute([]byte)header)
	if err != nil {
		return false
	}
	n, err = os.write(os.stdout, transmute([]byte)message)
	if err != nil {
		return false
	}
	os.flush(os.stdout)
	return true
}

strconv_parse_int :: proc(s: string) -> (int, bool) {
	if len(s) == 0 {
		return 0, false
	}
	result := 0
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		result = result * 10 + int(c - '0')
	}
	return result, true
}
```

- [ ] **Step 2: Verify it compiles**

Run: `odin build src/lsp -out:camp-lsp-test 2>&1 | head -20`

Note: This will fail because `src/lsp/` has no `main` proc yet. Instead, check syntax by creating a minimal test main. For now, just verify the file has no obvious syntax errors by attempting the build and checking that errors are about missing `main`, not syntax.

- [ ] **Step 3: Commit**

```bash
git add src/lsp/lsp_transport.odin
git commit -m "feat(lsp): add JSON-RPC transport layer"
```

---

### Task 2: LSP Protocol Types

**Files:**
- Create: `src/lsp/lsp_protocol.odin`

- [ ] **Step 1: Create `src/lsp/lsp_protocol.odin`**

```odin
package lsp

import "core:encoding/json"
import camp ".."

JSON_RPC_Version :: "2.0"

JSON_RPC_Error_Code :: enum int {
	ParseError     = -32700,
	InvalidRequest = -32600,
	MethodNotFound = -32601,
	InvalidParams  = -32602,
	InternalError  = -32603,
}

JSON_RPC_Error :: struct {
	code:    int,
	message: string,
	data:    json.Value,
}

JSON_RPC_Request :: struct {
	jsonrpc: string `json:"jsonrpc"`,
	id:      int    `json:"id"`,
	method:  string `json:"method"`,
	params:  json.Value `json:"params"`,
}

JSON_RPC_Response :: struct {
	jsonrpc: string       `json:"jsonrpc"`,
	id:      int          `json:"id"`,
	result:  json.Value   `json:"result,omitempty"`,
	error:   JSON_RPC_Error `json:"error,omitempty"`,
}

JSON_RPC_Notification :: struct {
	jsonrpc: string     `json:"jsonrpc"`,
	method:  string     `json:"method"`,
	params:  json.Value `json:"params"`,
}

LSP_Position :: camp.LSP_Position
LSP_Range :: camp.LSP_Range
LSP_Diagnostic :: camp.LSP_Diagnostic
LSP_DiagnosticSeverity :: camp.LSP_DiagnosticSeverity

LSP_Location :: struct {
	uri:  string   `json:"uri"`,
	range: LSP_Range `json:"range"`,
}

LSP_TextDocumentIdentifier :: struct {
	uri: string `json:"uri"`,
}

LSP_VersionedTextDocumentIdentifier :: struct {
	uri:     string `json:"uri"`,
	version: int    `json:"version"`,
}

LSP_TextDocumentItem :: struct {
	uri:        string `json:"uri"`,
	languageId: string `json:"languageId"`,
	version:    int    `json:"version"`,
	text:       string `json:"text"`,
}

LSP_TextDocumentContentChangeEvent :: struct {
	range:       LSP_Range `json:"range,omitempty"`,
	rangeLength: int       `json:"rangeLength,omitempty"`,
	text:        string    `json:"text"`,
}

LSP_MarkupKind :: enum {
	PlainText,
	Markdown,
}

LSP_MarkupContent :: struct {
	kind:  string `json:"kind"`,
	value: string `json:"value"`,
}

LSP_Hover :: struct {
	contents: LSP_MarkupContent `json:"contents"`,
	range:    LSP_Range         `json:"range,omitempty"`,
}

LSP_TextDocumentPositionParams :: struct {
	textDocument: LSP_TextDocumentIdentifier `json:"textDocument"`,
	position:     LSP_Position              `json:"position"`,
}

LSP_ServerCapabilities :: struct {
	textDocumentSync:  int  `json:"textDocumentSync"`,
	definitionProvider: bool `json:"definitionProvider"`,
	hoverProvider:     bool `json:"hoverProvider"`,
}

LSP_InitializeResult :: struct {
	capabilities: LSP_ServerCapabilities `json:"capabilities"`,
}

make_error_response :: proc(id: int, code: int, message: string) -> JSON_RPC_Response {
	return JSON_RPC_Response{
		jsonrpc = JSON_RPC_Version,
		id = id,
		error = JSON_RPC_Error{code = code, message = message},
	}
}

make_result_response :: proc(id: int, result: json.Value) -> JSON_RPC_Response {
	return JSON_RPC_Response{
		jsonrpc = JSON_RPC_Version,
		id = id,
		result = result,
	}
}

make_notification :: proc(method: string, params: json.Value) -> JSON_RPC_Notification {
	return JSON_RPC_Notification{
		jsonrpc = JSON_RPC_Version,
		method = method,
		params = params,
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp_protocol.odin
git commit -m "feat(lsp): add LSP protocol types and JSON-RPC helpers"
```

---

### Task 3: Document Store

**Files:**
- Create: `src/lsp/lsp_document_store.odin`

- [ ] **Step 1: Create `src/lsp/lsp_document_store.odin`**

```odin
package lsp

import "core:mem"

Document_Analysis :: struct {
	diagnostics: [dynamic]camp.LSP_Diagnostic,
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
	store.documents = make(map[string]^Open_Document, 16)
	store.allocator = allocator
}

store_destroy :: proc(store: ^Document_Store) {
	for uri, doc in store.documents {
		destroy_analysis(&doc.analysis)
		delete(doc.text, store.allocator)
		delete(doc.uri, store.allocator)
		destroy_document(doc)
	}
	delete(store.documents)
}

store_open :: proc(store: ^Document_Store, uri: string, text: string, version: int) {
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
	destroy_document(doc)
	delete(store.documents, uri)
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

destroy_document :: proc(doc: ^Open_Document) {
	free(doc)
}

clone_string :: proc(s: string, allocator: mem.Allocator) -> string {
	if len(s) == 0 {
		return ""
	}
	buf := make([]u8, len(s), allocator)
	copy(buf, transmute([]u8)s)
	return string(buf)
}
```

Note: `destroy_symbol_index` is defined in `lsp_symbol_index.odin` (Task 4). The import of `camp` is needed for `camp.LSP_Diagnostic`. This file will not compile until Task 4 is complete — that is expected.

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp_document_store.odin
git commit -m "feat(lsp): add document store for tracking open documents"
```

---

### Task 4: Symbol Index

**Files:**
- Create: `src/lsp/lsp_symbol_index.odin`

- [ ] **Step 1: Create `src/lsp/lsp_symbol_index.odin`**

```odin
package lsp

import camp ".."
import "core:mem"

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
	range:    camp.LSP_Range,
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
	delete(idx.by_name)
}

symbol_index_add :: proc(idx: ^Symbol_Index, name: string, uri: string, range: camp.LSP_Range, kind: Symbol_Kind, type_str: string) {
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
		idx.by_name[name] = []int{entry_index}
	} else {
		new_indices := make([]int, len(indices) + 1)
		copy(new_indices, indices)
		new_indices[len(indices)] = entry_index
		idx.by_name[name] = new_indices
	}
}

symbol_index_lookup :: proc(idx: ^Symbol_Index, name: string) -> []int {
	indices, ok := idx.by_name[name]
	if !ok {
		return nil
	}
	return indices
}

build_symbol_index :: proc(idx: ^Symbol_Index, file: ^camp.CFile, uri: string, source: string, store: ^camp.Type_Store) {
	for decl in file.decls {
		switch d in decl {
		case ^camp.CDecl_Const:
			name_str := camp.intern_get(store.interner, d.name.name)
			kind := Symbol_Kind.Function
			type_str := format_type_var(store, camp.Type_Var_ID(-1))

			type_result, type_found := store.bindings[d.name.name]
			if type_found {
				type_str = format_type_var(store, type_result)
			}

			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, kind, type_str)

		case ^camp.CDecl_Effect:
			name_str := camp.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Effect, "effect")

			for op in d.operations {
				op_name := camp.intern_get(store.interner, op.name)
				op_range := span_to_lsp_range(source, op.span)
				symbol_index_add(idx, op_name, uri, op_range, .Function, "operation")
			}

		case ^camp.CDecl_Trait:
			name_str := camp.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Type, "trait")

		case ^camp.CDecl_Alias:
			name_str := camp.intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Type, "type alias")
		case:
		}
	}
}

format_type_var :: proc(store: ^camp.Type_Store, id: camp.Type_Var_ID) -> string {
	if int(id) < 0 || int(id) >= len(store.vars) {
		return "?"
	}
	rid := camp.resolve_var(store, id)
	rv := camp.get_var(store, rid)
	switch kind in rv.link {
	case camp.Inferred_Type:
		switch kind.tag {
		case .Primitive:
			return camp.intern_get(store.interner, kind.primitive_name)
		case .Function:
			return fmt_tprintf("({} params) -> {}", len(kind.param_ids),
				format_type_var(store, kind.return_id))
		case .Record_Row:
			return "record"
		case .Tag_Union_Row:
			return "tag union"
		case .Effect_Row:
			effect_names: [dynamic]string
			for en in kind.effect_names {
				append(&effect_names, camp.intern_get(store.interner, en))
			}
			return fmt_tprintf("effect row")
		case:
			return "?"
		}
	case:
	}
	return "?"
}

fmt_tprintf :: proc(format: string, args: ..any) -> string {
	return fmt.tprintf(format, ..args)
}

span_to_lsp_range :: proc(source: string, span: camp.Source_Span) -> camp.LSP_Range {
	line, col := camp.diag_span_to_line_col(source, span)
	end_line, end_col := camp.span_end_to_line_col(source, span)
	return camp.LSP_Range{
		start = camp.LSP_Position{line = uint(line - 1), character = uint(col - 1)},
		end   = camp.LSP_Position{line = uint(end_line - 1), character = uint(end_col - 1)},
	}
}
```

Note: The implementer must verify that `Type_Store.bindings` is accessible from outside `src/typecheck.odin`. If `bindings` is a field of `Type_Env` (not `Type_Store`), the `build_symbol_index` function needs a `^Type_Env` parameter instead. Read `src/typecheck.odin` to confirm the correct type. The current code shows `Type_Env.bindings` holds the name-to-var mapping, so `build_symbol_index` likely needs both `Type_Store` and `Type_Env` — or the typecheck result needs to carry the env's bindings forward. The implementer should check how `typecheck_file` exposes its results and adjust accordingly.

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp_symbol_index.odin
git commit -m "feat(lsp): add symbol index for go-to-definition and hover"
```

---

### Task 5: Analysis

**Files:**
- Create: `src/lsp/lsp_analysis.odin`

- [ ] **Step 1: Create `src/lsp/lsp_analysis.odin`**

```odin
package lsp

import camp ".."
import "core:encoding/json"
import "core:fmt"
import "core:mem"

analyze_document :: proc(text: string, file_path: string, uri: string, allocator: mem.Allocator) -> Document_Analysis {
	result: Document_Analysis
	result.diagnostics = make([dynamic]camp.LSP_Diagnostic, 0, 16)
	symbol_index_init(&result.symbols)
	result.parse_ok = false
	result.typecheck_ok = false

	ctx: camp.Compilation_Context
	camp.context_init(&ctx)
	defer camp.context_destroy(&ctx)

	source := text
	file_rec := camp.Source_File{path = file_path, contents = source, id = 0}

	lexer: camp.Lexer
	camp.lexer_init(&lexer, file_rec, &ctx.collector, &ctx.interner)

	old_allocator := context.allocator
	context.allocator = ctx.allocator
	parser: camp.Parser
	camp.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	ast_file := camp.parser_parse_file(&parser)
	context.allocator = old_allocator

	if camp.diag_collector_has_errors(&ctx.collector) {
		for d in ctx.collector.diagnostics {
			lsp_diag := camp.lsp_from_diagnostic(d, source)
			append(&result.diagnostics, lsp_diag)
		}
		return result
	}

	result.parse_ok = true

	context.allocator = ctx.allocator
	canon := camp.canonicalize(ast_file, &ctx)
	context.allocator = old_allocator

	context.allocator = ctx.allocator
	store: camp.Type_Store
	camp.type_store_init(&store, &ctx.interner, &ctx.collector)
	camp.typecheck_file(canon, &store)
	context.allocator = old_allocator

	for d in ctx.collector.diagnostics {
		lsp_diag := camp.lsp_from_diagnostic(d, source)
		append(&result.diagnostics, lsp_diag)
	}

	if camp.diag_collector_has_errors(&ctx.collector) {
		defer camp.type_store_destroy(&store)
		return result
	}

	result.typecheck_ok = true

	build_symbol_index(&result.symbols, canon, uri, source, &store)

	camp.type_store_destroy(&store)

	return result
}
```

Note: The `canonicalize` and `typecheck_file` functions are called with `context.allocator` swapped — this matches the pattern in `src/cli.odin`. The implementer must verify that `camp.canonicalize` returns `^CFile` or `CFile` — adjust the `build_symbol_index` call accordingly (it currently assumes `CFile` value or takes a pointer).

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp_analysis.odin
git commit -m "feat(lsp): add document analysis using embedded compiler pipeline"
```

---

### Task 6: Feature Handlers

**Files:**
- Create: `src/lsp/lsp_handlers.odin`

- [ ] **Step 1: Create `src/lsp/lsp_handlers.odin`**

```odin
package lsp

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

handle_definition :: proc(server: ^LSP_Server, id: int, params: json.Value) {
	text_doc, ok := json_get_object(params, "textDocument")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing textDocument")
		return
	}
	uri, ok := json_get_string(text_doc, "uri")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing uri")
		return
	}
	position, ok := json_get_object(params, "position")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing position")
		return
	}
	line, _ := json_get_int(position, "line")
	character, _ := json_get_int(position, "character")

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		send_result(server, id, json.Null{})
		return
	}

	offset := position_to_offset(doc.text, int(line), int(character))
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

	loc_obj: json.Value
	loc_obj = json.Object{
		"uri"  = json.String{value = entry.uri},
		"range" = lsp_range_to_json(entry.range),
	}

	send_result(server, id, loc_obj)
}

handle_hover :: proc(server: ^LSP_Server, id: int, params: json.Value) {
	text_doc, ok := json_get_object(params, "textDocument")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing textDocument")
		return
	}
	uri, ok := json_get_string(text_doc, "uri")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing uri")
		return
	}
	position, ok := json_get_object(params, "position")
	if !ok {
		send_error(server, id, int(JSON_RPC_Error_Code.InvalidParams), "missing position")
		return
	}
	line, _ := json_get_int(position, "line")
	character, _ := json_get_int(position, "character")

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		send_result(server, id, json.Null{})
		return
	}

	offset := position_to_offset(doc.text, int(line), int(character))
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

	hover_obj: json.Value
	hover_obj = json.Object{
		"contents" = json.Object{
			"kind"  = json.String{value = "plaintext"},
			"value" = json.String{value = hover_text},
		},
		"range" = lsp_range_to_json(entry.range),
	}

	send_result(server, id, hover_obj)
}

publish_diagnostics :: proc(server: ^LSP_Server, uri: string, diagnostics: [dynamic]camp.LSP_Diagnostic) {
	diag_array: json.Value
	diag_array = json.Array{}

	for d in diagnostics {
		severity, ok := lsp_severity_to_int(d.severity)
		if !ok {
			continue
		}
		diag_obj: json.Value
		diag_obj = json.Object{
			"range"    = lsp_range_to_json(d.range),
			"severity" = json.Integer{value = severity},
			"message"  = json.String{value = d.message},
			"source"   = json.String{value = "camp"},
		}
		json.array_append(&diag_array.(json.Array), diag_obj)
	}

	notification := make_notification(
		"textDocument/publishDiagnostics",
		json.Object{
			"uri"        = json.String{value = uri},
			"diagnostics" = diag_array,
		},
	)

	send_notification(server, notification)
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
	case .Effect:    return "effect"
	case .Parameter: return "parameter"
	case .Local:     return "local"
	case:            return "unknown"
	}
}

lsp_severity_to_int :: proc(s: camp.LSP_DiagnosticSeverity) -> (int, bool) {
	switch s {
	case .Error:       return 1, true
	case .Warning:     return 2, true
	case .Information: return 3, true
	case .Hint:        return 4, true
	case:              return 0, false
	}
}

lsp_range_to_json :: proc(r: camp.LSP_Range) -> json.Value {
	return json.Object{
		"start" = json.Object{
			"line"      = json.Integer{value = int(r.start.line)},
			"character" = json.Integer{value = int(r.start.character)},
		},
		"end" = json.Object{
			"line"      = json.Integer{value = int(r.end.line)},
			"character" = json.Integer{value = int(r.end.character)},
		},
	}
}

json_object_get :: proc(v: json.Value, key: string) -> json.Value {
	obj, ok := v.(json.Object)
	if !ok {
		return nil
	}
	val, ok := obj[key]
	if !ok {
		return nil
	}
	return val
}

json_get_object :: proc(v: json.Value, key: string) -> (json.Value, bool) {
	val := json_object_get(v, key)
	if val == nil {
		return nil, false
	}
	return val, true
}

json_get_string :: proc(v: json.Value, key: string) -> (string, bool) {
	obj, ok := v.(json.Object)
	if !ok {
		return "", false
	}
	val, ok := obj[key]
	if !ok {
		return "", false
	}
	str_val, ok := val.(json.String)
	if !ok {
		return "", false
	}
	return str_val.value, true
}

json_get_int :: proc(v: json.Value, key: string) -> (int, bool) {
	obj, ok := v.(json.Object)
	if !ok {
		return 0, false
	}
	val, ok := obj[key]
	if !ok {
		return 0, false
	}
	int_val, ok := val.(json.Integer)
	if !ok {
		return 0, false
	}
	return int_val.value, true
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp_handlers.odin
git commit -m "feat(lsp): add feature handlers for definition, hover, diagnostics"
```

---

### Task 7: Server and Event Loop

**Files:**
- Create: `src/lsp/lsp.odin`

- [ ] **Step 1: Create `src/lsp/lsp.odin`**

```odin
package lsp

import camp ".."
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

LSP_Server :: struct {
	transport:   Transport,
	doc_store:   Document_Store,
	shutdown:    bool,
	running:     bool,
	allocator:   mem.Allocator,
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
		msg_bytes, ok := read_message(&server.transport)
		if !ok {
			break
		}

		var parsed: json.Value
		parsed, parse_err := json.parse(transmute([]byte)msg_bytes, server.allocator)
		if parse_err != nil {
			err_resp := make_error_response(0, int(JSON_RPC_Error_Code.ParseError), "parse error")
			send_response(server, err_resp)
			continue
		}

		method_val, has_method := json_get_string(parsed, "method")
		if !has_method {
			err_resp := make_error_response(0, int(JSON_RPC_Error_Code.InvalidRequest), "missing method")
			send_response(server, err_resp)
			continue
		}

		id_val, has_id := json_get_int(parsed, "id")

		if has_id {
			dispatch_request(server, id_val, method_val, parsed)
		} else {
			dispatch_notification(server, method_val, parsed)
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
		send_result(server, id, json.Object{})
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
	result := LSP_InitializeResult{
		capabilities = LSP_ServerCapabilities{
			textDocumentSync  = 1,
			definitionProvider = true,
			hoverProvider      = true,
		},
	}

	result_bytes, err := json.marshal(result, allocator = server.allocator)
	if err != nil {
		send_error(server, id, int(JSON_RPC_Error_Code.InternalError), "marshal error")
		return
	}

	var result_val: json.Value
	result_val, parse_err := json.parse(result_bytes, server.allocator)
	if parse_err != nil {
		send_error(server, id, int(JSON_RPC_Error_Code.InternalError), "marshal error")
		return
	}

	resp := make_result_response(id, result_val)
	send_response(server, resp)
}

handle_did_open :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, ok := json_get_object(params, "textDocument")
	if !ok {
		return
	}
	uri, ok := json_get_string(text_doc, "uri")
	if !ok {
		return
	}
	text, ok := json_get_string(text_doc, "text")
	if !ok {
		return
	}
	version, _ := json_get_int(text_doc, "version")

	store_open(&server.doc_store, uri, text, version)
}

handle_did_change :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, ok := json_get_object(params, "textDocument")
	if !ok {
		return
	}
	uri, ok := json_get_string(text_doc, "uri")
	if !ok {
		return
	}
	version, _ := json_get_int(text_doc, "version")

	changes_val := json_object_get(params, "contentChanges")
	if changes_val == nil {
		return
	}
	changes, ok := changes_val.(json.Array)
	if !ok {
		return
	}

	doc := store_get(&server.doc_store, uri)
	if doc == nil {
		return
	}

	new_text := doc.text
	if len(changes) > 0 {
		last_change := changes[len(changes) - 1]
		change_text, ok := json_get_string(last_change, "text")
		if ok {
			new_text = change_text
		}
	}

	store_update(&server.doc_store, uri, new_text, version)
}

handle_did_close :: proc(server: ^LSP_Server, params: json.Value) {
	text_doc, ok := json_get_object(params, "textDocument")
	if !ok {
		return
	}
	uri, ok := json_get_string(text_doc, "uri")
	if !ok {
		return
	}

	publish_diagnostics(server, uri, make([dynamic]camp.LSP_Diagnostic, 0))
	store_close(&server.doc_store, uri)
}

analyze_dirty_documents :: proc(server: ^LSP_Server) {
	for uri, doc in server.doc_store {
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
	if len(uri) > 7 && uri[:7] == "file://" {
		return uri[7:]
	}
	return uri
}

send_response :: proc(server: ^LSP_Server, resp: JSON_RPC_Response) {
	msg_bytes, err := json.marshal(resp, allocator = server.allocator)
	if err != nil {
		fmt.eprintln("lsp: failed to marshal response")
		return
	}
	write_message(&server.transport, string(msg_bytes))
}

send_error :: proc(server: ^LSP_Server, id: int, code: int, message: string) {
	resp := make_error_response(id, code, message)
	send_response(server, resp)
}

send_result :: proc(server: ^LSP_Server, id: int, result: json.Value) {
	resp := make_result_response(id, result)
	send_response(server, resp)
}

send_notification :: proc(server: ^LSP_Server, notif: JSON_RPC_Notification) {
	msg_bytes, err := json.marshal(notif, allocator = server.allocator)
	if err != nil {
		fmt.eprintln("lsp: failed to marshal notification")
		return
	}
	write_message(&server.transport, string(msg_bytes))
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lsp/lsp.odin
git commit -m "feat(lsp): add LSP server with event loop and message dispatch"
```

---

### Task 8: CLI Integration

**Files:**
- Modify: `src/cli.odin`
- Modify: `src/main.odin`

- [ ] **Step 1: Add `Lsp` to `CLI_Command` and `parse_command` in `src/cli.odin`**

In `src/cli.odin`, add `Lsp` to the `CLI_Command` enum:

```odin
CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
	Lsp,
}
```

Add `"lsp"` case to `parse_command`:

```odin
parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build": return .Build, true
	case "test":  return .Test, true
	case "fmt":   return .Fmt, true
	case "check": return .Check, true
	case "lsp":   return .Lsp, true
	case:         return .Build, false
	}
}
```

- [ ] **Step 2: Add `Lsp` dispatch in `src/main.odin`**

Add the import and dispatch case:

```odin
import "core:fmt"
import "core:os"
import lsp "../lsp"
```

Add the case in the switch:

```odin
	switch cmd {
	case .Build: run_build(remaining_args)
	case .Test:  fmt.println("TODO: camp test")
	case .Fmt:   fmt.println("TODO: camp fmt")
	case .Check: fmt.println("TODO: camp check")
	case .Lsp:   lsp.lsp_main()
	}
```

- [ ] **Step 3: Update usage string in `src/main.odin`**

Change the usage line to include `lsp`:

```odin
		fmt.println("Commands: build, test, fmt, check, lsp")
```

- [ ] **Step 4: Verify it compiles**

Run: `odin build src -out:camp 2>&1 | head -30`

This is the first full compilation test. Expect some type mismatches or missing imports. Fix them iteratively. Key things to check:
- `src/lsp/` imports of `camp ".."` resolve correctly
- JSON marshaling of LSP types works with Odin's `core:encoding/json`
- All cross-file references match actual type names and function signatures

- [ ] **Step 5: Commit**

```bash
git add src/cli.odin src/main.odin
git commit -m "feat(lsp): add `camp lsp` CLI command"
```

---

### Task 9: Integration Testing

**Files:**
- None (manual verification)

- [ ] **Step 1: Build the compiler with LSP support**

Run: `odin build src -out:camp`

- [ ] **Step 2: Test the LSP initialize handshake**

Run the LSP server manually and send an initialize request via stdin:

```bash
printf 'Content-Length: 76\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./camp lsp
```

Expected: Server responds with an `InitializeResult` JSON containing `capabilities` with `textDocumentSync: 1`, `definitionProvider: true`, `hoverProvider: true`.

- [ ] **Step 3: Test document open + diagnostics**

Send a sequence of LSP messages to test the full flow:

1. `initialize` request
2. `initialized` notification
3. `textDocument/didOpen` with a Camp file containing a syntax error
4. Verify `textDocument/publishDiagnostics` is sent back with the error

Use a script like:

```bash
cat <<'EOF' | ./camp lsp
Content-Length: 76

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
Content-Length: 52

{"jsonrpc":"2.0","method":"initialized","params":{}}
Content-Length: XXX

{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.camp","languageId":"camp","version":1,"text":"x = @"}}}
EOF
```

Note: The `Content-Length` values must be calculated exactly for the messages to parse. The implementer should calculate these or use a small script to generate them.

- [ ] **Step 4: Test go-to-definition**

Open a valid Camp file and send a `textDocument/definition` request for a known identifier.

- [ ] **Step 5: Test hover**

Same setup, send a `textDocument/hover` request.

- [ ] **Step 6: Test with a real editor**

If available, configure a minimal LSP client (e.g., Neovim with `vim.lsp.start`) to connect to `camp lsp` and verify:
- Diagnostics appear on file open and change
- Go-to-definition works (gd key)
- Hover works (K key)

- [ ] **Step 7: Run unit tests**

Run: `odin test src`

Expected: All existing tests still pass (no regressions)

- [ ] **Step 8: Commit any fixes**

If issues were found and fixed during integration testing:

```bash
git add -A src/lsp/ src/cli.odin src/main.odin
git commit -m "fix(lsp): integration test fixes"
```

---

### Task 10: Final Verification and Push

**Files:**
- None

- [ ] **Step 1: Run full unit test suite**

Run: `odin test src`

Expected: All tests pass

- [ ] **Step 2: Build the compiler**

Run: `odin build src -out:camp`

Expected: Successful build with no warnings

- [ ] **Step 3: Smoke test `camp lsp` with a valid Camp file**

Open a valid Camp file through the LSP and verify no errors are reported.

- [ ] **Step 4: Push**

```bash
git push
```
