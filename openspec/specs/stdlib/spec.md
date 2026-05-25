# Domain Specification: Standard Library

## Purpose

Define the standard library API for Camp: the stdlib tier composition, module listing, encode/decode codec framework, and the API design for each stdlib and official package module. For the package ecosystem (versioning, registry, git dependencies, embedding), see `openspec/specs/packages/spec.md`.

## Requirements

### Requirement: Stdlib API Permanence

Once a module is added to the stdlib, its public API SHALL NOT be removed in any future compiler release.

#### Scenario: Stdlib module remains available after addition

- Given the `Json` module is added to the stdlib in compiler version 0.5
- When the compiler is upgraded to version 1.0
- Then the `Json` module's public API SHALL remain available with backward-compatible signatures

### Requirement: Stdlib Tier Composition

The stdlib SHALL contain only modules that are either existing language-design-specified modules or additions justified by cross-language precedent and universal backend need.

#### Scenario: Module inclusion requires justification

- Given a proposed stdlib module `X`
- When the module is evaluated for inclusion
- Then it SHALL be included only if it meets Priority 1 (required for any non-trivial program), Priority 2 (required for most REST APIs), or Priority 3 (important for completeness) criteria

### Requirement: Encode/Decode Codec Framework

The stdlib SHALL provide format-agnostic `Encode` and `Decode` traits parameterized by `EncoderFormatting` and `DecoderFormatting` formatting traits, enabling a single type implementation to work across all supported formats.

#### Scenario: Type derives Encode and Decode for multiple formats

- Given a Camp type `@User : { name: Str, age: U64 }` with `derives Encode, Decode`
- When the `User` type is used with `Json.encode` and `Csv.encode`
- Then both formats SHALL produce correctly formatted output from the same derived implementation

#### Scenario: Format-specific null handling

- Given a record field with value `None`
- When encoded via `Json.Formatter`
- Then the encoder SHALL emit JSON `null`
- When encoded via `Csv.Formatter`
- Then the encoder SHALL emit an empty cell (absence)

### Requirement: Json Module

The stdlib SHALL include a `Json` module providing parsing, stringification, a `Value` type, `Encode`/`Decode` trait instances, and a streaming parser.

#### Scenario: Parse and stringify round-trip

- Given a JSON string `{"name": "Ada", "age": 36}`
- When `Json.decode` is called followed by `Json.encode`
- Then the result SHALL be semantically equivalent to the input

#### Scenario: Encode derived type to JSON

- Given a type `@User : { name: Str, age: U64 }` with `derives Encode, Decode`
- When `Json.encode(user)` is called
- Then it SHALL produce `{"name":"Ada","age":36}`

### Requirement: Regex Module

The stdlib SHALL include a `Regex` module providing compile, match, find, replace, split, and capture group operations.

#### Scenario: Match and extract capture groups

- Given a compiled regex `(\d{4})-(\d{2})-(\d{2})`
- When matched against `"2026-05-20"`
- Then the capture groups SHALL return `["2026", "05", "20"]`

### Requirement: Uri Module

The stdlib SHALL include a `Uri` module providing URI/URL parsing and construction with scheme, authority, path, query, fragment, and percent encoding.

#### Scenario: Parse URI components

- Given a URI string `"https://example.com:8080/api/users?limit=10#top"`
- When parsed by `Uri.parse`
- Then scheme SHALL be `"https"`, authority SHALL be `"example.com:8080"`, path SHALL be `"/api/users"`, query SHALL be `"limit=10"`, and fragment SHALL be `"top"`

### Requirement: Duration and DateTime Types

The stdlib SHALL include a `Duration` type with arithmetic (seconds, milliseconds, microseconds, nanoseconds, add, subtract, multiply, compare) and a `DateTime` type with Date, Time, DateTime, TimeZone, offset arithmetic, ISO 8601 parsing/formatting, and comparison.

#### Scenario: Duration arithmetic

- Given `Duration.from_seconds(5)` and `Duration.from_millis(500)`
- When added together
- Then the result SHALL equal `Duration.from_millis(5500)`

#### Scenario: DateTime ISO 8601 round-trip

- Given a DateTime value `2026-05-20T14:30:00Z`
- When parsed from ISO 8601 string and formatted back
- Then the round-trip SHALL produce an equivalent DateTime

### Requirement: Log Effect

The `Log` effect SHALL include a `Log!` effect with `debug!`, `info!`, `warn!`, and `error!` operations accepting a message string and optional key-value context.

#### Scenario: Structured log message

- Given `Log.info!("Request processed", { duration_ms: 42, path: "/api/users", status: 200 })`
- When a Log handler is installed
- Then the handler SHALL receive the message string and structured key-value context

### Requirement: Random! Effect with Multiple Handlers

