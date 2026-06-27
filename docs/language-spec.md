# Camp Language Syntax Recipe

This document is the authoritative reference for Camp's syntax decisions, produced from a comprehensive grilling
session. It serves as the recipe for updating specs, the compiler, and tests to achieve consistency.

**Status**: Decisions recorded. Implementation pending.

______________________________________________________________________

## 0. Core Principles

- **Everything is an expression**: Match, if/else, blocks, for loops, par blocks — all produce values. The last
  expression in a block is its value. Statements are expressions that produce `{}`.
- **Strict typing**: No `any`, `dynamic`, or unsafe casts. Type inference where possible, explicit annotations where
  needed.
- **Explicit over implicit**: No implicit type conversions, no implicit re-exports, no implicit method resolution
  fallbacks.
- **Functional core**: Pure functions, immutability by default, algebraic effects for side effects.

______________________________________________________________________

## 1. Lexical Structure

### Comments

- `//` line comments (no block comments, no nesting)
- `///` doc comments (CommonMark, doctest runner)
- `//#` hidden lines in doc code blocks

### Whitespace

- Newline-separated statements in blocks (NOT semicolon-separated)
- `{ stmt1\nstmt2\nresult }`

### Identifiers

- Lowercase: `snake_case` (functions, variables, effect operations)
- Uppercase: `UpperCamelCase` (types, traits, nominal types, tag variants, **effect type names**)
- `!` suffix on effect type names: `Console!`, `Throw!` (enforced by compiler)
- `!` suffix on effect operation names: `println!`, `raise!`
- `!` suffix on `main!` (part of the identifier name)
- `!` is NOT a prefix operator — it appears only as a suffix in identifiers. Use `not` for logical negation.
- Backtick raw identifiers: `` `keyword-as-name` ``
- `$` prefix for mutable variables: `$counter`
- `_` prefix for unused-but-named bindings: `_unused_result`
- `_` alone for discard/wildcard

### Literals

**Integers**: `42`, `0xFF`, `0o77`, `0b1010`, `1_000_000`

- No type suffixes (type inference handles it; annotate if ambiguous: `x: I64 = 42`)
- Numeric types: `I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`
- No implicit numeric conversions — all conversions are explicit

**Floats**: `3.14`, `1.0e10`, `1.0e-5`, `1_000.5`

- No leading dot (`.5` is invalid — avoids `.` ambiguity with method access)
- No type suffixes

**Booleans**: `True`, `False` (tag constructors, UpperCamelCase)

**Chars**: `'a'`

**Strings**: Two kinds

1. `"text"` — plain, single-line, with escapes (`\n \t \r \\ \" \$`) and Unicode (`\u{1F600}`), supports `${expr}`
   interpolation (expression must implement `Display` trait)
