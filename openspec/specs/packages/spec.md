# Domain Specification: Packages

## Purpose

Define the Camp package ecosystem: the `camp.toml` manifest format, dependency URIs,
version resolution via Minimal Version Selection, `camp.lock` integrity, single-file scripts
with embedded `deps` blocks, shebang support, project discovery, and the `camp` CLI.

## Requirements

### Requirement: camp.toml Manifest Format

The `camp.toml` file SHALL be the project manifest. It SHALL use TOML syntax and SHALL
contain at minimum a `[package]` table with `name` and `version`. `description` and `licenses`
MAY be present. `licenses`, when present, SHALL be a non-empty array of SPDX license
identifiers. Dependencies SHALL live in `[dependencies]` and `[dev-dependencies]` sections.

#### Scenario: Minimal camp.toml

- GIVEN a project with `camp.toml` containing only `[package]`, `name`, and `version`
- WHEN the build tool reads the manifest
- THEN it SHALL accept the manifest and resolve zero dependencies

#### Scenario: Full camp.toml

- GIVEN a `camp.toml` with `[package]` (name, version, description, licenses), `[dependencies]`, and `[dev-dependencies]`
- WHEN the build tool reads and validates the manifest
- THEN all fields SHALL parse correctly, and dependencies SHALL be resolved

#### Scenario: Missing package name

- GIVEN a `camp.toml` with no `name` in `[package]`
- WHEN the build tool reads the manifest
- THEN it SHALL produce an error: "`name` is required in `[package]`"

#### Scenario: Missing version

- GIVEN a `camp.toml` with no `version` in `[package]`
- WHEN the build tool reads the manifest
- THEN it SHALL produce an error: "`version` is required in `[package]`"

#### Scenario: Empty licenses array

- GIVEN a `camp.toml` with `licenses = []`
- WHEN the build tool validates the manifest
- THEN it SHALL produce an error: "`licenses` must be non-empty when present"

#### Scenario: Non-SPDX license identifier

- GIVEN a `camp.toml` with `licenses = ["NotARealLicense"]`
- WHEN the build tool validates the manifest
- THEN it SHALL produce an error referencing the invalid SPDX identifier

### Requirement: Dependency URIs

Dependencies SHALL be specified as bare URIs (no scheme) in the form
`host/owner/repo?param`. The query parameters SHALL support `?v=` (semver tag,
default), `?tag=` (explicit tag), `?branch=` (named branch), and `?rev=` (exact
commit). The `?v=` parameter SHALL be the recommended form and SHALL accept
semver three-part versions (`0.1.0`, `1.2.3`). The key on the left side
of each dependency SHALL be a `snake_case` alias used in `import` statements.

#### Scenario: Simple git dependency with version

- GIVEN `graphql = "github.com/user/camp-graphql?v=0.1.0"` in `[dependencies]`
- WHEN the build tool resolves dependencies
- THEN it SHALL clone `github.com/user/camp-graphql` and check out the semver tag `v0.1.0`

#### Scenario: Dependency with explicit tag

- GIVEN `http = "github.com/user/camp-http?tag=v2.0.0-rc1"` in `[dependencies]`
- WHEN the build tool resolves dependencies
- THEN it SHALL check out the tag `v2.0.0-rc1`

#### Scenario: Dependency with branch

- GIVEN `experimental = "github.com/user/camp-experimental?branch=next"` in `[dependencies]`
- WHEN the build tool resolves dependencies
- THEN it SHALL check out the `next` branch HEAD

#### Scenario: Dependency with exact rev

- GIVEN `pinned = "github.com/user/camp-pinned?rev=a1b2c3d4e5"` in `[dependencies]`
- WHEN the build tool resolves dependencies
- THEN it SHALL check out commit `a1b2c3d4e5`

#### Scenario: Non-snake_case alias

- GIVEN `GraphQL = "github.com/user/camp-graphql?v=0.1.0"` in `[dependencies]`
- WHEN the build tool validates the manifest
- THEN it SHALL produce an error: "dependency alias 'GraphQL' must be snake_case"

