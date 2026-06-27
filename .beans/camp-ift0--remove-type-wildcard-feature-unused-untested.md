---
# camp-ift0
title: Remove Type_Wildcard feature (unused, untested)
status: todo
type: task
priority: low
created_at: 2026-06-27T17:28:09Z
updated_at: 2026-06-27T23:21:00Z
---

Source: docs/language-spec.md §2 (Type Wildcard section removed 2026-06-27).

The `_`-in-type-position feature is mechanically wired but functionally dead weight:
- `Type_Wildcard` (src/frontend/ast.odin:519,590) / `CType_Wildcard` (src/semantics/canonical.odin:493,563)
- Lowers to a silent `fresh_value_var` at src/semantics/typecheck.odin:1308-1309 (convert_type_to_var_val). No diagnostics, no Agda/Haskell-style hole reporting.
- Zero tests exercise it (no e2e, no unit). Kitchen-sink has no `: _` annotation.
- Offers nothing over simply omitting the type annotation (Camp infers when annotations are absent).

## Work
1. Remove `Type_Wildcard` from src/frontend/ast.odin and `CType_Wildcard` from src/semantics/canonical.odin.
2. Remove the type-position `_` special case in src/frontend/parser.odin:2516-2521 (the type-atom parser's `.Identifier` case). A bare `_` in type position should produce a clear diagnostic ("type wildcards are not supported — omit the annotation instead") rather than silently becoming a fresh var.
3. Remove the `case CType_Wildcard` arm in src/semantics/typecheck.odin:1308-1309 and the passthrough/no-op arms in check_decl.odin (:803, :825, :859, :875) and lsp/symbol_index.odin:173.
4. Update the tree-sitter grammar if it has a `wildcard_type` node (tree-sitter/src/parser.c, node-types.json).
5. Tests: e2e test asserting `_` in type position produces the rejection diagnostic.

## Out of scope
If real hole-reporting (Agda-style "report inferred type at hole") becomes a roadmap goal later, re-introduce with a proper diagnostic mechanism. Don't leave the current silent half-implementation.
