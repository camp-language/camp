# Packages Domain Design

## Architecture

The Camp package ecosystem is organized in three tiers with increasing freedom and decreasing stability guarantees:

1. **Stdlib** (Tier 1): Ships with the compiler. API is permanent — once added, never removed.
2. **Official Packages** (Tier 2): Maintained by the Camp team under `camp-lang`. Independently versioned.
3. **Community Packages** (Tier 3): Third-party with no stability guarantee. Git dependencies only.

### Design Principles

1. **Stdlib permanence**: Following Rust's model — only add what is confident to be stable and correct.
2. **Composable primitives over frameworks**: Small, well-defined abstractions that compose into larger tools.
3. **One way to do things**: No redundant mechanisms for the same concern.
4. **Effects for I/O, pure for computation**: Pure computation + effect definitions in stdlib; WASI provides effectful primitives at runtime.
5. **Start monorepo, graduate to org**: Official packages initially in the compiler repo; long-term they move to `camp-lang/*` repos.

## Stdlib Module Inventory

### Existing Modules (from Language Design Spec)

| Module | Category | Contents |
|--------|----------|----------|
| `Int` | Pure | I8..I64, U8..U64 arithmetic, comparison, conversion, bitwise |
| `Float` | Pure | F32, F64 arithmetic, comparison, trig, rounding |
| `Bool` | Pure | True, False, logic |
| `Str` | Pure | UTF-8 string operations: concat, split, trim, find, slice, interpolate, length, chars |
| `List` | Pure | List(a) with iter(): construct, first, last, length, append, sort |
| `Iter` | Pure | Lazy iterator pipeline: map, filter, fold, collect, chain, enumerate, take, skip, zip, find, count, for_each |
| `Map` | Pure | Map(k, v) with iter(): get, insert, remove, contains, keys, values, size |
| `Set` | Pure | Set(a) with iter(): insert, remove, contains, union, intersection, difference |
| `Bytes` | Pure | Raw byte sequences, hex, base64, encode, decode |
| `Result` | Pure | Tag union helpers for Ok(a) \| Err(e) |
| `Option` | Pure | Tag union helpers for Some(a) \| None |
| `File` | Effect | File I/O: open!, close!, read!, write! |
| `Console` | Effect | Terminal I/O: print!, printerr!, readln! |
| `Async` | Effect | Concurrency: yield!, spawn!, join!, cancel! |
| `Throw` | Effect | Error effect: throw! operation |
| `Env` | Effect | CLI args, env vars: args!, get_env! |
| `Time` | Effect | Clock, duration: now!, sleep! |
| `Random` | Effect | Non-crypto random generation: int!, float!, bytes! |
| `Path` | Pure | File path manipulation: join, split, extension, directory, filename |
| `Fmt` | Pure | Formatting: Display trait, format function |
| `Hash` | Pure | Hashing: Hash trait, hash functions (SipHash, FNV) |
| `Serialize` | Pure | Serialization: Serialize, Deserialize traits, binary format |
| `Eq` | Pure | Equality: Eq trait, structural equality, reference equality |
| `Ord` | Pure | Ordering: Ord trait, Ordering type, comparison for sorting |

### New Stdlib Modules

**Priority 1 — Required for Any Non-Trivial Program:**

| Module | Category | Contents |
|--------|----------|----------|
| `Json` | Pure | JSON codec: parse, stringify, Value type, Encode/Decode trait instances, streaming parser |
| `Regex` | Pure | Regular expressions: compile, match, find, replace, split, capture groups |
| `Uri` | Pure | URI/URL parsing and construction: scheme, authority, path, query, fragment, percent encoding |
| `Duration` | Pure | Duration type with arithmetic: seconds, ms, µs, ns, from_parts, to_parts, add, subtract, multiply, compare |
| `DateTime` | Pure | Date/time types: Date, Time, DateTime, TimeZone, offset arithmetic, ISO 8601, parsing, formatting |
| `Log` | Effect | Structured logging: debug!, info!, warn!, error! with key-value context |

**Priority 2 — Required for Most REST APIs:**

| Module | Category | Contents |
|--------|----------|----------|
| `Crypto.Random` | Effect | Cryptographically secure random: bytes!, int!, uuid! |
| `Base64` | Pure | Base64, Base64URL, Base32, Base16 (Hex) encoding/decoding |
| `Gzip` | Pure | Gzip/zlib compression and decompression (pure computation on bytes) |
| `Uuid` | Pure | UUID generation and parsing: v4, v7, parse, from_string, to_string, Nil |