1. `\` per-line prefix — multiline, raw (no escapes), supports `${expr}` interpolation (expression must implement
   `Display` trait), SIMD-friendly lexing

**Unit**: `{}` (both type and value)

### Operators

- Arithmetic: `+ - * / %`
- Bitwise: `& | ^ << >> ~`
- Comparison: `== != < > <= >=`
- Logic: `and or not` (keyword only — no `&&`, `||`, or `!` prefix operator)
- Unary negation: `-`
- No custom operators
- No `++` concat (use `Str.concat` / `List.concat`)
- No `|>` pipe (use UFCS + dot lambda)
- No `$` function application
- No range syntax

**Operator precedence** (highest to lowest):

1. Unary: `-`, `not`
1. Multiplicative: `* / %`
1. Additive: `+ -`
1. Bitwise shift: `<< >>`
1. Bitwise AND: `&`
1. Bitwise XOR: `^`
1. Bitwise OR: `|`
1. Comparison: `== != < > <= >=`
1. Logical AND: `and`
1. Logical OR: `or`

`not` binds tighter than `and`/`or`: `not a and b` = `(not a) and b`

### Keywords

`if`, `else`, `match`, `is`, `derives`, `handle`, `in`, `with`, `import`, `as`, `for`, `and`, `or`, `not`, `expect`,
`test`, `pub`, `par`, `where`, `return`, `crash`, `todo`, `Self`

______________________________________________________________________

## 2. Types

### Primitive Types

`I8`, `I16`, `I32`, `I64`, `U8`, `U16`, `U32`, `U64`, `F32`, `F64`, `Bool`, `Char`, `Str`, `{}`

### Tuple Types

- Capped at 3 elements: `(T1, T2)`, `(T1, T2, T3)`
- No tuple types with 4+ elements — use records instead
- Element access: destructuring only (`(a, b) = pair` or pattern matching)
- No `.0`, `.1` field access (use destructuring or records for named access)

### Function Types

- Pure: `|Type1, Type2| -> ReturnType`
- Effectful: `|Type1, Type2| -[Effect! | Other!]-> ReturnType`
- **Parameter names banned** in type annotations (structural type equivalence)
- `->` for pure, `-[..]->` for effectful
- `|a, b| -[]-> I64` is a **compile error** — write `|a, b| -> I64` instead
- Effect row separator: `|` (or-semantics)
- Effect row variables at end: `-[Console! | ..effs]->`
- `where` clauses (trait constraints on type variables) appear on **declaration binders** that introduce type parameters
  — function declarations, nominal type declarations, and trait declarations — not on function *type annotations*. Type
  annotations are structurally equated and carry no parameter identity (§2 Function Types), so constraints on them would
  have no single discharge site

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
- Unused type parameters in an alias are a **compile error** — every declared param must appear in the target type.
  Structural aliases are transparent, so a phantom param carries no information.
- Semantic detection: if all fields are pure functions → usable as trait; if name ends in `!` and all members are
  effectful functions → effect

### Type Parameters (unused / phantom)

- Unused type parameters are an error in **alias** declarations (see Type Aliases above) and in **effect** declarations.
- In **nominal type** declarations, unused params are allowed when prefixed with `_` (e.g. `@Phantom(_a): pub [Tag]`).
  The `_` prefix marks the param as intentionally unused — a phantom type parameter. Bare unused params (no `_` prefix)
  in nominal types emit the C0908 warning.

______________________________________________________________________

## 3. Declarations

### Nominal Types

```
@Name(params) derives Trait1, Trait2 where a is Eq, e is Debug: pub [Ok(a) | Err(e)] { methods }
```

Order: `@Name(params)` → `derives ...` → `where ...` → `:` → body → `{ methods }`

- `@` prefix on declaration only
- Body: any type expression after `:` (tag unions, records, primitives, other nominal types, etc.)
- `@UserId: I64` desugars to `@UserId: pub [UserId(I64)]` — single-variant tag union where variant name = type name
- `pub` on body: all-or-nothing (all variants public or none)
- Method block: `{ method_name = |self: Self| -> ReturnType { body } }`
  - Methods are `pub` by default (they're in the method block specifically to be accessible)
  - `Self` available in method blocks, refers to the nominal type
  - Inherent methods accessed via dot syntax: `result.is_ok()`
- Self-referential types allowed (must have heap-backed collection in recursion path — `List`, `Map`, `Set` are OK;
  records/tuples/primitives cannot recurse directly)
- Mutual recursion: free within module (no forward declarations needed)

### Type Aliases

```
AliasName: ExistingType
```

- No `derives` (only on nominal types)
- No associated functions
- No method block

### Effect Definitions

```
Console!: {
  println!: |Str| -[Console!]-> {}
  read_line!: || -[Console!]-> Str
}
```

- Type alias syntax with `!` suffix on effect name (enforced by compiler)
- Operation names end in `!` (enforced by compiler)
- Operations are function-typed fields
- Effect operations are invoked module-qualified: `Console.println!(...)`

### Effect Aliases

```
Io!: [File! | Console!]
```

- Tag-union-like syntax with `!` suffix

### Throw! Effect (built-in)

```
Throw!(e): {
  raise!: |e| -[Throw!(e)]-> a
}
```

- Parameterized by error type `e`
- `raise!` never returns (inferred bottom type)
- `Throw!([..])` means "can throw any error type" (open tag union)

### Trait Definitions

```
Eq: { eq: |Self, Self| -> Bool }
Hash: { hash: |Self| -> U64 }
```

- Record alias where all fields are pure functions
- `Self` refers to the implementing type
- No associated types (methods only)
- No default implementations
- No higher-kinded types (HKT)

### Trait Implementations

```
Color is Eq: {
  eq = |a: Self, b: Self| -> Bool {
    match (a, b) {
      (Red, Red) => True
      (Green, Green) => True
      _ => False
    }
  }
}
```

- Separate `is` blocks (not inline on type definition)
- `Self` available in `is` blocks, refers to the nominal type being implemented
- One trait per block
- Must be in same module as the nominal type definition
- Strict orphan rule: compile error if type is not local to the module
- `is` blocks are always implicitly `pub` (implementing a trait makes it part of the type's public interface)
- `derives` on type definition auto-generates `is` blocks for built-in traits only

### Built-in Derivable Traits

`Eq`, `Ord`, `Hash`, `Debug`, `Default`

- `derives` generates compiler-internal implementations (not visible as `is` blocks in source)
- User-defined traits require manual `is` blocks
- `Display` is NOT derivable (must be implemented manually)

### Constants

```
pi: F64 = 3.14159
```

### Imports

```
import Module                          -- qualified use only: Module.func()
import Module { foo, bar }             -- unqualified + qualified
import Module as M { foo, bar }        -- alias + unqualified
import Result { [Ok, Err], map }       -- [brackets] for nominal type variants
```

- No `exposing` keyword — names listed directly in `{ }` after module name
- No wildcard imports (always explicit)
- `[Ok, Err]` brackets for nominal type variants (comma separator inside)
- No `@` prefix in imports
- No re-exports (every name has one canonical home)
- Circular imports: banned (compile error)

### Test Declarations

```
test "name" { body }
```

- Block syntax (not `= body`)
- Run via `camp test`

### Expect Declarations

```
expect condition
```

- Keyword + expression, no parens
- `///` doc comment on line before shown on failure
- `expect a == b` desugars to capture both operands + Debug representation
- Non-equality expects show "evaluated to False"

