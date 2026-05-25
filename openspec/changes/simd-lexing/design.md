# Design: SIMD Lexing

## Architecture Decisions

### AD1: Character Classification via 256-Entry Lookup Tables

**Decision**: Replace the `single_char_tokens` map (re-created per `lexer_next` call) with compile-time constant `[256]Token_Kind` and `[256]Char_Class` arrays.

**Rationale**: The current `map[u8]Token_Kind` with 17 entries is allocated on every `lexer_next` invocation that reaches the single-char-token fallthrough path. A fixed 256-entry array eliminates allocation entirely and provides O(1) lookup for all byte values. The `Char_Class` bitmask table enables SIMD scanners to classify bytes by category.

**File**: New `src/frontend/char_class.odin`

```odin
Char_Class :: enum bits {
    None           = 0,
    Whitespace     = 1,    // ' ', '\t', '\r'
    Newline        = 2,    // '\n'
    Ident_Start    = 4,    // a-z, A-Z, _
    Ident_Continue = 8,    // Ident_Start + 0-9
    Digit          = 16,   // 0-9
    Hex_Digit      = 32,   // 0-9, a-f, A-F
    Operator_Start = 64,   // +, -, *, /, %, &, |, ^, ~, =, <, >, !, ., :
    Delimiter      = 128,  // (, ), [, ], {, }
}

CHAR_CLASS: [256]Char_Class // compile-time populated
SINGLE_CHAR_TOKEN: [256]Token_Kind // 0 for non-token bytes
```

**Impact**: Eliminates per-call map allocation. Enables SIMD scanners to classify bytes by category. All existing tests pass unchanged.

### AD2: SIMD Whitespace Skipping — Unconditional Newline Consumption

**Decision**: The SIMD whitespace scanner always consumes newlines as whitespace. No newline tokens are ever emitted.

**Rationale**: Audit of the current parser shows it never receives `.Newline` tokens. The lexer's `lexer_skip_whitespace` consumes `\n` identically to spaces and tabs, with only `at_line_start = true` as a side effect. The 4 references to `.Newline` in the parser are unreachable exhaustive-match safety nets. This means the SIMD scanner can process whitespace in bulk without complex newline-emission logic — it only needs to track the `at_line_start` boolean.

**`at_line_start` tracking in SIMD**: After skipping a SIMD chunk, check if any `\n` byte was consumed via `popcount` on the newline bitmask. If yes, `at_line_start = true`. When non-whitespace content is encountered, `at_line_start = false`.

**Algorithm**:

```
skip_whitespace_simd:
  while pos < len:
    if remaining < 16: fall back to scalar
    
    chunk = u8x16_load_unaligned(source[pos:])
    ws_mask = lanes_eq(chunk, ' ') | lanes_eq(chunk, '\t') | lanes_eq(chunk, '\r')
    nl_mask = lanes_eq(chunk, '\n')
    all_ws = ws_mask | nl_mask
    
    first_non_ws = ctz(~all_ws)  // first byte that is NOT whitespace
    
    if first_non_ws < 16:
      // Some non-whitespace in this chunk
      if popcount(nl_mask & ((1 << first_non_ws) - 1)) > 0:
        at_line_start = true
      pos += first_non_ws
      
      // Check for // comment start
      if source[pos] == '/' and pos+1 < len and source[pos+1] == '/':
        if source[pos+2] == '/':
          break  // /// doc comment — let lexer_next emit it
        skip_to_next_newline()  // scalar: find end of line comment
        at_line_start = true
        continue
      
      at_line_start = false
      break  // found token start
    else:
      // All 16 bytes are whitespace
      if popcount(nl_mask) > 0: at_line_start = true
      pos += 16
```

**Comment handling**: When SIMD scan finds `//`, fall back to scalar for comment-end detection. For `///`, break out of whitespace skipping so `lexer_next` can produce the `Doc_Comment` token. This is a deliberate scalar fallback for a rare case.

