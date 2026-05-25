# Camp Language Syntax Recipe

This document is the authoritative reference for Camp's syntax decisions, produced from a comprehensive grilling session. It serves as the recipe for updating specs, the compiler, and tests to achieve consistency.

**Status**: Decisions recorded. Implementation pending.

---

## 1. Lexical Structure

### Comments
- `//` line comments (no block comments, no nesting)
- `///` doc comments (CommonMark, doctest runner)
- `//#` hidden lines in doc code blocks

### Whitespace
- Newline-separated statements in blocks (NOT semicolon-separated)
- `{ stmt1\nstmt2\nresult }`

### Identifiers
- Lowercase: `snake_case` (functions, variables, effects)
- Uppercase: `UpperCamelCase` (types, traits, nominal types, tag variants)
- `!` suffix on effect names: `Console!`, `Throw!` (enforced by compiler)
- `!` suffix on effect operation names: `println!`, `raise!`
- `!` suffix on `main!` (part of the identifier name)
- Backtick raw identifiers: `` `keyword-as-name` ``
- `$` prefix for mutable variables: `$counter`
- `_` prefix for unused-but-named bindings: `_unused_result`
- `_` alone for discard/wildcard

### Literals

**Integers**: `42`, `0xFF`, `0o77`, `0b1010`, `1_000_000`
- No type suffixes (type inference handles it; annotate if ambiguous: `x: I64 = 42`)
- Numeric types: `I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`

**Floats**: `3.14`, `1.0e10`, `1.0e-5`, `1_000.5`
- No leading dot (`.5` is invalid — avoids `.` ambiguity with method access)
- No type suffixes

**Booleans**: `True`, `False` (tag constructors, UpperCamelCase)

**Chars**: `'a'`

