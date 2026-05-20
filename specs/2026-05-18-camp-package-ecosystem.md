# Camp Package Ecosystem Design Specification

## 1. Overview

This document defines the full set of libraries Camp needs so that a developer building a complex REST API never has to implement missing basic infrastructure. It covers three tiers: the standard library (permanent API guarantee), official packages (stable but independently versioned), and community packages (no stability guarantee).

### Design Principles

1. **Stdlib permanence.** Following Rust's model: once in the stdlib, an API can never be removed. Only add what we're confident is stable and correct.

2. **Composable primitives over frameworks.** The stdlib provides small, well-defined abstractions (Iter, Result, Encode/Decode, effects) that packages compose into larger tools. No "one big framework" — instead, a set of pieces that fit together.

3. **One way to do things.** If the stdlib provides JSON encoding, there's one JSON module. If it provides hashing, there's one hash interface. No redundant mechanisms.

4. **Effects for I/O, pure for computation.** Following Camp's existing design: the stdlib provides pure computation + effect definitions. WASI provides the effectful primitives at runtime.

5. **Start monorepo, graduate to org.** Official packages initially live in the compiler repository for simplicity. Long-term, the compiler moves to `camp-lang/camp` and packages live under individual repos in the `camp-lang` GitHub organization.

---

## 2. Research Summary

### 2.1 Cross-Language Comparison

| Concern | Rust | Go | Python | Java | Zig | Unison |
|---------|------|----|--------|------|-----|--------|
| JSON in stdlib | No (serde) | Yes | Yes | No | Yes | Yes |
| Regex in stdlib | No | Yes | Yes | Yes | No | Yes |
| HTTP in stdlib | No | Yes | Yes | Yes (client) | Yes | Yes |
| Crypto in stdlib | No | Yes | Yes (hashlib/hmac) | Yes | Yes (extensive) | Yes |
| TLS in stdlib | No | Yes | Yes | Yes | Yes | No |
| DB access in stdlib | No | Yes (sql) | Yes (sqlite3) | Yes (sql) | No | No |
| Compression in stdlib | No | Yes | Yes | Yes | Yes | Yes (gzip) |
| CLI parsing in stdlib | No | Yes (flag) | Yes (argparse) | No | No | No |
| Time/Date in stdlib | Yes (minimal) | Yes | Yes | Yes | Yes | Yes |
| Collections in stdlib | Yes | Yes | Yes | Yes | Yes | Yes |
| Iterators/Lazy seqs | Yes | No | Yes | Yes (streams) | No | Yes |
| Logging in stdlib | No | Yes (slog) | Yes | Yes | Yes | No |
| Testing in stdlib | Yes | Yes | Yes | No | Yes | No |

### 2.2 Key Findings

- **Go and Zig** are the most "batteries-included" for backend development. Go's `net/http`, `encoding/json`, `crypto/*`, and `database/sql` mean you can build a REST API with zero third-party packages. Zig includes crypto (AES, Ed25519, TLS, X.509), HTTP, JSON, and compression in its stdlib.

- **Rust** is the most conservative: `serde`, `regex`, `tokio`, `reqwest`, `sqlx`, `tracing` are all third-party. This works because Cargo and crates.io are excellent. Camp won't have that ecosystem at launch.

- **Unison** is the closest analog to Camp (algebraic effects, functional). It includes HTTP, crypto, JSON, STM, channels, and URI parsing in its base library. This is the strongest precedent for Camp's approach.

- **Roc and Gleam** have minimal stdlibs but delegate heavily to platforms/packages. This works because Roc has the Zig platform layer and Gleam has 1,450+ packages on Hex. Camp won't have this ecosystem size at launch.

- **The JSON boundary**: Every language that excludes JSON from stdlib (Rust, Java) ends up with a dominant third-party library that is a de facto required dependency. Including JSON in stdlib avoids this.

- **Crypto in stdlib is surprisingly common**: Go, Python, Java, Zig, and Unison all include it. For a REST API, you need hashing, HMAC, and TLS at minimum.

- **The "no ecosystem yet" problem**: Camp will ship before it has thousands of community packages. This means the stdlib + official packages must cover more ground than Rust's stdlib needed to at launch.

---

## 3. Tier 1: Standard Library

The stdlib ships with the compiler. Its API is permanent — once added, it can never be removed. Only additions that we're confident about belong here.

### 3.1 Existing Stdlib (from Language Design Spec)

These modules are already specified and remain unchanged:

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
| `Result` | Pure | Tag union helpers for Ok(a) \| Err(e): map, and_then, or_else, unwrap |
| `Option` | Pure | Tag union helpers for Some(a) \| None: map, and_then, or_else, unwrap |
| `File` | Effect | File I/O: open!, close!, read!, write! |
| `Console` | Effect | Terminal I/O: print!, printerr!, readln! |
| `Async` | Effect | Concurrency: yield!, spawn!, join!, cancel! |
| `Throw` | Effect | Error effect: throw! operation, variant union tracking |
| `Env` | Effect | CLI args, env vars: args!, get_env! |
| `Time` | Effect | Clock, duration: now!, sleep! |
| `Random` | Effect | Random generation: int!, float!, bytes! |
| `Path` | Pure | File path manipulation: join, split, extension, directory, filename |
| `Fmt` | Pure | Formatting: Display trait, format function, string interpolation helpers |
| `Hash` | Pure | Hashing: Hash trait, hash functions (SipHash, FNV) |
| `Serialize` | Pure | Serialization: Serialize, Deserialize traits, binary format |
| `Eq` | Pure | Equality: Eq trait, structural equality, reference equality |
| `Ord` | Pure | Ordering: Ord trait, Ordering type (Less \| Equal \| Greater), comparison for sorting |

### 3.2 Proposed Stdlib Additions

These are the modules I believe should be added to the stdlib, ranked by importance.

#### Priority 1: Required for Any Non-Trivial Program