### AD3: SIMD Identifier Scanning

**Decision**: After detecting an identifier-start byte, scan forward in 16-byte chunks using `u8x16` range comparisons to find the identifier end.

**Algorithm**:

```
scan_identifier_simd:
  start = pos
  pos += 1  // consume identifier-start byte
  
  while pos < len:
    if remaining < 16:
      // scalar scan remainder
      while is_identifier_continue(source[pos]): pos += 1
      break
    
    chunk = u8x16_load_unaligned(source[pos:])
    lo_alpha = lanes_ge(chunk, 'a') & lanes_le(chunk, 'z')
    hi_alpha = lanes_ge(chunk, 'A') & lanes_le(chunk, 'Z')
    digit    = lanes_ge(chunk, '0') & lanes_le(chunk, '9')
    under    = lanes_eq(chunk, '_')
    
    ident_mask = lo_alpha | hi_alpha | digit | under
    first_non_ident = ctz(~ident_mask)
    
    if first_non_ident < 16:
      pos += first_non_ident
      break
    else:
      pos += 16
  
  // Absorb ! suffix (not before =)
  if pos < len and source[pos] == '!' and (pos+1 >= len or source[pos+1] != '='):
    pos += 1
  
  // Keyword lookup unchanged
  text = source[start:pos]
  kind = KEYWORDS[text] or Upper_Id or Identifier
```

**Alternative (deferred)**: `pshub`/`runtime_swizzle` approach — load a 256-byte classification table as 16-byte halves, swizzle each half to classify all 16 bytes in one operation. Potentially faster than 8 comparison operations but more complex. Evaluate after Phase 3 is working.

### AD4: SIMD String Body Scanning

**Decision**: Scan string bodies in 16-byte chunks looking for `"`, `\`, and `$`.

**Algorithm**:

```
scan_string_body_simd:
  while pos < len:
    if remaining < 16: fall back to scalar
    
    chunk = u8x16_load_unaligned(source[pos:])
    quote_mask = lanes_eq(chunk, '"')
    slash_mask = lanes_eq(chunk, '\\')
    dollar_mask = lanes_eq(chunk, '$')
    
    interesting = quote_mask | slash_mask | dollar_mask
    first = ctz(interesting)
    
    if first < 16:
      pos += first
      ch = source[pos]
      
      if ch == '"':
        pos += 1
        return String_Literal or Interpolated_String_Literal
      elif ch == '\\':
        // Escape sequence — scalar fallback for correctness
        handle_escape()  // existing logic
      elif ch == '$' and pos+1 < len and source[pos+1] == '{':
        // Interpolation start
        return Interpolated_String_Literal (partial)
    else:
      pos += 16
