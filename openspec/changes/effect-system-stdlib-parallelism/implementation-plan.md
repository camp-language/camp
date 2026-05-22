# Effect System, Stdlib & Parallelism — Detailed Implementation Plan

**Branch**: `smores/effect-system-stdlib-parallelism`
**Worktree**: `/home/smores/code/github.com/camp-language/camp.effect-system-stdlib-parallelism/`
**Status**: Groups 1-19 complete. All compiler-side infrastructure implemented.

## Pipeline Order (for reference)

```
lexer → parser → canonicalize → typecheck → annotate → mono
  → lower → effect_lower → closure_convert → cps → rc → codegen
```

Effect_lower runs BEFORE CPS and codegen. After effect_lower, `IR_Handle` and `IR_Perform` are fully lowered to `IR_I32_Load`/`IR_I32_Store`/`IR_Closure_Call`. Codegen should never see raw `IR_Handle` or `IR_Perform` — those paths emit `Wasm_Unreachable` as a safety net.

---

## Completed Groups (1-6)

### Group 1: Parser Syntax Alignment ✅
- Effect row syntax: `->{ Eff1, Eff2 }` → `-[Eff1 | Eff2]->`
- Handler arm params: `resume_id + op_params` → single `params` array (`params[0]` = resume)
- Updated across ast.odin, canonical.odin, typed.odin, ir.odin, and all pipeline files

### Group 2: Cherry-pick Bugfixes ✅
- Recursive definitions: `self_var`/`rec_vars` with occurs check exclusion
- Tag row kind: `fresh_tag_row` instead of `fresh_value_var` in pattern matching
- Cherry-picked from `d19f99c` on `smores/stdlib-impl`

### Group 3: Fix Existing Bugs ✅
- All 6 bugs (H2, M4, M9, C8, C7, M5) were already fixed in prior branches merged to main

### Group 4: Effect Row Subtraction ✅
- `subtract_effect_from_row(store, row, effect, span) -> Type_Var_ID` in `src/typecheck.odin:1403`
- Handles concrete rows (remove effect from names) and variable rows (constrain + return rest)
- Used in `CExpr_Handle` typechecking

### Group 5: Evidence Passing ✅
- `IR_Decl_Fn.effects: [dynamic]Canonical_Name` tracks which effects a function uses
- Effect_lower prepends evidence `i32` params to effectful functions
- Effect_lower appends evidence arguments at call sites
- `IR_Perform` → `IR_I32_Load` + `IR_Closure_Call` (O(1) dispatch via evidence record)
- `IR_Handle` → `camp_alloc` + `IR_I32_Store` per arm + body + `camp_dealloc`

### Group 6: CPS Continuation Capture ✅
- `IR_Resume` node added (resume_id, value, ev, type, span)
- Deep handler: `ev` passed to continuation (handler reinstalled)
- Shallow handler: `ev` NOT passed to continuation (handler not reinstalled)
- One-shot enforcement: zero `fn_idx` on first resume, trap on null
- Fixed `lower_call` in lower.odin (was discarding call arguments)

---

## Remaining Groups (7-19)

### Group 7: WASM Codegen for Effects

**Goal**: Effects execute end-to-end in WASM. Currently `IR_Handle` and `IR_Perform` emit `Wasm_Unreachable` in codegen — but after effect_lower, these are dead code paths. The real issue is codegen for the lowered forms.

**What actually needs codegen**:

After effect_lower, handle/perform become:
- `IR_I32_Load` — load handler fn_idx from evidence record
- `IR_I32_Store` — store handler closure into evidence record
- `IR_Closure_Call` — call the loaded handler
- `camp_alloc` / `camp_dealloc` — allocate/free evidence record

**Check**: `IR_I32_Load` and `IR_I32_Store` may NOT have codegen yet. Verify in `src/codegen.odin`.

#### 7.1: Codegen `IR_I32_Load`

In `emit_expr` (codegen.odin), add case for `^IR_I32_Load`:
```
1. Emit base expression (pushes i32 address onto stack)
2. Emit i32.load offset=<offset>
   - WASM opcode: 0x28, alignment=2, offset as LEB128
```

WASM binary encoding for `i32.load`:
```
0x28        — opcode
0x02 0x00   — alignment (2^n = 4 for i32, encoded as 2)
<offset>    — LEB128-encoded offset
```

#### 7.2: Codegen `IR_I32_Store`

In `emit_expr`, add case for `^IR_I32_Store`:
```
1. Emit base expression (pushes address)
2. Emit value expression (pushes value)
3. Emit i32.store offset=<offset>
   - WASM opcode: 0x36, alignment=2, offset as LEB128
```

WASM binary encoding for `i32.store`:
```
0x36        — opcode
0x02 0x00   — alignment (2^n = 4 for i32, encoded as 2)
<offset>    — LEB128-encoded offset
```

#### 7.3: Verify `IR_Closure_Call` codegen

Already implemented (lines 913-940 in codegen.odin). Uses `call_indirect` with function table. **No changes needed** — but verify it works with the evidence-loaded closures from effect_lower.

#### 7.4: Verify `IR_Resume` codegen

Already implemented (lines 823-871 in codegen.odin). One-shot check, zero fn_idx, call_indirect. **No changes needed** — but verify it works end-to-end.

#### 7.5: Codegen effectful `main!` — default handlers

When `main!` has effects in its row (checked via `decl.effects` being non-empty), the `_start` function needs to install default evidence records before calling `main!`.

**Current behavior**: `_start` already handles effectful main by extracting the body and wrapping it. Need to add default evidence record allocation.

**Default handlers needed**:
- `Console!`: `camp_print_str` for `println!`, `unreachable` for `readln!`
- `Throw!`: Print tag name to stderr + `proc_exit(1)` (no resume)
- Any other effect: Print "unhandled effect <name>" + `proc_exit(1)`