| Module | Category | Contents | Rationale |
|--------|----------|----------|-----------|
| `Json` | Pure | JSON codec: parse, stringify, Value type, Encode/Decode trait instances, streaming parser | Every REST API needs JSON. Go, Python, Zig, and Unison include it. Without it, Camp would require a third-party dep for the most basic API operation. The format-agnostic Encode/Decode framework already exists in the spec — Json is the primary format instance. |
| `Regex` | Pure | Regular expressions: compile, match, find, replace, split, capture groups | Virtually every backend validates input with regex. Go, Python, Java, and Haskell include it. The implementation wraps a WASM-compiled regex engine. |
| `Uri` | Pure | URI/URL parsing and construction: scheme, authority, path, query, fragment, percent encoding | HTTP APIs are defined by URIs. Every HTTP framework needs this. Go, Python, Java, Elixir, and Unison include it. |
| `Duration` | Pure | Duration type with arithmetic: seconds, milliseconds, microseconds, nanoseconds, from_parts, to_parts, add, subtract, multiply, compare | The existing `Time` effect returns U64 for now!, but there's no Duration type for expressing timeouts, intervals, or time differences. Every language has this. |
| `DateTime` | Pure | Date/time types: Date, Time, DateTime, TimeZone, offset arithmetic, parsing, formatting (ISO 8601), from_parts, to_parts, compare, add, subtract | Every REST API handles timestamps. Go, Python, Java, and Elixir all include date/time in stdlib. Unison and Zig include time types. |
| `Log` | Effect | Structured logging: debug!, info!, warn!, error! with key-value context | Every production service needs logging. Go (slog), Python (logging), Java (java.util.logging), and Zig (std.log) include it. Camp's effect system makes this natural — Log is an effect that handlers dispatch to WASI stdout/stderr or structured sinks. |

#### Priority 2: Required for Most REST APIs

| Module | Category | Contents | Rationale |
|--------|----------|----------|-----------|
| `Crypto.Random` | Effect | Cryptographically secure random: bytes!, int!, float!, uuid! | Separate from the existing `Random` effect (which is for non-crypto random). Token generation, nonce creation, and UUID generation require cryptographic randomness. Go (crypto/rand), Python (secrets), Java (SecureRandom), and Zig (std.crypto) all provide this. |
| `Base64` | Pure | Base64, Base64URL, Base32, Base16 (Hex) encoding/decoding | The existing `Bytes` module mentions hex and base64, but these are too important for JWT tokens, HTTP Basic auth, and binary-in-JSON to be afterthoughts. Promote to a proper module with URL-safe variants. |
| `Gzip` | Pure | Gzip/zlib compression and decompression: compress, decompress | HTTP content-encoding (gzip) is standard for REST APIs. Go, Python, Java, Zig, and Unison all include compression in stdlib. **Revised: pure, not an effect.** Compression is a pure computation on bytes — it takes Bytes in and produces Bytes out. Memory allocation is not an effect boundary in Camp's model (List.map allocates too). The only I/O is reading the input and writing the output, which the caller handles. |
| `Uuid` | Pure | UUID generation and parsing: v4, v7, parse, from_string, to_string, Nil | Every REST API generates unique IDs. UUID v7 (time-sortable) is becoming the standard for databases. This depends on `Crypto.Random` for generation. |

#### Priority 3: Important for Completeness

**Revised**: Applying the "easy to add later, impossible to remove" principle conservatively. The following modules are deferred to official packages or community packages. Only modules with strong cross-language precedent and clear "every backend needs this" justification remain in stdlib P3.

| Module | Category | Contents | Rationale |
|--------|----------|----------|-----------|
| `Html` | Pure | HTML escaping and basic parsing: escape, unescape, strip_tags, encode_entities, decode_entities | Web APIs that render any HTML need escaping. Go (html/template), Python (html), and Elixir include this. Not a template engine — just the safety primitives. |
| `Csv` | Pure | CSV reading and writing: Reader, Writer, parse_row, write_row, with_header | Data import/export is a common backend task. Go, Python, Java, and Zig all include CSV. |
| `Xml` | Pure | XML parsing and emission: parse, to_string, Element, Attribute, streaming parser | SOAP APIs, RSS feeds, SVG generation, and config files (Maven, Spring, Android) need XML. Go, Python, Java include XML. |
| `Mime` | Pure | MIME type constants and detection: type_by_extension, extension_by_type, parse, format | HTTP Content-Type headers, file upload handling, and email construction need MIME types. Go and Python include this. |
| `Net.Ip` | Pure | IP address types and parsing: Ipv4, Ipv6, parse, is_loopback, is_private, is_multicast | Network utilities need IP types. Go (net), Java (InetAddress), Python (ipaddress) include this. |
| `Version` | Pure | Semantic version parsing and comparison: parse, compare, satisfies, to_string | Package managers, API versioning, and compatibility checks all need semver. Elixir includes this. |

**Deferred to official/community packages:**

| Module | Reason for Deferral |
|--------|-------------------|
| `Sort` | `List.sort` and `List.sort_by` already exist. A dedicated Sort module with multiple algorithms (merge_sort, quick_sort, stable_sort) is niche — most code uses the built-in sort. Can be a community package. |
| `Bits` | Bit manipulation (count_ones, rotate_left, reverse_bits) is needed for low-level protocol work and crypto, not for typical REST APIs. Zig and Haskell provide it, but Camp's primary audience doesn't need it in stdlib. Community package. |
| `Tuple` | Camp records serve the same purpose as tuples. Lightweight 2-3-4 tuples are a convenience, not a necessity. If requested by users, can be added later — but removing them would be a breaking change. Community package initially. |

### 3.3 Existing Stdlib Modules That Need Expansion

