# LSP Correctness Improvements

## 1. `!` suffix in interner

**Problem:** `identifier_at_offset` includes `!` as an identifier character, returning `"main!"`. But the interner stores `"main"` (the `!` is a separate `.Bang` token in the lexer, and `is_effectful` is a separate bool flag). Hover and go-to-definition fail to match.

**Fix:** In `parser_parse_const_decl`, when `!` follows the identifier name, append `!` to the name string before interning. The `is_effectful` flag on the AST node remains unchanged — it serves typechecking and codegen, while the interner now stores the full surface name for LSP lookup.

**Files changed:** `src/parser.odin` (2 call sites: const decls and effect operations)

**Before:**
```odin
name_id := intern(p.intern, name.text)
is_effectful := false
if p.current.kind == .Bang {
    is_effectful = true
    parser_advance(p)
}
```

**After:**
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

No changes to lexer, canonicalizer, typechecker, or codegen. No change to `identifier_at_offset` — it already handles `!`.

---

## 2. Resolved type display in hover

**Problem:** `format_type_ann` reads the source-level `type_ann: ^CType` from `CDecl_Const`, which is nil for unannotated declarations (`x = 42`). Hover shows `"?"` for the type.

**Fix:** Add a `bindings: map[Intern_ID]Type_Var_ID` field to `Type_Store`, populated by `typecheck_file` after typechecking. `build_symbol_index` queries `store.bindings` to get the resolved `Type_Var_ID`, then calls `format_resolved_type` to format the actual type string.

**Files changed:**
- `src/types.odin` — add `bindings` field to `Type_Store` struct, init/destroy
- `src/typecheck.odin` — copy root `env.bindings` into `store.bindings` at end of `typecheck_file`
- `src/lsp_symbol_index.odin` — query `store.bindings` in `build_symbol_index`, restore `format_resolved_type`

**Type_Store change:**
```odin
Type_Store :: struct {
    vars:             [dynamic]Type_Var,
    next_id:          Type_Var_ID,
    current_level:    int,
    interner:         ^Intern_Table,
    collector:        ^Diagnostic_Collector,
    declared_effects: [dynamic]Intern_ID,
    bindings:         map[Intern_ID]Type_Var_ID,  // new: name -> resolved type var
}
```

**build_symbol_index change:**
```odin
type_str := "?"
if var_id, ok := store.bindings[d.name.name]; ok {
    type_str = format_resolved_type(store, var_id)
} else if d.type_ann != nil {
    type_str = format_type_ann(d.type_ann, store)
}
```

`format_resolved_type` resolves the type variable through `resolve_var`/`get_var` and formats the `Inferred_Type` variant (Primitive, Function, Constructor, Record_Row, Tag_Union_Row, Effect_Row).

---

## 3. `textDocument/didSave` notification handler

**Problem:** No handler registered for `textDocument/didSave`. Some editors send save notifications with full text; ignoring them means stale state.

**Fix:** Add `handle_did_save` in `lsp.odin` and register it in `dispatch_notification`. When `text` is included in the params (optional per LSP spec), update the document and mark dirty. `analyze_dirty_documents` already runs after every notification, so re-analysis is automatic.

**Files changed:** `src/lsp.odin` — add handler and case in dispatch

```odin
case "textDocument/didSave":
    handle_did_save(server, params)

handle_did_save :: proc(server: ^LSP_Server, params: json.Value) {
    text_doc, td_ok := json_get_object(params, "textDocument")
    if !td_ok do return
    uri, uri_ok := json_get_string(text_doc, "uri")
    if !uri_ok do return
    text, has_text := json_get_string(params, "text")
    if has_text {
        store_update(&server.doc_store, uri, text, 0)
    }
}
```