______________________________________________________________________

## 4. Expressions

### Three-Way Call Syntax

| Syntax | Semantics | Example | |--------|-----------|---------| | `obj.method(args)` | Nominal dispatch (type promised
it via trait/inherent method) | `list.map(fn)` | | `obj->func(args)` | Lexical UFCS (scope provides the function) |
`name->is_even()` | | `obj.(field)(args)` | Structural dispatch (value stores the function in a field) |
`callback.(handler)(data)` | | `Trait.func(obj, args)` | Qualified trait dispatch (explicit, disambiguation) |
`Eq.eq(a, b)` |

### Dot Syntax (`.`)

- `obj.field` — field access
- `obj.method(args)` — method call (parser distinguishes by `(` following — method lookup never falls through to fields)
- `(obj.field)(args)` — field-then-call (parens required around field expression)
- `.method(args)` — dot lambda (nominal dispatch)
- `.->func(args)` — dot lambda (lexical UFCS)
- `.(field)(args)` — dot lambda (structural dispatch)

### Arrow Syntax (`->`)

- After `|params|`: return-type arrow (committed parse — always interpreted as return type)
- After any expression: UFCS
- `|x| -> is_even(x)` is a **parse error** — write `|x| x->is_even()` instead
- Parens required: `obj->func()` not `obj->func`
- Module paths via casing: lowercase after `->` = local function; `Uppercase.` continues until `.lowercase` (module
  path); `Uppercase(` = tag constructor
- Tag constructors via `->`: `obj->Some()` = `Some(obj)` (type checker catches wrong arg count)
- `->` is a postfix operator at same precedence as `.`, evaluated left-to-right, chainable: `x->func()->method()`

### Function Calls

- `func(args)` — standard
- `@Type(args)` — nominal type construction (newtypes)
- `Tag(args)` — tag variant construction

### Lambda

```
|params| -> ReturnType { body }
|params| expr
```

- `|` delimiters, `->` return arrow
- Body: single expression or block
- Parameter destructuring allowed: `|{ name, age }| name`
- `where` clause: `|items| where a is Ord { ... }` (parsed after the body — see parser)

### Blocks

```
{
    stmt1
    stmt2
    result_expr
}
```

- Newline-separated, no semicolons
- Last expression is the return value
- Blocks are expressions

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
- As-patterns: `Some(x) as opt_x => opt_x` — binds the whole match to `opt_x` while also destructuring
- String/char literal matching: `"hello" => ...`, `'a' => ...`
- String pattern interpolation: `"Hello, ${name}!" => name` — binds `name` to the extracted substring. Multiple
  interpolation points allowed: `"${greeting}, ${name}!" => ...`. Interpolated values are `Str`.
