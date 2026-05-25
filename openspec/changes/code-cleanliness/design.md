# Design: Code Cleanliness & Memory Management Overhaul

## Architecture Decisions

### AD1: Error Propagation via Build_Result Union

**Decision**: `Build_Result :: union { Success: Build_Output, Failed: string }`

**Rationale**: Replaces 41 `os.exit` calls with structured error returns. `os.exit` moves to `main.odin` only. Enables compiler embedding as library.

**Impact**: `run_build_single`, `run_build_project`, `run_check`, `run_test` all return `Build_Result`. Callers in `main.odin` map `Failed` to `os.exit(1)`.

**Exit sites by file**:
- `build/build.odin` — 17 exits in `run_build_single`, `run_test`, `run_check`
- `build/project.odin` — 11 exits in `run_build_project`, `parse_and_canonicalize`, `combine_module_irs`
- `format/run.odin` — 7 exits in `run_format`
- `lsp/server.odin` — 2 exits (shutdown — keep as-is, process termination)
- `e2e/e2e.odin` — 1 exit (test runner failure — keep as-is)
- `e2e/runner.odin` — 1 exit (timeout kill)
- `test_bootstrap.odin` — 1 exit
- `test_integration.odin` — 1 exit

**Implementation strategy**:
1. Define `Build_Output :: struct { wasm_path: string, has_errors: bool }` and `Build_Error :: struct { message: string, code: int }`
2. Define `Build_Result :: union { Success: Build_Output, Failed: Build_Error }`
3. Replace each `os.exit(N)` with `return Build_Result.Failed(Build_Error{...})`
4. Format gets separate `Format_Result :: union { Success: Format_Output, Failed: Format_Error }` (different output type)
5. LSP/e2e/test exits remain — they're top-level process boundaries
6. `main.odin` pattern: `result := run_build_single(...); switch result { case .Failed: os.exit(1) }`

### AD2: LSP JSON Leak — Per-Request Arena

**Decision**: Allocate JSON parse trees from a small per-request arena destroyed after dispatch.

**Rationale**: Simple, clean, no manual tree walking. Arena lifetime matches request lifetime.

**Impact**: `server_loop` creates arena before `json.parse`, destroys after dispatch completes.

**Status**: IMPLEMENTED in Phase 2.

### AD3: Visitor Pattern — Function-Pointer Struct → WON'T DO

**Decision**: Keep `#partial switch` for transforms. `walk.odin` for pure traversals.

**Rationale**: All 6 IR passes and 3 AST passes are *transforms* (rebuild the tree), not pure traversals. A function-pointer visitor struct with 33+ methods must implement all methods even for identity traversal. The `walk_expr_children`/`walk_decl_children` procs in `src/ir/walk.odin` serve the pure-walking use case. For transforms, `#partial switch` is idiomatic Odin — the compiler flags unhandled variants when `#partial` is removed.

**Status**: WON'T DO for pass refactoring. `walk.odin` remains available for future pure-traversal needs.

### AD4: Type_Var — Index-Based Access

**Decision**: Replace `^Type_Var` with `store.vars[int(id)]` throughout. Remove `get_var` proc.

**Rationale**: Pointers into `[dynamic]` arrays are inherently unsafe (append can reallocate). Indexes are safe, cache-friendly, and follow DoD principles. No benchmark needed — safety win alone justifies it.

**Impact**: All `get_var` callers use `store.vars[int(id)]` instead of dereferencing a pointer. Eliminates latent UAF risk.

**Call sites by file** (70+ total):
- `semantics/types.odin` — `get_var` defined at line 317, called ~20 times within the file
- `semantics/unify.odin` — ~15 calls to `get_var`
- `semantics/typecheck.odin` — ~25 calls to `get_var`
- `semantics/lower_type.odin` — ~8 calls to `get_var`
- `mono/mono.odin` — ~5 calls to `get_var`

**Migration pattern**:
```odin
// Before (pointer, UAF risk):
v := get_var(store, id)
link := v.link        // could dangle if append happened
v.link = new_link     // writes to potentially-freed memory

// After (index, safe):
v := store.vars[int(id)]
link := v.link                    // value copy — safe
store.vars[int(id)].link = new_link  // direct mutation — safe
```

**Caveat**: Some patterns read a field, then call `fresh_var` (which appends), then read another field. With index-based access, re-reading `store.vars[int(id)]` after the append is safe. With pointers, the re-read would use a dangling pointer.

### AD5: #partial Switch Catch-Alls — Explicit Pass-Through

**Decision**: Replace bare `case:` catch-alls with explicit pass-through groups. Small unions → exhaustive `switch`.

**Rationale**: Bare `case:` in `#partial switch` silently swallows new variants. When a new expression type is added, the compiler won't flag these sites. Explicit pass-through lists are self-documenting and break at compile time when variants change.

