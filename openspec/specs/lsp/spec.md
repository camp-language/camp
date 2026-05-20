# Domain Specification: LSP

## Purpose

Provide Language Server Protocol support for Camp, enabling editors to receive diagnostics, navigate to definitions, and inspect types via hover — all driven by Camp's in-process compiler pipeline.

## Requirements

### Requirement: Server Lifecycle

The LSP server SHALL start via `camp lsp`, initialize over stdio JSON-RPC, and run until `exit` notification or stdin EOF.

#### Scenario: Successful initialization

- Given the server is started via `camp lsp`
- When the client sends an `initialize` request
- Then the server SHALL respond with `InitializeResult` containing capabilities for full text sync, definition provider, and hover provider

#### Scenario: Graceful shutdown

- Given the server is running
- When the client sends `shutdown` then `exit`
- Then the server SHALL exit with code 0

#### Scenario: Exit without shutdown

- Given the server is running
- When the client sends `exit` without prior `shutdown`
- Then the server SHALL exit with code 1

#### Scenario: Stdin EOF

- Given the server is running
- When stdin reaches EOF
- Then the server SHALL terminate

### Requirement: Document Synchronization

The server SHALL synchronize open documents using full text sync (textDocumentSync = 1).

#### Scenario: Document opened

- Given the server is initialized
- When the client sends `textDocument/didOpen` with document URI and text
- Then the server SHALL store the document and mark it dirty for analysis

#### Scenario: Document changed

- Given a document is open in the server
- When the client sends `textDocument/didChange` with new full text
- Then the server SHALL replace the document text and mark it dirty for analysis

#### Scenario: Document closed

- Given a document is open in the server
- When the client sends `textDocument/didClose`
- Then the server SHALL remove the document and send an empty `publishDiagnostics` notification for that URI

#### Scenario: Document saved

- Given a document is open in the server
- When the client sends `textDocument/didSave` with optional text
- Then the server SHALL update the document text (if provided) and mark it dirty for analysis

### Requirement: Diagnostic Publishing

The server SHALL publish diagnostics after analyzing dirty documents.

#### Scenario: Diagnostics after change

- Given a document has been marked dirty
- When the event loop finishes processing all pending messages
- Then the server SHALL re-analyze all dirty documents and send `textDocument/publishDiagnostics` for each

#### Scenario: Empty diagnostics on close

- Given a document is closed
- When the server processes the close notification
- Then the server SHALL send `textDocument/publishDiagnostics` with an empty diagnostics array for that URI

### Requirement: Go-to-Definition

The server SHALL resolve identifier positions to their definition locations.

#### Scenario: Identifier at cursor matches a symbol

- Given a document has been analyzed with a populated symbol index
- When the client sends `textDocument/definition` with a position containing an identifier
- Then the server SHALL look up the identifier in the symbol index and return matching `Location` entries

#### Scenario: Identifier not found

- Given a document has been analyzed
- When the client sends `textDocument/definition` for an identifier not in the symbol index
- Then the server SHALL return null

### Requirement: Hover

The server SHALL provide type and kind information for identifiers at a given position.

#### Scenario: Identifier at cursor matches a symbol

- Given a document has been analyzed with a populated symbol index
- When the client sends `textDocument/hover` with a position containing an identifier
- Then the server SHALL return a `Hover` with plaintext content showing the identifier's name, kind, and resolved type

#### Scenario: Identifier not found

- Given a document has been analyzed
- When the client sends `textDocument/hover` for an identifier not in the symbol index
- Then the server SHALL return null

### Requirement: Effectful Name Matching in Symbol Index

The symbol index SHALL match effectful function names including their `!` suffix.

#### Scenario: Hover on effectful function

- Given a function `main!` is defined in the source
- When the client sends `textDocument/hover` at the position of `main!`
- Then the server SHALL resolve `main!` in the symbol index and return its type information

### Requirement: Resolved Type Display in Hover

Hover SHALL display the inferred/resolved type for declarations, not just source-level annotations.

#### Scenario: Unannotated declaration

- Given a declaration `x = 42` with no type annotation
- When the client sends `textDocument/hover` at position of `x`
- Then the server SHALL display the resolved type (e.g., `I64`), not `"?"`

#### Scenario: Annotated declaration

- Given a declaration `x: String = "hello"`
- When the client sends `textDocument/hover` at position of `x`
- Then the server SHALL display the resolved type

### Requirement: Error Handling

The server SHALL NOT crash on malformed input.

#### Scenario: Malformed JSON-RPC message

- Given the server is running
- When a message with malformed JSON arrives
- Then the server SHALL send a `JSON_RPC_Error` with code -32700 and continue

#### Scenario: Unknown method

- Given the server is running
- When a request with an unknown method arrives
- Then the server SHALL send a `JSON_RPC_Error` with code -32601 and continue

#### Scenario: Analysis crash

- Given a document analysis run encounters an internal error
- Then the server SHALL send empty diagnostics for that document, log to stderr, and continue

### Requirement: Deferred Analysis (Debounce)

The server SHALL defer analysis until all pending messages are drained.

#### Scenario: Multiple rapid changes

- Given the client sends multiple `didChange` notifications in quick succession
- When the event loop processes them
- Then the server SHALL mark documents dirty for each change but re-analyze only after all pending messages are processed