- Match is an expression — it produces the value of the matched arm's body

### If/Else

```
if cond { ... }
if cond { ... } else { ... }
if cond { ... } else if cond2 { ... } else { ... }
```

- **Braces always required** for if/else bodies (no brace elision — avoids parsing ambiguity with condition termination)
- If/else is an expression — both branches must produce the same type

### For Loop

```
$total = 0
for x in xs {
    $total = $total + x
}
```

- Calls `.iter()` on `xs`
- Loop variable is immutable
- Returns `{}` (unit)
- For is an expression (producing `{}`)

### Par Blocks

```
par { x: e1, y: e2, z: e3 }
par for x in xs { body }
```

- Named entries only: `par { name: expr, ... }` returns record `{ name: T1, ... }`
- `par for` returns `{}` (unit, like regular `for`)
- Fail-fast: if any branch crashes, whole par block crashes, other branches cancelled
- Effects in par branches must be handled by a handler installed outside the par block
- `par for` error handling: fail-fast (same as `par` blocks)

### Handle

```
handle Console!, Throw! in body with {
  .println!(resume, msg) => { ... ; resume({}) }
  .raise!(resume, err) => { ... }
}
```

- Multiple effects per block: `handle E!, F! in body with { ... }`. It is a **compile error** for a multi-effect handle
  block to handle two or more effects that declare operations with the same name — the clause syntax
  `.op(resume, args) ...` carries no effect qualifier, so an op name shared across handled effects is ambiguous. Split
  into separate `handle` blocks (one per such effect) or rename the conflicting op.
- Single effect per block also valid: `handle Console! in body with { ... }`
- `.op(resume, args) => body` — `resume` is always the first param, followed by the operation's parameters in
  declaration order (the clause head uses the bare op name with no `!` and no effect qualifier; the effect is resolved
  implicitly from the handled-effect list)
