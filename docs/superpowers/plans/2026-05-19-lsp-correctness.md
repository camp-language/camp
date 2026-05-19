# LSP Correctness Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three correctness gaps — `!` suffix mismatch between LSP and interner, resolved type display in hover, `textDocument/didSave` handler.

**Architecture:** Incremental compiler-core changes (parser, Type_Store) plus LSP handler additions. All changes are additive — no breaking changes to existing APIs.

**Tech Stack:** Odin (dev-2026-04), core:strings, core:fmt

---

## File Structure

| File | What it does | Change |
|------|-------------|--------|
| `src/parser.odin` | AST construction from tokens | Intern `!` suffix in declaration names |
| `src/types.odin` | Type variable storage | Add `bindings` field to `Type_Store` |
| `src/typecheck.odin` | Type inference engine | Populate `store.bindings` after typecheck |
| `src/lsp_symbol_index.odin` | Symbol table for LSP | Query `store.bindings` for resolved types; restore `format_resolved_type` |
| `src/lsp.odin` | LSP server dispatch | Add `handle_did_save` handler |

---

### Task 1: Intern `!` suffix in parser const declarations

**Files:**
- Modify: `src/parser.odin:94-104` (const decl)
- Modify: `src/parser.odin:952-955` (effect op)

- [ ] **Step 1: Add `core:strings` import to parser**

```odin
// Insert after line 1:
import "core:strings"
```

- [ ] **Step 2: Change `parser_parse_const_decl` to append `!` to name before interning**

Replace lines 97-103 in `src/parser.odin`:

```odin
	name := parser_advance(p)
	name_id := intern(p.intern, name.text)

	is_effectful := false
	if p.current.kind == .Bang {
		is_effectful = true
		parser_advance(p)
	}
```

With:

```odin
	name := parser_advance(p)
	name_text := name.text

	is_effectful := false
	if p.current.kind == .Bang {
		is_effectful = true
		parser_advance(p)
		name_text = strings.concatenate({name.text, "!"}, context.temp_allocator)
	}

	name_id := intern(p.intern, name_text)
```

- [ ] **Step 3: Change `parser_parse_effect_decl` to append `!` to operation names**

Replace lines 953-955 in `src/parser.odin`:

```odin
		op_name_id := intern(p.intern, op_name_tok.text)
		is_effectful := p.current.kind == .Bang
		if is_effectful { parser_advance(p) }
```

With:

```odin
		op_name_text := op_name_tok.text
		is_effectful := p.current.kind == .Bang
		if is_effectful {
			parser_advance(p)
			op_name_text = strings.concatenate({op_name_tok.text, "!"}, context.temp_allocator)
		}
		op_name_id := intern(p.intern, op_name_text)
```

- [ ] **Step 4: Build and run existing tests**

```bash
odin build src -out:camp && odin test src 2>&1 | tail -2
```
Expected: 117 tests pass. The `test_effectful_naming_enforcement`, `test_integration_effectful_name`, `test_canonicalize_effectful_const` tests must still pass — they validate `is_effectful` flag behavior which is unchanged.

- [ ] **Step 5: Manual integration test — hover on effectful function**

```bash
cd /tmp && cat > test_effectful.sh << 'SCRIPT'
#!/bin/bash
CAMP="/home/smores/code/github.com/camp-language/camp.lsp-server/camp"
msg() { printf "Content-Length: %d\r\n\r\n%s" ${#1} "$1"; }
{
  msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
  msg '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///test.camp","languageId":"camp","version":1,"text":"main! = || -> I64 { 42 }"}}}'
  msg '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///test.camp"},"position":{"line":0,"character":0}}}'
  msg '{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///test.camp"},"position":{"line":0,"character":0}}}'
  msg '{"jsonrpc":"2.0","id":4,"method":"shutdown","params":null}'
  msg '{"jsonrpc":"2.0","method":"exit","params":null}'
} | "$CAMP" lsp
SCRIPT
chmod +x test_effectful.sh && bash test_effectful.sh
```
Expected: hover returns `"function main!: I64"` (or similar with resolved type), definition returns location. Before this fix, both returned `null`.

- [ ] **Step 6: Commit**

```bash
git add src/parser.odin
git commit -m "feat(parser): intern ! suffix in declaration names for LSP lookup"
```

---

### Task 2: Add `bindings` field to Type_Store

**Files:**
- Modify: `src/types.odin:70-77` (struct)
- Modify: `src/types.odin:79-91` (init/destroy)
- Modify: `src/typecheck.odin:93-104` (populate)

