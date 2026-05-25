# Tasks: Implement Test Blocks & Stdlib Test Coverage

## Phase 1: Fix Parser + Make `expect` Work

### 1.1 Parser Bug Fix
- [ ] Remove extra `parser_expect(p, .RBrace)` in `parser_parse_test_decl` (line 2156 of parser.odin)
- [ ] Update `tests/e2e/language/test-block-syntax/expected.toml` to expect successful compilation + execution
- [ ] Verify `camp test tests/e2e/language/test-block-syntax/Main.camp` works

### 1.2 First-Class `Expr_Expect` in AST
- [ ] Add `Expr_Expect :: struct { condition: Expr, message: Expr, span: Source_Span }` to `src/frontend/ast.odin`
- [ ] Add `Expr_Expect` variant to `Expr` union
- [ ] Change `parser_parse_expr_or_decl` to produce `Expr_Expect` instead of desugaring to `expect(cond)` call (line 1053 area)
- [ ] Parse optional message: check for `String_Literal` after `expect` keyword before condition? No — the syntax recipe says `expect condition`, keyword + expression, no parens. Message comes from `///` doc comment only. So `Expr_Expect.message` is initially always nil.

### 1.3 Canonical `Expr_Expect`
- [ ] Add `CExpr_Expect :: struct { condition: CExpr, message: CExpr, span: Source_Span }` to `src/semantics/canonical.odin`
- [ ] Add `CExpr_Expect` to `CExpr` union
- [ ] Add canonicalization case in `src/semantics/canonicalize.odin`

### 1.4 Typed `Expr_Expect`
- [ ] Add `TExpr_Expect :: struct { condition: TExpr, message: TExpr, span: Source_Span }` to `src/semantics/typed.odin`
- [ ] Add `TExpr_Expect` to `TExpr` union
- [ ] Add typecheck case in `src/semantics/check_expr.odin`: condition unified with `Bool`, message typechecked as `Str` (or nil)
- [ ] Add `TExpr_Expect` passthrough cases in all existing `#partial switch` sites that handle `TExpr`

### 1.5 IR `Expr_Expect`
- [ ] Add `IR_Expr_Expect :: struct { condition: IR_Expr, message: IR_Expr, span: Source_Span }` to `src/ir/ir.odin`
- [ ] Add `IR_Expr_Expect` to `IR_Expr` union
- [ ] Add lowering case in `src/ir/lower.odin`: `TExpr_Expect` → `IR_Expr_Expect`
- [ ] If `TExpr_Expect.message` is nil, create `IR_Expr_String` from condition source text (extract via span)
- [ ] Add passthrough/skip cases in all IR passes that traverse `IR_Expr` (effect_lower, closure_convert, cps, rc, reuse)

### 1.6 Codegen `IR_Expr_Expect`
- [ ] Add codegen case in `src/codegen/emit_expr.odin`:
  - Emit condition evaluation
  - Emit `if` test on condition result
  - If false: emit message string, call Exit with code 1
  - Follow `IR_Crash` pattern (emit_expr.odin line 1338)

### 1.7 Top-Level `Decl_Expect` as Synthetic Tests
- [ ] Modify `run_test` in `src/build/build.odin` to create test entries for `Decl_Expect`:
  - Test name: `"expect at line {span.start_line}"`
  - Test body: wrap the expect condition as `CExpr_Expect`
- [ ] Verify top-level `expect` works via `camp test`

### 1.8 Smoke Test
- [ ] Create e2e test `tests/e2e/language/expect-runtime/Main.camp` with basic `expect` assertions
- [ ] Verify `camp test` reports pass/fail correctly
- [ ] Verify failure message includes condition source text

## Phase 2: Doc Comment Attachment

### 2.1 Parser Pending Doc
- [ ] Add `pending_doc: string` field to `Parser` struct
- [ ] In `parser_parse_decl`, consume `.Doc_Comment` tokens before dispatch, accumulate into `pending_doc`
- [ ] Clear `pending_doc` after attaching to a declaration
- [ ] Attach `pending_doc` to `Decl_Expect`, `Decl_Test`, and other declaration types
- [ ] For inline `expect` in `parser_parse_expr_or_decl`, same doc-comment consumption

### 2.2 Propagate Doc Through Pipeline
- [ ] Add `message: Expr` to `Decl_Expect` (currently only has `condition`)
- [ ] Propagate `message` through canonical (`CDecl_Expect.message`), typed (`TDecl_Expect.message`), IR
- [ ] At codegen: prefer `message` over condition source text when present
- [ ] Verify e2e test with `///` doc comment before `expect`