| Module | Addition | Rationale |
|--------|----------|-----------|
| `Str` | from_str, to_str for every primitive (already partially there); grapheme-aware operations (graphemes, reverse_graphemes, normalize); case folding (not just uppercase/lowercase — Unicode case folding for comparison) | REST APIs do a lot of string parsing. Grapheme-aware operations are needed for user-facing text. |
| `Bytes` | Hex encoding/decoding, Base64 encoding/decoding should move to `Base64` module; add Bytes.Builder for efficient construction; add read_int, write_int for binary protocol work | Bytes needs a builder pattern (like Go's bytes.Buffer or Elixir's bytes_tree) for efficient concatenation. |
| `Iter` | Add: try_map (map with early exit on Err), chunks_of, windows, intersperse, scan, group_by, partition, unique, min_by, max_by, flat_map, enumerate already specified — also add step, stride, cycle | These are the "long tail" of iterator operations that eliminate the need for `itertools`-style packages. |
| `Map` | Add: update (update a value in-place if present), get_or_insert (entry API like Rust), map_values (transform values), filter_map | Entry API patterns are essential for caches and counters in APIs. |
| `List` | Add: find_index, find_last, chunk, windows, intersperse, scan, group_by, partition, unique_by, min_by, max_by, flat_map, sublist, rotate | These complement Iter and provide convenient eager versions. |
| `Serialize` | Rename/restructure to `Encode`/`Decode` traits with `EncoderFormatting`/`DecoderFormatting` formatting traits: format-agnostic encoding/decoding; then Json, Xml, Csv, Binary are format instances providing formatting trait implementations | The current spec has `Serialize` with binary format only. The Roc-inspired formatting trait design lets every format (JSON, XML, CSV, TOML, MsgPack) use the same Encode/Decode mechanism while handling format-specific concerns (null vs absence, arrays vs rows, type tagging). See §6 for full design. |
| `Time` | Change now! return type from U64 to DateTime; add monotonic_now! for benchmarking; add elapsed!, timeout! combinators | U64 is too low-level for timestamps. DateTime is the right return type. |
| `Random` | Clarify: this is non-cryptographic random (for simulations, shuffling, testing). Crypto.Random is separate. Add: shuffle, sample, weighted. **Boundary**: `Random` uses a fast PRNG (xoshiro256 or similar) seeded from WASI; `Crypto.Random` uses WASI's `random_get` syscall directly. They share the same WASI entropy source at seed time but diverge afterward — `Random` trades security for speed (suitable for simulations, property-based testing, shuffling), while `Crypto.Random` is suitable for token/nonce/key generation. Operations overlap intentionally: `Random.int!` is fast but not secret; `Crypto.Random.int!` is secret but slower. | Two distinct random sources with clear API boundaries and distinct performance/security tradeoffs. |

### 3.4 Proposed New Effect Definitions

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

### 3.5 Proposed New Traits

| Trait | Methods | Derivable? | Rationale |
|-------|---------|------------|-----------|
| `Encode` | `encode : fmt -> Self -> fmt` (parameterized by `EncoderFormatting fmt`) | Yes | Format-agnostic encoding. A single implementation works for JSON, XML, CSV, Binary, etc. |
| `Decode` | `decode : fmt -> Result((fmt, Self), DecodeError)` (parameterized by `DecoderFormatting fmt`) | Yes | Format-agnostic decoding. A single implementation works for every format. |
| `Validate` | `validate : Self -> Result(Self, Str)` | Yes | Input validation. REST APIs validate every incoming request. A trait lets validation compose with Codec. |

### 3.6 Stdlib Module Summary

| Module | Category | Priority | New/Existing |
|--------|----------|----------|-------------|
| `Int` | Pure | Existing | Existing |
| `Float` | Pure | Existing | Existing |
| `Bool` | Pure | Existing | Existing |
| `Str` | Pure | Existing | Existing (expand) |
| `List` | Pure | Existing | Existing (expand) |
| `Iter` | Pure | Existing | Existing (expand) |
| `Map` | Pure | Existing | Existing (expand) |
| `Set` | Pure | Existing | Existing |
| `Bytes` | Pure | Existing | Existing (expand) |
| `Result` | Pure | Existing | Existing |
| `Option` | Pure | Existing | Existing |
| `Path` | Pure | Existing | Existing |
| `Fmt` | Pure | Existing | Existing |
| `Hash` | Pure | Existing | Existing |
| `Serialize`/`Encode`/`Decode` | Pure | Existing | Existing (restructure to formatting-traits design) |
| `Eq` | Pure | Existing | Existing |
| `Ord` | Pure | Existing | Existing |
| `Json` | Pure | P1 | New |
| `Regex` | Pure | P1 | New |
| `Uri` | Pure | P1 | New |
| `Duration` | Pure | P1 | New |
| `DateTime` | Pure | P1 | New |
| `Log` | Effect | P1 | New |
| `Crypto.Random` | Effect | P2 | New |
| `Base64` | Pure | P2 | New |
| `Gzip` | Pure | P2 | New |
| `Uuid` | Pure | P2 | New |
| `Version` | Pure | P3 | New |
| `Html` | Pure | P3 | New |
| `Csv` | Pure | P3 | New |
| `Xml` | Pure | P3 | New |
| `Mime` | Pure | P3 | New |
| `Net.Ip` | Pure | P3 | New |
| `File` | Effect | Existing | Existing |
| `Console` | Effect | Existing | Existing |
| `Async` | Effect | Existing | Existing |
| `Throw` | Effect | Existing | Existing |
| `Env` | Effect | Existing | Existing |
| `Time` | Effect | Existing | Existing (expand) |
| `Random` | Effect | Existing | Existing (clarify scope) |

---

## 4. Tier 2: Official Packages

Official packages are maintained by the Camp team under the `camp-lang` GitHub organization. They are versioned independently from the compiler. Initially they live in the compiler repository for simplicity; long-term they graduate to individual repos.

### 4.1 Priority 1: Required for a Production REST API