#### Scenario: File dependency

- GIVEN `local-lib = "file://../local-lib?v=0.1.0"` in `[dependencies]`
- WHEN the build tool resolves dependencies
- THEN it SHALL use the local path `../local-lib`

### Requirement: Dev Dependencies

Dependencies listed in `[dev-dependencies]` SHALL only be available during
`camp test`. They SHALL NOT be propagated to downstream consumers. They
SHALL NOT appear in any published package metadata.

#### Scenario: Dev dep available in tests

- GIVEN `camp-test = "github.com/user/camp-test?v=0.3.0"` in `[dev-dependencies]`
- WHEN `camp test` runs
- THEN `camp-test` SHALL be resolved and importable in test files

#### Scenario: Dev dep not propagated

- GIVEN project A depends on project B, and B has dev-dependencies
- WHEN A resolves its dependency graph
- THEN B's dev-dependencies SHALL NOT appear in A's resolved graph

### Requirement: Version Resolution (Minimal Version Selection)

Dependencies SHALL be resolved using Minimal Version Selection (MVS). Each
dependency declares a minimum acceptable semver version. MVS SHALL traverse
the full dependency graph and select the highest minimum version of each package.
Resolution SHALL be deterministic: the same `camp.toml` and transitive
dependency graphs SHALL produce the same resolved versions every time.

#### Scenario: Direct dependency resolution

- GIVEN `graphql = "github.com/user/camp-graphql?v=0.1.0"` in `[dependencies]`
- WHEN the resolver runs
- THEN it SHALL select the highest semver tag ≥v0.1.0 and <v0.2.0 from the git repository

#### Scenario: Transitive dependency with higher minimum

- GIVEN project A requires `graphql?v=0.1.0` and project B requires `graphql?v=0.2.0`
- WHEN MVS traverses the graph
- THEN it SHALL select the highest minimum: ≥v0.2.0, <v0.3.0

#### Scenario: MVS determinism

- GIVEN a dependency graph
- WHEN MVS resolves it multiple times
- THEN each invocation SHALL produce identical resolved versions

#### Scenario: No compatible version found

- GIVEN a dependency requiring `graphql?v=0.1.0` but the repo has only v1.0.0+ tags
- WHEN MVS resolves
- THEN it SHALL produce an error: "no compatible version found for graphql: need ≥0.1.0 <0.2.0, found [v1.0.0, v1.1.0]"

### Requirement: camp.lock Integrity

The `camp.lock` file SHALL capture the fully-resolved dependency graph with exact
commit hashes and content hashes. It SHALL be TOML format, auto-generated by `camp`,
and SHALL NOT be hand-edited. Each entry SHALL record the package name, source URI,
resolved version, git commit rev, and a SHA-256 content hash of the resolved tree.

#### Scenario: Lockfile generated on first build

- GIVEN a project with `camp.toml` dependencies and no `camp.lock`
- WHEN `camp build` runs
- THEN a `camp.lock` SHALL be generated with all resolved packages

#### Scenario: Lockfile reused on subsequent builds

- GIVEN a `camp.lock` exists and `camp.toml` is unchanged
- WHEN `camp build` runs
- THEN resolved versions from `camp.lock` SHALL be used without re-resolution

#### Scenario: Content hash mismatch

- GIVEN a `camp.lock` with `hash = "sha256:abc..."` for a package
- WHEN the fetched package content hashes to a different value
- THEN `camp` SHALL produce an error: "content hash mismatch for graphql: expected sha256:abc..., got sha256:def..."

#### Scenario: --locked flag

- GIVEN `camp build --locked`
- WHEN `camp.toml` does not match `camp.lock`
- THEN `camp` SHALL produce an error and refuse to build

#### Scenario: --frozen flag

- GIVEN `camp build --frozen`
- WHEN any network access would be required to resolve or fetch
- THEN `camp` SHALL produce an error and refuse to build