**Strategy**:
- **Small unions** (≤8 variants, e.g. `IR_Pattern` with 7): convert to exhaustive `switch` with all cases listed
- **Large unions** (>8 variants, e.g. `IR_Expr` with 37): keep `#partial switch` but replace bare `case:` with explicit pass-through lists:
  ```odin
  // Before:
  #partial switch expr {
  case .Int:
      ...
  case:  // silently catches everything else
  }

  // After:
  #partial switch expr {
  case .Int:
      ...
  case .Float, .String, .Bool, .Name, .Call, .Lambda, .Binop, ...:
      // explicit pass-through — compiler flags new variants
  }
  ```
- **Traversal switches** (walk children, collect locals): wait until walk pattern is more mature

**Priority sites** (by count):
1. `codegen/emit_expr.odin` — 30+ bare `case:` in `emit_expr` and `collect_locals`
2. `semantics/typecheck.odin` — 12 bare `case:` in `typecheck_synth`
3. `ir/lower.odin` — 8 bare `case:` in `lower_texpr`
4. `ir/effect_lower.odin` — 3 bare `case:`
5. `analysis/unused.odin` — 7 bare `case:` in `collect_uses_expr`
6. `ir/cps.odin` — 5 bare `case:`
7. `ir/closure_convert.odin` — 5 bare `case:`
8. `ir/rc.odin` — 5 bare `case:`
9. `mono/mono.odin` — 3 bare `case:`
10. `semantics/canonicalize.odin` — 2 bare `case:`

### AD6: Inferred_Type — Sparse Fields via Parallel Arrays

**Decision**: Move variant-specific data to parallel arrays in Type_Store. Inferred_Type shrinks to tag + index.

**Rationale**: Most Inferred_Type variants carry 3-4 nil fields. Sparse storage saves ~40 bytes per type var on average and improves cache locality for the common case (unlinked/fresh vars).

**Depends on**: Task 9 (index-based access) — after removing `get_var` pointer patterns, parallel arrays become natural.

**Current Inferred_Type** (~96 bytes):
```odin
Inferred_Type :: struct {
    tag:            Inferred_Type_Tag,
    param_ids:      []Type_Var_ID,     // only .Function, .Newtype
    return_id:      Type_Var_ID,        // only .Function
    effect_id:      Type_Var_ID,        // only .Function
    record_fields:  []Record_Field,     // only .Record_Row
    tag_entries:    []Tag_Entry,        // only .Tag_Union_Row
    effects:        []Type_Var_ID,      // only .Effect_Row
    bound:          Type_Var_ID,        // only .Con, .Arrow
    scope:          Intern_ID,          // only .Con
}
```

**Target Inferred_Type** (~8 bytes):
```odin
Inferred_Type :: struct {
    tag:   Inferred_Type_Tag,
    index: int,  // index into the relevant parallel array
}

// In Type_Store:
function_data:    [dynamic]Function_Data,     // param_ids, return_id, effect_id
record_row_data:  [dynamic]Record_Row_Data,   // fields
tag_union_data:   [dynamic]Tag_Union_Data,    // entries
effect_row_data:  [dynamic]Effect_Row_Data,  // effects
primitive_data:   [dynamic]Primitive_Data,    // bound, scope (for Con/Arrow)
handle_data:      [dynamic]Handle_Data,       // effect, ops
newtype_data:     [dynamic]Newtype_Data,      // param_ids, tag_id
```

**Access pattern change**:
```odin
// Before:
inf, ok := v.link.(Inferred_Type)
param_ids := inf.param_ids  // directly on struct

// After:
inf, ok := v.link.(Inferred_Type)
switch inf.tag {
case .Function:
    fd := store.function_data[inf.index]
    param_ids := fd.param_ids
case .Record_Row:
    rd := store.record_row_data[inf.index]
    fields := rd.fields
...
}
```

**type_store_destroy simplification**:
```odin
// Before: walks every Inferred_Type variant and deletes variant-specific slices
// After: just delete top-level parallel arrays
delete(store.function_data)
delete(store.record_row_data)
delete(store.tag_union_data)
delete(store.effect_row_data)
delete(store.primitive_data)
delete(store.handle_data)
delete(store.newtype_data)
```

### AD7: WASM Atomics — Table-Driven

**Decision**: Replace ~100 identical struct definitions + ~80 encoding cases with single `Wasm_Atomic_Mem` struct + opcode lookup helpers.

**Rationale**: ~500 lines of structural copy-paste. Table-driven approach is ~50 lines.