| Package | Category | Contents | Rationale |
|---------|----------|----------|-----------|
| `Http` | HTTP server + client | Request, Response, Method, Headers, Body, status codes, content negotiation, routing, middleware chain, query parsing, cookie handling | The single most important package. Go includes this in stdlib; every other language has a dominant HTTP framework. Camp's effect system means HTTP is an effect that handlers dispatch. |
| `Http.Tls` | TLS | TLS configuration, certificate loading, TLS handshake via WASI or rustls-compiled-to-WASM | Every production API needs HTTPS. Go (crypto/tls), Java (javax.net.ssl), Zig (std.crypto.tls) include this in stdlib. Camp should keep it in a package because TLS API surface is large and evolving. |
| `Cli` | CLI argument parsing | Declarative argument definitions, subcommands, help generation, env var fallback | Every server and CLI tool needs argument parsing. Rust (clap), Go (cobra), Python (argparse), OCaml (cmdliner) provide this. |
| `Config` | Configuration | Layered config: files (TOML, JSON, YAML), env vars, CLI args; merging; typed access; hot reload | Every production service reads config from multiple sources. Rust (config), Go (viper), Python (dynaconf) provide this. |
| `Validate` | Input validation | Declarative validation rules: required, email, min/max length, regex, custom validators; nested record validation; error collection | Every REST API validates input. Python (pydantic), Go (validator), C# (FluentValidation) provide this. Camp's structural types + Validate trait make this natural. |
| `Tls` | TLS primitives | Certificate parsing, X.509, PEM/DER, key generation, CSR creation | Subsumed by Http.Tls for most users, but also needed for mTLS, certificate management, and secure WebSocket. |
| `Database` | Database access | Generic database interface: connect!, query!, execute!, prepare!, transaction!, connection pooling; parameterized queries; result row iteration | Go (database/sql), Java (JDBC), and Python (sqlite3/DBAPI) include generic DB interfaces. Camp should provide a database effect + driver interface. |
| `Database.Postgres` | PostgreSQL driver | PostgreSQL-specific driver implementing Database interface: connection, prepared statements, LISTEN/NOTIFY, COPY, array types, JSONB, UUID columns | PostgreSQL is the most common database for REST APIs. The driver implements the generic Database effect. |
| `Database.Sqlite` | SQLite driver | SQLite-specific driver implementing Database interface | SQLite is essential for development, testing, embedded, and edge deployments. |
| `Database.Migration` | Schema migration | Versioned migration files (up/down), migration runner, dirty state recovery, schema introspection | Every database-backed service needs migrations. Rust (refinery), Go (golang-migrate, goose), Java (Flyway) provide this. |
| `Jwt` | JWT tokens | JWT creation, parsing, validation; HS256, RS256, ES256, EdDSA algorithms; claims extraction; expiration checking | REST APIs use JWT for authentication. Every ecosystem has a JWT library. |
| `Crypto.Hash` | Cryptographic hashing | sha256, sha512, blake2b, blake2s, blake3, hmac | Moved from stdlib: implementation bugs (side-channel timing, padding oracles) need independent versioning for fast security patches. WASM lacks constant-time memory operations, making side-channel mitigation a continuing concern. Keeping this out of stdlib lets the package ship fixes without a compiler release. |

### 4.2 Priority 2: Important for Most Production Services

| Package | Category | Contents | Rationale |
|---------|----------|----------|-----------|
| `Http.Client` | HTTP client | Async HTTP client: get!, post!, put!, delete!, patch!; request building; response handling; connection pooling; redirects; timeouts; TLS | Not all services are servers — many are clients calling other APIs. Separate from the server for clear dependency boundaries. |
| `Http.Middleware` | HTTP middleware | CORS, request ID, request logging, response compression, request decompression, timeout, request body size limiting, trace context propagation | Middleware is what makes HTTP servers production-ready. Rust (tower-http), Go (chi middleware), Python (Starlette middleware) provide these. |
| `Auth` | Authentication | Session management, OAuth2 client flows (authorization code, client credentials, PKCE), token refresh, scope handling | Beyond JWT — OAuth2 flows and session management. Rust (oauth2), Go (golang.org/x/oauth2), Python (Authlib) provide this. |
| `Auth.Password` | Password hashing | Argon2id, bcrypt, scrypt; salt generation; verification; PHC string format | User registration/login requires password hashing. Rust (argon2), Go (x/crypto/bcrypt), Python (passlib) provide this. |
| `WebSocket` | WebSocket protocol | WebSocket upgrade, frame parsing, text/binary frames, ping/pong, close frames, async message streaming | Real-time APIs need WebSocket. Rust (tokio-tungstenite), Go (gorilla/websocket), Python (websockets) provide this. |
| `Email` | Email sending | SMTP transport, email construction (To, From, Subject, Body, attachments), HTML+text multipart, template rendering | User notifications, password reset, welcome emails. Rust (lettre), Go (go-mail), Python (smtplib) provide this. |
| `Cache` | Caching | In-memory LRU cache, TTL-based expiration, cache effect for async backends (Redis), cache-aside pattern helpers | Every API caches responses. Rust (moka), Go (bigcache, ristretto), Python (cachetools) provide this. |
| `RateLimit` | Rate limiting | Token bucket, sliding window, fixed window; per-IP, per-user, per-route; in-memory and Redis-backed stores | API protection against abuse. Rust (governor), Go (x/time/rate) provide this. |
| `OpenApi` | API documentation | OpenAPI 3.1 spec generation from route definitions; Swagger UI serving; schema generation from Codec types | API documentation is required for team collaboration and client generation. Rust (utoipa), Go (swag), Python (FastAPI auto-generates) provide this. |
| `Log.Structured` | Structured logging | JSON log output, log rotation, log level filtering, context propagation, OpenTelemetry bridge | Production services need structured logs for aggregation. Go (slog), Rust (tracing), Python (structlog) provide this. The stdlib `Log` effect is the interface; this package provides production handlers. |
| `Template` | Template rendering | Type-safe template language, HTML auto-escaping, layout/partial composition, compile-time template checking | Server-rendered HTML, email templates, and report generation. Rust (askama, tera), Go (html/template), Python (Jinja2) provide this. |
| `Toml` | TOML codec | TOML parser and emitter; Codec instance for TOML format | Camp's own `camp.toml` uses TOML. Config files commonly use TOML. |
| `Yaml` | YAML codec | YAML parser and emitter; Codec instance for YAML format | CI/CD configs (GitHub Actions, GitLab CI), Kubernetes manifests, and many config files use YAML. |
| `Collections` | Specialized collections | Queue (FIFO: push, pop, peek, length), Stack (LIFO: push, pop, peek, length) | Moved from stdlib: not every program needs Queue/Stack, and the stdlib permanence guarantee means they can never be removed once added. As official packages they can iterate independently. |
| `Collections.Sorted` | Ordered collections | SortedMap (ordered map with range queries), SortedSet (ordered set with range queries) | Moved from stdlib: ordered maps/sets are needed for leaderboards, time-series, range scans — but not "every program needs this." Haskell (Data.Map), Java (TreeMap) provide these. |