**Priority 3 — Important for Completeness:**

| Module | Category | Contents |
|--------|----------|----------|
| `Html` | Pure | HTML escaping and basic parsing: escape, unescape, strip_tags, encode_entities |
| `Csv` | Pure | CSV reading and writing: Reader, Writer, parse_row, write_row, with_header |
| `Xml` | Pure | XML parsing and emission: parse, to_string, Element, Attribute, streaming parser |
| `Mime` | Pure | MIME type constants and detection: type_by_extension, extension_by_type |
| `Net.Ip` | Pure | IP address types and parsing: Ipv4, Ipv6, parse, is_loopback, is_private |
| `Version` | Pure | Semantic version parsing and comparison: parse, compare, satisfies |

### Deferred to Official/Community Packages

| Module | Reason |
|--------|--------|
| `Sort` | `List.sort`/`List.sort_by` already exist; multiple algorithms is niche |
| `Bits` | Low-level protocol work, not typical REST APIs |
| `Tuple` | Camp records serve the same purpose |
| `Crypto.Hash` | Implementation bugs need independent versioning; WASM side-channel risk |
| `Collections` (Queue, Stack) | Not every program needs these; stdlib permanence means never removable |

### Existing Module Expansions

| Module | Additions |
|--------|-----------|
| `Str` | Grapheme-aware ops, case folding, from_str/to_str for every primitive |
| `Bytes` | Move hex/base64 to `Base64` module; add Builder; add read_int, write_int |
| `Iter` | try_map, chunks_of, windows, intersperse, scan, group_by, partition, unique, min_by, max_by, flat_map, step, stride, cycle |
| `Map` | update, get_or_insert (entry API), map_values, filter_map |
| `List` | find_index, find_last, chunk, windows, intersperse, scan, group_by, partition, unique_by, min_by, max_by, flat_map, sublist, rotate |
| `Serialize` | Restructure to `Encode`/`Decode` traits with `EncoderFormatting`/`DecoderFormatting` formatting traits |
| `Time` | Change now! return type from U64 to DateTime; add monotonic_now!, elapsed!, timeout! |
| `Random` | Clarify as non-cryptographic; add shuffle, sample, weighted |

### New Effect Definitions

```
effect Log {
  debug!   : Str ->{ Log } {}
  info!    : Str ->{ Log } {}
  warn!    : Str ->{ Log } {}
  error!   : Str ->{ Log } {}
}

effect Crypto.Random {
  bytes! : U64 ->{ Crypto.Random } Bytes
  int!   : Int, Int ->{ Crypto.Random } Int
  uuid!  : || ->{ Crypto.Random } Uuid
}
```

### New Traits

| Trait | Methods | Derivable |
|-------|---------|-----------|
| `Encode` | `encode : fmt -> Self -> fmt` (parameterized by `EncoderFormatting fmt`) | Yes |
| `Decode` | `decode : fmt -> Result((fmt, Self), DecodeError)` (parameterized by `DecoderFormatting fmt`) | Yes |
| `Validate` | `validate : Self -> Result(Self, Str)` | Yes |

## Codec Framework Design

### The Problem with a Simple Codec Trait

A naive `Codec` trait with `encode : Self -> Bytes` and `decode : Bytes -> Result(Self, Str)` assumes all formats are interchangeable, but they are not:

- **Null vs absence**: JSON has `null`; XML has `xsi:nil`; CSV has empty cells (absence)
- **Collections vs records**: JSON uses arrays `[1,2,3]`; CSV uses rows
- **Type tagging**: JSON has no type tags; MsgPack uses field numbers; XML uses element names
- **Streaming vs buffered**: Different allocation patterns per format

### Roc-Inspired Formatting Traits

