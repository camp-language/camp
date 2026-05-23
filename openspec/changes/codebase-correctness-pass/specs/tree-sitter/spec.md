## MODIFIED Requirements

### Requirement: Match arm uses fat arrow
Match arm syntax SHALL use `=>` to separate the pattern from the body, not `->`.

#### Scenario: Simple match arm
- **WHEN** parsing `match x { 1 => "one" | _ => "other" }`
- **THEN** the `=>` separates each arm's pattern from its body

### Requirement: Effect row uses bracket-arrow syntax
The tree-sitter grammar SHALL parse effect rows as `-[E | E]->` matching the language spec. The `->{ E }` syntax is NOT valid.

#### Scenario: Effect row in function type
- **WHEN** parsing `|Str| -[Console!]-> {}`
- **THEN** the grammar produces an `effect_row` node containing `-[Console!]->`

### Requirement: Handle expression includes effect name and in keyword
The `handle`/`intercept` expression SHALL include the effect name and `in` keyword: `handle EffectName! in body with { arms }`.

#### Scenario: Handle expression parsing
- **WHEN** parsing `handle Console! in Console.println!("hi") with { .println!(resume) => resume(()) }`
- **THEN** the grammar produces a node with `effect`, `in`, `body`, and `arms` fields

### Requirement: Handler arms use dot-lambda prefix and fat arrow
Handler arm syntax SHALL use `.operation_name!(params) => body`, with a dot-lambda prefix, `!` on effectful operations, multiple parameters, and `=>` arrow.

#### Scenario: Handler arm with multiple parameters
- **WHEN** parsing `.throw!(resume, err) => Err(err)`
- **THEN** the grammar produces a handler arm with two parameters and a fat arrow

### Requirement: Record spread appears before fields
Record functional update syntax SHALL place the spread expression before fields: `{ ..record, field: value }`.

#### Scenario: Functional update parsing
- **WHEN** parsing `{ ..base, name: "new" }`
- **THEN** the `spread` field appears before the `fields` field in the AST

### Requirement: Integer and float regex disallow leading zeros and trailing underscores
Integer tokens SHALL NOT allow leading zeros (except `0`) or trailing underscores. Float tokens SHALL NOT allow trailing underscores on either part.

#### Scenario: Leading zero rejected
- **WHEN** tokenizing `01`
- **THEN** the lexer produces an error or splits into `0` and `1` rather than accepting `01` as an integer

#### Scenario: Trailing underscore rejected
- **WHEN** tokenizing `1_`
- **THEN** the lexer rejects the token

### Requirement: pub and derives are reserved keywords
`pub` and `derives` SHALL be reserved keywords in the tree-sitter grammar.

#### Scenario: pub used as variable name
- **WHEN** parsing `pub = 42`
- **THEN** the grammar recognizes `pub` as a keyword, not an identifier

### Requirement: Effect operation names support bang suffix
Effect operation names in the grammar SHALL support the `!` suffix (e.g., `println!`, `readln!`).

#### Scenario: Effectful operation name
- **WHEN** parsing an effect declaration with operation `println!`
- **THEN** the grammar produces an operation node with name `println!`