- [ ] **Step 1: Add `bindings` field to Type_Store struct**

In `src/types.odin`, replace lines 70-77:

```odin
Type_Store :: struct {
	vars:            [dynamic]Type_Var,
	next_id:         Type_Var_ID,
	current_level:   int,
	interner:        ^Intern_Table,
	collector:       ^Diagnostic_Collector,
	declared_effects: [dynamic]Intern_ID,
}
```

With:

```odin
Type_Store :: struct {
	vars:             [dynamic]Type_Var,
	next_id:          Type_Var_ID,
	current_level:    int,
	interner:         ^Intern_Table,
	collector:        ^Diagnostic_Collector,
	declared_effects: [dynamic]Intern_ID,
	bindings:         map[Intern_ID]Type_Var_ID,
}
```

- [ ] **Step 2: Initialize `bindings` in `type_store_init`**

In `src/types.odin`, add after line 85 (`store.declared_effects = ...`):

```odin
	store.bindings = make(map[Intern_ID]Type_Var_ID, 64)
```

- [ ] **Step 3: Destroy `bindings` in `type_store_destroy`**

In `src/types.odin`, after line 90 (`delete(store.declared_effects)`):

```odin
	delete(store.bindings)
```

- [ ] **Step 4: Populate `store.bindings` in `typecheck_file`**

In `src/typecheck.odin`, after the `for decl in file.decls` loop ends (after line 103), add lines to copy environment bindings into store:

```odin
	for name_id, var_id in env.bindings {
		store.bindings[name_id] = var_id
	}
```

This copies the root environment's name→type mappings into the persisted store. The `env.bindings` is still deleted by the `defer` on line 98 — we're copying out before it's freed.

- [ ] **Step 5: Build and run tests**

```bash
odin build src -out:camp && odin test src 2>&1 | tail -2
```
Expected: 117 tests pass. No existing behavior should change — we're only adding data to the store that existing code ignores.

- [ ] **Step 6: Commit**

```bash
git add src/types.odin src/typecheck.odin
git commit -m "feat(types): add bindings map to Type_Store for LSP type queries"
```

---

### Task 3: Restore `format_resolved_type` and query it in `build_symbol_index`

**Files:**
- Modify: `src/lsp_symbol_index.odin:68-96` (build_symbol_index)
- Modify: `src/lsp_symbol_index.odin:98-122` (format_type_ann → add format_resolved_type)

- [ ] **Step 1: Add `format_resolved_type` function**

Add after the existing `format_type_ann` proc (after line 122 in `src/lsp_symbol_index.odin`):

```odin
format_resolved_type :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> string {
	resolved := resolve_var(store, var_id)
	v := get_var(store, resolved)
	inf, is_inf := v.link.(Inferred_Type)
	if !is_inf {
		return "?"
	}
	switch inf.tag {
	case .Primitive:
		return intern_get(store.interner, inf.primitive_name)
	case .Function:
		b: strings.Builder
		strings.builder_init_len_cap(&b, 0, 64)
		for i, pid in inf.param_ids {
			if i > 0 do strings.write_string(&b, ", ")
			strings.write_string(&b, format_resolved_type(store, pid))
		}
		strings.write_string(&b, " -> ")
		strings.write_string(&b, format_resolved_type(store, inf.return_id))
		result := strings.to_string(b)
		strings.builder_destroy(&b)
		return result
	case .Constructor:
		return intern_get(store.interner, inf.primitive_name)
	case .Record_Row:
		return "{ ... }"
	case .Tag_Union_Row:
		return "[ ... ]"
	case .Effect_Row:
		return "{}"
	case:
		return "?"
	}
}
```

- [ ] **Step 2: Add `core:strings` import to lsp_symbol_index.odin**

Add after the `package camp` line:

```odin
import "core:strings"
```

- [ ] **Step 3: Update `build_symbol_index` to query `store.bindings`**

In `src/lsp_symbol_index.odin`, replace each use of `format_type_ann(d.type_ann, store)` with a lookup that tries `store.bindings` first.

For `CDecl_Const` (lines 73-77), replace:

```odin
		case ^CDecl_Const:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := format_type_ann(d.type_ann, store)
			symbol_index_add(idx, name_str, uri, range, .Function, type_str)
```

With:

```odin
		case ^CDecl_Const:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else if d.type_ann != nil {
				type_str = format_type_ann(d.type_ann, store)
			}
			symbol_index_add(idx, name_str, uri, range, .Function, type_str)
```

