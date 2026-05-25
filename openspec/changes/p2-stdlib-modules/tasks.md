# Tasks: Priority 2 Standard Library Modules

## Phase 1: Random! Modification

- [x] Add `bytes! : U64 -> -[Random!]-> Bytes` operation to `Random!` effect declaration (already in .camp, needs stdlib.odin sync)
- [ ] Add `random_crypto : Handler(Random!)` handler (WASI `random_get` intrinsic)
- [x] Update `stdlib/Random.camp` comment to reference two handlers (per D31)
- [ ] Add Random! handler entries to `src/build/stdlib.odin`
- [x] Remove `Crypto.Random!` from spec.md and impl-spec.md (folded into Random!) — done in prior commit
- [ ] Verify existing Random! tests still pass
- [ ] Add tests for `bytes!` operation with both handlers
- [ ] Add tests for `random_crypto` handler (crypto-grade randomness)

## Phase 2: Uuid Module

- [x] Create `stdlib/Uuid.camp` with type declarations and function stubs
- [x] Add UUID_CAMP to `src/build/stdlib.odin` and register in STDLIB_MODULES
- [x] Define `@Uuid : pub Bytes` newtype (16 bytes, opaque)
- [x] Define `@UuidErr`, `@UuidVariant`, `@UuidFormat` types
- [x] Implement `v4! : -[Random!]-> Uuid` (intrinsic: call `Random!.bytes!(16)`, set version nibble)
- [x] Implement `v7! : I64 -> -[Random!]-> Uuid` (intrinsic: embed timestamp, call `Random!.bytes!(6)`, set version/variant)
- [x] Implement `parse : Str -> Result(Uuid, UuidErr)` (pure Camp: validate length, hyphens, hex, version)
- [x] Implement `from_bytes : Bytes -> Result(Uuid, UuidErr)` (pure Camp: validate length, version nibble)
- [x] Implement `to_str : Uuid -> Str` (pure Camp: format 8-4-4-4-12 lowercase hex)
- [x] Implement `format : UuidFormat, Uuid -> Str` (pure Camp: Standard/Compact/Urn/Braced)
- [x] Implement `to_bytes : Uuid -> Bytes` (pure Camp: unwrap the newtype)
- [x] Implement `version : Uuid -> U8` (pure Camp: extract version nibble)
- [x] Implement `variant : Uuid -> UuidVariant` (pure Camp: extract variant bits)
- [x] Implement `timestamp : Uuid -> Result(I64, [Absent])` (pure Camp: V7 only, extract 48-bit ms timestamp)
- [x] Add kitchen-sink test entries for Uuid types and operations
- [ ] Write unit tests: parse round-trip, format variants, v4!/v7! generation, error cases

## Phase 3: Json Module

- [x] Create `stdlib/Json.camp` with type declarations and function stubs
- [x] Add JSON_CAMP to `src/build/stdlib.odin` and register in STDLIB_MODULES
- [x] Define `@JsonNumber : pub [PosInt(U64) | NegInt(I64) | Float(F64)]` type
- [x] Define `@JsonValue : pub [Null | Bool(Bool) | Num(JsonNumber) | Str(Str) | Arr(List(JsonValue)) | Obj(Map(Str, JsonValue))]` type
- [x] Define `@JsonErr` error type
- [x] Implement `decode : Str -> Result(JsonValue, JsonErr)` (intrinsic: recursive-descent parser)
- [x] Implement `encode : JsonValue -> Str` (intrinsic: serializer)
- [x] Implement `encode_pretty : JsonValue -> Str` (intrinsic: pretty-printer, 2-space indent)
- [x] Implement JsonNumber accessors: `is_int`, `is_float`, `as_i64`, `as_u64`, `as_f64` (pure Camp)
- [x] Implement JsonValue accessors: `get`, `get_at`, `keys`, `values`, `length` (pure Camp)
- [x] Define `@JsonEvent` streaming event type
- [x] Define `@JsonParser` state type
- [x] Implement `parse_init`, `parse_next`, `parse_all` (intrinsic: streaming parser)
- [x] Add kitchen-sink test entries for Json types and operations
- [ ] Write unit tests: decode/encode round-trip, number type preservation, streaming parser, error cases, nested structures, large inputs

## Phase 4: Regex Module

