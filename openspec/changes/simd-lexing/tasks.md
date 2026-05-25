# Tasks: SIMD Lexing Implementation

## Phase 1: Character Classification Lookup Tables

- [x] Create `src/frontend/char_class.odin` with `Char_Class` bitmask enum, `CHAR_CLASS: [256]Char_Class` table, and `SINGLE_CHAR_TOKEN: [256]Token_Kind` table
- [x] Replace `single_char_tokens` map in `lexer_next` with `SINGLE_CHAR_TOKEN[byte]` array lookup
- [x] Add SIMD helper procs: `is_identifier_continue_simd`, `classify_chunk` (load + classify 16 bytes)
- [x] Verify all 16 existing unit tests pass unchanged
- [ ] Add benchmark harness: `src/frontend/lexer_benchmark.odin` with large Camp source file, measure scalar baseline throughput in MB/s

## Phase 2: SIMD Whitespace & Newline Skipping

- [x] Implement `skip_whitespace_simd` proc using `u8x16` comparisons for space/tab/CR/newline detection
- [x] Implement `at_line_start` tracking via `popcount` on newline bitmask within SIMD chunks
- [x] Implement `//` comment detection after SIMD whitespace scan (scalar fallback for comment-end)
- [x] Implement `///` doc comment break-out (stop SIMD scan, let `lexer_next` produce token)
- [x] Gate with `runtime.HAS_HARDWARE_SIMD`; keep `skip_whitespace_scalar` as fallback
- [ ] Add edge-case tests: empty source, whitespace-only, 32+ consecutive spaces, CRLF, chunk boundaries (15/16/17 bytes), comment at chunk boundary, doc comment detection
- [ ] Add `at_line_start` tests: `\` at column 0, `  \` with leading whitespace, `x\` (not line start), multiple blank lines before `\`
- [ ] Add token-stream equivalence test: SIMD path vs scalar path on large varied source

## Phase 3: SIMD Identifier Scanning

- [x] Implement `scan_identifier_simd` proc using `u8x16` range comparisons for `[a-z]`, `[A-Z]`, `[0-9]`, `_`
- [x] Implement `!` suffix absorption after SIMD scan (same rule: not before `=`)
- [x] Gate with `runtime.HAS_HARDWARE_SIMD`; keep `lexer_lex_identifier` as fallback
- [ ] Add edge-case tests: identifiers at 16/32/48 characters (chunk boundaries), keyword boundary, `Upper_Id` vs `Identifier`, `!` suffix with and without `!=` follow, `$` and `_` prefixed identifiers, backtick raw identifiers
- [ ] Verify token-stream equivalence test passes

## Phase 4: SIMD String Body Scanning

- [x] Implement `scan_string_body_simd` proc using `u8x16` comparisons for `"`, `\`, `$`
- [x] Implement escape sequence scalar fallback (unchanged logic)
- [x] Implement interpolation `${` detection in SIMD context
- [x] Implement per-line string inter-line scanning: SIMD whitespace between `\`-prefixed lines
- [x] Gate with `runtime.HAS_HARDWARE_SIMD`; keep `lexer_lex_string` as fallback
- [ ] Add edge-case tests: closing `"` at chunk boundaries, all escape sequences, `${` spanning chunk boundary, per-line strings (single line, multiple consecutive, interrupted by blank line, interrupted by comment), long strings (>256 bytes)
- [ ] Verify token-stream equivalence test passes

## Phase 5: SIMD Number Scanning

- [x] Implement `scan_number_simd` proc using `u8x16` range comparisons for digits, hex digits, `_` separators, `.`
- [x] Handle `0x`, `0o`, `0b` prefixes (scalar — only 2 bytes)
- [x] Gate with `runtime.HAS_HARDWARE_SIMD`; keep `lexer_lex_number` as fallback
- [ ] Add edge-case tests: hex/octal/binary at chunk boundaries, floats, underscored numbers, `1_000_000`
- [ ] Verify token-stream equivalence test passes

## Phase 6: SSE4.2 Optional Enhancement (Deferred)

- [ ] Create `src/frontend/lexer_simd.odin` with `#+build i386, amd64` SSE4.2 fast-paths
- [ ] Implement `_mm_cmpistri` whitespace scanning (single instruction, 16 bytes)
- [ ] Implement `_mm_cmpistri` identifier-end scanning
- [ ] Implement `_mm_cmpistri` string-terminator scanning
- [ ] Gate behind `runtime.HAS_HARDWARE_SIMD` + CPUID SSE4.2 check
- [ ] Add benchmarks comparing `core:simd` path vs SSE4.2 path

## Phase 7: Spec Update & Benchmark Validation

- [ ] Add lexer performance requirement to `openspec/specs/compiler/spec.md`
- [ ] Run final benchmark: SIMD vs scalar throughput on large Camp source file
- [ ] Verify CI threshold: SIMD ≥ 2x scalar on large files, no regression on small files
- [ ] Verify all existing e2e tests pass (`just test-e2e`)
- [ ] Verify kitchen-sink test unchanged (`tests/e2e/language/kitchen-sink/`)

## Implementation Order

1. **Phase 1** (lookup tables) — highest impact, lowest risk, foundation for all SIMD
2. **Phase 2** (whitespace SIMD) — highest performance impact (hottest loop)
3. **Phase 3** (identifier SIMD) — second highest performance impact
4. **Phase 4** (string SIMD) — moderate impact, especially long strings
5. **Phase 5** (number SIMD) — low impact, follows established pattern
6. **Phase 7** (spec + benchmarks) — validate and document
7. **Phase 6** (SSE4.2) — optional, deferred, platform-specific optimization