The stdlib SHALL provide a single `Random!` effect with two handler implementations: `random_prng` (fast, non-cryptographic) and `random_crypto` (WASI `random_get`, cryptographically secure). The effect interface includes `bytes!`, `int!`, `float!`, and `bool!` operations. The handler choice determines the security guarantee — the effect signature alone does not guarantee cryptographic security.

#### Scenario: Cryptographic random generation via handler

- Given a `random_crypto` handler is installed
- When `Random.bytes!(16)` is called
- Then the result SHALL be 16 bytes of cryptographically secure random data sourced from WASI's `random_get` syscall

#### Scenario: Fast PRNG via handler

- Given a `random_prng` handler is installed with seed 42
- When `Random.int!(1, 100)` is called
- Then the result SHALL be fast but MUST NOT be used for token or key generation

#### Scenario: Same effect interface, different security

- Given `Random.int!(1, 100)` is called
- When the `random_prng` handler is installed, the result uses a fast PRNG
- And when the `random_crypto` handler is installed, the result uses WASI's `random_get` syscall
- Then both produce valid random integers but with different security guarantees

### Requirement: Uuid Module

The stdlib SHALL include a `Uuid` module supporting v4, v7 generation, parsing, and formatting, depending on `Random!` for generation. The handler choice (fast PRNG vs cryptographic) determines the security guarantee of generated UUIDs.

#### Scenario: UUID v7 generation

- Given a `Random!` handler is installed
- When `Uuid.v7!(timestamp_ms)` is called
- Then the result SHALL be a time-sortable UUID with the given timestamp embedded

### Requirement: Base64 Module

The stdlib SHALL include a `Base64` module supporting Base64, Base64URL, Base32, and Base16 (Hex) encoding and decoding.

#### Scenario: URL-safe Base64 encoding

- Given binary data containing bytes 0xFF and 0xFE
- When encoded via `Base64URL.encode`
- Then the result SHALL use `-` and `_` instead of `+` and `/`

### Requirement: Gzip Module

The stdlib SHALL include a `Gzip` module providing pure compression and decompression on bytes (not an effect).

#### Scenario: Gzip round-trip

- Given `Bytes` of length 10000
- When compressed via `Gzip.compress` then decompressed via `Gzip.decompress`
- Then the result SHALL be identical to the original bytes

### Requirement: Official Packages

Official packages SHALL be maintained by the Camp team, versioned independently from the compiler, and initially live in the compiler repository before graduating to individual repos under the `camp-lang` GitHub organization.

#### Scenario: Http package provides server and client

- Given the `Http` official package is available
- When a developer adds it as a dependency
- Then `Http.Server`, `Http.Client`, and core types (`Request`, `Response`, `Method`, `Headers`, `Body`) SHALL be available

### Requirement: HTTP Effect Design

The `Http.Server` package SHALL define `Http.Server!` and `Http.Client!` effects with `listen!`, `route!`, `serve!` for servers and `get!`, `post!`, `put!`, `delete!`, `patch!`, `request!` for clients.

#### Scenario: HTTP server route registration

- Given an `Http.Server!` handler is installed
- When `Http.Server.route!(Get, "/api/users", handler_fn)` is called
- Then the handler SHALL route GET requests to `/api/users` to `handler_fn`

#### Scenario: HTTP client request

- Given an `Http.Client!` handler is installed
- When `Http.Client.get!("https://example.com/api")` is called
- Then it SHALL return an `Http.Response` with status, headers, and body

### Requirement: Database Effect Design

The `Database` package SHALL define a `Database!` effect with `query!`, `execute!`, `prepare!`, and `transaction!` operations, and a `Database.Pool!` effect with `acquire!` and `release!`.

#### Scenario: Parameterized query

- Given a `Database!` handler connected to PostgreSQL
- When `Database.query!("SELECT * FROM users WHERE id = $1", [user_id])` is called
- Then it SHALL return rows matching the parameterized query

#### Scenario: Transaction execution

- Given a `Database!` handler with transaction support
- When `Database.transaction!(|| { query!(...); execute!(...) })` is called
- Then all operations SHALL execute atomically — either all succeed or all roll back

### Requirement: Database Drivers

Official packages SHALL provide `Database.Postgres`, `Database.Sqlite`, `Database.MySql`, and `Database.Redis` drivers implementing the `Database` effect interface.

#### Scenario: PostgreSQL driver connection

- Given the `Database.Postgres` package is available and a network capability handle
- When connected to a PostgreSQL server via TCP
- Then the driver SHALL implement the PostgreSQL wire protocol v3 in pure WASM

#### Scenario: SQLite in-process operation

- Given the `Database.Sqlite` package is available
- When a SQLite database is opened
- Then the driver SHALL use SQLite's C API compiled to WASM and linked into the Camp module

### Requirement: Crypto.Hash in Official Package