**Implementation**: In `codegen_effectful_start` (or wherever `_start` is generated for effectful main):
1. For each effect in `main!.effects`:
   - Allocate evidence record: `call $camp_alloc (i32.const <N * 8>)` where N = number of ops
   - For each operation, create a default handler function + store in record
   - Pass evidence pointer as argument to `main!`

**Default handler function signatures** (same as any handler arm):
```
(env: i32, op_args..., resume_fn: i32, resume_env: i32, ev: i32) -> result_type
```

For `Console!.println!`: body calls `camp_print_str` with the string arg, then calls resume.
For `Throw!.throw!`: body calls `camp_print_str` with error tag, then `proc_exit(1)` — does NOT call resume.

**Add runtime constant**: `RUNTIME_PRINT_ERR :: 6` (or reuse RUNTIME_PRINT_STR with fd=2).

#### 7.6: E2E test

Create `tests/e2e/effects/effect-execution.camp`:
```camp
effect Ask { read! }
main = handle Ask in Ask.read!() with { .read!(resume) => resume(42) }
```
Expected: exit code 42 (or 0 if main returns unit — adapt as needed).

Create `tests/e2e/effects/effect-execution.expected.toml`:
```toml
stdout = ""
stderr = ""
exit = 0
```

---

### Group 8: Effect `:` Syntax Migration

**Goal**: Remove `effect` keyword. Effects become type aliases with `!` names.

#### 8.1: Remove `Kw_Effect` from lexer

In `src/token.odin`: Remove `Kw_Effect` from `Token_Kind` enum.
In `src/lexer.odin`: Remove `"effect"` from the keyword map.

**Impact**: Every file that pattern-matches on `Kw_Effect` needs updating:
- `src/parser.odin` — effect declaration parsing
- `src/canonicalize.odin` — canonicalization dispatch
- `src/format_decl.odin` — effect declaration formatting
- `src/test_lexer.odin`, `src/test_parser.odin` — test fixtures

#### 8.2: Add `Kw_Par` to lexer

In `src/token.odin`: Add `Kw_Par` to `Token_Kind` enum.
In `src/lexer.odin`: Add `"par"` to the keyword map.

#### 8.3: Extend parser for `Name! : { ... }` syntax

**Current**: `parser_parse_effect_decl` expects `Kw_Effect` then `Upper_Id` then `{`.

**New flow**: In `parser_parse_colon_decl` (or wherever `:` definitions are parsed — check `parser_parse_const_decl` which handles `name = expr` and `name : type`):

When parsing a `:` definition:
1. Parse the name token (could be `Upper_Id` or `Upper_Id` followed by `!`)
2. If the name ends with `!` (lexer produces `Upper_Id` + `Bang`, or the identifier text itself ends with `!`):
   - If the body is a record of function signatures → `CDecl_Effect`
   - If the body is a type (not a record) → error: "only effect types may end with !"
3. If the name doesn't end with `!`:
   - If the body is a record of function signatures → `CDecl_Trait`
   - If the body is a type → `CDecl_Alias` (type alias)

**Parsing challenge**: The `!` is currently a separate token (`Bang`). For `Console!`, the tokens are `Upper_Id("Console")` then `Bang`. The name with `!` appended becomes `"Console!"`.

**Implementation**:
```odin
// In parser_parse_prefix or parser_parse_file:
// When seeing Upper_Id followed by Bang:
name_tok := parser_advance(p)  // Upper_Id
name_text := name_tok.text
is_effect_name := false
if p.current.kind == .Bang {
    parser_advance(p)
    name_text = strings.concatenate({name_tok.text, "!"}, context.allocator)
    is_effect_name = true
}
// Then parse : and body
parser_expect(p, .Colon)
// Parse body...
if is_effect_name {
    // Parse as effect definition (record of function signatures)
} else {
    // Parse as trait or type alias
}
```

#### 8.4: Enforce effect operation type annotations are required

When parsing an effect definition body, each operation MUST have a type annotation:
```
Console! : { println!: |Str| -[Console!]-> {} }  // OK
Console! : { println! }                            // ERROR
```

In the parser: after parsing an operation name (with `!`), if `Colon` doesn't follow, emit a diagnostic: "effect operation type annotations are required".

#### 8.5: Error if non-effect type name ends with `!`

After parsing `Name! : <body>`:
- If `body` is NOT a record of function signatures → emit error: "only effect types may end with !"

#### 8.6: Update canonicalize

In `src/canonicalize.odin`, the `Decl_Effect` case must handle the new parsing output. The canonicalization logic itself shouldn't change much — `CDecl_Effect` and `CEffect_Op` structs stay the same. But the dispatch in `canonicalize` that matches on `Decl_Effect` vs `Decl_Alias` may need updating if the parser now produces different AST node types.

**Check**: Does the parser still produce `Decl_Effect`? Yes — the parser should route `Name! : { ... }` to `Decl_Effect` just as it did for `effect Name { ... }`.

#### 8.7: Update `format_decl`

In `src/format_decl.odin`, `format_decl_effect` should emit:
```
Console! : {
  println!: |Str| -[Console!]-> {},
}
```
Instead of:
```
effect Console {
  println!: Str,
}
```

#### 8.8: Update all e2e tests

Every `.camp` file using `effect X { ... }` needs updating to `X! : { ... }` syntax. Grep for `effect ` in `tests/e2e/` to find all affected files.

#### 8.9: Update formatter

The formatter (`src/run_fmt.odin` or `src/format_decl.odin`) should produce the new syntax.

---

### Group 9: Parameterized Effects + Variant Widening

**Goal**: Effects can have type parameters. Tag union parameters widen through general tag row unification.