```
trait EncoderFormatting fmt {
  record_start   : fmt -> Str -> fmt
  record_end     : fmt -> fmt
  field          : fmt -> Str -> fmt -> fmt
  list_start     : fmt -> fmt
  list_end       : fmt -> fmt
  element        : fmt -> fmt -> fmt
  string         : fmt -> Str -> fmt
  int            : fmt -> Int -> fmt
  float          : fmt -> Float -> fmt
  bool           : fmt -> Bool -> fmt
  null           : fmt -> fmt
}

trait DecoderFormatting fmt {
  record_start   : fmt -> Result(fmt, DecodeError)
  field          : fmt -> Str -> Result(fmt, DecodeError)
  list_start     : fmt -> Result(fmt, DecodeError)
  element        : fmt -> Result(fmt, DecodeError)
  string         : fmt -> Result(Str, DecodeError)
  int            : fmt -> Result(Int, DecodeError)
  float          : fmt -> Result(Float, DecodeError)
  bool           : fmt -> Result(Bool, DecodeError)
  null           : fmt -> Result((), DecodeError)
}
```

### Format-Agnostic Encode/Decode

```
trait Encode a is EncoderFormatting fmt => {
  encode : fmt -> a -> fmt
}

trait Decode a is DecoderFormatting fmt => {
  decode : fmt -> Result((fmt, a), DecodeError)
}
```

A single `Encode` implementation works for every format providing an `EncoderFormatting` instance.

### Format Instances

| Format | Module | Status |
|--------|--------|--------|
| JSON | `Json` | Stdlib (P1) |
| Binary | `Binary` | Stdlib (existing `Serialize`, renamed) |
| CSV | `Csv` | Stdlib (P3) |
| XML | `Xml` | Stdlib (P3) |
| TOML | `Toml` | Official package (P2) |
| YAML | `Yaml` | Official package (P2) |
| MsgPack | `MsgPack` | Official package (P3) |
| Protobuf | `Protobuf` | Official package (P3) |

### Derive Integration

```
@derive [Encode, Decode]
User := { name: Str, age: U64 }
```

Generates format-agnostic implementations. Per-field override supported.

### Convenience Functions

```
Json.encode : Encode a => a -> Str
Json.decode : Decode a => Str -> Result(a, DecodeError)
```

## HTTP Effect Design

### Server Effect

```
effect Http.Server {
  listen!  : Str, U16 ->{ Http.Server } {}
  route!   : Method, Str, (Request ->{ Http } Response) ->{ Http.Server } {}
  serve!   : || ->{ Http.Server, Throw(HttpError) } {}
}
```

### Client Effect

```
effect Http.Client {
  get!     : Str ->{ Http.Client, Throw(HttpError) } Response
  post!    : Str, Body ->{ Http.Client, Throw(HttpError) } Response
  put!     : Str, Body ->{ Http.Client, Throw(HttpError) } Response
  delete!  : Str ->{ Http.Client, Throw(HttpError) } Response
  patch!   : Str, Body ->{ Http.Client, Throw(HttpError) } Response
  request! : Request ->{ Http.Client, Throw(HttpError) } Response
}
```

### Core Types

```
Http.Request  := { method: Method, uri: Uri, headers: Map(Str, Str), body: Body }
Http.Response := { status: U16, headers: Map(Str, Str), body: Body }
Http.Method   := [Get | Post | Put | Delete | Patch | Head | Options | Connect | Trace]
Http.Body     := [Empty | Text(Str) | Binary(Bytes) | Stream(Iter(Bytes))]
```

## Database Effect Design

### Generic Database Interface

```
effect Database {
  query!     : Str, List(Value) ->{ Database, Throw(DbError) } Rows
  execute!   : Str, List(Value) ->{ Database, Throw(DbError) } Result
  prepare!   : Str ->{ Database, Throw(DbError) } Statement
  transaction! : || ->{ Database, Throw(DbError) } a ->{ Database, Throw(DbError) } a
}

effect Database.Pool {
  acquire!  : || ->{ Database.Pool } Connection
  release!  : Connection ->{ Database.Pool } {}
}
```

### Driver Interface

Drivers implement handlers for the `Database` effect, translating Camp operations into WASI socket calls:

| Driver | Package | Protocol |
|--------|---------|----------|
| PostgreSQL | `Database.Postgres` | PostgreSQL wire protocol v3 |
| SQLite | `Database.Sqlite` | SQLite C API via WASI |
| MySQL | `Database.MySql` | MySQL wire protocol |
| Redis | `Database.Redis` | RESP3 protocol |

### Query Builder

```
Query.select("users")
  .where("age", Gt, 18)
  .order_by("name", Asc)
  .limit(10)
  .build()
```

