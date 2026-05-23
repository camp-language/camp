## Context

Camp currently supports only plain `"..."` string literals with `\` escape processing. String construction with embedded values requires explicit `Str.concat` calls or the `+` operator (which desugars to `Str.concat`). The language spec already uses `"${name}"` syntax in two example snippets (language/spec.md line 574 and language/design.md line 174), but the compiler has no interpolation support.

The compiler pipeline is: lexing → parsing → canonicalization → typechecking → lowering → effect lowering → closure conversion → CPS → RC insertion → WASM codegen. Interpolation touches the first five phases plus formatter, tree-sitter, and LSP.

String concatenation is already implemented: `a + b` where both are `Str` lowers to `Str.concat(a, b)` in `lower.odin`. The `Str.concat` runtime function exists in codegen (`camp_str_concat`). Trait parsing exists but constraint solving, UFCS dispatch, and `is` verification are not yet implemented.

## Goals / Non-Goals

**Goals:**
- Provide `"${expr}"` interpolation syntax inside double-quoted strings (auto-detected when `${` appears)
- Require interpolated expressions to implement `Display`; insert `Display.to_str()` automatically
- Propagate effect rows from interpolated expressions
- Support `r"..."` raw interpolated strings and `"""..."""` multiline interpolated strings
- Preserve interpolation as a distinct AST node through typechecking for quality error messages
- Desugar to `Str.concat` + `Display.to_str` calls in lowering (no new IR node)

**Non-Goals:**
- Format specifiers (`${expr:fmt}`, `%d{expr}`) — deferred to future work
- Tagged template literals (JS style) — not needed
- Multi-line expressions inside `${...}` holes — single-line only for V1
- Raw multiline strings (`r"""..."""`) — syntax reserved but not implemented in V1
- String builder optimization for multi-hole interpolation — naive nested-concat is sufficient for V1
- Auto-conversion of all types (universal `.toString()`) — explicitly rejected; `Display` is opt-in

## Decisions

### Decision 1: `${expr}` syntax with auto-detection

**Choice**: A `"..."` string containing `${` is interpolated. No prefix needed.

**Rationale**: Matches the existing spec examples. Most common delimiter across modern languages (JS, Kotlin, Dart, Nix, Roc, Bash, Scala). The `$` prefix doesn't conflict with mutable variable syntax (`$x`) because `${x}` has braces and occurs inside string literals — a different lexical context.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| `` `...${expr}...` `` (backtick, JS-style) | Introduces a new string delimiter just for interpolation; regular `"..."` would never interpolate |
| `f"...${expr}..."` (prefix, Python-style) | Adds syntax to learn; every interpolated string needs a prefix |
| `{expr}` (brace-only, C#/Python-style) | Ambiguous with record literals `{x: 1}`; bad for JSON/CSS content; needs `{{`/`}}` escaping |
| `\(expr)` (Swift-style) | Unique to Swift; unfamiliar; backslash already used for escapes |

### Decision 2: `Display` trait constraint (not `Str`-only)

**Choice**: Interpolated expressions must implement `Display`. The compiler inserts `Display.to_str(expr)` automatically.

**Rationale**: Camp is strictly-typed — implicit universal `.toString()` violates this principle. But requiring every non-`Str` expression to be manually wrapped in `.to_str()` (Roc's approach) is unnecessarily verbose for primitive types. `Display` provides a middle ground: common types opt in, custom types must explicitly implement it, and no type auto-converts without a declared implementation.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| `Str` type only (Roc-style) | Too verbose: `${Num.to_str(count)}` for every non-string value |
| Universal `.toString()` (JS/Kotlin-style) | Violates strict typing; hidden conversion; "toString pollution" |
| Format specifiers (F#/Rust-style) | Adds format syntax complexity; deferred to future work |

**Display prelude implementations**:
```camp
trait Display {
  to_str : Self -> Str
}

-- Str is Display (identity)
-- I64 is Display (intrinsic: int_to_str)
-- I32 is Display (intrinsic: int_to_str)
-- F64 is Display (intrinsic: float_to_str)
-- Bool is Display (match True => "True", False => "False")
```

### Decision 3: Special AST node through typechecking, desugar at lowering

**Choice**: `SExpr_Interpolated_String` → `CExpr_Interpolated_String` → `TExpr_Interpolated_String` → desugar to `Str.concat`/`Display.to_str` in lowering.

**Rationale**: Preserving the interpolation structure through typechecking enables:
- Error messages that point to the interpolation hole, not a generated `Str.concat` call
- Effect row composition visible at the `TExpr` level
- Future tooling (formatter, LSP) can work with the interpolation structure

After typechecking, desugaring to existing IR nodes (`IR_Call` + `IR_Literal_String`) means no new IR variants, no changes to effect lowering, closure conversion, CPS, RC, or codegen.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| Desugar at canonicalization (Roc-style) | Loses interpolation structure for error messages; typechecker sees only concat calls |
| Preserve through all phases to codegen | Unnecessary; no codegen benefit; more nodes to maintain |

### Decision 4: Single-line expressions with nested braces

**Choice**: Expressions inside `${...}` must be single-line. Nested `{}` are allowed (brace-depth tracking for `}` matching).

**Rationale**: Single-line keeps interpolated strings readable — if the expression is complex enough to need multiple lines, extract it into a `let` binding. Nested braces are needed for record expressions like `${record.{name}}`.

**Implementation**: The lexer (or parser, depending on approach) tracks `{`/`}` depth inside `${...}` to find the matching closing `}`.

### Decision 5: `\$` escape for literal `${`

**Choice**: `\$` produces a literal `$` character in all string kinds. A `$` not followed by `{` is always literal and needs no escaping.

**Rationale**: Consistent with the existing `\` escape convention in Camp. Familiar from Kotlin, Dart, Groovy, Nix, and Bash. Works in raw strings too — `\$` is the one escape processed in `r"..."` strings.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| `$${` (doubling, Scala-style) | Unfamiliar; inconsistent with Camp's other escaping |
| `{{`/`}}` (C#/Python-style) | Only relevant for `{expr}` syntax; not needed for `${expr}` |
| Separate non-interpolated string kind | Over-engineering; `\$` handles the rare case |

### Decision 6: `r"..."` for raw interpolated strings

**Choice**: `r"..."` disables `\` escape processing but still supports `${expr}` interpolation. `\$` is still processed (to escape `${`).

**Rationale**: Useful for regex patterns, Windows paths, and any string with literal backslashes. Follows Python's `rf"..."` concept (raw + interpolation combined). The `r` prefix is a clear visual signal. `\$` remains active in raw strings so `${` can always be escaped regardless of string kind.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| Triple-quoted `"""..."""` as raw+interpolated (Kotlin-style) | `"""..."""` also needs escape processing for `\$`; better to keep it as multiline with normal escapes |
| Elixir-style uppercase sigil `~S(...)` | Camp has no sigil infrastructure |
| Dart-style (raw = no interpolation) | Less useful; would need concatenation for any raw string with embedded values |

### Decision 7: `"""..."""` for multiline interpolated strings

**Choice**: `"""..."""` allows newlines in the string literal body, with `${expr}` interpolation and normal `\` escape processing. Expressions inside `${...}` remain single-line.

**Rationale**: Matches Roc's multiline string design. Newlines are literal in the string body (no `\n` needed). Escapes (`\n`, `\t`, `\$`, `\\`) are still processed. Expressions must be single-line to keep the structure readable.

### Decision 8: Lexer emits single interpolated token, parser splits

**Choice**: The lexer emits the entire interpolated string as a single `Interpolated_String_Literal` token (or flagged `String_Literal`). The parser is responsible for splitting it into literal segments and expression holes by re-scanning the token text.

**Rationale**: The current lexer is simple and stateless. Having it track `${}` depth and emit alternating content/expression tokens would require significant lexer state management. A single token with parser-side splitting keeps the lexer simple and puts expression parsing where it naturally belongs.

**Alternatives considered**:
| Alternative | Why rejected |
|-------------|-------------|
| Lexer emits alternating tokens | Complex lexer state; hard to handle nested `{}`; breaks the current simple lexer model |
| External scanner (tree-sitter only) | Only solves the problem for tree-sitter, not the compiler lexer |

### Decision 9: Naive nested-concat desugaring

**Choice**: `"Hello ${name}, ${age}!"` → `Str.concat("Hello ", Str.concat(Display.to_str(name), Str.concat(", ", Str.concat(Display.to_str(age), "!"))))`

**Rationale**: Simplest correct implementation. No new IR node, no runtime builder pattern. Intermediate strings are a cost but acceptable for V1. The Perceus RC system will correctly manage reference counts for intermediate strings.

**Future optimization**: When `Str.concat` is properly implemented (not `crash`), a builder pattern or precomputed total-length allocation can be added as a lowering optimization without changing semantics.

## Risks / Trade-offs

**[Risk] Display trait depends on unimplemented trait system** → Mitigation: Implementing Display trait verification requires `is` checking and UFCS dispatch. This is a prerequisite task. If trait implementation proves too large, fall back to `Str`-only interpolation temporarily.

**[Risk] `\$` in raw strings creates an inconsistency** → Mitigation: Document clearly. `\$` is the one escape processed in `r"..."` strings. This matches the principle that "you must always be able to escape the interpolation delimiter."

**[Risk] Naive nested-concat creates intermediate strings** → Mitigation: Acceptable for V1. Perceus RC handles intermediate string deallocation. Optimize later with a builder pattern if profiling shows it matters.

**[Risk] Parser-side splitting of interpolated tokens is error-prone** → Mitigation: Write comprehensive unit tests for the parser covering all edge cases (empty holes, adjacent holes, nested braces, escaped `\$`, unterminated `${`).

**[Risk] Tree-sitter external scanner needed** → Mitigation: The tree-sitter grammar already noted this in its README. An external C scanner for brace-depth tracking is standard practice (Python, Ruby, C# tree-sitter grammars all use external scanners for interpolation).