```

**Per-line strings**: Each `\`-prefixed line is a separate segment. Between lines, use Phase 2 whitespace scanner (find next `\` at line start or detect end of per-line block). Within each line, use Phase 4 string scanning.

### AD5: SIMD Number Scanning — Lower Priority

**Decision**: SIMD-accelerate number scanning but deprioritize relative to other phases.

**Rationale**: Numeric literals are typically short (3-8 bytes). The SIMD benefit is marginal but follows the same pattern as identifier scanning. Implement after Phases 1-4.

**Algorithm**: Same chunk-based approach — `lanes_ge`/`lanes_le` for digit ranges, `lanes_eq` for `_` separators and `.` decimal points. Hex digits require additional `[a-f]`/`[A-F]` ranges.

### AD6: Platform Detection — Portable core:simd Primary, x86 SSE4.2 Optional

**Decision**: Use `core:simd` (portable `u8x16` operations) as the primary SIMD path. x86 SSE4.2 `_mm_cmpistri` intrinsics are an optional Phase 6 enhancement.

**Rationale**: `core:simd` works across x86, ARM (NEON), and WebAssembly SIMD. The x86 SSE4.2 string instructions are purpose-built for character-class searching but only available on x86. Portability first, platform-specific optimization second.

**Gating**:

```odin
if runtime.HAS_HARDWARE_SIMD {
    skip_whitespace_simd(l)
} else {
    skip_whitespace_scalar(l)
}
```

**Unaligned loads**: `core:simd` load operations handle unaligned data. Source text scanning requires unaligned loads since token positions are arbitrary byte offsets.

### AD7: Test Architecture — Equivalence + Edge Cases + Benchmarks

**Decision**: Three-tier testing strategy ensuring SIMD and scalar paths produce identical output.

**Tier 1: Full token-stream equivalence** — Lex a large, varied Camp source file with both SIMD and scalar paths. Assert every token (kind, text, span, int_value, f64_value) is identical. This is the most important test.

**Tier 2: Edge-case focused tests** (each validated against scalar baseline):
- Empty source, whitespace-only, comment-only
- Every possible single-byte token
- Source exactly 15, 16, 17 bytes (SIMD chunk boundaries)
- 32+ consecutive spaces (multiple full SIMD chunks)
- Identifiers at exactly 16, 32, 48 characters
- String closing `"` at chunk boundaries (byte 15, 16, 17)
- All escape sequences: `\n \t \r \\ \" \$ \u{1F600}`
- `${` interpolation spanning chunk boundary
- Per-line strings: single line, multiple consecutive lines, interrupted by blank line, interrupted by comment
- `///` doc comment followed by code on next line
- `//` comment at chunk boundary
- All numeric formats: `0xFF`, `0o77`, `0b1010`, `3.14`, `1_000_000`, at chunk boundaries
- All keywords, all single-char operators, all two-char operators
- Backtick raw identifiers
- `!` suffix on identifiers (blocked before `=`)
- `$` mutable variable names
- `_` prefix unused bindings
- UTF-8 in strings/comments (identifiers are ASCII-only)
- `\r\n` (CRLF) line endings
- Null bytes (error recovery)

**Tier 3: Performance benchmarks**:
- Large source (~10K lines): measure MB/s throughput
- Small source (1-10 lines): verify SIMD doesn't regress on tiny inputs
- CI threshold: SIMD path ≥ 2x scalar throughput on large files

### AD8: `at_line_start` Correctness in SIMD Context

**Decision**: Track `at_line_start` using `popcount` on newline bitmasks within SIMD chunks.

**Critical invariants**:
1. `at_line_start = true` after consuming any `\n`
2. `at_line_start = false` when encountering non-whitespace, non-comment content
3. `\` at line start = per-line string; `\` not at line start = Backslash token
4. Between consecutive whitespace-only SIMD chunks, if any chunk contains a `\n`, `at_line_start` remains true

**Test cases specific to `at_line_start`**:
- `\` at column 0 → per-line string
- `  \` (spaces then backslash at line start) → per-line string
- `x\` (identifier then backslash) → Backslash token
- Multiple blank lines before `\` → still per-line string
- `\` at end of file (no newline after) → per-line string

## File Structure

```
src/frontend/char_class.odin    — NEW: Char_Class enum, CHAR_CLASS table, SINGLE_CHAR_TOKEN table
src/frontend/lexer.odin          — MODIFY: Replace single_char_tokens map, add SIMD scanner procs
src/frontend/lexer_simd.odin     — NEW (Phase 6): SSE4.2 x86-specific fast-paths
src/frontend/lexer_benchmark.odin — NEW: Throughput benchmark harness
src/test_lexer.odin              — MODIFY: Add equivalence tests, edge-case tests
openspec/specs/compiler/spec.md  — MODIFY: Add lexer performance requirement
```

## What Does NOT Change

- Token types or `Token` struct
- `lexer_next` pull-based API
- Parser interface
- Error diagnostics or error recovery behavior
- String interpolation semantics
- Per-line string semantics
- Keyword set or operator set