#### 9.1: Type parameters in effect definitions

**AST change** (`src/ast.odin`): Add type params to `Decl_Effect`:
```odin
Decl_Effect :: struct {
    name:        Intern_ID,
    type_params: [dynamic]Type_Param,  // NEW
    is_pub:      bool,
    operations:  [dynamic]Effect_Op,
    span:        Source_Span,
}
```

**Parser change** (`src/parser.odin`): After the effect name (with `!`), if `<` follows, parse type parameters:
```
Throw! : <e> { throw!: |e| -[Throw!(e)]-> a }
```

Wait — the `:` syntax for effects means we need to parse `<e>` between the name and `:`:
```
Throw!<e> : { throw!: |e| -[Throw!(e)]-> a }
```

Or with the current syntax:
```
Throw! : { throw!: |e| -[Throw!(e)]-> a }
```

The type parameter `e` appears in the operation type annotations. The effect definition itself is implicitly parameterized by any type variables used in its operations that aren't bound elsewhere. **Decision**: Explicit type parameters on the effect definition.

**Canonical change** (`src/canonical.odin`): Add type params to `CDecl_Effect`:
```odin
CDecl_Effect :: struct {
    name:        Canonical_Name,
    type_params: [dynamic]CType_Param,  // NEW
    is_pub:      bool,
    operations:  [dynamic]CEffect_Op,
    span:        Source_Span,
}
```

**IR change** (`src/ir.odin`): Add type params to `IR_Effect_Def`:
```odin
IR_Effect_Def :: struct {
    name:        Canonical_Name,
    type_params: [dynamic]Intern_ID,  // NEW
    operations:  [dynamic]IR_Effect_Op,
}
```

#### 9.2: Track effect type arguments in effect rows

**Current**: `Inferred_Type.effect_names: []Intern_ID` — just names, no type args.

**Change to**: `effect_names` becomes a more expressive structure. Two options:

**Option A** (simpler, recommended): Keep `effect_names: []Intern_ID` but add `effect_type_args: map[Intern_ID]Type_Var_ID` — maps effect name to its type argument (if any). An effect without type args has no entry in the map.

**Option B** (more general): Change to `effects: []Effect_Row_Entry` where:
```odin
Effect_Row_Entry :: struct {
    name:      Intern_ID,
    type_args: []Type_Var_ID,  // empty for unparameterized effects
}
```

**Recommended**: Option B is cleaner. Changes needed:

- `src/types.odin`: Replace `effect_names: []Intern_ID` with `effects: []Effect_Row_Entry` in `Inferred_Type`
- `src/typecheck.odin`: All places that read/write `effect_names` must use `effects`
- `src/unify.odin`: `unify_effect_rows` must compare `effects` entries (name + type args)
- `src/format_type.odin`: Format `Throw!([NotFound | PermissionDenied])` instead of `Throw!`

**AST change** (`src/ast.odin`):
```odin
Type_Effect_Row :: struct {
    effects: [dynamic]Type_Effect_Entry,  // was [dynamic]Intern_ID
    rest:    Intern_ID,
    is_open: bool,
    span:    Source_Span,
}

Type_Effect_Entry :: struct {
    name:      Intern_ID,
    type_args: [dynamic]Type,  // empty for unparameterized
    span:      Source_Span,
}
```

**Parser change** (`src/parser.odin`): In `parser_parse_effect_row_type`, after `Upper_Id`, check for `(`:
```
-[Throw!([NotFound | PermissionDenied]) | Console!]->
```
Parse `Throw!` as `Upper_Id("Throw") + Bang`, then `(` + type_args + `)`.

**Canonical change** (`src/canonical.odin`):
```odin
CType_Effect_Row :: struct {
    effects: [dynamic]CType_Effect_Entry,  // was [dynamic]Intern_ID
    rest:    Intern_ID,
    is_open: bool,
    span:    Source_Span,
}

CType_Effect_Entry :: struct {
    name:      Intern_ID,
    type_args: [dynamic]CType,
    span:      Source_Span,
}
```

#### 9.3: Tag row unification for effect type parameters

**In `src/unify.odin`**: When unifying two `Effect_Row` types that both contain the same effect name with type arguments:

```
Row A: effects = [{name: "Throw!", type_args: [tag_row_var_1]}]
Row B: effects = [{name: "Throw!", type_args: [tag_row_var_2]}]
```

Unify `tag_row_var_1` with `tag_row_var_2` using **tag row unification** (`unify_tag_union_rows`). This produces a merged tag row that contains all tags from both sides — that's variant widening.

**No Throw-specific code**. Any effect with a tag union type parameter widens automatically:
```
Signal!([Click]) + Signal!([KeyPress]) → Signal!([Click | KeyPress])
```

The unification logic:
1. For each effect in row A, find matching effect in row B (by name)
2. If both have type args and arity matches, unify each type arg pair
3. For type args that are tag rows → tag row unification (widening)
4. For type args that are value types → standard unification (exact match)
5. Effects only in A or only in B → handled by existing set-difference logic

#### 9.4: Remove Throw-specific widening code

Search `src/typecheck.odin` and `src/unify.odin` for any Throw-specific widening code. With general tag row unification (9.3), there should be none. But verify and remove if found.

#### 9.5: E2E tests

```camp
Throw! : { throw!: |e| -[Throw!(e)]-> a }

NotFound : tag
PermissionDenied : tag

risky = || -[Throw!([NotFound])]-> {} { Throw!.throw!(NotFound) }
risky2 = || -[Throw!([PermissionDenied])]-> {} { Throw!.throw!(PermissionDenied) }

combined = || -[Throw!([NotFound | PermissionDenied])]-> {} {
  risky()
  risky2()
}
```

---