Less magical than a full ORM, more type-safe than raw SQL strings.

### Future: Typed Query Effects

The current `Database` effect uses string queries with `List(Value)` parameters. Camp's effect system opens the possibility of typed query effects where the result type is tracked in the effect signature. Research-grade; deferred beyond v1.

## Logging Architecture

### Stdlib: Log Effect (Interface)

```
effect Log {
  debug! : Str ->{ Log } {}
  info!  : Str ->{ Log } {}
  warn!  : Str ->{ Log } {}
  error! : Str ->{ Log } {}
}
```

### Official Package: Log.Structured (Production Handlers)

- `JsonHandler` — JSON-structured logs to stdout
- `TextHandler` — Human-readable logs with colors
- `FileHandler` — Rotating log files
- `FilterHandler` — Filters by log level
- `OpenTelemetryHandler` — Bridges to OTLP

## WASI Architecture

### WASI Preview 2 Capability Mapping

| WASI Interface | Camp Mapping |
|----------------|--------------|
| `wasi:sockets/tcp` | `Database.Postgres`, `Database.MySql`, `Http.Client`, `Email` |
| `wasi:http/incoming-handler` | `Http.Server` — Camp exports a handler, host handles TLS, framing |
| `wasi:http/outgoing-handler` | `Http.Client` — delegated to host for TLS support |
| `wasi:filesystem` | `File` effect |
| `wasi:clocks` | `Time.now!`, `Time.monotonic_now!` |
| `wasi:random` | `Crypto.Random` (direct), `Random` (seeded PRNG) |
| `wasi:cli/environment` | `Env.get_env!`, `Env.args!` |
| `wasi:cli/stdin-stdout` | `Console.print!`, `Console.readln!` |
| `wasi:io/streams` | `File.read!`, `File.write!`, `Http.Body.Stream` |

### Key Constraints

| Constraint | Impact |
|------------|--------|
| No threading | `Async` uses stackful coroutines on one WASM thread; CPU parallelism requires multiple WASM instances |
| No fork/exec | No `Process` module; shell-out requires WASI host extension |
| No `wasi:crypto` | `Crypto.Hash` compiles to pure WASM; side-channel mitigation limited |
| TLS is Phase 1 only | `Http.Tls` uses host-provided TLS via WASI HTTP interfaces |
| Capability-based security | Socket operations require `network` capability handle from host |

### HTTP Server Architecture

Camp targets `wasi:http/incoming-handler`. The host handles TLS termination, TCP listen/accept, HTTP/1.1 and HTTP/2 framing, and request routing. Camp exports a handler function:

```
handle : Http.Request ->{ Http } Http.Response
```

### Database Driver Architecture

PostgreSQL and MySQL drivers use `wasi:sockets/tcp`: acquire network capability, connect via TCP, implement wire protocol in pure WASM, send/receive over TCP stream.

SQLite uses WASM-compiled SQLite C library linked into the Camp module (standard practice: D1, wa-sqlite).

## Package Repository Strategy

### Current: Git-Based

Dependencies are git repos with `camp.toml` at root. No central registry needed at launch.

### Future: Central Registry

When the community grows: first-come-first-served names, immutable versions, metadata index, `camp.toml` gains `version` field alongside `git` deps.

### Official Package Locations

| Phase | Location |
|-------|----------|
| Initial | Same repo as compiler (`smores56/camp`) |
| Graduation | `camp-lang/camp` (compiler), `camp-lang/http`, `camp-lang/database`, etc. |

## Official Package Inventory

### Priority 1: Required for Production REST API

| Package | Contents |
|---------|----------|
| `Http` | HTTP server + client: Request, Response, Method, Headers, Body, status codes, routing, middleware, query parsing, cookies |
| `Http.Tls` | TLS via host WASI |
| `Cli` | Declarative argument parsing, subcommands, help generation, env var fallback |
| `Config` | Layered config: files (TOML, JSON, YAML), env vars, CLI args; merging; typed access; hot reload |
| `Validate` | Declarative validation rules: required, email, min/max, regex, custom; nested record; error collection |
| `Tls` | Certificate parsing, X.509, PEM/DER, key generation, CSR creation |
| `Database` | Generic database interface: connect!, query!, execute!, prepare!, transaction!, connection pooling |
| `Database.Postgres` | PostgreSQL driver: wire protocol v3, prepared statements, LISTEN/NOTIFY, COPY, JSONB, UUID columns |
| `Database.Sqlite` | SQLite driver: C API via WASM |
| `Database.Migration` | Versioned migration files (up/down), migration runner, dirty state recovery |
| `Jwt` | JWT creation, parsing, validation; HS256, RS256, ES256, EdDSA |
| `Crypto.Hash` | sha256, sha512, blake2b, blake2s, blake3, hmac (separate from stdlib for independent security patching) |

