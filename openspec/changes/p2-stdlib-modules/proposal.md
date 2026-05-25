# Priority 2 Standard Library Modules

## Problem

The Camp stdlib currently provides 38 Priority 1 modules covering core types (Result, Bool, Str, List, Map, Set), numeric types, I/O effects (Console!, File!, Env!), and foundational traits (Eq, Ord, Hash, Debug, Display). However, several practical modules needed for real-world Camp programs are missing:

- **JSON** — the lingua franca of web APIs; every non-trivial program needs to parse or produce JSON
- **Regex** — text processing, validation, and pattern matching
- **URI** — URL parsing and construction for any networked code
- **UUID** — universally unique identifiers for distributed systems
- **Base64** — binary-to-text encoding for transport and storage
- **Cryptographic randomness** — secure random bytes for tokens, keys, and nonces

The spec (`openspec/specs/stdlib/spec.md` lines 55–152) defines these as Priority 2 with feature descriptions, but no impl-spec exists yet.

Additionally, the spec lists `Crypto.Random!` as a separate effect module, but this is better served by folding it into the existing `Random!` effect as a second handler — aligning with algebraic effect theory where effects define interfaces and handlers provide implementations.

## Affected Spec Domains

- `stdlib` — new module definitions, impl-spec additions, Random! modification
- `language` — no syntax changes; new types are ordinary Camp types

## Current Implementation Status

- 38 Priority 1 modules fully specified in `openspec/specs/stdlib/impl-spec.md`
- `Random!` effect exists with `int!` and `float!` operations, plus `random_prng` handler
- `Crypto.Random!` listed in spec as separate effect — not yet implemented
- All 6 P2 modules listed in spec with feature descriptions only — no impl-spec
- No Camp runtime code for any P2 module

## Goals

1. Define impl-specs for all 6 Priority 2 modules: Json, Regex, Uri, Uuid, Base64, and the Random! modification
2. Fold `Crypto.Random!` into `Random!` as a second handler (`random_crypto`), eliminating the separate effect
3. Add `bytes!` operation to `Random!` — needed by Uuid and any binary random use case
4. Preserve integer/float distinction in JSON numbers (following Rust serde_json's design)
5. Use RE2-style regex engine (no backtracking, guaranteed O(n))
6. Store URI queries as raw strings with parsed accessor (following Rust url crate)
7. Make Base64 and Uri pure Camp implementations (no intrinsics needed for these)
8. Keep Uuid generation effectful (needs Random!) but parsing/formatting pure

## Non-Goals

- Encode/Decode codec framework traits (Priority 3 — deferred)
- EncoderFormatting/DecoderFormatting (Priority 3 — deferred)
- Gzip compression (Priority 3 — deferred)
- Http package (official package, not stdlib)
- Crypto.Hash package (official package, not stdlib)
- DateTime package (official package, not stdlib per D24)
- Changing any existing P1 module API (only adding `bytes!` to Random! and a new handler)
- Arbitrary-precision JSON numbers (F64 + I64/U64 covers the 99% case)