### Group 10: Effect Polymorphism

**Goal**: Effect row variables as generic type parameters.

#### 10.1: Add `is_effect` to `Type_Param`

**In `src/ast.odin`**:
```odin
Type_Param :: struct {
    name:        Intern_ID,
    constraints: [dynamic]Intern_ID,
    is_effect:   bool,  // NEW — true when used in effect row position
}
```

**Propagation**: `Type_Param` flows through the entire pipeline. Update:
- `src/canonical.odin`: `CType_Param` — add `is_effect: bool`
- `src/typed.odin`: If there's a typed version of type params
- `src/types.odin`: When creating type variables from params, use `is_effect` to determine `Type_Var_Kind` (`.Value` vs `.Row_Effect`)

#### 10.2: Set `is_effect` at use site

**In `src/typecheck.odin`**: When processing a function's type parameters, check if each parameter appears in effect row position. If so, set `is_effect = true`.

```odin
// For each type param:
for param in type_params {
    if appears_in_effect_row(param.name, function_type) {
        param.is_effect = true
    }
}
```

When instantiating the type parameter:
- `is_effect = false` → `fresh_value_var(store)` (kind = `.Value`)
- `is_effect = true` → `fresh_effect_row(store)` (kind = `.Row_Effect`)

#### 10.3: Effect row variable unification

**In `src/unify.odin`**: The `unify` function already handles `.Row_Effect` kind variables via `unify_effect_rows`. But need to verify that:

1. Two unlinked effect row variables can be unified (they share the same row)
2. An effect row variable can be unified with a concrete effect row (variable gets bound)
3. An effect row variable can be unified with another row variable (linked together)

**Check**: `unify_effect_rows` already handles most of this via set-difference + rest unification. Verify it handles the case where BOTH sides are unlinked variables.

#### 10.4: Effect row composition

`-[Parallel! | e]->` unifies with `-[e]->` by adding `Parallel!`.

This should already work through `unify_effect_rows`:
- Side A effects: `[Parallel!]`, rest: `e`
- Side B effects: `[]`, rest: `e`
- `a_only = [Parallel!]`, `b_only = []`
- Unify A's rest with `[Parallel! | shared_rest]`
- Unify B's rest with `[shared_rest]`

**Verify** this works with the existing unification. If not, fix.

#### 10.5: Effect row subtraction with variables

When `handle Parallel! in body` where body has `-[Parallel! | e]->`:

`subtract_effect_from_row` already handles this case (Group 4):
- Creates `[Parallel! | handled_rest]`, unifies with body row
- Returns `handled_rest` (= `e`)
- Result: `-[e]->`

**Verify** this works with the parameterized effect rows from Group 9.

#### 10.6: Handler arm type verification

When typechecking a handler arm, verify the arm's parameter types and return type match the declared operation signature.

```odin
// For each handler arm:
// 1. Look up the operation in the effect's declared operations
// 2. Verify the arm's parameter count matches (excluding resume)
// 3. Unify each arm param type with the declared op param type
// 4. Unify the arm's return type with the handle expression's expected type
```

#### 10.7: E2E tests

```camp
map = <a, b, e>|f: |a| -[e]-> b, items: List(a)| -[Parallel! | e]-> List(b) {
  items.par_map!(f)
}
```

---

### Group 11: Prelude Effects

**Goal**: Console! and Throw! defined in the prelude, not in user code.

#### 11.1: Add Console! to prelude

**In `src/typecheck.odin` → `inject_prelude`**:

Add effect declarations alongside existing type/tag injections:
```odin
// Console! effect
console_id := fresh_effect_row(store)
// Create Inferred_Type for Console! with operations [println!, readln!]
// Store in store.declared_effects
```

The prelude injection needs to:
1. Create a `Function` type for each operation (params, return type, effects)
2. Create the effect row type for `Console!`
3. Register `Console!` in `store.declared_effects`

**Challenge**: Currently `inject_prelude` only injects simple types and tags. Effects require registering operation signatures. Need to extend the prelude injection.

**Implementation approach**: Create a helper `inject_effect(store, name, operations)` that:
1. Creates a fresh effect row variable for the effect
2. Registers the effect name in `store.declared_effects`
3. Stores operation signatures in `store` (may need a new `effect_ops: map[Intern_ID][]Type_Var_ID` field or similar)

#### 11.2: Add Throw! to prelude

Same pattern as Console!, but `Throw!` has a type parameter:
```
Throw! : { throw!: |e| -[Throw!(e)]-> a }
```

The `a` return type is polymorphic — throw can return any type. This requires the operation to have a universally quantified return type.

#### 11.3: Default Throw! handler in `_start`

In codegen, when generating `_start` for an effectful `main!`:
- If `Throw!` is in `main!.effects`, allocate a default evidence record
- The default `throw!` handler: print error info to stderr, call `proc_exit(1)`, do NOT call resume

#### 11.4: Remove non-resuming handler special case

Search for `is_non_resuming` or any special-case handling of Throw! in:
- `src/effect_lower.odin`
- `src/codegen.odin`

With Throw! as a normal resumable effect, there's no type-level distinction. All handlers use the same arm signature. Remove any Throw-specific code paths.

#### 11.5: E2E tests

- Throw! resumable handler: `handle Throw! in ... with { .throw!(resume, err) => resume(0) }`
- Throw! non-resuming handler: `handle Throw! in ... with { .throw!(resume, err) => Err(err) }`
- Default Throw! in main: program that throws at top level exits with code 1

---

### Group 12: Prelude Expansion

**Goal**: Expand Odin-injected prelude with full type/tag/effect/operator declarations.

#### 12.1: Expand type declarations

**In `src/typecheck.odin` → `inject_prelude`**:

Add:
| Name | Kind | Arity |
|------|------|-------|
| I8 | Primitive | 0 |
| I16 | Primitive | 0 |
| U8 | Primitive | 0 |
| U16 | Primitive | 0 |
| U32 | Primitive | 0 |
| Bytes | Primitive | 0 |
| List | Constructor | 1 |
| Iter | Constructor | 1 |
| Map | Constructor | 2 |
| Set | Constructor | 1 |
| Handle | Constructor | 1 |
| Ordering | Constructor | 0 |
| Result | Constructor | 2 |
| Option | Constructor | 1 |

Each is added as:
```odin
id := fresh_value_var(store)
store_alloc(store, .{
    tag = .Primitive,  // or .Constructor
    primitive_name = intern(interner, "I8"),
    arity = 0,
    ...
})
store.bindings[name_id] = id
```

#### 12.2: Expand collection type declarations

Same as 12.1 — List(a), Iter(a), Map(k,v), Set(a), Handle(a) are constructors with arity.

#### 12.3: Expand tag declarations

Add to `inject_prelude`:
| Tag | Tags in union |
|-----|--------------|
| Ok | `[Ok(a) | ...]` |
| Err | `[Err(e) | ...]` |
| Some | `[Some(a) | ...]` |
| None | `[None | ...]` |
| Less | `[Less | ...]` |
| Equal | `[Equal | ...]` |
| Greater | `[Greater | ...]` |
| Nil | `[Nil | ...]` |
| Cons | `[Cons(a) | ...]` |

Each tag injection creates a `Tag_Union_Row` Inferred_Type with one tag entry and a fresh rest variable.

#### 12.4: Add effect name declarations

Add to `inject_prelude`:
- Console!, Throw!, Async!, Parallel!, Spawn!, File!, Env!, Time!, Random!, Log!, Crypto.Random!

Each effect name registered in `store.declared_effects` with operation signatures.

#### 12.5: Add operator function declarations

Add numeric, comparison, and boolean operators as prelude functions:
- `+`, `-`, `*`, `/` for I64, I32, F64, etc.
- `==`, `!=`, `<`, `>`, `<=`, `>=` for comparable types
- `and`, `or`, `not` for Bool

These are injected as function bindings in the type environment so that type inference can resolve them.

---

### Group 13: Runtime WASM Primitives

**Goal**: Add WASM runtime functions for operations that cannot be written in Camp.

All runtime functions are in `src/runtime.odin` (the WASM module that gets linked with compiled Camp code). They're called by function index from codegen.

#### 13.1: List runtime functions

Add to `src/runtime.odin`:
- `camp_list_alloc() -> i32`: Allocate a new empty list (returns pointer)
- `camp_list_push(list: i32, value: i32) -> i32`: Push value onto list
- `camp_list_len(list: i32) -> i32`: Get list length
- `camp_list_get(list: i32, index: i32) -> i32`: Get element at index

Implementation: Lists are heap-allocated arrays with a header (length, capacity).

Add to `src/codegen.odin`:
```odin
RUNTIME_LIST_ALLOC :: 6
RUNTIME_LIST_PUSH  :: 7
RUNTIME_LIST_LEN   :: 8
RUNTIME_LIST_GET   :: 9
```

Update `RUNTIME_FUNC_COUNT`.

#### 13.2: String runtime functions

- `camp_str_concat(a: i32, b: i32) -> i32`: Concatenate two strings
- `camp_str_len(s: i32) -> i32`: String length
- `camp_str_eq(a: i32, b: i32) -> i32`: String equality (1 = true, 0 = false)
- `camp_str_slice(s: i32, start: i32, end: i32) -> i32`: Substring

#### 13.3: File I/O runtime functions

- `camp_print_str(s: i32)`: Already exists (WASI fd_write to stdout). May need `camp_print_err(s: i32)` for stderr.
- `camp_read_str(fd: i32, buf: i32, len: i32) -> i32`: Read from file descriptor

#### 13.4: Env runtime functions

- `camp_args() -> i32`: Return pointer to args list
- `camp_get_env(name: i32) -> i32`: Get environment variable

#### 13.5: Time runtime functions

- `camp_time_now() -> i64`: Current timestamp (WASI `clock_time_get`)
- `camp_time_sleep(ms: i32)`: Sleep for milliseconds (WASI `poll_oneoff` with timeout)

#### 13.6: Random runtime functions

- `camp_random_bytes(buf: i32, len: i32)`: Fill buffer with random bytes (WASI `random_get`)
- `camp_random_int(min: i32, max: i32) -> i32`: Random integer in range

---

### Group 14: Stdlib Infrastructure — .camp File Embedding

**Goal**: Camp-language stdlib modules embedded in the compiler binary.

#### 14.1: Create `stdlib/` directory

At the repo root (or in `src/stdlib/`), create:
```
stdlib/
  Result.camp
  Option.camp
  Bool.camp
  Int.camp
  Str.camp
  List.camp
  Iter.camp
  Map.camp
  Set.camp
  Eq.camp
  Ord.camp
  Hash.camp
  Fmt.camp
  Path.camp
  Console!.camp
  Throw!.camp
  File!.camp
  Env!.camp
  Time!.camp
  Random!.camp
  Serialize.camp
  Bytes.camp
```

#### 14.2-14.3: Write initial .camp files

**Result.camp**:
```camp
Result : <a, e> [Ok(a) | Err(e)]

is_ok = <a, e>|r: Result(a, e)| -> Bool {
  match r { Ok(_) => True | Err(_) => False }
}

is_err = <a, e>|r: Result(a, e)| -> Bool {
  match r { Ok(_) => False | Err(_) => True }
}

map = <a, b, e>|f: |a| -> b, r: Result(a, e)| -> Result(b, e) {
  match r { Ok(v) => Ok(f(v)) | Err(e) => Err(e) }
}
```

