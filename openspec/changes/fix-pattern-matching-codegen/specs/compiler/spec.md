## MODIFIED Requirements

### Requirement: Source-to-WASM Compilation
The compiler SHALL accept Camp source text and produce valid WASM/WASI modules.

#### Scenario: Compile a simple program
- **WHEN** Camp source `"main! = || -> I64 { 42 }"` is compiled
- **THEN** the compiler SHALL produce a valid WASM/WASI module that passes wasmtime validation and exits with code 42

#### Scenario: memory.copy encoding
- **WHEN** the compiler emits a `memory.copy` instruction
- **THEN** the WASM binary SHALL encode `0xFC 0x0A 0x00 0x00` (opcode + two memidx bytes for memory 0)

#### Scenario: _start function has sufficient locals
- **WHEN** the _start function inlines a match expression that requires temporary locals (e.g. i64 scrutinee)
- **THEN** the function's local declarations SHALL include all dynamically-allocated temporaries

### Requirement: Match Pattern Typechecking
The compiler SHALL typecheck match patterns against their scrutinee types. Pattern variables SHALL be bound into the type environment with correct types. Tag payload loads SHALL use type-aware load instructions matching the payload's WASM type.

#### Scenario: Tag payload i64 field loaded correctly
- **WHEN** a match on `[Ok(I64) | Error(I64)]` extracts payload `v` from `Ok(v)`
- **THEN** the generated WASM SHALL use `i64.load` for the payload field, not `i32.load`

#### Scenario: Tag payload i32 field loaded correctly
- **WHEN** a match on `[Ok(I32) | Error(I32)]` extracts payload `v` from `Ok(v)`
- **THEN** the generated WASM SHALL use `i32.load` for the payload field