### Requirement: Global Dependency Cache

Fetched packages SHALL be stored in a global content-addressed cache at
`$XDG_CACHE_HOME/camp/packages/` (defaulting to `~/.cache/camp/packages/`).
Packages SHALL be keyed by source URI and resolved commit hash. The
cache SHALL be shared across all projects on the machine.

#### Scenario: First fetch populates cache

- GIVEN no cache entry for `github.com/user/camp-graphql` at commit `a1b2c3d4`
- WHEN the resolver fetches the package
- THEN it SHALL clone into `~/.cache/camp/packages/github.com/user/camp-graphql/a1b2c3d4/`

#### Scenario: Second fetch hits cache

- GIVEN a cache entry already exists for the exact source and commit
- WHEN another project resolves the same dependency at the same commit
- THEN the cached copy SHALL be used without re-cloning

### Requirement: Project Discovery

The compiler SHALL discover the project root by walking up from the current
working directory. If `camp.toml` is found, that directory SHALL be the
project root. If no `camp.toml` is found but `src/` containing `.camp` files
is found, the project SHALL be treated as having an implicit empty manifest.
If neither is found, the compiler SHALL produce an error.

#### Scenario: camp.toml found

- GIVEN a directory tree with `camp.toml` and `src/Main.camp`
- WHEN the compiler discovers the project from any subdirectory
- THEN the `camp.toml` directory SHALL be the project root

#### Scenario: src/ fallback

- GIVEN a directory tree with `src/Main.camp` but no `camp.toml`
- WHEN the compiler discovers the project
- THEN the `src/` parent SHALL be the project root with an implicit empty manifest

#### Scenario: Neither found

- GIVEN a directory with no `camp.toml` and no `src/` containing `.camp` files
- WHEN the compiler discovers the project
- THEN it SHALL produce an error: "no Camp project found — expected camp.toml or src/ directory"

#### Scenario: camp.toml takes precedence over src/

- GIVEN a directory with both `camp.toml` and `src/`
- WHEN the compiler discovers the project
- THEN `camp.toml` SHALL be the authoritative manifest

### Requirement: Single-File Scripts with deps Block

A `.camp` file MAY declare a `deps` block at the top of the file, before
any `import` statements. The `deps` block SHALL use the syntax
`deps { alias: "uri", ... }` where each alias is `snake_case` and each URI
follows the same format as `camp.toml` dependency URIs. The `deps` keyword
SHALL only be recognized as a dependency block when it appears before all
`import` statements. Elsewhere, `deps` SHALL be a normal identifier.

#### Scenario: Script with deps block

- GIVEN a `.camp` file with `deps { graphql: "github.com/user/camp-graphql?v=0.1.0" }` before imports
- WHEN the compiler processes the file
- THEN `graphql` SHALL be resolved as a dependency and available for `import graphql { ... }`

#### Scenario: deps block must precede imports

- GIVEN a `.camp` file with `import List` appearing before a `deps { ... }` block
- WHEN the compiler processes the file
- THEN it SHALL produce an error: "`deps` block must appear before all `import` statements"

#### Scenario: deps as normal identifier

- GIVEN a `.camp` file where `deps` appears after imports (e.g., `deps = 42`)
- WHEN the compiler processes the file
- THEN `deps` SHALL be treated as a normal variable binding

#### Scenario: Non-snake_case alias in deps block

- GIVEN `deps { GraphQL: "github.com/user/camp-graphql?v=0.1.0" }`
- WHEN the compiler validates the file
- THEN it SHALL produce an error: "dependency alias 'GraphQL' in deps block must be snake_case"

### Requirement: Shebang Support

Camp files MAY begin with a shebang line (`#!`). The compiler SHALL skip the
shebang line before parsing. A shebang followed by a `deps` block SHALL be
recognized as a standalone script. The canonical shebang SHALL be
`#!/usr/bin/env camp`.

#### Scenario: Shebang with deps block