### 4.3 Priority 3: Useful but Less Common

| Package | Category | Contents | Rationale |
|---------|----------|----------|-----------|
| `Database.Redis` | Redis driver | Redis commands, pub/sub, pipelines, Lua scripts, connection pooling | Caching, session storage, rate limiting, and message queues. |
| `Database.MySql` | MySQL driver | MySQL-specific driver implementing Database interface | Some organizations standardize on MySQL. |
| `Task` | Background jobs | Async task queue: enqueue!, dequeue!, retry, schedule, priority, dead letter queue; in-memory and Redis-backed | Email sending, report generation, data processing. Rust (fang), Go (asynq), Python (Celery, ARQ) provide this. |
| `Http.Sse` | Server-Sent Events | SSE stream construction, event formatting, retry protocol, Last-Event-ID | Real-time updates without WebSocket complexity. |
| `Http.Multipart` | Multipart form data | File upload parsing, form field extraction, streaming large uploads | File upload handling. |
| `Http.Static` | Static file serving | MIME type detection, ETag, Last-Modified, range requests, gzip pre-compressed | Serving frontend assets. |
| `Grpc` | gRPC | Protobuf codec, gRPC service definitions, streaming RPC | Microservice communication. |
| `MsgPack` | MessagePack codec | MessagePack parser and emitter; Codec instance | Efficient binary serialization for APIs. |
| `Protobuf` | Protocol Buffers | Protobuf parser and emitter; Codec instance | gRPC and inter-service communication. |
| `GraphQl` | GraphQL | Query parsing, schema definition, resolver framework, introspection | Alternative to REST for some teams. |
| `Ssh` | SSH | SSH client, key management, remote command execution | Infrastructure automation. |
| `Ftp` | FTP | FTP client, file transfer, directory listing | Legacy system integration. |
| `Database.Admin` | Database admin | Connection management UI, query editor, schema viewer | Development tooling. |
| `Prometheus` | Metrics | Counter, Gauge, Histogram, Summary; exposition format; HTTP endpoint | Production monitoring. |
| `OpenTelemetry` | Observability | Traces, metrics, logs; OTLP export; context propagation | Distributed tracing across services. |
| `Retry` | Retry policies | Exponential backoff, jitter, max attempts, retry budget | Network operations need retry logic. |
| `CircuitBreaker` | Resilience | Circuit breaker (closed/open/half-open), failure tracking, recovery | Preventing cascade failures. |
| `Bulkhead` | Resilience | Concurrent request limiting, thread pool isolation | Resource protection. |
| `Resilience` | Combined | Retry + CircuitBreaker + Bulkhead + Timeout composition | Polished composition of resilience patterns. |

### 4.4 Official Package Summary

| Package | Priority | Category |
|---------|----------|----------|
| `Http` | P1 | HTTP |
| `Http.Tls` | P1 | HTTP |
| `Cli` | P1 | CLI |
| `Config` | P1 | Configuration |
| `Validate` | P1 | Validation |
| `Database` | P1 | Database |
| `Database.Postgres` | P1 | Database |
| `Database.Sqlite` | P1 | Database |
| `Database.Migration` | P1 | Database |
| `Jwt` | P1 | Auth |
| `Crypto.Hash` | P1 | Crypto |
| `Http.Client` | P2 | HTTP |
| `Http.Middleware` | P2 | HTTP |
| `Auth` | P2 | Auth |
| `Auth.Password` | P2 | Auth |
| `WebSocket` | P2 | Real-time |
| `Email` | P2 | Communication |
| `Cache` | P2 | Performance |
| `RateLimit` | P2 | API Protection |
| `OpenApi` | P2 | Documentation |
| `Log.Structured` | P2 | Observability |
| `Template` | P2 | Rendering |
| `Toml` | P2 | Codec |
| `Yaml` | P2 | Codec |
| `Collections` | P2 | Data Structures |
| `Collections.Sorted` | P2 | Data Structures |
| `Database.Redis` | P3 | Database |
| `Database.MySql` | P3 | Database |
| `Task` | P3 | Background |
| `Http.Sse` | P3 | Real-time |
| `Http.Multipart` | P3 | HTTP |
| `Http.Static` | P3 | HTTP |
| `Grpc` | P3 | Communication |
| `MsgPack` | P3 | Codec |
| `Protobuf` | P3 | Codec |
| `GraphQl` | P3 | API |
| `Ssh` | P3 | Infrastructure |
| `Ftp` | P3 | Infrastructure |
| `Prometheus` | P3 | Observability |
| `OpenTelemetry` | P3 | Observability |
| `Retry` | P3 | Resilience |
| `CircuitBreaker` | P3 | Resilience |
| `Bulkhead` | P3 | Resilience |
| `Resilience` | P3 | Resilience |

---

## 5. Tier 3: Community Packages

Community packages are third-party libraries with no stability guarantee. They live in individual GitHub repositories and are referenced via `camp.toml` git dependencies. A central registry can be added later without changing the format.

### 5.1 Expected Community Package Categories

| Category | Example Packages |
|----------|-----------------|
| ORM alternatives | Declarative ORM with relations, query builders, code-gen models |
| Cloud SDKs | AWS S3, Google Cloud Storage, Azure Blob, SendGrid, Stripe, Twilio |
| Message queues | Kafka, RabbitMQ, NATS, Amazon SQS |
| Search | Elasticsearch, Meilisearch, Typesense drivers |
| Additional databases | MongoDB, DynamoDB, CouchDB, Cassandra drivers |
| Additional formats | BSON, CBOR, Apache Avro, Thrift, TOML extended |
| UI frameworks | Server-side HTML rendering, component libraries |
| Testing utilities | Property-based testing, mock frameworks, HTTP mock servers, test fixtures |
| Data transformation | CSV advanced, Parquet, Excel, PDF generation |
| Image processing | Image resize, crop, format conversion |
| PDF generation | Invoice rendering, report generation |
| Machine learning | ONNX runtime, model serving |
| Geospatial | GeoJSON, distance calculation, coordinate systems |
| i18n | Translation file loading, plural rules, locale formatting |
| Graph algorithms | Shortest path, traversal, community detection |
| Cryptography extended | Age encryption, PGP, SSH key handling |
| Encoding | Charset detection, legacy encoding support |
| Async patterns | Stream processing, backpressure, reactive extensions |