`Crypto.Hash` (sha256, sha512, blake2b, blake2s, blake3, hmac) SHALL be an official package, NOT a stdlib module, to enable independent versioning for security patches.

#### Scenario: Security patch without compiler release

- Given a timing side-channel vulnerability is discovered in `Crypto.Hash.sha256`
- When a fix is released
- Then the fix SHALL be available as a package version bump without requiring a compiler release

### Requirement: WASI Capability-Based Security

All stdlib and official package operations that access network, filesystem, or other WASI capabilities SHALL require explicit capability handles from the host.

#### Scenario: Database connection requires network capability

- Given a Camp program using `Database.Postgres`
- When connecting to a database server
- Then the program SHALL accept a `network` capability parameter (or have one injected by the runtime) — implicit network access SHALL NOT be permitted

### Requirement: HTTP Server via WASI incoming-handler

The `Http.Server` effect SHALL target the `wasi:http/incoming-handler` interface, where the host handles TLS termination, TCP listen/accept, and HTTP framing, and Camp exports a handler function.

#### Scenario: Host-managed HTTP server

- Given a Camp module exports a `wasi:http/incoming-handler`
- When the host (Wasmtime, Spin, Fastly) receives an HTTP request
- Then the host SHALL call Camp's handler with the incoming request and Camp SHALL return the outgoing response

### Requirement: TLS via Host

TLS SHALL NOT be implemented in Camp WASM code. The `Http.Tls` package SHALL use host-provided TLS via `wasi:http/outgoing-handler` (client) or `wasi:http/incoming-handler` (server). The host terminates TLS; Camp never handles raw TLS handshakes.

#### Scenario: HTTPS client request

- Given an `Http.Client` request to an HTTPS URL
- When the handler dispatches the request
- Then the host SHALL handle TLS termination and Camp SHALL receive the decrypted response

### Requirement: No Fork/Exec

The stdlib SHALL NOT include a `Process` module for subprocess spawning, since WASI does not provide fork/exec.

#### Scenario: Shell-out pattern unavailability

- Given a Camp program running on WASI
- When the developer needs to run a subprocess
- Then there SHALL be no `Process` module — shell-out patterns require a WASI host extension

### Requirement: Derive Integration for Encode/Decode

The `derives` clause SHALL generate format-agnostic implementations that work for every format providing `EncoderFormatting`/`DecoderFormatting` instances. Per-field override SHALL be supported.

#### Scenario: Derived codec works for all formats

- Given `@User derives Encode, Decode : { name: Str, age: U64 }`
- When `User` is used with `Json`, `Xml`, and `Csv` formats
- Then all three formats SHALL encode and decode `User` correctly without separate implementations

### Requirement: Embedded Stdlib Modules

The compiler SHALL embed stdlib `.camp` source files at build time. Stdlib modules SHALL be compiled alongside user modules with the same pipeline (lexing, parsing, canonicalization, typechecking, lowering, codegen). The resolution order SHALL be: user `src/` first, then embedded stdlib. This ensures user modules can shadow stdlib modules of the same name.

#### Scenario: Stdlib module available without explicit import

- Given a Camp project with no `import` statement for `List`
- When the compiler resolves the name `List`
- Then it SHALL find the embedded stdlib `List` module

#### Scenario: User module shadows stdlib module

- Given a Camp project with a `List.camp` file in its `src/` directory
- When the compiler resolves the name `List`
- Then it SHALL use the user's `List.camp` instead of the embedded stdlib `List`

#### Scenario: Stdlib module compiled through same pipeline

- Given the embedded stdlib `Result.camp` file
- When the compiler processes it
- Then it SHALL be lexed, parsed, canonicalized, typechecked, lowered, and codegenned using the same passes as user modules

#### Scenario: Embedded stdlib content inclusion method

- Given the compiler is built from source
- When the build system compiles the Odin compiler
- Then all `.camp` files in the `stdlib/` directory SHALL be embedded into the compiler binary using `#embed` or equivalent, making them available without filesystem access at compile time

#### Scenario: Stdlib module listing

- Given the embedded stdlib
- When the compiler initializes
- Then the following stdlib modules SHALL be available: `Result`, `Bool`, `Str`, `List`, `Iter`, `Map`, `Set`, `Display`, `Num.I64`, `Num.I32`, `Num.I16`, `Num.I8`, `Num.U64`, `Num.U32`, `Num.U16`, `Num.U8`, `Num.F64`, `Num.F32`, `Bytes`, `Eq`, `Ord`, `Hash`, `Debug`, `Default`, `IntoIter`, `FromIter`, `From`, `TryFrom`, `Console!`, `Throw!`, `File!`, `Env!`, `Time!`, `Random!`, `Log!`, `Path`, `Duration`, `Fmt`, `Json`, `Regex`, `Uri`, `Uuid`, `Base64`

For the complete syntax reference, see `docs/syntax-recipe.md`.