### Priority 2: Important for Most Production Services

| Package | Contents |
|---------|----------|
| `Http.Client` | Async HTTP client with connection pooling, redirects, timeouts, TLS |
| `Http.Middleware` | CORS, request ID, logging, compression, timeout, body size limiting, trace context |
| `Auth` | Session management, OAuth2 flows (authorization code, client credentials, PKCE), token refresh |
| `Auth.Password` | Argon2id, bcrypt, scrypt; salt generation; PHC string format |
| `WebSocket` | WebSocket upgrade, frame parsing, text/binary frames, ping/pong, async streaming |
| `Email` | SMTP transport, email construction, HTML+text multipart, template rendering |
| `Cache` | In-memory LRU, TTL-based, cache effect for async backends, cache-aside helpers |
| `RateLimit` | Token bucket, sliding window, fixed window; per-IP, per-user, per-route; Redis-backed |
| `OpenApi` | OpenAPI 3.1 spec generation from routes; Swagger UI; schema from Codec types |
| `Log.Structured` | JSON output, rotation, level filtering, context propagation, OpenTelemetry bridge |
| `Template` | Type-safe template language, HTML auto-escaping, layout/partial composition |
| `Toml` | TOML parser and emitter; Codec instance |
| `Yaml` | YAML parser and emitter; Codec instance |
| `Collections` | Queue (FIFO), Stack (LIFO) |
| `Collections.Sorted` | SortedMap (range queries), SortedSet (range queries) |

### Priority 3: Useful but Less Common

`Database.Redis`, `Database.MySql`, `Task`, `Http.Sse`, `Http.Multipart`, `Http.Static`, `Grpc`, `MsgPack`, `Protobuf`, `GraphQl`, `Ssh`, `Ftp`, `Database.Admin`, `Prometheus`, `OpenTelemetry`, `Retry`, `CircuitBreaker`, `Bulkhead`, `Resilience`.

## Implementation Order

### Phase 1: Stdlib Core

1. Primitives + collections
2. Basic effects (Console, File, Throw, Env)
3. Codec framework (Encode/Decode with formatting traits) + Json
4. Uri, Regex, Duration, DateTime
5. Log effect
6. Crypto.Random, Base64
7. Gzip, Uuid
8. Remaining P3 stdlib modules

### Phase 2: Official Packages

1. Http (server + client)
2. Database + Database.Postgres + Database.Sqlite
3. Cli, Config, Validate
4. Crypto.Hash, Jwt, Auth, Auth.Password
5. Http.Middleware, Http.Tls
6. WebSocket, Email
7. Database.Migration, Cache, RateLimit
8. Log.Structured, OpenApi, Template
9. Toml, Yaml, Collections
10. Remaining P3 packages

### Phase 3: Community Growth

Publish official packages, document package authoring, encourage contributions, launch registry when warranted.

## Cross-Language Comparison

Camp with its official packages matches Go's "batteries included" coverage for REST API development, while keeping the stdlib smaller and more conservative. Every capability that requires a third-party dep in Rust (serde, regex, tokio, reqwest, sqlx, tracing) is covered by Camp's stdlib + official packages.

## Explicit Exclusions from Stdlib

| Excluded | Reason | Where Instead |
|----------|--------|---------------|
| HTTP server/client | API surface too large, needs independent versioning | Official: `Http` |
| TLS | Complex, rapidly evolving standards | Official: `Http.Tls` |
| Database drivers | Many backends, driver APIs vary | Official: `Database.*` |
| ORM | Too opinionated | Community |
| Crypto hashing | Security-critical, needs rapid patch versioning | Official: `Crypto.Hash` |
| Specialized collections | Not every program needs them; stdlib permanence | Official: `Collections` |
| Full crypto suite | Too large, security-critical | Official + community |