---

## 6. Codec Framework Design

The existing `Serialize` trait in the spec handles binary serialization. This should be generalized into a `Codec` framework that all format instances share.

### 6.1 The Problem with a Simple Codec Trait

A naive `Codec` trait with `encode : Self -> Bytes` and `decode : Bytes -> Result(Self, Str)` assumes all formats are interchangeable — but they aren't:

| Problem | Example |
|---------|---------|
| **Null vs absence** | JSON has `null` (a value); XML has `xsi:nil` (an attribute); CSV has empty cells (absence). A format-agnostic `Encode` can't know whether to emit null or omit the field. |
| **Collections vs records** | JSON encodes lists as arrays `[1,2,3]`; CSV encodes them as rows (one list element per row, same columns). A format-agnostic `Encode` can't decide between "this is an array element" and "this is a row with columns." |
| **Type tagging** | JSON has no type tags — `{"name": "Ada"}` is just an object. MsgPack and Protobuf use field numbers. XML uses element names. The encoding of a record's structure is format-specific. |
| **Streaming vs buffered** | JSON and XML benefit from streaming encoders (write opening tag, write fields, write closing tag). Binary formats write field-by-field with length prefixes. A single `encode : Self -> Bytes` forces all formats into the same allocation pattern. |

### 6.2 Roc-Inspired Design: Formatting Traits

Roc solves this with `EncoderFormatting` and `DecoderFormatting` traits that separate "what to encode" from "how to format it." Camp should adopt the same approach:

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

Each format provides an instance of these traits:

| Format | EncoderFormatting instance | DecoderFormatting instance |
|--------|---------------------------|---------------------------|
| JSON | `Json.Formatter` (emits `{`, `"key":`, `null`, `[`, etc.) | `Json.Parser` (reads JSON tokens) |
| XML | `Xml.Formatter` (emits `<record>`, `<field>`, `xsi:nil`, etc.) | `Xml.Parser` (reads XML elements) |
| CSV | `Csv.Formatter` (emits rows with comma separators) | `Csv.Parser` (reads CSV rows) |
| Binary | `Binary.Formatter` (emits length-prefixed fields) | `Binary.Parser` (reads binary fields) |

### 6.3 Encode and Decode Traits (Format-Agnostic)

User types implement `Encode` and `Decode` against an abstract formatter:

```
trait Encode a is EncoderFormatting fmt => {
  encode : fmt -> a -> fmt
}

trait Decode a is DecoderFormatting fmt => {
  decode : fmt -> Result((fmt, a), DecodeError)
}
```

The formatter is a parameter, not a fixed type. This means a single `Encode` implementation works for every format that provides an `EncoderFormatting` instance.

### 6.4 Format Instances

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

### 6.5 Derive Integration

```
@derive [Encode, Decode]
User := { name: Str, age: U64 }
```

This generates `Encode` and `Decode` implementations that call `EncoderFormatting`/`DecoderFormatting` methods. The generated code is format-agnostic — it works for every format that provides the formatting traits. If a specific field needs custom encoding, the derive can be overridden per-field.

### 6.6 Convenience Functions

Each format module provides convenience functions for the common case:

```
Json.encode : Encode a => a -> Str
Json.decode : Decode a => Str -> Result(a, DecodeError)
```

---

## 7. Database Effect Design

### 7.1 Generic Database Interface

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

### 7.2 Driver Interface

Drivers implement a handler for the `Database` effect. The handler translates Camp's effect operations into WASI socket calls to the database server.

| Driver | Package | Protocol |
|--------|---------|----------|
| PostgreSQL | `Database.Postgres` | PostgreSQL wire protocol v3 |
| SQLite | `Database.Sqlite` | SQLite C API via WASI |
| MySQL | `Database.MySql` | MySQL wire protocol |
| Redis | `Database.Redis` | RESP3 protocol |

### 7.3 Query Building

Rather than a full ORM, Camp should provide a composable query builder:

```
Query.select("users")
  .where("age", Gt, 18)
  .order_by("name", Asc)
  .limit(10)
  .build()
```

This is less magical than a full ORM (no lazy loading, no N+1, no impedance mismatch) and more type-safe than raw SQL strings. The query builder lives in the `Database` package. A separate community ORM can be built on top if desired.

### 7.4 Future Work: Typed Query Effects

The current `Database` effect uses string queries with `List(Value)` parameters — equivalent to Go's `database/sql`. Camp's effect system opens a more ambitious possibility: **typed query effects** where the query result type is tracked in the effect signature, enabling compile-time verification that every query result is consumed and every error is handled.

This is research-grade work. For v1, the Go-style string-query interface gives Camp a practical advantage over Go (effect tracking already ensures errors are handled), while leaving room for typed queries as the language and type system mature. The key challenge is making query types expressive enough to be useful without requiring a full dependent-type system.

---

## 8. HTTP Effect Design

### 8.1 Server Effect

```
effect Http.Server {
  listen!  : Str, U16 ->{ Http.Server } {}
  route!   : Method, Str, (Request ->{ Http } Response) ->{ Http.Server } {}
  serve!   : || ->{ Http.Server, Throw(HttpError) } {}
}
```

### 8.2 Client Effect

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

### 8.3 Core Types

```
Http.Request  := { method: Method, uri: Uri, headers: Map(Str, Str), body: Body }
Http.Response := { status: U16, headers: Map(Str, Str), body: Body }
Http.Method   := [Get | Post | Put | Delete | Patch | Head | Options | Connect | Trace]
Http.Body     := [Empty | Text(Str) | Binary(Bytes) | Stream(Iter(Bytes))]
Http.Header    := { name: Str, value: Str }
```