- GIVEN a `.camp` file starting with `#!/usr/bin/env camp` followed by a `deps { ... }` block
- WHEN the compiler processes the file
- THEN it SHALL enter script mode: resolve dependencies from the `deps` block, ignore `camp.toml`

#### Scenario: Shebang without deps block

- GIVEN a `.camp` file starting with `#!/usr/bin/env camp` but no `deps` block
- WHEN the compiler processes the file
- THEN it SHALL skip the shebang and compile normally (project or script mode based on context)

#### Scenario: Script mode ignores camp.toml

- GIVEN a `.camp` file with shebang and `deps` block in a directory with `camp.toml`
- WHEN the compiler processes the file
- THEN it SHALL use `deps` block dependencies and SHALL ignore `camp.toml`

#### Scenario: No shebang on non-Unix systems

- GIVEN a `.camp` file with `deps` block but no shebang (e.g., on Windows)
- WHEN the compiler processes the file
- THEN it SHALL still recognize the `deps` block and enter script mode

### Requirement: External Package Imports

External packages resolved from `camp.toml` or `deps { }` SHALL be importable
using the dependency alias as a namespace root. Submodules within the package
SHALL be accessible via dot notation: `import alias.Module { ... }`. This SHALL
mirror Camp's existing `import Http.Server` module path syntax.

#### Scenario: Top-level import from external package

- GIVEN `graphql = "github.com/user/camp-graphql?v=0.1.0"` in `camp.toml`
- WHEN a source file contains `import graphql { query, mutate }`
- THEN `query` and `mutate` SHALL resolve from the top-level public API of the `camp-graphql` package

#### Scenario: Submodule import from external package

- GIVEN `graphql = "github.com/user/camp-graphql?v=0.1.0"` in `camp.toml`
- WHEN a source file contains `import graphql.Query { execute }`
- THEN `execute` SHALL resolve from `camp-graphql`'s `src/Query.camp` module

#### Scenario: Importing non-existent submodule

- GIVEN an import `import graphql.Nonexistent { ... }`
- WHEN the compiler resolves the import
- THEN it SHALL produce an error: "module 'Nonexistent' not found in package 'graphql'"

#### Scenario: Alias shadowing a local module

- GIVEN `graphql = "..."` in `camp.toml` AND a local `src/graphql.camp` file
- WHEN the compiler resolves `import graphql { ... }`
- THEN it SHALL produce an error: "dependency alias 'graphql' conflicts with local module 'graphql'"

### Requirement: CLI Commands

The `camp` binary SHALL support build-tool commands when no subcommand matches
a `.camp` file. Available commands SHALL include `build`, `test`, `run`, `add`,
`update`, and `init`. The `camp <file.camp>` form SHALL run the file as a
script (single-file mode).

#### Scenario: camp build

- GIVEN a project with `camp.toml` and `src/`
- WHEN `camp build` is invoked
- THEN the project SHALL compile to a WASM/WASI binary

#### Scenario: camp test

- GIVEN a project with `camp.toml` and test files
- WHEN `camp test` is invoked
- THEN tests SHALL run with dev-dependencies available

#### Scenario: camp add

- GIVEN `camp add github.com/user/camp-graphql?v=0.1.0`
- WHEN the command runs
- THEN the dependency SHALL be added to `camp.toml`, resolved, and `camp.lock` updated

#### Scenario: camp update

- GIVEN a project with existing dependencies and `camp.lock`
- WHEN `camp update` is invoked
- THEN all dependencies SHALL be re-resolved with MVS and `camp.lock` regenerated

#### Scenario: camp init

- GIVEN an empty directory
- WHEN `camp init github.com/user/new-project` is invoked
- THEN `camp.toml` SHALL be scaffolded with `[package] name = "github.com/user/new-project"` and `version = "0.0.0"`

#### Scenario: Script invocation

- GIVEN a `.camp` file with shebang and `deps` block
- WHEN `camp ./script.camp` is invoked
- THEN the script SHALL compile and run in script mode

For the complete syntax reference, see `docs/syntax-recipe.md`.
