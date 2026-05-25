# Domain Specification: Packages

## Purpose

Define the Camp package ecosystem: dependency resolution, versioning, community packages, and the `camp.toml` format. For standard library API design and module listing, see `openspec/specs/stdlib/spec.md`.

## Requirements

### Requirement: Community Package Dependencies

Community packages SHALL be referenced via `camp.toml` git dependencies with no stability guarantee. A central registry MAY be added later without changing the dependency format.

#### Scenario: Git dependency in camp.toml

- Given a community package `camp-graphql` at `github.com/user/camp-graphql`
- When added to `camp.toml` as a git dependency
- Then the package SHALL be resolved and available for import

### Requirement: Package Repository Strategy

Package dependencies SHALL initially be git-based with no central registry. When the community grows, a registry MAY be added where package names are first-come-first-served, versions are immutable once published, and the `camp.toml` format gains a `version` field alongside `git` deps.

#### Scenario: Git dependency resolution

- Given a `camp.toml` with a git dependency
- When the build tool resolves dependencies
- Then it SHALL clone the referenced git repository and use the package at the specified commit/branch

For the complete syntax reference, see `docs/syntax-recipe.md`.
