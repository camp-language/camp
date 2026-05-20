# LSP Design

## Architecture

Four-layer embedded compiler design:

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

**Key constraint:** Each document analysis run creates its own `Compilation_Context` (arena + allocator + interner + `Diagnostic_Collector`). The context is destroyed after results are extracted. No global state leaks between analysis runs.

**Separation from compiler core:**
- `src/lsp/` imports from the `camp` package
- The compiler pipeline does NOT import from `src/lsp/`
- `lsp_analysis.odin` is the only file that touches compiler internals
- `lsp_protocol.odin` and `lsp_transport.odin` have zero knowledge of Camp's types

## Data Flow on Document Change

1. Client sends `textDocument/didChange`
2. Transport reads JSON-RPC message, strips `Content-Length` framing
3. Protocol unmarshals into typed notification
4. Server updates document store with new text
5. Server marks document dirty — analysis is deferred until all pending messages are drained
6. After message drain, server re-analyzes all dirty documents: full re-parse + typecheck
7. Analysis produces `Diagnostic_Collector` + symbol index
8. Server maps `Diagnostic` → `LSP_Diagnostic` via `lsp_from_diagnostic`
9. Server sends `textDocument/publishDiagnostics` notification to client

## File Structure

All LSP code lives under `src/lsp/` as a separate Odin package:

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

CLI integration (`src/main.odin`): Add `Lsp` to `CLI_Command` enum, `camp lsp` calls `lsp_main()`.

## JSON-RPC Transport

**Reading:** Loop on stdin. Parse `Content-Length: N\r\n\r\n` header, read exactly N bytes. Block until complete. Both reader and writer are synchronous and blocking. Single-threaded event loop.

**Writing:** Format `Content-Length: N\r\n\r\n` header, write JSON body to stdout. Flush after each write.

**Error handling:**
- EOF on stdin → server exits
- Malformed `Content-Length` → log to stderr, skip line, retry
- Incomplete JSON body → log to stderr, discard partial read

## LSP Protocol Types

JSON-RPC 2.0: `JSON_RPC_Request`, `JSON_RPC_Response`, `JSON_RPC_Notification`, `JSON_RPC_Error`

Standard error codes: -32700 (Parse Error), -32600 (Invalid Request), -32601 (Method Not Found), -32602 (Invalid Params)

LSP-specific types: `LSP_Position`, `LSP_Range`, `LSP_Location`, `LSP_TextDocumentItem`, `LSP_VersionedTextDocId`, `LSP_ContentChangeEvent`, `LSP_Hover`, `LSP_MarkupContent`, `LSP_InitializeParams`, `LSP_InitializeResult`, `LSP_ServerCapabilities`

Reuses diagnostic framework types: `LSP_Diagnostic`, `LSP_DiagnosticSeverity`, `LSP_DiagnosticRelatedInfo` from `src/diag_renderer_lsp.odin`.

**Unmarshaling strategy:** For requests with known param shapes, unmarshal directly into typed Odin structs. For notifications with variant params, unmarshal into dynamic `Any` and extract fields manually.

## Document Store

```odin
Open_Document :: struct {
    uri:       string,
    text:      string,
    version:   int,
    analysis:  Document_Analysis,
    dirty:     bool,
}

Document_Store :: struct {
    documents: map[string]^Open_Document,
    allocator: mem.Allocator,
}
```

Operations: `store_open`, `store_update` (full text replacement), `store_close`, `store_get`. Sync kind: Full (incremental is future work).

## Analysis Pipeline

`analyze_document(text: string, file_path: string) → Document_Analysis`:

1. Create fresh `Compilation_Context`
2. Run lexer — if errors, extract diagnostics and return early
3. Run parser — if errors, extract diagnostics and return early
4. Run canonicalize
5. Run typecheck — if errors, extract diagnostics; symbol index is incomplete
6. If typecheck succeeds, build symbol index from typed canonical AST
7. Map each `Diagnostic` → `LSP_Diagnostic` via `lsp_from_diagnostic`
8. Destroy `Compilation_Context`
9. Return `Document_Analysis`