**Current state** (`wasm.odin` lines 108-253):
- ~100 structs like `Wasm_I32_Atomic_Load`, `Wasm_I64_Atomic_Load`, `Wasm_I32_Atomic_Load8U`, etc.
- All have identical fields: `{ align: u32, offset: u32 }`

**Current state** (`wasm.odin` lines 628-958):
- ~80 encoding `case` arms, all identical except for a 2-byte opcode prefix

**Target design**:
```odin
// Single struct replaces all ~100 variants
Wasm_Atomic_Mem :: struct {
    align:   u32,
    offset:  u32,
}

// Two helpers for opcode lookup
atomic_opcode_base :: proc(op: Atomic_Op) -> (prefix: u8, sub_opcode: u8) { ... }
atomic_width_offset :: proc(width: Atomic_Width) -> u8 { ... }

// Encoding becomes:
case .Atomic_Mem:
    prefix, sub := atomic_opcode_base(instr.op)
    width_off := atomic_width_offset(instr.width)
    append(buf, 0xFE)         // atomic prefix
    append(buf, sub + width_off)
    encode_u32_leb128(instr.mem.align, buf)
    encode_u32_leb128(instr.mem.offset, buf)
```

**Wasm_Instruction union change**:
```odin
// Before: ~100 union variants
Wasm_I32_Atomic_Load,
Wasm_I64_Atomic_Load,
Wasm_I32_Atomic_Load8U,
...

// After: single variant with op + width + mem
Atomic_Mem: Wasm_Atomic_Mem,  // op + width encode the specific instruction
```

**Requires**: Adding `op: Atomic_Op` and `width: Atomic_Width` fields to `Wasm_Atomic_Mem`, or storing them alongside the instruction variant.

**Estimated savings**: ~500 lines removed from `wasm.odin`.

### AD8: Package Splits → WON'T DO

**Decision**: Keep `base` and `semantics` as single packages.

**Rationale for base**:
- 7 files already provide file-level separation (intern.odin, token.odin, span.odin, etc.)
- Sub-packages would change `base.Intern_ID` → `base.intern.Intern_ID` everywhere
- 59 files import `camp:base` — the namespace verbosity outweighs organizational clarity
- No coupling issue: files within a package can't create circular dependencies

**Rationale for semantics**:
- Same argument: 22 files import `camp:semantics`
- `Type_Store`, `Inferred_Type`, `IR_Type` are used pervasively across the codebase
- `semantics.core.Type_Store` vs `semantics.Type_Store` — no functional benefit

### AD9: Build_Result Union — Detailed Design

**Types**:
```odin
Build_Output :: struct {
    wasm_path:  string,
    has_errors: bool,
}

Build_Error :: struct {
    message: string,
    code:    int,  // exit code (typically 1)
}

Build_Result :: union {
    Success: Build_Output,
    Failed:  Build_Error,
}
```

**Per-function return types**:
| Function | Current exit pattern | New return type |
|----------|---------------------|-----------------|
| `run_build_single` | `os.exit` × 6 | `Build_Result` |
| `run_build_project` | `os.exit` × 11 | `Build_Result` |
| `run_check` | `os.exit` × 4 | `Build_Result` |
| `run_test` | `os.exit` × 3 | `Build_Result` |
| `run_format` | `os.exit` × 7 | `Format_Result` |

**Format_Result** (different output type):
```odin
Format_Result :: union {
    Success: Format_Output,
    Failed:  Build_Error,  // reuse Build_Error
}
```

**main.odin pattern**:
```odin
result := build.run_build_single(...)
switch result {
case .Success:
    // done
case .Failed:
    os.exit(1)  // os.exit only here
}
```

**Error messages**: Each `os.exit` site is replaced with a descriptive error:
```odin
// Before:
if !strings.has_suffix(path, ".camp") do os.exit(1)

// After:
if !strings.has_suffix(path, ".camp") {
    return Build_Result.Failed(Build_Error{
        message = fmt.tprintf("invalid file extension: {}", path),
        code = 1,
    })
}
```

**LSP impact**: LSP doesn't use `os.exit` for errors (it sends error responses), so no change needed.

### AD10: Inferred_Type Parallel Arrays — Detailed Data Layout

**Function_Data**:
```odin
Function_Data :: struct {
    param_ids:  []Type_Var_ID,
    return_id:  Type_Var_ID,
    effect_id:  Type_Var_ID,
}
```

**Record_Row_Data**:
```odin
Record_Row_Data :: struct {
    fields: []Record_Field,
}
```

**Tag_Union_Data**:
```odin
Tag_Union_Data :: struct {
    entries: []Tag_Entry,
}
```

**Effect_Row_Data**:
```odin
Effect_Row_Data :: struct {
    effects: []Type_Var_ID,
}
```