## Phase 3: Compilation Modes

### 3.1 Build_Mode Enum
- [ ] Add `Build_Mode :: enum { Debug, Test, Production }` to `src/build/context.odin`
- [ ] Add `mode: Build_Mode` field to `Compilation_Context`
- [ ] CLI: `camp build` → `Production`, `camp test` → `Test`, `camp check` → `Debug`, `camp build --debug` → `Debug`
- [ ] Parse `--debug` flag in `src/cli.odin`
- [ ] Pass mode from `main.odin` to all build functions

### 3.2 Mode-Dependent IR Lowering
- [ ] In `lower.odin`: Debug/Test mode lowers `TExpr_Expect` → `IR_Expr_Expect`; Production mode skips it (no-op)
- [ ] In `lower.odin`: Production mode `todo` produces a diagnostic error
- [ ] Effect row: in Production mode, `expect` sub-expression effects are not included
- [ ] Verify: production build of file with `expect` compiles without the assertion

## Phase 4: Pure Camp Stdlib Test Coverage

### 4.1 Result (highest priority)
- [ ] `test "Result.map on Ok"` { expect (Result.map (Ok 5) (\x -> x + 1)) == Ok 6 }
- [ ] `test "Result.map on Err"` { expect (Result.map (Err "e") (\x -> x + 1)) == Err "e" }
- [ ] `test "Result.map_err on Err"` { expect (Result.map_err (Err 5) (\x -> x + 1)) == Err 6 }
- [ ] `test "Result.map_err on Ok"` { expect (Result.map_err (Ok 5) (\x -> x + 1)) == Ok 5 }
- [ ] `test "Result.and_then on Ok"` { expect (Result.and_then (Ok 5) (\x -> Ok (x + 1))) == Ok 6 }
- [ ] `test "Result.and_then on Err"` { expect (Result.and_then (Err "e") (\x -> Ok (x + 1))) == Err "e" }
- [ ] `test "Result.or_else on Err"` { expect (Result.or_else (Err "e") (\x -> Ok 0)) == Ok 0 }
- [ ] `test "Result.or_else on Ok"` { expect (Result.or_else (Ok 5) (\x -> Ok 0)) == Ok 5 }
- [ ] `test "Result.is_ok"` { expect Result.is_ok (Ok 5); expect not Result.is_ok (Err "e") }
- [ ] `test "Result.is_err"` { expect Result.is_err (Err "e"); expect not Result.is_err (Ok 5) }
- [ ] `test "Result.unwrap_or on Ok"` { expect (Result.unwrap_or (Ok 5) 0) == 5 }
- [ ] `test "Result.unwrap_or on Err"` { expect (Result.unwrap_or (Err "e") 0) == 0 }
- [ ] `test "Result.filter matching"` { expect (Result.filter (Ok 5) (\x -> x > 3)) == Ok 5 }
- [ ] `test "Result.filter non-matching"` { expect (Result.filter (Ok 1) (\x -> x > 3)) == Err () }
- [ ] `test "Result.flatten Ok(Ok)"` { expect (Result.flatten (Ok (Ok 5))) == Ok 5 }
- [ ] `test "Result.flatten Ok(Err)"` { expect (Result.flatten (Ok (Err "e"))) == Err "e" }
- [ ] `test "Result.to_list Ok"` { expect (Result.to_list (Ok 5)) == [5] }
- [ ] `test "Result.to_list Err"` { expect (Result.to_list (Err "e")) == [] }
- [ ] `test "Result.from_list non-empty"` { expect (Result.from_list [5]) == Ok 5 }
- [ ] `test "Result.from_list empty"` { expect (Result.from_list []) == Err () }

### 4.2 Bool
- [ ] `test "Bool.not"` { expect Bool.not True == False; expect Bool.not False == True }
- [ ] `test "Bool.xor"` { expect Bool.xor True False == True; expect Bool.xor True True == False }
- [ ] `test "Bool.and"` { expect Bool.and True True == True; expect Bool.and True False == False }
- [ ] `test "Bool.or"` { expect Bool.or False True == True; expect Bool.or False False == False }