```odin
Document_Analysis :: struct {
    diagnostics:  [dynamic]LSP_Diagnostic,
    symbols:      Symbol_Index,
    parse_ok:     bool,
    typecheck_ok: bool,
}
```

**Debounce:** Documents marked dirty on `didChange`, re-analyzed after all pending messages drained. **File ID:** Each analysis uses `file_id = 0` in `Source_Span`; URI mapping is at document store level.

## Symbol Index

```odin
Symbol_Entry :: struct {
    name:     string,
    uri:      string,
    range:    LSP_Range,
    kind:     Symbol_Kind,
    type_str: string,
}

Symbol_Kind :: enum { Function, Type, Effect, Parameter, Local }

Symbol_Index :: struct {
    entries: [dynamic]Symbol_Entry,
    by_name: map[string][]int,
}
```

Built by walking `CFile.decls` after successful typecheck. Each entry's `range` computed via `span_to_line_col`.

## Feature Handlers

**Go-to-Definition:** Convert LSP position to byte offset → find identifier at offset (scan for word boundaries `[a-zA-Z0-9_!]`) → look up in `Symbol_Index.by_name` → return `LSP_Location` or null. Same-file only for now.

**Hover:** Same position → identifier resolution → build `LSP_MarkupContent` (kind `"plaintext"`) with name, kind, and type string → return `LSP_Hover` or null.

**Diagnostics:** Server-to-client notification after analysis. Closed documents get empty diagnostics array.

## Event Loop

1. Read `initialize` → send `InitializeResult` with capabilities
2. Read `initialized` → no-op
3. Main loop: read message, dispatch, then re-analyze dirty documents
4. Dispatch targets: `didOpen`, `didChange`, `didClose`, `didSave`, `definition`, `hover`, `shutdown`, `exit`

Capabilities: `textDocumentSync: 1` (Full), `definitionProvider: true`, `hoverProvider: true`

## Correctness Fixes

### `!` suffix in interner

**Problem:** `identifier_at_offset` returns `"main!"` but the interner stores `"main"` (the `!` is a separate `.Bang` token). Hover/go-to-definition fail to match.

**Fix:** In `parser_parse_const_decl`, when `!` follows the identifier, append `!` to the name string before interning:

```odin
name_text := name.text
is_effectful := false
if p.current.kind == .Bang {
    is_effectful = true
    parser_advance(p)
    name_text = strings.concatenate({name_text, "!"}, context.temp_allocator)
}
name_id := intern(p.intern, name_text)
```

No changes to lexer, canonicalizer, typechecker, or codegen.

### Resolved type display in hover

**Problem:** `format_type_ann` reads source-level `type_ann` which is nil for unannotated declarations. Hover shows `"?"`.

**Fix:** Add `bindings: map[Intern_ID]Type_Var_ID` to `Type_Store`, populated by `typecheck_file` after typechecking. `build_symbol_index` queries `store.bindings` first, falls back to `format_type_ann`:

```odin
type_str := "?"
if var_id, ok := store.bindings[d.name.name]; ok {
    type_str = format_resolved_type(store, var_id)
} else if d.type_ann != nil {
    type_str = format_type_ann(d.type_ann, store)
}
```

### `textDocument/didSave` handler

**Fix:** Add `handle_did_save` in `lsp.odin`, registered in `dispatch_notification`. When `text` is included in params, update document and mark dirty. Re-analysis is automatic.

## Diagnostic Framework Integration

The LSP server depends on:
1. `LSP_Diagnostic` type from `src/diag_renderer_lsp.odin`
2. `lsp_from_diagnostic` for converting `Diagnostic` → `LSP_Diagnostic`
3. `span_to_line_col` / `span_end_to_line_col` from `src/diag_renderer_cli.odin`
4. `Diagnostic_Collector` created fresh per-analysis

Dependency order: Diagnostic framework must be implemented first.

## Future Work (out of scope)

- Incremental text sync
- Completion, references, rename
- Formatting via `textDocument/formatting`
- Semantic tokens
- Code actions / quick fixes
- Multi-file analysis (cross-file go-to-definition)
- TCP transport
- Cancellation (`$/cancelRequest`)
