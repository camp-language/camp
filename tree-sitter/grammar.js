/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

export default grammar({
  name: "camp",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

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
      $.identifier,
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
