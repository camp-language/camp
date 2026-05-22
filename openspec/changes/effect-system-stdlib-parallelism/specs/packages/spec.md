## MODIFIED Requirements

### Requirement: Stdlib Tier Composition

The stdlib SHALL contain only modules that are either existing language-design-specified modules or additions justified by cross-language precedent and universal backend need. Effect modules in the stdlib SHALL use `!` suffix naming: `Console!`, `Throw!`, `File!`, `Env!`, `Time!`, `Random!`, `Log!`, `Crypto.Random!`.

#### Scenario: Effect modules use ! naming

- **GIVEN** the stdlib includes a `Console!` effect module
- **WHEN** a user writes `import Console!` and calls `Console!.println!("hello")`
- **THEN** the `!` on the effect name SHALL be part of the module name

### Requirement: Encode/Decode Codec Framework

The stdlib SHALL provide a simple `Codec` trait with format-specific encode/decode methods. The formatting-trait parameterization architecture (EncoderFormatting/DecoderFormatting) is deferred to a future change.

#### Scenario: Type derives Codec for JSON

- **GIVEN** a Camp type `User := { name: Str, age: U64 }` with `@derive [Codec]`
- **WHEN** `Json.encode(user)` is called
- **THEN** it SHALL produce `{"name":"Ada","age":36}`

### Requirement: Log Effect

The stdlib SHALL include a `Log!` effect with `debug!`, `info!`, `warn!`, and `error!` operations accepting a message string and optional key-value context.

#### Scenario: Structured log message

- **GIVEN** `Log!.info!("Request processed", { duration_ms: 42, path: "/api/users", status: 200 })`
- **WHEN** a Log! handler is installed
- **THEN** the handler SHALL receive the message string and structured key-value context

### Requirement: Crypto.Random Effect

The stdlib SHALL include a `Crypto.Random!` effect separate from the non-cryptographic `Random!` effect, providing `bytes!`, `int!`, and `uuid!` operations suitable for token/nonce/key generation.

#### Scenario: Cryptographic random generation

- **GIVEN** a `Crypto.Random!` handler is installed
- **WHEN** `Crypto.Random!.bytes!(16)` is called
- **THEN** the result SHALL be 16 bytes of cryptographically secure random data

#### Scenario: Separation from non-crypto Random!

- **GIVEN** `Random!.int!(1, 100)` uses a fast PRNG seeded from WASI
- And `Crypto.Random!.int!(1, 100)` uses WASI's `random_get` syscall directly
- **THEN** `Random!` SHALL trade security for speed and `Crypto.Random!` SHALL trade speed for security