- [x] Create `stdlib/Regex.camp` with type declarations and function stubs
- [x] Add REGEX_CAMP to `src/build/stdlib.odin` and register in STDLIB_MODULES
- [x] Define `@Regex : pub { pattern : Str }` opaque type
- [x] Define `@RegexErr`, `@MatchGroup`, `@Match` types
- [x] Implement `compile : Str -> Result(Regex, RegexErr)` (intrinsic: RE2 NFA compiler)
- [x] Implement `is_match : Regex, Str -> Bool` (intrinsic)
- [x] Implement `find : Regex, Str -> Result(Match, [Absent])` (intrinsic)
- [x] Implement `find_all : Regex, Str -> List(Match)` (intrinsic)
- [x] Implement `replace : Regex, Str, Str -> Str` (intrinsic: literal replacement, first match)
- [x] Implement `replace_all : Regex, Str, Str -> Str` (intrinsic: literal replacement, all matches)
- [x] Implement `split : Regex, Str -> List(Str)` (intrinsic)
- [x] Implement `splitn : Regex, Str, U64 -> List(Str)` (intrinsic: limited splits)
- [x] Implement `escape : Str -> Str` (pure Camp: escape metacharacters)
- [x] Add kitchen-sink test entries for Regex types and operations
- [ ] Write unit tests: compile+match, capture groups, find_all, replace, split, escape, error cases, RE2 constraints (no backreference, no lookahead)

## Phase 5: Uri Module

- [x] Create `stdlib/Uri.camp` with type declarations and function stubs
- [x] Add URI_CAMP to `src/build/stdlib.odin` and register in STDLIB_MODULES
- [x] Define `@UriAuthority`, `@Uri`, `@UriErr` types
- [x] Implement `parse : Str -> Result(Uri, UriErr)` (pure Camp: RFC 3986 parsing)
- [x] Implement `to_str : Uri -> Str` (pure Camp: reconstruct URI string)
- [x] Implement `encode_component : Str -> Str` (pure Camp: percent-encode unreserved chars only)
- [x] Implement `decode_component : Str -> Result(Str, UriErr)` (pure Camp: percent-decode)
- [x] Implement `parse_query : Str -> List((Str, Str))` (pure Camp: form-encoded parsing)
- [x] Implement `format_query : List((Str, Str)) -> Str` (pure Camp: form-encoded formatting)
- [x] Implement `with_scheme`, `with_authority`, `with_path`, `with_query`, `with_fragment` (pure Camp)
- [x] Add kitchen-sink test entries for Uri types and operations
- [ ] Write unit tests: parse various URI forms, round-trip, percent encoding/decoding, query parsing, construction helpers, error cases, edge cases (no authority, empty path, etc.)

## Phase 6: Base64 Module

- [x] Create `stdlib/Base64.camp` with type declarations and function stubs
- [x] Add BASE64_CAMP to `src/build/stdlib.odin` and register in STDLIB_MODULES
- [x] Define `@Base64Format : pub [Standard | UrlSafe | Base32 | Hex]` type
- [x] Define `@Base64Err` error type
- [x] Implement `encode : Base64Format, Bytes -> Str` (pure Camp: lookup table + bit shifting)
- [x] Implement `decode : Base64Format, Str -> Result(Bytes, Base64Err)` (pure Camp: reverse lookup)
- [x] Implement `encode_str`, `decode_str` string convenience functions (pure Camp: UTF-8 bridge)
- [x] Implement shorthand functions: `encode64`/`decode64`, `encode64url`/`decode64url`, `encode16`/`decode16` (pure Camp: delegate to parameterized versions)
- [x] Add kitchen-sink test entries for Base64 operations
- [ ] Write unit tests: encode/decode round-trip per format, padding, invalid characters, string convenience, error cases

## Phase 7: Spec Updates & Integration

- [x] Update `openspec/specs/stdlib/spec.md`: remove Crypto.Random! as separate module, update Random! description, mark P2 modules as specified
- [x] Update `openspec/specs/stdlib/impl-spec.md`: add all 5 new module sections + Random! modification, update module registry table
- [x] Record D31–D40 in design decision section of impl-spec
- [x] Fix Option→Result(a, [Absent]) in impl-spec P2 modules (per D1: no Option type)
- [x] Update kitchen-sink test (`tests/e2e/language/kitchen-sink/Main.camp`) with P2 module examples
- [ ] Update kitchen-sink `expected.toml` via `just update-snapshots`
- [ ] Verify all existing tests pass: `odin test src`
- [ ] Verify e2e tests pass: `just test-e2e`

## Implementation Order

1. **Phase 1** (Random! modification) — foundation for Uuid, no breaking changes
2. **Phase 2** (Uuid) — depends on Phase 1, smallest new module, good warmup
3. **Phase 6** (Base64) — pure Camp, no intrinsics, simplest algorithms, independent
4. **Phase 5** (Uri) — pure Camp, moderate complexity string parsing, independent
5. **Phase 3** (Json) — largest module, intrinsic-heavy, most complex types
6. **Phase 4** (Regex) — most complex intrinsic (RE2 engine), independent
7. **Phase 7** (Spec updates & integration) — after all modules implemented