---

## 9. Logging Architecture

### 9.1 Stdlib: Log Effect (Interface)

The stdlib provides the `Log` effect — the interface that application code calls:

```
effect Log {
  debug! : Str ->{ Log } {}
  info!  : Str ->{ Log } {}
  warn!  : Str ->{ Log } {}
  error! : Str ->{ Log } {}
}
```

This is minimal by design. Application code calls `Log.info!("Request processed")` and doesn't care where the logs go.

### 9.2 Official Package: Log.Structured (Production Handlers)

The `Log.Structured` package provides handlers that format and route logs:

- `JsonHandler` — writes JSON-structured logs to stdout
- `TextHandler` — writes human-readable logs with colors
- `FileHandler` — writes to rotating log files
- `FilterHandler` — filters by log level
- `OpenTelemetryHandler` — bridges to OTLP

### 9.3 Key-Value Context

```
Log.info!("Request processed", { duration_ms: 42, path: "/api/users", status: 200 })
```

Log messages carry structured key-value context. Handlers decide how to format this (JSON fields, text suffixes, OTLP attributes). This follows Go's slog and Rust's tracing approach.

---

## 10. WASI Architecture

Camp compiles to WASM/WASI Preview 2. Every stdlib module and official package must work within WASI constraints. This section documents how.

### 10.1 WASI Preview 2 Capabilities

| WASI Interface | What It Provides | Camp Mapping |
|----------------|-------------------|--------------|
| `wasi:sockets/tcp` | TCP connect/listen (requires `network` capability) | `Database.Postgres`, `Database.MySql`, `Http.Client`, `Email` (SMTP) |
| `wasi:sockets/udp` | UDP send/receive | `Dns` (future) |
| `wasi:http/incoming-handler` | Host calls your handler with incoming HTTP requests | `Http.Server` — Camp exports a handler, host handles TLS, framing |
| `wasi:http/outgoing-handler` | Make outgoing HTTP requests | `Http.Client` — delegated to host for TLS support |
| `wasi:filesystem` | File read/write/directory operations | `File` effect |
| `wasi:clocks` | Wall clock, monotonic clock | `Time.now!`, `Time.monotonic_now!` |
| `wasi:random` | Cryptographic random bytes | `Crypto.Random` (direct), `Random` (seeded PRNG) |
| `wasi:cli/environment` | Environment variables, CLI arguments | `Env.get_env!`, `Env.args!` |
| `wasi:cli/stdin-stdout` | Standard input/output streams | `Console.print!`, `Console.readln!` |
| `wasi:io/streams` | Async byte streams | `File.read!`, `File.write!`, `Http.Body.Stream` |

### 10.2 Key Constraints

| Constraint | Impact on Camp | Design Implications |
|------------|----------------|---------------------|
| **No threading** | No OS threads, no thread::spawn | Camp's `Async` effect uses stackful coroutines (cooperative scheduling within a single WASM thread). This is sufficient — async I/O handles concurrency, and CPU parallelism requires multiple WASM instances. |
| **No fork/exec** | Cannot spawn subprocesses | No `Process` module in stdlib. Shell-out patterns require a WASI host extension. |
| **No `wasi:crypto`** | No standard crypto primitives interface | `Crypto.Hash` must compile to pure WASM (no host calls). Algorithms implemented in Camp/WASM, verified against test vectors. Side-channel mitigation is limited — see §4.1 Crypto.Hash rationale. |
| **TLS is Phase 1 only** | No standard TLS interface in WASI Preview 2 | `Http.Tls` must use host-provided TLS via `wasi:http/outgoing-handler` (client) or `wasi:http/incoming-handler` (server). The host terminates TLS; Camp never sees raw TLS handshake. |
| **Capability-based security** | All socket operations require a `network` capability handle from the host | Database drivers, HTTP client, and email must accept a `network` parameter (or have one injected by the runtime). No implicit network access. |

### 10.3 HTTP Server Architecture

Camp's HTTP server targets the `wasi:http/incoming-handler` interface. The host (e.g., Wasmtime, Spin, Fastly) handles:

- TLS termination (certificates, handshakes)
- TCP listen/accept
- HTTP/1.1 and HTTP/2 framing
- Request routing to the WASM module

Camp exports a handler function that receives `wasi:http/incoming-request` and returns `wasi:http/outgoing-response`. This is the same model used by Fermyon Spin, Fastly Compute, and the WASI HTTP proposal reference implementations.

```
// Camp's handler interface (conceptual)
handle : Http.Request ->{ Http } Http.Response
```

The host calls this handler for each incoming request. Camp's `Http.Server` effect is a thin wrapper around this interface.

### 10.4 Database Driver Architecture

PostgreSQL and MySQL drivers use `wasi:sockets/tcp` to connect to database servers:

1. Acquire a `network` capability handle from the host (capability-based security)
2. Connect via TCP to the database host:port
3. Implement the wire protocol (PostgreSQL v3, MySQL) in pure WASM
4. Send/receive messages over the TCP stream

SQLite uses a different approach: since there's no subprocess, SQLite's C library must be compiled to WASM and linked into the Camp module. This is standard practice — WASM-compiled SQLite is used by D1 (Cloudflare), wa-sqlite, and similar projects.

---

## 11. Package Repository Strategy

### 10.1 Current: Git-Based (No Registry)

Following the language design spec: dependencies are git repos with `camp.toml` at their root. No central registry needed at launch.

### 10.2 Future: Central Registry

When the community grows, add a registry (like crates.io, npm, or Hex):

- Package names are claimed on a first-come, first-served basis
- Versions are immutable once published
- The registry indexes package metadata for fast resolution
- The `camp.toml` format gains a `version` field for registry deps alongside `git` deps

### 10.3 Official Package Locations

| Phase | Location | Rationale |
|-------|----------|-----------|
| Initial | Same repo as compiler (`smores56/camp`) | Simplest; no multi-repo tooling needed |
| Graduation | `camp-lang/camp` (compiler), `camp-lang/http`, `camp-lang/database`, etc. | Compiler and packages decouple for independent versioning |