- Resume: one-shot (0 or 1 times). 0 = abort (don't call resume), 1 = continue (call resume once). Runtime error on
  double-resume. Compile-time detection where possible.
- Deep handlers only (handler reinstalls itself on continuation)

### Control Flow

- `return expr` — exits function only (never exits a block). `return` is an expression with inferred bottom type.
- `crash "msg"` — unrecoverable abort. Expression with inferred bottom type (can appear in any expression position).
- `todo` — placeholder, panics at runtime in debug builds. Expression with inferred bottom type.
- `todo "msg"` — placeholder with message. Same semantics.

### Assignment

- `x = expr` — immutable binding
- `$x = expr` — mutable binding (`$` always present on both declaration and reassignment: `$x = 1` then `$x = 2`)
- No shadowing (compile error if `x` redefined in same scope)
- No `$` at top level (module scope is always immutable)
- Type annotation: `x: Int = 42` (annotation before `=`, consistent with all other `:` annotations)

### Destructuring

- `{ name, age } = person` — record destructuring (no `let` keyword)
- `[a, b, ...rest] = list` — list destructuring
- `@UserId(n) = uid` — nominal type destructuring
- `(a, b) = tuple` — tuple destructuring

### Record Literal

```
{ name: "Alice", age: 30 }
{ name: "new", ..record }
```

- Spread at end only (update, not merge)
- `..record` must be the last entry

### List Literal

```
[1, 2, 3]
[1, 2, ..rest, 5]
```

- Multiple `..spread` allowed in construction (not in patterns)

### Tuple Literal

```
(42, "hello")
(1, 2, 3)
```

- Max 3 elements
- Parenthesized, comma-separated

### Nominal Type Construction

- Tag variants: `Ok(42)`, `Err("oops")`, `None` (no `@` prefix)
- Newtypes: `@UserId(42)` — `@` prefix distinguishes nominal type construction from tag construction
- Rule: `@` is used when the constructor name IS the type name (newtype pattern: `@UserId` type has `UserId`
  constructor). When they differ (like `@Result` type with `Ok`/`Err` constructors), no `@` needed.
- From outside module: `Result.Ok(42)` or `Ok(42)` if imported via `import Result { [Ok, Err], ... }`
- Newtypes from outside: `@UserId(42)` always (the `@` is part of the construction syntax, not the module path)

______________________________________________________________________

## 5. Patterns

### Pattern Types

- Tag: `Ok(x)`, `None`
- Record: `{ name, age }`
- List: `[a, b, ..rest]`
- Tuple: `(a, b)`, `(a, b, c)`
- Integer/String/Char/Bool literal: `42`, `"hello"`, `'a'`, `True`
- Identifier: `x` (binds)
- Wildcard: `_`
- Unused-but-named: `_name`
- Nominal destructuring: `@UserId(n)` — `@` prefix for newtype patterns
- Or-pattern: `Red | Green | Blue`
- As-pattern: `pattern as name`
- Guard: `if condition`
- Rest: `..rest` (one per list pattern, at any position; one per record pattern, at end only)

### Empty Tag Patterns

- `None` (not `None()`) — casing disambiguates from identifiers

### String Pattern Interpolation

```
match input {
    "Hello, ${name}!" => name
    "${greeting}, ${target}!" => Str.concat(greeting, ", to, ", target)
    _ => "unknown"
}
```

- Multiple interpolation points allowed
- Interpolated bindings are `Str` type

______________________________________________________________________

## 6. Module System

- One file = one module (module name = filename without extension)
- Nested modules via directory structure only (no inline `module` declarations)
- `.camp` file extension
- `camp.toml` for project manifest (dependencies, metadata)
- Single scripts with shebang don't need manifest (dependency syntax in header TBD)
- `pub` per-declaration (two-level: type export vs variant export)
- No re-exports (every name has one canonical home)
- Circular imports: banned (compile error)
- Prelude is compiler-injected (not a source module); no opt-out

______________________________________________________________________

## 7. Effect System

### Effect Invocation

- Always module-qualified: `Console.println!(...)`
- Never `Console!.println!(...)` (the `!` only on the effect type name and operation names in definitions)
- Within the defining module: either use `Console.println!(...)` or just `println!(...)`

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
- Single effect per handle block also valid: `handle E! in body with { ... }`

### Non-Prelude Runtime-Backed Effects (Process!)

Runtime-backed effects that are not prelude effects SHALL be defined in the stdlib as regular effect declarations. Users
SHALL import them explicitly. The codegen SHALL provide built-in handlers that bridge effect operations to host
syscalls. `Process!` (backed by WASIX `proc_spawn`/`wait` via wasmer) is the canonical example.

- `Process.spawn!(cmd)` requires `import Process { Process!, Command, ProcessHandle, ... }`; `main!`'s effect row SHALL
  include `Process!`
- When `Process.spawn!` is performed, the runtime handler SHALL marshal the `Command` into WASIX `proc_spawn` arguments
  and return a `ProcessHandle` with optional pipe handles
- When a `Command` has `stdout: Capture` and is spawned via `Process.spawn!`, `ProcessHandle.stdout` SHALL be
  `Some(handle)` and `Process.read!(handle)` SHALL return bytes from the child's stdout pipe

______________________________________________________________________

## 8. Entry Point

```
pub main! = || -[Console! | Throw!([..])]-> I64 {
  // ...
}
```

- Returns any type implementing `Termination` trait
- `I64` → exit code, `{}` → exit 0, `Result(a, e)` → Ok=0/Err=1
- `Throw!([..])` means "can throw any error type" (open tag union)
- `main!` is a regular identifier with `!` suffix (consistent with effect naming)

### Termination Trait

```
Termination: {
  report: |Self| -> I64
}
```

- Implemented by: `I64` (returns self), `{}` (returns 0), `Result(a, e)` (Ok→0, Err→1)
- The runtime calls `report` on the value returned by `main!`

______________________________________________________________________

## 9. Prelude

Rich prelude (like Rust), compiler-injected. Includes:

- Types: `Bool`, `I8`–`I64`, `U8`–`U64`, `F32`, `F64`, `Char`, `Str`, `List`, `Map`, `Set`, `Result`, `Bytes`, `Iter`,
  `{}`
- Tag variants: `True`, `False`, `Ok`, `Err`
- Effects: `Console!`, `Throw!`, `Parallel!`, `Spawn!`, `Async!`, `File!`, `Env!`, `Time!`, `Random!`, `Log!`,
  `Crypto.Random!`
- Common functions: `map`, `filter`, `foldl`, `println!`, etc.
- Common traits: `Eq`, `Ord`, `Hash`, `Debug`, `Display`, `Default`
- No re-exports — prelude is compiler-injected
- `Bool` is a nominal type in the prelude: `@Bool: pub [True | False]`
- Can be disabled with `no_prelude = true` in `camp.toml`

______________________________________________________________________

## 10. Standard Library Types

### Result

```
@Result(a, e): pub [Ok(a) | Err(e)]
```

- Library type, imported in prelude with `[Ok, Err]`

### List

```
@List(a): pub [Cons(a, List(a)) | Nil]
```

- Library type, array-backed (contiguous buffer with `len`/`cap`/`data_ptr`, growable); runtime layout in
  `src/codegen/runtime.odin` (`List_Alloc`/`List_Push`/`List_Len`/`List_Get`/`List_Grow`). The surface `Cons(a, List(a)) | Nil`
  is the logical API, not the in-memory representation.

### Str

- String type is `Str` (not `String`)
- UTF-8 byte-array-backed (contiguous buffer); intrinsic operations (`length`, `byte_size`, `take`, `slice`, `split`,…)
  require runtime UTF-8/Unicode support. See `stdlib/Str.camp` and codegen runtime funcs `str_len`/`str_eq`/`str_concat`/`str_slice`.

______________________________________________________________________

## 11. Traits

- Traits = record aliases where all fields are pure functions
- `Self` in trait definitions refers to implementing type
- `Self` in `is` blocks refers to the nominal type being implemented
- `Self` in method blocks refers to the nominal type
- No associated types (methods only)
- No default implementations
- No higher-kinded types (THIS MUST BE GUARANTEED)
- Auto-deriving: built-in traits only (like Swift): `Eq`, `Ord`, `Hash`, `Debug`, `Default`
- Manual impl: `Color is Eq { ... }` separate blocks
- Strict orphan rule: type must be local to the module

### Debug vs Display

- `Debug`: developer-facing (verbose, shows structure), derivable
- `Display`: user-facing (clean, formatted), NOT derivable (must implement manually)
- `${expr}` in string interpolation requires/uses `Display` trait

______________________________________________________________________

## 12. Error Handling

Both mechanisms:

1. **Throw! effect**: `Throw.raise!("error")` or `raise!("error")` (if imported) — effect system, handlers decide
1. **Result type**: `@Result(a, e): pub [Ok(a) | Err(e)]` — explicit, no hidden control flow

______________________________________________________________________

## 13. Key Syntax Changes from Current Implementation

| Current (Parser/Spec) | Decision | Action |
|---|---|---|
| Effect row `,` separator | `\|` separator | Done |
| `test "name" = body` | `test "name" { body }` | Done |
| `intercept` keyword | Remove | Done |
| `@` in type-use positions | No `@` in type-use | Done |
| `@` absent in expressions/patterns | `@` for nominal construction/destruction | Done |
| `r"..."` raw strings | Removed (use `\` per-line) | Done |
| `"""..."""` multiline | Removed (use `\` per-line) | Done |
| `\|>` pipe operator | Removed | Done |
| `++` concat operator | Removed | Done |
| `&& \|\| !` logic operators | `and or not` keywords | Done |
| `@Variant` in imports | `[Ok, Err]` brackets | Done |
| `is` on type def header | Separate `is` blocks only | Done |
| `unsafe` keyword | Removed | Done |
| `exposing` keyword | Removed (names in `{ }` directly) | Done |
| `\|x\| -> is_even(x)` | Parse error (use `\|x\| x->is_even()`) | Done |
| `obj.method(args)` ambiguity | Rust-style disambiguation | Done |
| No `->` UFCS syntax | Add `->` for lexical UFCS | Done |
| No `.(field)()` syntax | Add for structural dispatch | Done |
| `derives` on type aliases | `derives` only on nominal types | Done |
| `Self` in free functions | `Self` in traits + method blocks + `is` blocks only | Done |
| `None()` tag construction | `None` (no parens) | Done |
| `\|a, b\| -[]-> I64` empty effect row | Compile error, use `->` | Done |
| `@inline` annotation | Removed | Done |
| Brace-elided if/else | Braces always required | Done |