For `CDecl_Trait` (lines 87-90), replace:

```odin
		case ^CDecl_Trait:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			symbol_index_add(idx, name_str, uri, range, .Type, "trait")
```

With:

```odin
		case ^CDecl_Trait:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else {
				type_str = "trait"
			}
			symbol_index_add(idx, name_str, uri, range, .Type, type_str)
```

For `CDecl_Effect` (lines 78-86), keep hardcoded `"effect"` — effects don't have a type variable binding (they aren't typechecked as expressions).

For `CDecl_Alias` (lines 91-94), same pattern: try `store.bindings` first, fall back to `format_type_ann` on `d.target`:

```odin
		case ^CDecl_Alias:
			name_str := intern_get(store.interner, d.name.name)
			range := span_to_lsp_range(source, d.span)
			type_str := "?"
			if var_id, ok := store.bindings[d.name.name]; ok {
				type_str = format_resolved_type(store, var_id)
			} else if d.target != nil {
				type_str = format_type_ann(d.target, store)
			}
			symbol_index_add(idx, name_str, uri, range, .Type, type_str)
```

- [ ] **Step 4: Build and test**

```bash
odin build src -out:camp && odin test src 2>&1 | tail -2
```
Expected: 117 tests pass.

- [ ] **Step 5: Manual integration test — hover shows resolved type**

```bash
cd /tmp && bash test_lsp_hover.sh
```
Expected: hover on `x = 42` shows `"function x: I64"` instead of `"function x: ?"`.

- [ ] **Step 6: Commit**

```bash
git add src/lsp_symbol_index.odin
git commit -m "feat(lsp): query Type_Store.bindings for resolved type display in hover"
```

---

### Task 4: Add `textDocument/didSave` handler

**Files:**
- Modify: `src/lsp.odin:78-97` (dispatch_notification)
- Modify: `src/lsp.odin:167-193` (add handler after handle_did_close)

- [ ] **Step 1: Add case to `dispatch_notification`**

In `src/lsp.odin`, add after the `didClose` case (line 86-87):

```odin
	case "textDocument/didSave":
		handle_did_save(server, params)
```

- [ ] **Step 2: Add `handle_did_save` handler**

Add after `handle_did_close` proc (after line 193 in `src/lsp.odin`):

```odin
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
```

- [ ] **Step 3: Build and test**

```bash
odin build src -out:camp && odin test src 2>&1 | tail -2
```
Expected: 117 tests pass.

- [ ] **Step 4: Manual integration test — didSave with text**

```bash
cd /tmp && cat > test_did_save.sh << 'SCRIPT'
#!/bin/bash
CAMP="/home/smores/code/github.com/camp-language/camp.lsp-server/camp"
msg() { printf "Content-Length: %d\r\n\r\n%s" ${#1} "$1"; }
{
  msg '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
  msg '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  # Open with text, then save should be no-op
  msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///test.camp","languageId":"camp","version":1,"text":"x = 1"}}}'
  # Save with different text
  msg '{"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"file:///test.camp"},"text":"x = 2"}}'
  # Hover should now show the updated text
  msg '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///test.camp"},"position":{"line":0,"character":0}}}'
  msg '{"jsonrpc":"2.0","id":3,"method":"shutdown","params":null}'
  msg '{"jsonrpc":"2.0","method":"exit","params":null}'
} | "$CAMP" lsp
SCRIPT
chmod +x test_did_save.sh && bash test_did_save.sh
```
Expected: hover returns the type of `x = 2` (the saved content), not `x = 1`.

- [ ] **Step 5: Commit**

```bash
git add src/lsp.odin
git commit -m "feat(lsp): add textDocument/didSave handler"
```

---

### Task 5: Final verification

- [ ] **Step 1: Full test suite**

```bash
odin test src 2>&1 | tail -2
```
Expected: 117 tests pass.

- [ ] **Step 2: All integration tests**

```bash
cd /tmp && bash test_lsp.sh && bash test_lsp_full.sh && bash test_lsp_hover.sh && bash test_effectful.sh && bash test_did_save.sh
```
Expected: all scripts pass, no segfaults, correct outputs.

- [ ] **Step 3: Commit final state and push**

```bash
git add -A
git commit -m "chore(lsp): final verification after correctness improvements"
git push
```

- [ ] **Step 4: Clean build artifact**

```bash
rm -f camp
```
