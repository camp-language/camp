---
# camp-of2c
title: Wire parameterized type alias syntax in parser
status: todo
type: task
priority: normal
created_at: 2026-06-27T17:28:15Z
updated_at: 2026-06-27T17:28:20Z
blocking:
    - camp-h9x1
---

Source: docs/language-spec.md §2 "Type Aliases" (AliasName(a): List(a)).

Parameterized type alias syntax is documented in the recipe but NOT implemented.

## Gap
parser_parse_const_decl (src/frontend/parser.odin:417) never fills Decl_Alias.type_params for the alias path. The name `Maybe` followed by `(a)` hits parser_expect(.Eq) at line 648 with `(` still as current token — produces EXPECTED TOKEN error, not a parameterized alias. Decl_Alias has the type_params: [dynamic]Type_Param field (src/frontend/ast.odin:76-83) but it stays empty for aliases.

Evidence: all kitchen-sink alias examples are commented out (tests/e2e/language/kitchen-sink/Main.camp:128-130). The recipe prescribes Maybe(a) : [...] syntax (recipe §2).

## Work
1. In parser_parse_const_decl or a new helper, after the Upper_Id name for an alias, accept an optional `( param, param, ... )` type-param list (mirror the @Name(params) path at parser.odin:3158-3178, including the C0317 duplicate-param check).
2. Fill Decl_Alias.type_params with the parsed params.
3. Canonicalize: propagate through canonicalize into CDecl_Alias (canonical.odin).
4. Typecheck: resolve param vars in check_decl.odin:197-223 (the CDecl_Alias arm) — bind each param to a fresh value var like typecheck_newtype_decl does at check_decl.odin:343-347.
5. Tests: e2e for a working Maybe(a) alias; un-comment the kitchen-sink alias examples.

This unblocks camp-h9x1 (the unused-type-param check) for the alias case.
