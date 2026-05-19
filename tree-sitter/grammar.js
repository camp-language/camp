/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

export default grammar({
  name: "camp",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

  conflicts: ($) => [
    [$._primary_expression, $.tag_expression],
  ],

  rules: {
    source_file: ($) => repeat($._declaration),

    comment: ($) => token(seq("--", /.*/)),

    _declaration: ($) => choice(
      $.const_declaration,
    ),

    const_declaration: ($) => seq(
      $.identifier,
      "=",
      $._expression,
    ),

    _expression: ($) => $._primary_expression,

    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.dollar_identifier,
      $.identifier,
      $.type_identifier,
      $.tag_expression,
      $.list_expression,
      $.parenthesized_expression,
    ),

    // --- Literals ---
    integer: ($) => /[0-9][0-9_]*/,

    float: ($) => /[0-9][0-9_]*\.[0-9][0-9_]*/,

    string: ($) => seq(
      '"',
      repeat(choice(/[^\\"\n]+/, $.escape_sequence)),
      '"',
    ),

    escape_sequence: ($) => token(seq("\\", /[nrt"\\]/)),

    boolean: ($) => choice("true", "false"),

    // --- Identifiers ---
    identifier: ($) => /[_a-z][_a-zA-Z0-9]*/,

    // --- Identifiers (continued) ---
    type_identifier: ($) => /[A-Z][a-zA-Z0-9]*/,

    dollar_identifier: ($) => seq("$", $.identifier),

    // --- Expressions ---
    tag_expression: ($) => seq(
      field("name", $.type_identifier),
      optional(field("arguments", $.arguments)),
    ),

    arguments: ($) => seq(
      "(",
      optional(seq($._expression, repeat(seq(",", $._expression)))),
      ")",
    ),

    list_expression: ($) => seq(
      "[",
      optional(seq($._expression, repeat(seq(",", $._expression)))),
      "]",
    ),

    parenthesized_expression: ($) => seq(
      "(",
      $._expression,
      ")",
    ),

    // --- Keywords ---
    _if: ($) => "if",
    _else: ($) => "else",
    _match: ($) => "match",
    _effect: ($) => "effect",
    _trait: ($) => "trait",
    _is: ($) => "is",
    _alias: ($) => "alias",
    _handle: ($) => "handle",
    _intercept: ($) => "intercept",
    _in: ($) => "in",
    _with: ($) => "with",
    _import: ($) => "import",
    _exposing: ($) => "exposing",
    _as: ($) => "as",
    _unsafe: ($) => "unsafe",
    _for: ($) => "for",
    _and: ($) => "and",
    _or: ($) => "or",
    _not: ($) => "not",
    _expect: ($) => "expect",
    _test: ($) => "test",
  },
});
