# LSP Server Design Spec

**Goal:** Implement a Language Server Protocol server for Camp, available via `camp lsp`, providing diagnostics, go-to-definition, and hover. The server embeds Camp's compiler pipeline in-process — no subprocess delegation.

**Architecture:** Embedded compiler approach. Four-layer design: transport (stdio JSON-RPC), protocol (LSP message types), server state (document store + event loop), analysis (reuses Camp pipeline). Builds on the diagnostic framework's `LSP_Diagnostic` type and `lsp_from_diagnostic` mapping.

**Tech Stack:** Odin, `core:encoding/json`, `core:net`, `core:os`, `core:fmt`, `core:strings`, `core:mem`

**Prerequisite:** Diagnostic framework must land first (provides `LSP_Diagnostic`, `lsp_from_diagnostic`, `span_to_line_col`).

---

## 1. Architecture

```
┌──────────────────────────────────┐
│  Transport                       │  Stdio JSON-RPC reader/writer
│  (lsp_transport.odin)            │  Content-Length framing
├──────────────────────────────────┤
│  Protocol                        │  LSP message types, unmarshal/marshal,
│  (lsp_protocol.odin)             │  request dispatch, notification routing
├──────────────────────────────────┤
│  Server State                    │  Document store, analysis results,
│  (lsp_server.odin)               │  feature handlers, event loop
├──────────────────────────────────┤
│  Analysis                        │  Reuses Camp's compiler pipeline
│  (lsp_analysis.odin)             │  (lexer → parser → typecheck) in-process
│                                  │  Builds symbol index from typed AST
└──────────────────────────────────┘
```

**Data flow on document change:**

1. Client sends `textDocument/didChange`
2. Transport reads JSON-RPC message, strips `Content-Length` framing
3. Protocol unmarshals into typed notification
4. Server updates document store with new text
5. Server marks document dirty — analysis is deferred until after all pending messages are drained
6. After message drain, server re-analyzes all dirty documents: full re-parse + typecheck
7. Analysis produces `Diagnostic_Collector` + symbol index
8. Server maps `Diagnostic` → `LSP_Diagnostic` via `lsp_from_diagnostic`
9. Server sends `textDocument/publishDiagnostics` notification to client

**Key constraint:** Each document analysis run creates its own `Compilation_Context` (arena + allocator + interner + `Diagnostic_Collector`). The context is destroyed after results are extracted. No global state leaks between analysis runs.

---

## 2. File Structure

All LSP code lives under `src/lsp/` as a separate Odin package.

```
src/lsp/
  lsp.odin                  — LSP_Server struct, event loop, init/shutdown
  lsp_transport.odin        — JSON-RPC reader/writer over stdio
  lsp_protocol.odin         — LSP message types, unmarshal/marshal helpers
  lsp_document_store.odin   — URI → document state (text, version, analysis)
  lsp_analysis.odin        — Runs Camp pipeline in-process, produces diagnostics + symbol index
  lsp_handlers.odin        — Feature handlers: definition, hover, diagnostics publishing
  lsp_symbol_index.odin    — Symbol table: name → definition location, built from typed AST
```

**CLI integration** (`src/main.odin`):
- Add `Lsp` to `CLI_Command` enum
- `camp lsp` → call `lsp_main()` which initializes the server and runs the event loop

**Separation from compiler core:**
- `src/lsp/` imports from the `camp` package (the compiler pipeline)
- The compiler pipeline does NOT import from `src/lsp/`
- `lsp_analysis.odin` is the only file that touches compiler internals (lexer, parser, typecheck)
- `lsp_protocol.odin` and `lsp_transport.odin` have zero knowledge of Camp's types

---

## 3. JSON-RPC Transport

**Reading (`lsp_transport.odin`):**

Loop on stdin. Parse `Content-Length: N\r\n\r\n` header, then read exactly N bytes of JSON. Return raw JSON string. Block until a complete message is available.

**Writing (`lsp_transport.odin`):**

Format `Content-Length: N\r\n\r\n` header, then write JSON body to stdout. Flush after each write.

Both reader and writer are synchronous and blocking. The event loop reads one message, processes it, then reads the next. No threading.

**Error handling:**
- EOF on stdin → server exits
- Malformed `Content-Length` header → log to stderr, skip line, try again
- Incomplete JSON body → log to stderr, discard partial read

---

## 4. LSP Protocol Types

**JSON-RPC 2.0 types (`lsp_protocol.odin`):**

```
JSON_RPC_Request       — {jsonrpc: "2.0", id, method, params}
JSON_RPC_Response      — {jsonrpc: "2.0", id, result?, error?}
JSON_RPC_Notification  — {jsonrpc: "2.0", method, params}
JSON_RPC_Error         — {code, message, data?}
```