**Option.camp**:
```camp
Option : <a> [Some(a) | None]

is_some = <a>|o: Option(a)| -> Bool {
  match o { Some(_) => True | None => False }
}

is_none = <a>|o: Option(a)| -> Bool {
  match o { Some(_) => False | None => True }
}
```

**Bool.camp**, **Int.camp**, **Str.camp**: Type-specific operations that aren't injected by the prelude.

**Note**: These files CANNOT be compiled until the compiler supports enough language features (generics, traits, imports). They serve as specification and will be enabled incrementally.

#### 14.4: Embed .camp files at build time

**In `src/cli.odin` or a new `src/stdlib.odin`**:

Use Odin's `embed_file` or `#embed` to embed stdlib files:
```odin
import "core:embed"

RESULT_CAMP :: embed_file("stdlib/Result.camp")
OPTION_CAMP :: embed_file("stdlib/Option.camp")
// etc.
```

At runtime, extract to a temp directory or read from memory. The module system should check embedded stdlib as a fallback after `src/`.

#### 14.5: Update module system for stdlib resolution

**In `src/discovery.odin` or `src/import_resolve.odin`**:

When resolving `import List`:
1. Check `src/List.camp` (project-local) → if found, use it
2. Check embedded stdlib for `List` → if found, use it
3. If neither → error: module not found

The embedded stdlib can be exposed as a virtual filesystem or by writing to a temp directory on first access.

#### 14.6-14.14: Write remaining .camp files

Each stdlib module needs a `.camp` file with the module's public API. These will be written as Camp code following the language spec. Details for each module are in `openspec/specs/packages/design.md` and `openspec/specs/packages/spec.md`.

**Implementation order** (by dependency):
1. Result, Option (no deps)
2. Bool, Int, Str (no deps beyond prelude)
3. Eq, Ord (traits, need generics)
4. List (needs Eq, Ord)
5. Iter (needs List)
6. Map, Set (needs Eq, Hash)
7. Hash (trait)
8. Fmt (needs Str)
9. Path (needs Str, List)
10. Effect .camp files (need effects support)
11. Serialize (needs Codec trait)
12. Bytes (needs Int)

---

### Group 15: Parallel Effect — Sequential Handler + Syntax

**Goal**: `Parallel!` effect with sequential handler, `par` block syntax, method sugar.

#### 15.1: Add Parallel! to prelude

**In `src/typecheck.odin` → `inject_prelude`**:

```odin
// Parallel! effect with operations:
// map!, for_each!, filter!, reduce!, all!, any!
```

Register `Parallel!` in `store.declared_effects` with 6 operations.

#### 15.2: Sequential Parallel! handler

The sequential handler is NOT generated by the compiler — it's a handler the user writes (or the runtime provides). For the initial implementation, the user writes:

```camp
handle Parallel! in ... with {
  .map!(resume, items, f) => resume(items.iter().map(f).collect())
  .for_each!(resume, items, f) => { items.iter().for_each(f); resume({}) }
  .filter!(resume, items, pred) => resume(items.iter().filter(pred).collect())
  .reduce!(resume, items, init, f) => resume(items.iter().fold(init, f))
  .all!(resume, tasks) => resume(tasks.iter().map(|t| t()).collect())
  .any!(resume, tasks) => ...
}
```

**Compiler responsibility**: Ensure the typechecker accepts `Parallel!` operations and the handler arm types check correctly.

#### 15.3: Method sugar in canonicalize

**In `src/canonicalize.odin`**:

Add a desugaring table:
```odin
METHOD_SUGAR :: map[string]struct {
    effect:      string,
    operation:   string,
    arg_shift:   int,  // how many args shift from method target to first arg
}

// Entries:
// "par_map!"      → {effect: "Parallel!", operation: "map!", arg_shift: 0}
// "par_filter!"   → {effect: "Parallel!", operation: "filter!", arg_shift: 0}
// "par_reduce!"   → {effect: "Parallel!", operation: "reduce!", arg_shift: 0}
// "par_for_each!" → {effect: "Parallel!", operation: "for_each!", arg_shift: 0}
```

When canonicalizing a `CExpr_Method_Call` where the method name is in the table:
```
receiver.par_map!(args...)  →  Parallel!.map!(receiver, args...)
```

Transform to a `CExpr_Perform` (effect operation call):
1. Create `CExpr_Perform{effect="Parallel!", op="map!", args=[receiver, ...args]}`
2. The receiver moves from method target to first argument of the effect operation

#### 15.4: `par { }` block desugaring

**In `src/canonicalize.odin`**:

When canonicalizing a `CExpr_Par` (new AST node, see 15.5):
```camp
par { e1, e2, e3 }
```
Desugars to:
```camp
Parallel!.all!([|| e1, || e2, || e3])
```

Implementation:
1. For each expression in the par block, wrap in a lambda: `|| e`
2. Create a list of these lambdas
3. Create `CExpr_Perform{effect="Parallel!", op="all!", args=[lambda_list]}`

#### 15.5: `par for` desugaring

```camp
par for x in xs { body }
```
Desugars to:
```camp
Parallel!.for_each!(xs, |x| body)
```

**AST nodes needed** (in `src/ast.odin`):
```odin
Expr_Par :: struct {
    expressions: [dynamic]Expr,  // for par { e1, e2 }
    for_var:     Intern_ID,      // for par for x in xs
    for_iter:    Expr,           // the xs
    for_body:    Expr,           // the body
    span:        Source_Span,
}
```

**Parser** (`src/parser.odin`): When `Kw_Par` is seen:
- If `{` follows → `par { }` block
- If `Kw_For` follows → `par for x in xs { body }`