### 4.3 Iter
- [ ] `test "Iter.empty"` { expect Iter.empty->Iter.count == 0 }
- [ ] `test "Iter.singleton"` { expect Iter.singleton 42->Iter.count == 1 }
- [ ] `test "Iter.map"` { expect Iter.singleton 5->Iter.map (\x -> x * 2)->Iter.count == 1 }
- [ ] `test "Iter.filter"` { expect [1, 2, 3, 4]->Iter.from_list->Iter.filter (\x -> x > 2)->Iter.count == 2 }
- [ ] `test "Iter.fold sum"` { expect [1, 2, 3]->Iter.from_list->Iter.fold 0 (\acc x -> acc + x) == 6 }
- [ ] `test "Iter.count"` { expect [1, 2, 3]->Iter.from_list->Iter.count == 3 }
- [ ] `test "Iter.any"` { expect [1, 2, 3]->Iter.from_list->Iter.any (\x -> x > 2) }
- [ ] `test "Iter.all"` { expect [2, 4, 6]->Iter.from_list->Iter.all (\x -> x % 2 == 0) }
- [ ] `test "Iter.contains"` { expect [1, 2, 3]->Iter.from_list->Iter.contains 2 }
- [ ] `test "Iter.take"` { expect [1, 2, 3, 4, 5]->Iter.from_list->Iter.take 3->Iter.count == 3 }
- [ ] `test "Iter.skip"` { expect [1, 2, 3, 4, 5]->Iter.from_list->Iter.skip 2->Iter.count == 3 }
- [ ] `test "Iter.chain"` { expect Iter.chain [1, 2]->Iter.from_list [3, 4]->Iter.from_list->Iter.count == 4 }
- [ ] `test "Iter.zip"` { expect Iter.zip [1, 2]->Iter.from_list [3, 4]->Iter.from_list->Iter.count == 2 }
- [ ] `test "Iter.enumerate"` { expect [10, 20]->Iter.from_list->Iter.enumerate->Iter.count == 2 }
- [ ] `test "Iter.find"` { expect [1, 2, 3]->Iter.from_list->Iter.find (\x -> x == 2) == Some 2 }

### 4.4 Num.I64 (representative integer type)
- [ ] `test "I64.abs"` { expect I64.abs (-5) == 5; expect I64.abs 5 == 5 }
- [ ] `test "I64.clamp"` { expect I64.clamp 3 1 5 == 3; expect I64.clamp 0 1 5 == 1; expect I64.clamp 10 1 5 == 5 }
- [ ] `test "I64.max"` { expect I64.max 3 5 == 5 }
- [ ] `test "I64.min"` { expect I64.min 3 5 == 3 }
- [ ] `test "I64.neg"` { expect I64.neg 5 == -5; expect I64.neg (-5) == 5 }
- [ ] `test "I64.bitwise_and"` { expect I64.bitwise_and 0b1100 0b1010 == 0b1000 }
- [ ] `test "I64.shift_left"` { expect I64.shift_left 1 3 == 8 }
- [ ] `test "I64.checked_add normal"` { expect I64.checked_add 1 2 == Ok 3 }
- [ ] `test "I64.to_str"` { expect I64.to_str 42 == "42" }
- [ ] `test "I64.range"` { expect I64.range 0 3->Iter.count == 3 }

### 4.5 Num.F64 (representative float type)
- [ ] `test "F64.clamp"` { expect F64.clamp 3.0 1.0 5.0 == 3.0 }
- [ ] `test "F64.neg"` { expect F64.neg 5.0 == -5.0 }
- [ ] `test "F64.abs"` { expect F64.abs (-5.0) == 5.0 }
- [ ] `test "F64.ceiling"` { expect F64.ceiling 3.2 == 4.0 }
- [ ] `test "F64.floor"` { expect F64.floor 3.8 == 3.0 }
- [ ] `test "F64.is_nan"` { expect F64.is_nan F64.nan }
- [ ] `test "F64.sqrt"` { expect F64.sqrt 4.0 == 2.0 }
- [ ] `test "F64.pi"` { expect F64.pi > 3.0; expect F64.pi < 4.0 }

### 4.6 Other Num Types (subset tests)
- [ ] I32: abs, clamp, max, min, to_str
- [ ] I16/I8: clamp, max, min
- [ ] U64: clamp, max, min, wrapping_add
- [ ] U32/U16/U8: clamp, max, min
- [ ] F32: abs, ceiling, floor, is_nan, sqrt