Standard error codes:
- -32700: Parse Error (malformed JSON)
- -32600: Invalid Request
- -32601: Method Not Found
- -32602: Invalid Params

**LSP-specific types (only what we need):**

```
LSP_Position             — {line: uint, character: uint} (0-based)
LSP_Range                — {start: LSP_Position, end: LSP_Position}
LSP_Location             — {uri: string, range: LSP_Range}
LSP_TextDocumentItem     — {uri, languageId, version, text}
LSP_VersionedTextDocId   — {uri, version}
LSP_ContentChangeEvent   — {range?, rangeLength?, text}
LSP_Hover                — {contents: LSP_MarkupContent, range?}
LSP_MarkupContent        — {kind: "plaintext" | "markdown", value}
LSP_InitializeParams     — {processId, rootUri, capabilities}
LSP_InitializeResult     — {capabilities: LSP_ServerCapabilities}
LSP_ServerCapabilities   — {textDocumentSync, definitionProvider, hoverProvider}
```

**Reusing diagnostic framework types:**
- `LSP_Diagnostic`, `LSP_DiagnosticSeverity`, `LSP_DiagnosticRelatedInfo`, `LSP_Position`, `LSP_Range` — defined in `src/diag_renderer_lsp.odin`
- `lsp_protocol.odin` does NOT duplicate these — it imports them via `import camp "../"` (the `camp` package in `src/`)

**Unmarshaling strategy:**

Odin's `core:encoding/json` uses runtime type info. For requests with known param shapes (e.g., `textDocument/definition`), unmarshal directly into a typed Odin struct. For notifications with variant params, unmarshal into a dynamic `Any` and extract fields manually, or use intermediate structs with optional fields.

---

## 5. Document Store

**`Open_Document` struct:**

```odin
Open_Document :: struct {
    uri:       string,
    text:      string,
    version:   int,
    analysis:  Document_Analysis,
    dirty:     bool,
}
```

**`Document_Store` struct:**

```odin
Document_Store :: struct {
    documents: map[string]^Open_Document,
    allocator: mem.Allocator,
}
```

Operations:
- `store_open(store, uri, text, version)` — register a new document, mark dirty
- `store_update(store, uri, changes, version)` — apply full text replacement, mark dirty
- `store_close(store, uri)` — remove document, free memory
- `store_get(store, uri) → ^Open_Document` — lookup (nil if not found)

**Sync kind:** Full. The client sends the entire document text on each change. Incremental sync is future work. When `didChange` arrives with `ContentChangeEvent` entries where `range` is absent, the entire text is replaced.

---

## 6. Analysis

**`analyze_document(text: string, file_path: string) → Document_Analysis`:**

1. Create a fresh `Compilation_Context` (calls `context_init`)
2. Run `lexer_init` + full tokenization
3. If errors, extract diagnostics and return early (no parse)
4. Run `parser_init` + `parser_parse_file`
5. If errors, extract diagnostics and return early (no typecheck)
6. Run `canonicalize`
7. Run `type_store_init` + `typecheck_file`
8. If typecheck errors, extract diagnostics; symbol index is incomplete
9. If typecheck succeeds, build symbol index from typed canonical AST
10. Map each `Diagnostic` → `LSP_Diagnostic` via `lsp_from_diagnostic`
11. Destroy `Compilation_Context` (arena cleanup via `context_destroy`)
12. Return `Document_Analysis`

**`Document_Analysis` struct:**

```odin
Document_Analysis :: struct {
    diagnostics:  [dynamic]LSP_Diagnostic,
    symbols:      Symbol_Index,
    parse_ok:     bool,
    typecheck_ok: bool,
}
```

**Debounce strategy:** Documents are marked dirty on `didChange`. After the event loop finishes processing all pending messages from stdin (draining the pipe), all dirty documents are re-analyzed. This avoids running the full pipeline on every keystroke while still providing low-latency feedback.

**File ID:** Each document analysis uses `file_id = 0` in `Source_Span`. The URI mapping is handled at the document store level, not in the compiler's `Source_Span`. This avoids changing the compiler's `file_id` scheme.

---

## 7. Symbol Index

**`Symbol_Entry` struct:**

```odin
Symbol_Entry :: struct {
    name:     string,
    uri:      string,
    range:    LSP_Range,
    kind:     Symbol_Kind,
    type_str: string,
}

Symbol_Kind :: enum {
    Function,
    Type,
    Effect,
    Parameter,
    Local,
}

Symbol_Index :: struct {
    entries: [dynamic]Symbol_Entry,
    by_name: map[string][]int,
}
```

**Building the index:**

After a successful typecheck, walk `CFile.decls`:

- `CDecl_Const` — entry with kind `.Function` (if it's a function) or `.Local`, name from `Canonical_Name`, span from the decl, type string from the inferred type
- `CDecl_Effect` — entry with kind `.Effect`, name from the effect name
- `CDecl_Type` — entry with kind `.Type`, name from the type name
- Parameters and locals — extracted from function body patterns and let-bindings

Each entry's `range` is computed by converting the decl's `Source_Span` to `LSP_Range` via `span_to_line_col`.

---

## 8. Feature Handlers

### Go-to-Definition (`textDocument/definition`)

1. Convert LSP position (0-based line:char) to byte offset in document text
2. Find the identifier at that offset (scan backward/forward from offset to find word boundaries — `[a-zA-Z0-9_!]` characters)
3. Look up the identifier string in `Symbol_Index.by_name`
4. If found, return matching `Symbol_Entry` locations as `LSP_Location`
5. If not found, return null

This handles same-file definitions. Cross-file references work once Camp has modules — for now, all definitions are in the same file.

### Hover (`textDocument/hover`)

1. Same position → identifier resolution as go-to-definition
2. Look up the identifier in `Symbol_Index`
3. If found, build `LSP_MarkupContent` with kind `"plaintext"` containing: name, kind, and type string (e.g., `main! : || -> {IO} I64`)
4. Return `LSP_Hover` with contents and range
5. If not found, return null

### Diagnostics (`textDocument/publishDiagnostics`)

Not a request handler — this is a server-to-client notification sent after analysis:

1. After re-analyzing a dirty document, take `Document_Analysis.diagnostics`
2. Send `textDocument/publishDiagnostics` with the document's URI and diagnostic array
3. When a document is closed, send an empty diagnostics array to clear markers

---

## 9. Event Loop & Lifecycle

**`lsp_main()`:**

1. Create `LSP_Server` (allocates document store, stdin/stdout handles)
2. Read `initialize` request → send `InitializeResult` with capabilities
3. Read `initialized` notification → no-op, marks server as ready
4. Main loop:
   a. Read next JSON-RPC message from stdin
   b. Dispatch to handler based on method:
      - `textDocument/didOpen` → open document in store, mark dirty
      - `textDocument/didChange` → update document in store, mark dirty
      - `textDocument/didClose` → close document, send empty diagnostics
      - `textDocument/definition` → look up in symbol index, send response
      - `textDocument/hover` → look up in symbol index, send response
      - `shutdown` → set shutdown flag, send empty response
      - `exit` → exit process (code 0 if shutdown received, 1 if not)
   c. After dispatch, if any documents are dirty:
      - Re-analyze each dirty document
      - Send `publishDiagnostics` for each
      - Clear dirty flags
5. Exit on EOF from stdin or `exit` notification

**Capabilities advertised in `InitializeResult`:**

```json
{
  "capabilities": {
    "textDocumentSync": 1,
    "definitionProvider": true,
    "hoverProvider": true
  }
}
```

`textDocumentSync: 1` = Full sync (client sends complete document text on each change).

**Error handling in the loop:**
- Malformed JSON → send `JSON_RPC_Error` with code -32700
- Unknown method → send error with code -32601
- Analysis crash → send empty diagnostics for that document, log to stderr (never crash the server)

---

## 10. Integration with Diagnostic Framework

The LSP server depends on the diagnostic framework for:

1. **`LSP_Diagnostic` type** — defined in `src/diag_renderer_lsp.odin`, used directly by `lsp_protocol.odin` and `lsp_handlers.odin`. No duplication.

2. **`lsp_from_diagnostic`** — converts each `Diagnostic` from the collector into an `LSP_Diagnostic`. Called in `lsp_analysis.odin` after each analysis run.

3. **`span_to_line_col` / `span_end_to_line_col`** — defined in `src/diag_renderer_cli.odin`, reused by `lsp_analysis.odin` and `lsp_symbol_index.odin` for converting `Source_Span` byte offsets to LSP positions. These are shared utilities.

4. **`Diagnostic_Collector`** — used in each analysis run. The collector is created fresh per-analysis via `context_init` and destroyed after results are extracted.

**Dependency order:** Diagnostic framework must be implemented first. The LSP server cannot build without `LSP_Diagnostic`, `lsp_from_diagnostic`, `span_to_line_col`, and `span_end_to_line_col`.

---

## 11. Future Work (explicitly out of scope)

- **Incremental text sync** — receive `ContentChangeEvent` with ranges instead of full text
- **Completion** — `textDocument/completion`
- **References** — `textDocument/references`
- **Rename** — `textDocument/rename`
- **Formatting** — `textDocument/formatting` (calls `camp fmt`)
- **Semantic tokens** — `textDocument/semanticTokens/full`
- **Code actions / quick fixes** — `textDocument/codeAction`
- **Multi-file analysis** — cross-file go-to-definition once Camp has modules
- **TCP transport** — `camp lsp --tcp :port`
- **Cancellation** — respond to `$/cancelRequest`, abort in-progress analysis
