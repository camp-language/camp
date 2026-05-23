## Why

Camp currently allows dead code without complaint — a binding can be created and never used, wasting computation and obscuring intent. In a strict, effect-tracking language, unused pure bindings are always wasted work, and unused effectful bindings whose results are discarded hide subtle bugs. The language needs a compiler-enforced discipline: every binding's value must be consumed, with an explicit opt-out mechanism for cases where the programmer intentionally discards a value.

## What Changes

- **Unused binding detection**: The compiler emits a hard error when a binding is never used and is not explicitly marked as unused via `_` prefix
- **`_` prefix convention**: Bindings named `_` or `_name` are exempt from unused checking. `_` is the explicit "I don't care about this value" signal
- **Pointless evaluation warning**: Using `_ = pureExpr` (discarding a pure expression) emits a warning; `_ = effectfulExpr` is silent
- **Reassignable `$`-var per-assignment tracking**: Each assignment to a `$`-var creates a new value that must be consumed. Overwrite-before-read is an error
- **`_$` / `$_` contradictory prefix error**: Combining `_` (ignore) with `$` (each value matters) is contradictory; both spellings parsed and reported as a dedicated error
- **Record field unused checking**: Record literal fields that are never accessed locally must be used or the record must escape. No `_`-discard escape hatch for pure field access
- **Import unused checking**: Unused imports are hard errors with no `_` suppression (imports are pure). Wildcard imports are not allowed
- **Top-level binding rules**: Private top-levels must be used (no `_` escape); public top-levels are exempt
- **Loop structural dead value exemption**: A `$`-var's final assignment in a loop body is exempt from the "must be consumed" rule if the `$`-var has essential reads (transitively reaches observable effects) within the loop
- **Shadowing priority**: Shadowing error takes priority over unused-binding error when both apply

## Capabilities

### New Capabilities
- `unused-analysis`: Compiler analysis pass that detects unused bindings, unused record fields, unused imports, pointless discards, and contradictory `_$`/`$_` prefixes — with hard errors, warnings, and loop exemptions

### Modified Capabilities
- `diagnostics`: New typed error variants for unused-binding errors, pointless-evaluation warnings, contradictory-prefix errors, no-op-assignment errors, and unused-import errors
- `language`: The `_` prefix naming convention and `_ = expr` discard syntax are now part of the language's formal semantics, not just style

## Impact

- **Compiler pipeline**: New analysis pass after typechecking, before code generation. Must run on the typed AST to distinguish effectful from pure expressions
- **Diagnostics**: Multiple new error/warning variants added to the diagnostic system
- **Language spec**: Formalizes `_` prefix rules, `_ = expr` discard semantics, and interaction with `$`-vars
- **Existing code**: **BREAKING** — any Camp program with unused bindings will fail to compile. Requires adding `_` prefixes or removing dead code
- **E2E tests**: New test cases for every category of unused detection; kitchen-sink test may need updates if it has unused bindings