### 4.7 List
- [ ] `test "List.empty"` { expect List.empty->List.is_empty }
- [ ] `test "List.singleton"` { expect List.singleton 5->List.length == 1 }
- [ ] `test "List.append"` { expect List.append [1, 2] [3, 4]->List.length == 4 }
- [ ] `test "List.length"` { expect [1, 2, 3]->List.length == 3 }
- [ ] `test "List.first"` { expect [1, 2, 3]->List.first == Some 1 }
- [ ] `test "List.last"` { expect [1, 2, 3]->List.last == Some 3 }
- [ ] `test "List.rest"` { expect [1, 2, 3]->List.rest == Some [2, 3] }

### 4.8 Duration
- [ ] `test "Duration.from_seconds"` { expect Duration.from_seconds(1)->Duration.as_millis == 1000 }
- [ ] `test "Duration.add"` { expect Duration.add (Duration.from_seconds 1) (Duration.from_seconds 2)->Duration.as_seconds == 3 }
- [ ] `test "Duration.is_zero"` { expect Duration.zero->Duration.is_zero }
- [ ] `test "Duration.sub"` { expect Duration.sub (Duration.from_seconds 3) (Duration.from_seconds 1)->Duration.as_seconds == 2 }

## Phase 5: Intrinsic Stdlib Test Coverage (E2E Execution Tests)

### 5.1 Str
- [ ] E2E test: `Str.length "hello"` == 5
- [ ] E2E test: `Str.is_empty ""` == true
- [ ] E2E test: `Str.starts_with "hello" "hel"` == true
- [ ] E2E test: `Str.concat "hello" " world"` == "hello world"
- [ ] E2E test: `Str.to_upper "hello"` == "HELLO"
- [ ] E2E test: `Str.trim "  hi  "` == "hi"
- [ ] E2E test: `Str.split "a,b,c" ","` → ["a", "b", "c"]
- [ ] E2E test: `Str.replace "hello" "l" "r"` == "herro"
- [ ] E2E test: `Str.take "hello" 3` == "hel"
- [ ] E2E test: `Str.contains "hello" "ell"` == true

### 5.2 Map
- [ ] E2E test: Map.insert Map.new "key" 42 → Map.get "key" == Some 42
- [ ] E2E test: Map.contains after insert == true
- [ ] E2E test: Map.size after 3 inserts == 3
- [ ] E2E test: Map.remove key → Map.contains == false
- [ ] E2E test: Map.keys → list of keys
- [ ] E2E test: Map.from_list [("a", 1)] → Map.get "a" == Some 1

### 5.3 Set
- [ ] E2E test: Set.insert Set.new 42 → Set.contains 42 == true
- [ ] E2E test: Set.size after 3 inserts == 3
- [ ] E2E test: Set.union → combined set
- [ ] E2E test: Set.is_subset → true/false
- [ ] E2E test: Set.from_list [1, 2, 3] → Set.size == 3

### 5.4 Bytes, Path, Fmt
- [ ] Bytes: new, length, get, concat, to_str
- [ ] Path: new, join, is_absolute, filename, extension
- [ ] Fmt: concat, pad_left, pad_right

## Phase 6: Trait/Effect Declaration Typechecking Tests

### 6.1 Core Traits
- [ ] E2E test: Eq — program using `==` on type with Eq instance compiles
- [ ] E2E test: Eq — program using `==` on type without Eq instance fails typecheck
- [ ] E2E test: Ord — `compare` produces `@Order` values
- [ ] E2E test: Debug — `debug` produces string
- [ ] E2E test: Default — `default` produces value

### 6.2 Effects
- [ ] E2E test: Console! — `println!` in handled context compiles and runs
- [ ] E2E test: Throw! — `raise!` + handle compiles
- [ ] E2E test: File! — file operations in handled context
- [ ] E2E test: Time! — `now!` in handled context
- [ ] E2E test: Random! — `int!` in handled context
- [ ] E2E test: Env! — `get!` in handled context
- [ ] E2E test: Log! — `info!` in handled context

## Implementation Order

1. **Phase 1.1** (parser bug fix) — unblocks everything, one line change
2. **Phase 1.2-1.6** (Expr_Expect pipeline) — makes `expect` work at runtime
3. **Phase 1.7** (top-level expect as synthetic test) — makes `expect` work outside test blocks
4. **Phase 1.8** (smoke test) — verify the pipeline works end-to-end
5. **Phase 4** (stdlib test coverage) — write tests for pure Camp modules (can start before Phase 2/3)
6. **Phase 2** (doc comments) — richer failure messages
7. **Phase 3** (compilation modes) — production mode `expect` stripping
8. **Phase 5** (intrinsic tests) — E2E execution tests for Str, Map, Set, etc.
9. **Phase 6** (trait/effect typechecking tests) — typechecking coverage