**Strings**: Two kinds
1. `"text"` — plain, single-line, with escapes (`\n \t \r \\ \" \$`) and Unicode (`\u{1F600}`), supports `${expr}` interpolation
2. `\` per-line prefix — multiline, raw (no escapes), supports `${expr}` interpolation, SIMD-friendly lexing

**Unit**: `{}` (both type and value)

### Operators
- Arithmetic: `+ - * / %`
- Bitwise: `& | ^ << >> ~`
- Comparison: `== != < > <= >=`
- Logic: `and or not` (keyword only, no `&& || !`)
- Unary negation: `-`
- No custom operators
- No `++` concat (use `Str.concat` / `List.concat`)
- No `|>` pipe (use UFCS + dot lambda)
- No `$` function application
- No range syntax

### Keywords
`if`, `else`, `match`, `is`, `derives`, `handle`, `in`, `with`, `import`, `exposing`, `as`, `for`, `and`, `or`, `not`, `expect`, `test`, `pub`, `par`, `where`, `return`, `crash`, `todo`

Removed: `intercept`, `unsafe`

---

## 2. Types

### Primitive Types
`I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`, `Bool`, `Char`, `Str`, `{}`

### Function Types
- Pure: `|Type1, Type2| -> ReturnType`
- Effectful: `|Type1, Type2| -[Effect! | Other!]-> ReturnType`
- **Parameter names banned** in type annotations (structural type equivalence)
- `->` for pure, `-[...]->` for effectful (empty effect row `-[[]->` is a compile error — use `->`)
- Effect row separator: `|` (or-semantics)
- Effect row variables at end: `-[Console! | ..effs]->`

### Generic Types
- `List(a)`, `Map(k, v)` — parens like function application
- Positional only (no named type params, no defaults)

### Tag Union Types
- `[Ok(a) | Err(e)]` — `|` separator
- Row variable at end (optional): `[Ok | Err | ..rest]`
- Empty tag args: `None` (not `None()`) — casing disambiguates from identifiers

### Record Types
- `{ name: Str, age: I64 }` — comma separator
- Open: `{ name: Str, .. }` (anonymous extension)
- Named row variable: `{ name: Str, ..rest }`

### Type Aliases
- `AliasName: ExistingType` — pure synonym, no associated functions
- Can have type params: `AliasName(a): List(a)`
- Semantic detection: if all fields are pure functions → usable as trait; if name ends in `!` and all fields are effectful → effect

### Type Wildcard
- `_` valid in type position as type hole

---

## 3. Declarations

### Nominal Types
```
@Name(params) derives Trait1, Trait2 where a is Eq, e is Debug: pub [Ok(a) | Err(e)] { methods }
```

- `@` prefix on declaration only
- `derives` before `where` before `:` before body
- Body: any type expression after `:` (tag unions, records, primitives, other types)
- `@UserId: I64` desugars to `@UserId: pub [UserId(I64)]`
- `pub` on body: all-or-nothing (all variants public or none)
- Method block: `{ method_name = |self: Self| -> ReturnType { body } }`
- `Self` available in method blocks, refers to the nominal type
- Self-referential types allowed (must have heap-backed collection in recursion path)
- Mutual recursion: free within module

### Type Aliases
```
AliasName: ExistingType
```
- No `derives` (only on nominal types)
- No associated functions

### Effect Definitions
```
Console! : {
  println!: |Str| -> {}
  read_line!: || -[Console!]-> Str
}
```
- Type alias syntax with `!` suffix on effect name
- Operation names end in `!`
- Operations are function-typed fields

### Effect Aliases
```
Io!: [File! | Console!]
```
- Tag-union-like syntax with `!` suffix

### Trait Definitions
```
Eq : { eq: |Self, Self| -> Bool }
Hash : { hash: |Self| -> U64 }
```
- Record alias where all fields are pure functions
- `Self` refers to the implementing type
- No associated types (methods only)
- No default implementations
- No higher-kinded types (HKT)

### Trait Implementations
```
Color is Eq {
  eq = |a, b| -> Bool {
    match [a, b] {
      [Red, Red] => True
      [Green, Green] => True
      _ => False
    }
  }
}
```
- Separate `is` blocks (not inline on type definition)
- One trait per block
- Must be in same module as the nominal type definition
- Strict orphan rule: compile error if type is not local
- `derives` on type definition auto-generates impl for built-in traits only

### Constants
```
pi: F64 = 3.14159
```

### Imports
```
import Module { foo, bar }
import Module as M { foo, bar }
import Result { [Ok, Err], map }
```
- No wildcard imports (always explicit)
- `[Ok, Err]` brackets for nominal type variants (comma separator)
- No `@` prefix in imports
- No re-exports (every name has one canonical home)
- Circular imports: banned (compile error)

### Test Declarations
```
test "name" { body }
```
- Block syntax (not `= body`)

### Expect Declarations
```
expect condition
```
- Keyword + expression, no parens
- `///` doc comment on line before shown on failure
- `expect a == b` desugars to capture both operands + Debug representation

---

## 4. Expressions

### Three-Way Call Syntax

| Syntax | Semantics | Example |
|--------|-----------|---------|
| `obj.method(args)` | Nominal dispatch (type promised it) | `list.map(fn)` |
| `obj->func(args)` | Lexical UFCS (scope provides function) | `name->is_even()` |
| `obj.(field)(args)` | Structural dispatch (value stores function) | `callback.(handler)(data)` |
| `Trait.func(obj, args)` | Qualified trait dispatch | `Eq.eq(a, b)` |

### Dot Syntax (`.`)
- `obj.field` — field access
- `obj.method(args)` — method call (parser distinguishes by `(` following)
- `(obj.field)(args)` — field-then-call (parens required)
- `.method(args)` — dot lambda (nominal)
- `.->func(args)` — dot lambda (lexical)
- `.(field)(args)` — dot lambda (structural)

### Arrow Syntax (`->`)
- After `|params|`: return-type arrow (committed parse)
- After any expression: UFCS
- `|x| -> is_even(x)` is a **parse error** — write `|x| x->is_even()`
- Parens required: `obj->func()` not `obj->func`
- Module paths via casing: lowercase = local, `Upper.` continues until `.lowercase`
- Tag constructors via `->`: `obj->Some()` = `Some(obj)` (type checker catches wrong arg count)

### Function Calls
- `func(args)` — standard
- `@Type(args)` — nominal type construction
- `Tag(args)` — tag variant construction

### Lambda
```
|params| -> ReturnType { body }
|params| expr
```
- `|` delimiters, `->` return arrow
- Body: single expression or block
- Parameter destructuring allowed: `|{ name, age }| name`

### Blocks
```
{ stmt1
  stmt2
  result_expr }
```
- Newline-separated, no semicolons
- Last expression is the return value

### Match
```
match expr {
  Pattern1 => body1
  Pattern2 if guard => body2
  Pattern3 | Pattern4 => body3
}
```
- Newline/whitespace-separated arms (no commas between arms)
- `|` for or-patterns within a single arm
- `=>` (FatArrow) for arm body
- `if` guard for pattern guards
- Exhaustive (compile error on missing patterns)
- Nested patterns: `Some(Ok(x))`
- As-patterns: `pattern as name`
- String/char literal matching: `"hello" => ...`, `'a' => ...`
- String pattern interpolation: `"Hello, ${name}!" => name` (multiple interpolation points allowed)

### If/Else
```
if cond { ... }
if cond { ... } else { ... }
if cond { ... } else if cond2 { ... } else { ... }
```
- Braces required for blocks
- Single-expr one-liners can elide braces: `if x > 0 then x else -x` (entire if/else on one line)

### For Loop
```
for x in xs { body }
```
- Calls `.iter()` on `xs`
- Loop variable is immutable
- `$` prefix for accumulators
- Returns `{}` (unit)

### Par Blocks
```
par { x: e1, y: e2, z: e3 }
par for x in xs { body }
```
- Named entries only: `par { name: expr, ... }` returns record `{ name: T1, ... }`
- `par for` returns `{}` (unit, like regular `for`)
- Fail-fast: if any branch crashes, whole par block crashes, other branches cancelled

### Handle
```
handle Console!, Throw! in body with {
  .println!(resume, msg) => { ... ; resume({}) }
  .raise!(resume, err) => { ... }
}
```
- Multiple effects per block: `handle E!, F! in ...`
- Single effect per block also valid
- `.op!(resume, args) => body` — `resume` always first param
- Resume: one-shot (0 or 1 times). 0 = abort, 1 = continue. Runtime error on double-resume.
- Deep handlers only (reinstall on continuation)

### Control Flow
- `return expr` — exits function only (never exits a block)
- `crash "msg"` — unrecoverable, no bottom type keyword (inferred)
- `todo` — placeholder, debug-only
- `todo "msg"` — placeholder with message

### Assignment
- `x = expr` — immutable binding
- `$x = expr` — mutable binding (`$` always present on both declaration and reassignment)
- No shadowing (compile error if `x` redefined in same scope)
- No `$` at top level (module scope is always immutable)
- Type annotation: `x: Int = 42`

### Destructuring
- `{ name, age } = person` — record destructuring (no `let` keyword)
- `[a, b, ...rest] = list` — list destructuring
- `@UserId(n) = uid` — nominal type destructuring

### Record Literal
```
{ name: "Alice", age: 30 }
{ ..record, name: "new" }
```
- Spread at end only (update, not merge)

### List Literal
```
[1, 2, 3]
[1, 2, ...rest, 5]
```
- Multiple `..spread` allowed in construction

### Nominal Type Construction
- Tag variants: `Ok(42)`, `Err("oops")`
- Newtypes: `@UserId(42)` — `@` prefix distinguishes from tag construction
- From outside module: `Result.Ok(42)` or `Ok(42)` if imported

---

## 5. Patterns

### Pattern Types
- Tag: `Ok(x)`, `None`
- Record: `{ name, age }`
- List: `[a, b, ...rest]`
- Integer/String/Char/Bool literal: `42`, `"hello"`, `'a'`, `True`
- Identifier: `x` (binds)
- Wildcard: `_`
- Unused-but-named: `_name`
- Nominal destructuring: `@UserId(n)`
- Or-pattern: `Red | Green | Blue`
- As-pattern: `pattern as name`
- Guard: `if condition`
- Rest: `..rest` (one per list pattern, at any position; one per record pattern, at end only)

### Empty Tag Patterns
- `None` (not `None()`) — casing disambiguates

---

## 6. Module System

- One file = one module (module name = filename without extension)
- Nested modules via directory structure only (no inline `module` declarations)
- `.camp` file extension
- `camp.toml` for project manifest (dependencies, metadata)
- Single scripts with shebang don't need manifest (dependencies in header)
- `pub` per-declaration (two-level: type export vs variant export)
- No re-exports (every name has one canonical home)
- Circular imports: banned

---

## 7. Effect System

### Effect Invocation
- Always module-qualified: `Console.println!(...)`
- Never `Console!.println!(...)` (the `!` only on the effect type name and operation names in definitions)

### Effect Rows
- `|` separator (or-semantics)
- Pure: `-> ReturnType`
- Effectful: `-[Effect! | Other!]-> ReturnType`
- Row variables at end: `-[Console! | ..effs]-> ReturnType`
- Functions generic over effect row: `|a| -[Console! | ..effs]-> I64`

### Handlers
- Deep only (reinstall on continuation)
- `intercept` keyword removed
- Resume: one-shot (0 or 1 times)
- Multiple effects per handle block: `handle E!, F! in body with { ... }`

---

## 8. Entry Point

```
pub main! = || -[Console! | Throw!([..])]-> I64 {
  // ...
}
```
- Returns any type implementing `Termination` trait
- `I64` → exit code, `{}` → exit 0, `Result(a, e)` → Ok=0/Err=1

---

## 9. Prelude

Rich prelude (like Rust), compiler-injected. Includes:
- Types: `Bool`, `I8`–`I64`, `U8`–`U64`, `F32`, `F64`, `Char`, `Str`, `List`, `Map`, `Set`, `Option`, `Result`, `{}`
- Tag variants: `True`, `False`, `Some`, `None`, `Ok`, `Err`
- Common functions: `map`, `filter`, `foldl`, `println!`, etc.
- Common traits: `Eq`, `Ord`, `Hash`, `Debug`, `Display`
- No re-exports — prelude is compiler-injected

---

## 10. Standard Library Types

### Option
```
@Option(a): pub [Some(a) | None]
```
- Library type, imported in prelude with `[Some, None]`

### Result
```
@Result(a, e): pub [Ok(a) | Err(e)]
```
- Library type, imported in prelude with `[Ok, Err]`

### List
```
@List(a): pub [Cons(a, List(a)) | Nil]
```
- Library type, recursive (heap-backed)

### Str
- String type is `Str` (not `String`)

---

## 11. Traits

- Traits = record aliases where all fields are pure functions
- `Self` in trait definitions refers to implementing type
- No associated types (methods only)
- No default implementations
- No higher-kinded types
- Auto-deriving: built-in traits only (like Swift): `Eq`, `Ord`, `Hash`, `Debug`, etc.
- Manual impl: `Color is Eq { ... }` separate blocks
- Strict orphan rule: type must be local to the module

### Debug vs Display
- `Debug`: developer-facing (verbose, shows structure), derivable
- `Display`: user-facing (clean, formatted), not derivable

---

## 12. Error Handling

Both mechanisms:
1. **Throw! effect**: `raise!("error")` — effect system, handlers decide
2. **Result type**: `@Result(a, e): [Ok(a) | Err(e)]` — explicit, no hidden control flow

---

## 13. Key Syntax Changes from Current Implementation

| Current (Parser/Spec) | Decision | Action |
|---|---|---|
| Effect row `,` separator | `\|` separator | Fix parser |
| `test "name" = body` | `test "name" { body }` | Fix parser + spec |
| `intercept` keyword | Remove | Fix parser + spec |
| `@` in type-use positions | No `@` in type-use | Fix parser |
| `@` in expressions/patterns | `@` for nominal construction/destruction | Add to parser |
| `r"..."` raw strings | Removed (use `\` per-line) | Fix lexer + spec |
| `"""..."""` multiline | Removed (use `\` per-line) | Fix lexer + spec |
| `\|>` pipe operator | Removed | Fix parser |
| `++` concat operator | Removed | Fix parser |
| `&& \|\| !` logic operators | `and or not` keywords | Fix parser |
| `@Variant` in imports | `[Ok, Err]` brackets | Fix parser + spec |
| `is` on type def header | Separate `is` blocks only | Fix parser + spec |
| `unsafe` keyword | Removed | Fix parser + spec |
| `|x| -> is_even(x)` | Parse error (use `\|x\| x->is_even()`) | Fix parser |
| `obj.method(args)` ambiguity | Rust-style disambiguation | Fix parser |
| No `->` UFCS syntax | Add `->` for lexical UFCS | Add to parser |
| No `.(field)()` syntax | Add for structural dispatch | Add to parser |
| `derives` on type aliases | `derives` only on nominal types | Fix spec |
| `Self` in free functions | `Self` in traits + method blocks only | Fix spec |
| `None()` tag construction | `None` (no parens) | Fix parser + spec |
| `-[[]->` empty effect row | Compile error, use `->` | Add check |
| `@inline` annotation | Removed | Fix kitchen sink |

---

## 14. Open Items (Deferred)

| Item | Status | Notes |
|---|---|---|
| FFI design | Bead task created | Research needed before design |
| Re-exports | Decided: no | Every name has one canonical home |
| Conditional compilation | Decided: no | Use runtime checks or separate modules |
| Compiler annotations | Decided: no | No `@inline`, `@deprecated`, etc. |
| List comprehensions | Decided: no | Use `List.map`, `List.filter`, `par for` |
| Higher-kinded types | Decided: no | Ship without, observe, add associated types later if needed |
| Multi-shot continuations | Decided: no | One-shot only; backtracking as library effect |
