# Tasks: Priority 2 Standard Library Modules

## Phase 1: Random! Modification

- [ ] Add `bytes! : U64 -> -[Random!]-> Bytes` operation to `Random!` effect declaration
- [ ] Add `random_crypto : Handler(Random!)` handler (WASI `random_get` intrinsic)
- [ ] Update `Random.camp` impl-spec section with new operation and handler
- [ ] Remove `Crypto.Random!` from spec.md and impl-spec.md (folded into Random!)
- [ ] Verify existing Random! tests still pass
- [ ] Add tests for `bytes!` operation with both handlers
- [ ] Add tests for `random_crypto` handler (crypto-grade randomness)

## Phase 2: Uuid Module

- [ ] Define `@Uuid : pub Bytes` newtype (16 bytes, opaque)
- [ ] Define `@UuidErr`, `@UuidVariant`, `@UuidFormat` types
- [ ] Implement `v4! : -[Random!]-> Uuid` (intrinsic: call `Random!.bytes!(16)`, set version nibble)
- [ ] Implement `v7! : I64 -> -[Random!]-> Uuid` (intrinsic: embed timestamp, call `Random!.bytes!(6)`, set version/variant)
- [ ] Implement `parse : Str -> Result(Uuid, UuidErr)` (pure Camp: validate length, hyphens, hex, version)
- [ ] Implement `from_bytes : Bytes -> Result(Uuid, UuidErr)` (pure Camp: validate length, version nibble)
- [ ] Implement `to_str : Uuid -> Str` (pure Camp: format 8-4-4-4-12 lowercase hex)
- [ ] Implement `format : UuidFormat, Uuid -> Str` (pure Camp: Standard/Compact/Urn/Braced)
- [ ] Implement `to_bytes : Uuid -> Bytes` (pure Camp: unwrap the newtype)
- [ ] Implement `version : Uuid -> U8` (pure Camp: extract version nibble)
- [ ] Implement `variant : Uuid -> UuidVariant` (pure Camp: extract variant bits)
- [ ] Implement `timestamp : Uuid -> Result(I64, [])` (pure Camp: V7 only, extract 48-bit ms timestamp)
- [ ] Add Uuid impl-spec section to `openspec/specs/stdlib/impl-spec.md`
- [ ] Add kitchen-sink test entries for Uuid types and operations
- [ ] Write unit tests: parse round-trip, format variants, v4!/v7! generation, error cases

## Phase 3: Json Module

- [ ] Define `@JsonNumber : pub [PosInt(U64) | NegInt(I64) | Float(F64)]` type
- [ ] Define `@JsonValue : pub [Null | Bool(Bool) | Num(JsonNumber) | Str(Str) | Arr(List(JsonValue)) | Obj(Map(Str, JsonValue))]` type
- [ ] Define `@JsonErr` error type
- [ ] Implement `decode : Str -> Result(JsonValue, JsonErr)` (intrinsic: recursive-descent parser)
- [ ] Implement `encode : JsonValue -> Str` (intrinsic: serializer)
- [ ] Implement `encode_pretty : JsonValue -> Str` (intrinsic: pretty-printer, 2-space indent)
- [ ] Implement JsonNumber accessors: `is_int`, `is_float`, `as_i64`, `as_u64`, `as_f64` (pure Camp)
- [ ] Implement JsonValue accessors: `get`, `get_at`, `keys`, `values`, `length` (pure Camp)
- [ ] Define `@JsonEvent` streaming event type
- [ ] Define `@JsonParser` state type
- [ ] Implement `parse_init`, `parse_next`, `parse_all` (intrinsic: streaming parser)
- [ ] Add Json impl-spec section to `openspec/specs/stdlib/impl-spec.md`
- [ ] Add kitchen-sink test entries for Json types and operations
- [ ] Write unit tests: decode/encode round-trip, number type preservation, streaming parser, error cases, nested structures, large inputs

## Phase 4: Regex Module