**Canonical** (`src/canonical.odin`):
```odin
CExpr_Par :: struct {
    expressions: [dynamic]CExpr,
    for_var:     Intern_ID,
    for_iter:    CExpr,
    for_body:    CExpr,
    span:        Source_Span,
}
```

#### 15.6: Effect row propagation

Each Parallel! operation carries its inner function's effects through effect polymorphism:
```camp
map! : <a, b, e>|items: List(a), f: |a| -[e]-> b| -[Parallel! | e]-> List(b)
```

The typechecker needs to:
1. Extract the effect row variable `e` from the callback's type
2. Compose it with `Parallel!` in the operation's effect row
3. This is just effect polymorphism (Group 10) applied to Parallel! operations

#### 15.7: Formatter support

In `src/format_expr.odin`, add formatting for:
- `par { }` blocks
- `par for` blocks
- Method sugar calls (format as `list.par_map!(f)`)

#### 15.8: E2E tests

```camp
// Sequential parallel map
handle Parallel! in
  [1, 2, 3].par_map!(|x| x * 2)
with {
  .map!(resume, items, f) => resume(items.iter().map(f).collect())
}

// par block
handle Parallel! in
  par { compute_a!(), compute_b!() }
with {
  .all!(resume, tasks) => resume(tasks.iter().map(|t| t()).collect())
  ...
}
```

---

### Group 16: Spawn Effect — Sequential Handler

#### 16.1: Add Spawn! to prelude

In `inject_prelude`:
```odin
// Spawn! effect with operations:
// spawn!, join!, cancel!
```

#### 16.2: Add Handle(a) to prelude

`Handle(a)` is an opaque type with arity 1. Injected as a `Constructor` with arity 1.

#### 16.3: Sequential Spawn! handler

User writes:
```camp
handle Spawn! in ... with {
  .spawn!(resume, thunk) => {
    h = run_immediately(thunk)  // opaque handle
    resume(h)
  }
  .join!(resume, handle) => {
    result = get_result(handle)
    resume(result)
  }
  .cancel!(resume, handle) => resume({})
}
```

The compiler needs to support this handler pattern. Sequential implementation means spawn runs the thunk immediately (blocking).

#### 16.4: E2E tests

```camp
handle Spawn! in {
  h = Spawn!.spawn!(|| 42)
  result = Spawn!.join!(h)
  result
} with { ... }
```

---

### Group 17: Async Runtime

**Goal**: Coroutine scheduler + WASI poll bridge for concurrent I/O.

This is primarily **Odin host code** (not compiler passes). The scheduler runs in the WASM runtime, managing coroutines.

**Full design**: See `openspec/specs/parallelism/design.md` Phase 1.

**Implementation order**:
1. Scheduler data structures (ready queue, blocked map, handle table)
2. Scheduler loop (dequeue, resume, block, poll, complete)
3. Runtime functions (`camp_async_*`) in `src/runtime.odin`
4. WASI poll bridge
5. Short read/write handling
6. `Time.sleep!` via poll timeout
7. `Async!.yield!` and `Async!.spawn!`
8. Structured concurrency enforcement
9. Codegen integration (initialize scheduler in `_start` when `Async!` in main)
10. E2E tests

**Estimated scope**: ~1,410 lines of Odin.

---

### Group 18: Multi-Instance Spawn

**Goal**: True parallelism via multiple WASM instances on separate OS threads.

This is **Odin host code** (thread pool, closure serialization) + compiler changes (two-module compilation, `--threads=N` flag).

**Full design**: See `openspec/specs/parallelism/design.md` Phase 3.

**Implementation order**:
1. `--threads=N` CLI flag + `CAMP_THREADS` env var
2. Thread pool manager (MPMC queue, result map, workers)
3. Worker loop
4. Two-module compilation (or single dual-purpose module)
5. Closure serialization format
6. Closure deserialization in worker
7. Spawn! handler (serialize, submit, wait, deserialize)
8. Parallel! handler (chunk, spawn, join, concatenate)
9. Cross-instance data (deep copy strings/lists)
10. Error propagation (serialize thrown tags)
11. Structured concurrency tracking
12. E2E tests + benchmarks

**Estimated scope**: ~1,560 lines of Odin.

---

### Group 19: WASM Threads

**Goal**: In-process parallelism using WASM shared memory + atomics.

This requires IR node additions and codegen changes.

**Full design**: See `openspec/specs/parallelism/design.md` Phase 5.

#### 19.1-19.3: IR node types

Add to `src/ir.odin`:
```odin
IR_Atomic_Load :: struct {
    base:   IR_Expr,
    offset: int,
    width:  Atomic_Width,   // B1, B2, B4, B8
    span:    Source_Span,
}

IR_Atomic_Store :: struct {
    base:   IR_Expr,
    offset: int,
    value:  IR_Expr,
    width:  Atomic_Width,
    span:    Source_Span,
}

IR_Atomic_RMW :: struct {
    base:   IR_Expr,
    offset: int,
    value:  IR_Expr,
    op:     Atomic_Op,       // Add, Sub, And, Or, Xor, Xchg, CmpXchg
    width:  Atomic_Width,
    span:    Source_Span,
}

IR_Atomic_Fence :: struct {
    span: Source_Span,
}

IR_Wait :: struct {
    base:     IR_Expr,
    offset:   int,
    expected: IR_Expr,
    timeout:  IR_Expr,
    width:    Atomic_Width,
    span:      Source_Span,
}

IR_Notify :: struct {
    base:   IR_Expr,
    offset: int,
    count:  IR_Expr,
    span:    Source_Span,
}

Atomic_Width :: enum { B1, B2, B4, B8 }
Atomic_Op :: enum { Add, Sub, And, Or, Xor, Xchg, CmpXchg }
```

