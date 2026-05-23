## ADDED Requirements

### Requirement: i64 arithmetic and bitwise WASM instructions
The compiler SHALL support the following WASM i64 instructions: `i64.div_s` (0x7F), `i64.div_u` (0x80), `i64.rem_s` (0x81), `i64.rem_u` (0x82), `i64.and` (0x83), `i64.or` (0x84), `i64.xor` (0x85), `i64.shl` (0x86), `i64.shr_s` (0x87), `i64.shr_u` (0x88).

#### Scenario: i64 bitwise AND produces correct opcode
- **WHEN** the compiler lowers an i64 bitwise AND expression to WASM
- **THEN** the emitted binary contains opcode byte `0x83`

#### Scenario: i64 bitwise OR produces correct opcode
- **WHEN** the compiler lowers an i64 bitwise OR expression to WASM
- **THEN** the emitted binary contains opcode byte `0x84`

#### Scenario: i64 division produces correct opcodes
- **WHEN** the compiler lowers signed i64 division to WASM
- **THEN** the emitted binary contains opcode byte `0x7F`

#### Scenario: i64 remainder produces correct opcodes
- **WHEN** the compiler lowers unsigned i64 remainder to WASM
- **THEN** the emitted binary contains opcode byte `0x82`

### Requirement: i32.rem_u WASM instruction
The compiler SHALL support `i32.rem_u` (0x70).

#### Scenario: i32 unsigned remainder
- **WHEN** the compiler lowers an unsigned i32 remainder expression to WASM
- **THEN** the emitted binary contains opcode byte `0x70`

### Requirement: f64.load emits exactly one opcode
The `f64.load` instruction SHALL emit exactly opcode `0x2B` with its align and offset operands, and SHALL NOT emit any additional instructions.

#### Scenario: f64.load produces correct single opcode
- **WHEN** the compiler lowers an f64.load to WASM
- **THEN** the emitted binary contains `0x2B` followed by align and offset, with no trailing `0x37` (i64.store)
