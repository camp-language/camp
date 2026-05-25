# SIMD Lexing for Maximally Performant Lexing/Parsing

## Problem

The Camp lexer (`src/frontend/lexer.odin`) processes source text one byte at a time with no batch or vectorized processing. It creates a `single_char_tokens` map on every `lexer_next` call. The `lexer_skip_whitespace` loop — the hottest path for typical source files — scans every byte individually. The `lexer_lex_identifier` and `lexer_lex_string` loops are similarly byte-by-byte.

The syntax recipe explicitly marks `\` per-line strings as "SIMD-friendly", indicating SIMD lexing was intended from the start.

Odin has first-class SIMD support (`core:simd`) with `u8x16` comparisons, bitmask extraction, and platform detection (`runtime.HAS_HARDWARE_SIMD`). The intern table already uses SWAR bit-operations, demonstrating the project's comfort with bit-manipulation techniques.

## Affected Spec Domains

- `compiler` — lexer performance requirements, character classification architecture

## Current Implementation Status

- 76-variant `Token_Kind` enum in `src/base/token.odin`
- 459-line character-by-character lexer in `src/frontend/lexer.odin`
- `single_char_tokens` map re-created per `lexer_next` call
- No SIMD code anywhere in the codebase
- 16 unit tests in `src/test_lexer.odin`
- Parser never receives Newline tokens (lexer consumes them as whitespace)
- `at_line_start` boolean is the only newline-sensitive state (for per-line string detection)

## Goals

1. Replace per-call map allocation with zero-allocation lookup tables
2. SIMD-accelerate whitespace/comment skipping (hottest loop)
3. SIMD-accelerate identifier scanning (second hottest)
4. SIMD-accelerate string body scanning (find `"`, `\`, `$`)
5. SIMD-accelerate number scanning (lower priority, short tokens)
6. Maintain identical token-stream output (SIMD and scalar produce same tokens)
7. Gate all SIMD paths behind `runtime.HAS_HARDWARE_SIMD` with scalar fallback
8. Add comprehensive test coverage ensuring SIMD/scalar equivalence

## Non-Goals

- Token buffering or batched token production (parser API unchanged)
- Changing the `lexer_next` pull-based API
- Emitting Newline tokens (current architecture never produces them)
- SSE4.2-specific intrinsics (deferred to optional Phase 6)
- Changing token types, parser interface, or error diagnostics