**Primitive_Data** (for Con, Arrow, and simple variants):
```odin
Primitive_Data :: struct {
    bound: Type_Var_ID,  // .Con, .Arrow
    scope: Intern_ID,    // .Con
}
```

**Handle_Data**:
```odin
Handle_Data :: struct {
    effect_id: Type_Var_ID,
    ops:       map[Intern_ID][]Type_Var_ID,
}
```

**Newtype_Data**:
```odin
Newtype_Data :: struct {
    param_ids: []Type_Var_ID,
    tag_id:    Type_Var_ID,
}
```

**Index assignment**: When creating a new Inferred_Type, allocate from the relevant parallel array:
```odin
// Before:
inf := Inferred_Type{
    .Function,
    param_ids = ...,
    return_id = ...,
    effect_id = ...,
}
v.link = Inferred_Type(inf)

// After:
idx := len(store.function_data)
append(&store.function_data, Function_Data{param_ids = ..., return_id = ..., effect_id = ...})
v.link = Inferred_Type{.Function, index = idx}
```

**Unlinked/Fresh vars**: No parallel array needed — `index` is unused for these tags. Can use `index = -1` as sentinel.

### AD11: Intern_Table SoA — Deferred

**Current** (`base/intern.odin`):
```odin
Intern_Table :: struct {
    strings: map[string]Intern_ID,   // hash map: string → ID
    ids:     [dynamic]string,         // ID → string
}
```

**Target**:
```odin
Intern_Table :: struct {
    count:       int,
    capacity:    int,
    hashes:      [dynamic]u64,        // FNV-1a hashes
    offsets:     [dynamic]u32,         // byte offset into string_buffer
    lengths:     [dynamic]u32,        // string length in bytes
    string_buf:  [dynamic]u8,         // contiguous string storage
    lookup_idx:  [dynamic]int,        // open-addressing indices
}
```

**Savings**: Eliminates per-string `map` entry overhead + per-entry `[dynamic]string` allocation. Strings stored contiguously → better cache locality for interning. Estimated ~50% memory reduction.

**DEFERRED**: Current interner is small (<1000 entries typical). Custom hash table adds ~150 lines for marginal runtime benefit. Revisit if profiling shows interning as a hotspot.

### AD12: emit_start.odin Extraction

**Current**: `codegen` proc (790 lines) contains `emit_start_function` logic inline (~400 lines of CPS evidence allocation, closure construction, main call, string data emission).

**Target**: Extract to `src/codegen/emit_start.odin`:
- `emit_start_function :: proc(env: ^Codegen_Env, mod: ^Wasm_Module, ir_decls: []IR_Decl, ...)`
- String data emission helpers
- CPS continuation setup

**Cross-file state**: Add `func_type_indices: map[string]int` to `Codegen_Env` so `emit_start` can look up function type indices created in the main `codegen` proc.

**Result**: `codegen.odin` shrinks from ~987 to ~600 lines. `emit_start.odin` is ~400 lines.

### AD13: check_decl.odin Extraction

**Current**: `typecheck.odin` (1834 lines) contains declaration typechecking interleaved with expression typechecking.

**Procs to move** to `src/semantics/check_decl.odin`:
- `typecheck_decl` — dispatches on CDecl variants
- `typecheck_newtype_decl` — newtype declaration checking
- `typecheck_trait_decl` — trait declaration
- `verify_trait_conformance` — trait implementation verification
- `ctype_contains_self` — self-type checking
- `convert_ctype_self_aware` — self-type conversion
- `extract_trait_methods_from_ctype` — method extraction
- `check_constraint_violation` — constraint checking
- `typecheck_newtype_construct` — newtype construction
- `newtype_owning_tag` — tag ownership
- `is_same_module` — module comparison

**Same `package semantics`** — no import changes needed. All procs reference `Type_Store`, `Type_Env`, `Inferred_Type` etc. from the same package.

**Result**: `typecheck.odin` shrinks from ~1834 to ~1200 lines. `check_decl.odin` is ~650 lines.

## Memory Management Design

### Allocator Switching Simplification
Current: 72 `context.allocator` assignments with save/restore pairs.
Target: Set `context.allocator = ctx.allocator` once at top of each compilation entry point with `defer` restore. Remove all intermediate save/restores.

**Status**: IMPLEMENTED for `run_build_single` (Phase 2) and `project.odin` (Phase 4).

### type_store_destroy Under Arena
Currently does O(n) per-element deletes that are no-ops under arena. After index-based Type_Var refactor (Task 9) and parallel arrays (Task 10), simplify to just `delete()` of the parallel arrays + top-level containers. The arena handles the rest.

### Missing defers
**Status**: ALL IMPLEMENTED in Phase 2.

### e2e Test String Leaks
**Status**: IMPLEMENTED in Phase 2 (`destroy_tests` proc).