---

## 12. Implementation Order

Building the ecosystem in the right order matters — each package depends on its prerequisites.

### Phase 1: Stdlib Core (with compiler milestones)

These ship as the compiler reaches each phase:

1. Primitives + collections (Int, Str, List, Map, Set, Iter, Option, Result)
2. Basic effects (Console, File, Throw, Env)
3. Codec framework (Encode/Decode with EncoderFormatting/DecoderFormatting traits) + Json (the first format instance)
4. Uri, Regex, Duration, DateTime
5. Log effect
6. Crypto.Random, Base64
7. Gzip (pure), Uuid
8. Remaining P3 stdlib modules (Html, Csv, Xml, Mime, Net.Ip, Version)

### Phase 2: Official Packages (after compiler is stable)

1. Http (server + client) — the foundation everything else builds on
2. Database + Database.Postgres + Database.Sqlite
3. Cli, Config, Validate
4. Crypto.Hash, Jwt, Auth, Auth.Password
5. Http.Middleware, Http.Tls
6. WebSocket, Email
7. Database.Migration, Cache, RateLimit
8. Log.Structured, OpenApi, Template
9. Toml, Yaml, Collections, Collections.Sorted
10. Remaining P3 packages

### Phase 3: Community Growth

- Publish the official packages
- Document the package authoring guide
- Encourage community contributions
- Launch a registry when the package count warrants it

---

## 13. What Camp Explicitly Does NOT Include in Stdlib

| Excluded | Reason | Where Instead |
|----------|--------|---------------|
| HTTP server/client | API surface too large, needs independent versioning | Official package: `Http` |
| TLS | Complex, rapidly evolving standards | Official package: `Http.Tls` |
| Database drivers | Many backends, driver APIs vary | Official packages: `Database.*` |
| ORM | Too opinionated, many design choices | Community packages |
| Template engine | Multiple valid designs (Jinja2-style, type-safe compile-time, etc.) | Official package: `Template` |
| OAuth2 | Complex flows, many provider-specific quirks | Official package: `Auth` |
| Email | Multiple transport mechanisms | Official package: `Email` |
| WebSocket | Protocol-level complexity, framing, ping/pong | Official package: `WebSocket` |
| gRPC/Protobuf | Niche, large API surface | Official package: `Grpc` |
| GraphQL | Niche, complex resolver model | Community package |
| Full crypto suite (AES, RSA, ECDSA, TLS, X.509) | Too large, security-critical (needs rapid updates) | Official packages + community |
| Crypto hashing | Implementation bugs need independent versioning for fast security patches; WASM side-channel risk | Official package: `Crypto.Hash` |
| Specialized collections (Queue, Stack, SortedMap, SortedSet) | Not every program needs these; stdlib permanence means they can never be removed | Official packages: `Collections`, `Collections.Sorted` |
| Multiple sort algorithms | `List.sort`/`List.sort_by` cover the common case | Community package |
| Bit manipulation | Niche — protocol work and crypto, not typical REST APIs | Community package |
| Tuple types | Camp records serve the same purpose | Community package |
| Message queues (Kafka, RabbitMQ) | Niche, many backends | Community packages |
| Cloud SDKs | Provider-specific, constantly changing | Community packages |
| UI frameworks | Opinionated, many valid approaches | Community packages |
| Debugging/Profiling tools | Runtime-specific, needs compiler integration | Compiler tooling |

---

## 14. Comparison: Camp vs Peer Languages for REST API Coverage

| Capability | Camp Stdlib | Camp + Official | Rust | Go |
|-----------|-------------|------------------|------|----|
| JSON | Yes (Json) | Yes | serde (3rd) | Yes |
| HTTP server | No | Yes (Http) | axum/actix (3rd) | Yes |
| HTTP client | No | Yes (Http.Client) | reqwest (3rd) | Yes |
| TLS | No | Yes (Http.Tls) | rustls (3rd) | Yes |
| Database | No | Yes (Database.*) | sqlx/diesel (3rd) | Yes |
| Regex | Yes | Yes | regex (3rd) | Yes |
| URI parsing | Yes (Uri) | Yes | url (3rd) | Yes |
| Crypto hashing | No | Yes (Crypto.Hash) | sha2 (3rd) | Yes |
| Crypto random | Yes (Crypto.Random) | Yes | rand (3rd) | Yes |
| UUID | Yes (Uuid) | Yes | uuid (3rd) | 3rd |
| JWT | No | Yes (Jwt) | jsonwebtoken (3rd) | 3rd |
| Password hashing | No | Yes (Auth.Password) | argon2 (3rd) | 3rd |
| OAuth2 | No | Yes (Auth) | oauth2 (3rd) | 3rd |
| CLI parsing | No | Yes (Cli) | clap (3rd) | Yes (flag) |
| Configuration | No | Yes (Config) | config (3rd) | 3rd |
| Validation | No | Yes (Validate) | validator (3rd) | 3rd |
| Logging | Yes (Log) | Yes (Log.Structured) | tracing (3rd) | Yes |
| Template rendering | No | Yes (Template) | tera/askama (3rd) | Yes |
| Email | No | Yes (Email) | lettre (3rd) | 3rd |
| WebSocket | No | Yes (WebSocket) | tokio-tungstenite (3rd) | 3rd |
| Rate limiting | No | Yes (RateLimit) | governor (3rd) | 3rd |
| Caching | No | Yes (Cache) | moka (3rd) | 3rd |
| DB migrations | No | Yes (Database.Migration) | refinery (3rd) | 3rd |
| OpenAPI | No | Yes (OpenApi) | utoipa (3rd) | 3rd |
| TOML | No | Yes (Toml) | toml (3rd) | 3rd |
| YAML | No | Yes (Yaml) | serde_yaml (3rd) | 3rd |
| Compression | Yes (Gzip, pure) | Yes | flate2 (3rd) | Yes |
| Date/Time | Yes (DateTime) | Yes | chrono (3rd) | Yes |

Camp with its official packages matches Go's "batteries included" coverage for REST API development, while keeping the stdlib smaller and more conservative than Go's.