- [ ] Define `@Regex : pub { pattern : Str }` opaque type
- [ ] Define `@RegexErr`, `@MatchGroup`, `@Match` types
- [ ] Implement `compile : Str -> Result(Regex, RegexErr)` (intrinsic: RE2 NFA compiler)
- [ ] Implement `is_match : Regex, Str -> Bool` (intrinsic)
- [ ] Implement `find : Regex, Str -> Option(Match)` (intrinsic)
- [ ] Implement `find_all : Regex, Str -> List(Match)` (intrinsic)
- [ ] Implement `replace : Regex, Str, Str -> Str` (intrinsic: literal replacement, first match)
- [ ] Implement `replace_all : Regex, Str, Str -> Str` (intrinsic: literal replacement, all matches)
- [ ] Implement `split : Regex, Str -> List(Str)` (intrinsic)
- [ ] Implement `splitn : Regex, Str, U64 -> List(Str)` (intrinsic: limited splits)
- [ ] Implement `escape : Str -> Str` (pure Camp: escape metacharacters)
- [ ] Add Regex impl-spec section to `openspec/specs/stdlib/impl-spec.md`
- [ ] Add kitchen-sink test entries for Regex types and operations
- [ ] Write unit tests: compile+match, capture groups, find_all, replace, split, escape, error cases, RE2 constraints (no backreference, no lookahead)

## Phase 5: Uri Module

- [ ] Define `@UriAuthority`, `@Uri`, `@UriErr` types
- [ ] Implement `parse : Str -> Result(Uri, UriErr)` (pure Camp: RFC 3986 parsing)
- [ ] Implement `to_str : Uri -> Str` (pure Camp: reconstruct URI string)
- [ ] Implement `encode_component : Str -> Str` (pure Camp: percent-encode unreserved chars only)
- [ ] Implement `decode_component : Str -> Result(Str, UriErr)` (pure Camp: percent-decode)
- [ ] Implement `parse_query : Str -> List((Str, Str))` (pure Camp: form-encoded parsing)
- [ ] Implement `format_query : List((Str, Str)) -> Str` (pure Camp: form-encoded formatting)
- [ ] Implement `with_scheme`, `with_authority`, `with_path`, `with_query`, `with_fragment` (pure Camp)
- [ ] Add Uri impl-spec section to `openspec/specs/stdlib/impl-spec.md`
- [ ] Add kitchen-sink test entries for Uri types and operations
- [ ] Write unit tests: parse various URI forms, round-trip, percent encoding/decoding, query parsing, construction helpers, error cases, edge cases (no authority, empty path, etc.)

## Phase 6: Base64 Module

- [ ] Define `@Base64Format : pub [Standard | UrlSafe | Base32 | Hex]` type
- [ ] Define `@Base64Err` error type
- [ ] Implement `encode : Base64Format, Bytes -> Str` (pure Camp: lookup table + bit shifting)
- [ ] Implement `decode : Base64Format, Str -> Result(Bytes, Base64Err)` (pure Camp: reverse lookup)
- [ ] Implement `encode_str`, `decode_str` string convenience functions (pure Camp: UTF-8 bridge)
- [ ] Implement shorthand functions: `encode64`/`decode64`, `encode64url`/`decode64url`, `encode16`/`decode16` (pure Camp: delegate to parameterized versions)
- [ ] Add Base64 impl-spec section to `openspec/specs/stdlib/impl-spec.md`
- [ ] Add kitchen-sink test entries for Base64 operations
- [ ] Write unit tests: encode/decode round-trip per format, padding, invalid characters, string convenience, error cases

## Phase 7: Spec Updates & Integration

- [x] Update `openspec/specs/stdlib/spec.md`: remove Crypto.Random! as separate module, update Random! description, mark P2 modules as specified
- [x] Update `openspec/specs/stdlib/impl-spec.md`: add all 5 new module sections + Random! modification, update module registry table
- [x] Record D31–D39 in design decision section of impl-spec
- [ ] Update kitchen-sink test (`tests/e2e/language/kitchen-sink/Main.camp`) with P2 module examples
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
