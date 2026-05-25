# Specs: Code Cleanliness & Memory Management

## Compiler Build Pipeline

### Build Result Propagation
- Given a compilation that encounters an error
- When `run_build_single` processes the error
- Then it SHALL return `Build_Result.Failed` with a descriptive message
- And it SHALL NOT call `os.exit` directly
- And `os.exit` SHALL only be called in `main.odin`

### Build Result Types
- `Build_Output :: struct { wasm_path: string, has_errors: bool }`
- `Build_Error :: struct { message: string, code: int }`
- `Build_Result :: union { Success: Build_Output, Failed: Build_Error }`
- `Format_Result :: union { Success: Format_Output, Failed: Build_Error }`

### Arena Cleanup on Error
- Given a compilation that fails after arena initialization
- When the error is detected
- Then `context_destroy` SHALL be called via `defer` before returning
- And `type_store_destroy` SHALL be called via `defer` immediately after `type_store_init`

### Allocator Switching
- Given a compilation entry point (`run_build_single`, `run_build_project`, `run_check`)
- When the arena allocator is set
- Then `context.allocator` SHALL be set once at the top with a single `defer` restore
- And intermediate save/restore pairs SHALL be removed

## LSP Server

### JSON Parse Tree Lifetime
- Given an LSP server processing a request
- When `json.parse` allocates a value tree
- Then the tree SHALL be allocated from a per-request arena
- And the arena SHALL be destroyed after request dispatch completes
- And no JSON parse tree memory SHALL persist between requests

### LSP Error Handling
- Given a malformed LSP request with invalid JSON fields
- When `json_get_int` or `json_get_string` fails
- Then the server SHALL return an error response with `InvalidParams` code
- And it SHALL NOT silently produce default (0,0) coordinates

## Codegen

### Layer Isolation
- Given the codegen package
- When it needs type information for match compilation
- Then it SHALL read `payload_wasm_types` from `IR_Pat_Tag` nodes
- And it SHALL NOT import the `semantics` package

### File Organization
- Given `codegen.odin` exceeds 2500 lines
- When decomposed into separate files
- Then `emit_expr` SHALL live in `emit_expr.odin`
- And runtime function emission SHALL live in `emit_runtime.odin`
- And `_start` function emission SHALL live in `emit_start.odin`
- And `func_type_indices: map[string]int` SHALL be added to `Codegen_Env` for cross-file state

### WASM Atomics
- Given ~100 near-identical WASM atomic struct definitions
- When a new atomic operation variant is needed
- Then it SHALL be added to a single `Wasm_Atomic_Mem` struct with `op` and `width` fields
- And no per-variant struct definition SHALL be required
- And encoding SHALL use `atomic_opcode_base` + `atomic_width_offset` helpers
- And the `Wasm_Instruction` union SHALL use a single `Atomic_Mem` variant

## Type System

### Type_Var Access Safety
- Given a `Type_Var_ID` value
- When accessing the type variable
- Then code SHALL use `store.vars[int(id)]` (index-based access)
- And it SHALL NOT use `get_var` (returns `^Type_Var` pointer, UAF risk)
- And `get_var` SHALL be removed from `semantics/types.odin`
- And `^Type_Var` pointers SHALL NOT be stored across `fresh_var` calls

### Inferred_Type Memory Layout
- Given an `Inferred_Type` value
- When it is created
- Then it SHALL contain only `tag: Inferred_Type_Tag` + `index: int` fields
- And variant-specific data SHALL live in parallel arrays in `Type_Store`
- And `.Function` variants SHALL store data in `store.function_data[index]`
- And `.Record_Row` variants SHALL store data in `store.record_row_data[index]`
- And `.Tag_Union_Row` variants SHALL store data in `store.tag_union_data[index]`
- And `.Effect_Row` variants SHALL store data in `store.effect_row_data[index]`
- And `.Con`/`.Arrow` variants SHALL store data in `store.primitive_data[index]`
- And `.Handle` variants SHALL store data in `store.handle_data[index]`
- And `.Newtype` variants SHALL store data in `store.newtype_data[index]`
- And `.Unlinked`/`.Fresh`/`.Link` variants SHALL use `index = -1`

### type_store_destroy Simplification
- Given a `Type_Store` with parallel arrays
- When `type_store_destroy` is called
- Then it SHALL `delete` each parallel array (`function_data`, `record_row_data`, etc.)
- And it SHALL NOT iterate per-variant to delete variant-specific slices

## Diagnostics

### Format String Constants
- Given the format string `"expected {}, got {}"`
- When used in diagnostic constructors
- Then it SHALL reference a single named constant `EXPECTED_GOT_FMT`
- And the constant SHALL be defined once in `diagnostics/constructors.odin`

### Diagnostic Constructors
- Given 40+ diagnostic constructor procs in `constructors.odin`
- When a new diagnostic is needed
- Then a new constructor proc SHALL be added with type-safe parameters
- And constructors SHALL NOT be replaced by a data-driven enum approach
- And each constructor's unique parameters, format, labels, and hints are inherent to the type-safe design

## Switch Exhaustiveness

### #partial Switch Catch-Alls
- Given a `#partial switch` over an enum or union type
- When the switch has a bare `case:` catch-all
- Then it SHALL be replaced with explicit pass-through group listing all unhandled variants
- And small unions (≤8 variants) SHALL use exhaustive `switch` instead of `#partial switch`
- And adding a new variant to the union SHALL cause a compile error at pass-through sites

## IR Walk

### IR Child Traversal
- Given an IR expression tree
- When a pass needs to traverse children without transforming
- Then the pass SHALL use `walk_expr_children` from `src/ir/walk.odin`
- And `walk_decl_children` SHALL traverse `IR_Decl` children
- And adding a new IR node type SHALL require updating only `walk.odin`

### IR Transforms
- Given an IR pass that transforms the tree (lower, cps, closure_convert, effect_lower, rc, mono)
- When implementing the pass
- Then `#partial switch` SHALL remain the idiomatic pattern
- And the pass SHALL NOT be required to implement a visitor struct

## Package Organization

### base Package
- Given the `base` package with 7 files
- When organizing types
- Then file-level separation within a single package SHALL suffice
- And sub-packages (`base/intern`, `base/source`, `base/types`) SHALL NOT be created
- And the `base.X` namespace SHALL remain flat

### semantics Package
- Given the `semantics` package with 10 files
- When organizing typechecking
- Then a single package SHALL suffice
- And sub-packages (`semantics/core`, `semantics/check`) SHALL NOT be created

## Test Infrastructure

### Test Helper Consolidation
- Given 4 near-identical test setup functions in `test_typecheck.odin`
- When a new test variation is needed
- Then it SHALL use `setup_for_typecheck :: proc(opts: Test_Options) -> Test_Context`
- And `Test_Options` SHALL encode variations (with_prelude, with_module, full_pipeline)

### Test Memory Cleanup
- Given a test that creates a `Diagnostic_Collector`
- When the test completes
- Then `diag_collector_destroy` SHALL be called before `free(collector)`
- And the internal `[dynamic]Diagnostic` array SHALL be freed

## Intern_Table (Deferred)

### SoA Layout
- Given the `Intern_Table` with `map[string]Intern_ID` + `[dynamic]string`
- When interning becomes a performance hotspot
- Then it SHALL be restructured to `hashes: [dynamic]u64` + `offsets: [dynamic]u32` + contiguous string buffer
- And the current AoS layout SHALL remain until profiling justifies the change