Add all to `IR_Expr` union. Update all pipeline passes to handle them (effect_lower, closure_convert, cps, rc, lower, codegen).

#### 19.4: Mid-end pass updates

Each pass needs a `#partial switch` case for the new IR types. Most passes can just recursively traverse (atomic ops are leaf-like). CPS and effect_lower may need specific handling.

#### 19.5: WASM opcode emission

Atomic opcodes use the `0xFE` prefix:
| IR Node | WASM Opcode |
|---------|------------|
| `IR_Atomic_Load{.B4}` | `0xFE 0x10` |
| `IR_Atomic_Store{.B4}` | `0xFE 0x17` |
| `IR_Atomic_RMW{.Add, .B4}` | `0xFE 0x1E` |
| `IR_Atomic_RMW{.CmpXchg, .B4}` | `0xFE 0x48` |
| `IR_Atomic_Fence` | `0xFE 0x50` |
| `IR_Wait{.B4}` | `0xFE 0x52` |
| `IR_Notify` | `0xFE 0x54` |

Each needs alignment byte + offset LEB128 after the opcode.

#### 19.6-19.7: Shared memory work queue

The work queue lives in shared WASM memory:
```
struct WorkQueue {
    head:     u32 (atomic)  // next dequeue index
    tail:     u32 (atomic)  // next enqueue index
    capacity: u32
    entries:  []WorkEntry   // { fn_index, env_offset, result_slot, flags }
}
```

Enqueue: `i32.atomic.rmw.add(tail, 1)` + write entry + `memory.atomic.notify`
Dequeue: `i32.atomic.rmw.add(head, 1)` + read entry

#### 19.8: Worker entry function codegen

Generate a `camp_worker_entry` export that loops:
```
loop:
  entry = dequeue(work_queue)
  if entry == 0: return  // queue empty
  call_indirect(entry.fn_index, entry.env_offset)
  store result in entry.result_slot
  memory.atomic.notify(result_slot)
  goto loop
```

#### 19.9-19.10: Per-thread heap regions

Each WASM agent allocates from its own region in shared memory. Bump allocator within the region (non-atomic — own thread only).

```odin
camp_alloc_region :: proc(size: i32, thread_id: i32) -> i32 {
    base = THREAD_HEAP_BASE + thread_id * THREAD_HEAP_SIZE
    offset = atomic_rmw_add(base + alloc_offset, size)
    return base + offset
}
```

#### 19.11-19.12: Migrate handlers to in-process

Spawn! and Parallel! handlers switch from multi-instance (serialize/deserialize closures) to in-process (pass closure pointers in shared memory).

#### 19.13: COOP/COEP warning

When targeting browsers, emit a warning if `--threads=N > 1` that `SharedArrayBuffer` requires COOP/COEP headers.

#### 19.14: Runtime detection + fallback

At compiler startup, detect WASM threads support:
1. Try creating shared `Memory` → if fails, fall back to multi-instance
2. Try multi-instance (N stores on N threads) → if fails, fall back to sequential
3. Sequential handler always works

#### 19.15: E2E tests

Test that `Spawn!.spawn!` and `Parallel!.map!` work within a single WASM module using shared memory.

---

## Key Data Structures Reference

### Current Type_Store (src/types.odin)
```odin
Type_Store :: struct {
    vars:             [dynamic]Type_Var,
    next_id:          Type_Var_ID,
    current_level:    int,
    interner:         ^Intern_Table,
    collector:        ^Diagnostic_Collector,
    declared_effects: [dynamic]Intern_ID,
    bindings:         map[Intern_ID]Type_Var_ID,
    newtype_decls:    map[Intern_ID]Newtype_Decl_Info,
    trait_registry:   map[Intern_ID]Trait_Info,
    trait_impls:      [dynamic]Trait_Impl,
    type_constraints: map[Type_Var_ID][]Intern_ID,
    rec_vars:         [dynamic]Type_Var_ID,  // from Group 2 cherry-pick
}
```

**Will need additions for**:
- `effect_ops: map[Intern_ID][]Effect_Op_Info` — operation signatures per effect (Group 11)
- Potentially `effect_type_params: map[Intern_ID][]Intern_ID` — type parameter names per effect (Group 9)

### Current Runtime Functions (src/codegen.odin)
```odin
RUNTIME_ALLOC     :: 0
RUNTIME_DUP       :: 1
RUNTIME_DROP      :: 2
RUNTIME_PRINT_STR :: 3
RUNTIME_EXIT      :: 4
RUNTIME_DEALLOC   :: 5
RUNTIME_FUNC_COUNT :: 6
```

**Will need additions for** Groups 13, 17 (list ops, string ops, async scheduler, etc.)

### Current IR_Expr Variants (28)
```
IR_Literal_Int, IR_Literal_Float, IR_Literal_String, IR_Literal_Bool,
IR_Var, IR_Let, IR_Call, IR_Tail_Call,
IR_If, IR_Match, IR_Construct_Tag, IR_Construct_Record,
IR_Field_Access, IR_Method_Call, IR_Handle, IR_Perform,
IR_Resume, IR_Closure, IR_Closure_Call, IR_Return,
IR_Block, IR_BinOp, IR_Dup, IR_Drop,
IR_Drop_Reuse, IR_Alloc_At, IR_Crash, IR_I32_Load,
IR_I32_Store
```

**Will need additions for** Group 19 (atomic ops).

### Pipeline Pass Order
```
parse → canonicalize → typecheck → annotate → mono
  → lower → effect_lower → closure_convert → cps → rc → codegen
```

**Key constraint**: effect_lower runs before CPS and codegen. After effect_lower, `IR_Handle` and `IR_Perform` are dead code. The codegen `Wasm_Unreachable` for those nodes is a safety net, not the primary path.
