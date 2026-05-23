/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

export default grammar({
  name: "camp",

  extras: ($) => [/\s/, $.comment],

  word: ($) => $.identifier,

  externals: ($) => [
    $._string_start,
    $._string_start_r,
    $._string_start_triple,
    $._string_content,
    $._interpolation_start,
    $._interpolation_end,
    $._string_end,
  ],

  conflicts: ($) => [
    [$.block, $.record_expression],
    [$._primary_expression, $.lambda_parameter],
    [$.block, $._statement],
    [$.arguments, $.paren_lambda],
    [$.arguments, $.parenthesized_expression],
    [$._type, $.applied_type],
    [$._pattern, $.tag_pattern],
    [$.effect_row, $.record_type],
    [$.anonymous_method_expression, $.field_access_expression, $.method_call_expression],
    [$.anonymous_method_expression],
    [$.anonymous_method_expression, $.method_call_expression],
    [$.record_pattern_fields],
  ],

  rules: {
    source_file: ($) => repeat($._declaration),

    comment: ($) => token(seq("--", /.*/)),

    _declaration: ($) => choice(
      $.const_declaration,
      $.effect_declaration,
      $.trait_declaration,
      $.alias_declaration,
      $.newtype_declaration,
      $.import_declaration,
      $.test_declaration,
      $.expect_declaration,
    ),

    const_declaration: ($) => seq(
      optional("pub"),
      field("name", $.identifier),
      optional("!"),
      optional(seq(":", field("type_annotation", $.type_annotation))),
      optional($.where_clause),
      "=",
      field("body", $._expression),
    ),

    effect_declaration: ($) => seq(
      "effect",
      field("name", $.type_identifier),
      "{",
      field("operations", repeat($.effect_operation)),
      "}",
    ),

    effect_operation: ($) => seq(
      field("name", $.identifier),
      optional("!"),
      optional(seq("(", optional(field("parameters", $.effect_parameters)), ")")),
      optional(seq("->", field("return_type", $._type))),
    ),

    effect_parameters: ($) => seq(
      $.effect_parameter,
      repeat(seq(",", $.effect_parameter)),
    ),

    effect_parameter: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("type", $._type))),
    ),

    trait_declaration: ($) => seq(
      "trait",
      field("name", $.type_identifier),
      optional(seq("is", field("parent", $.type_identifier))),
      "{",
      repeat($.trait_method),
      "}",
    ),

    trait_method: ($) => seq(
      field("name", $.identifier),
      ":",
      field("type", $._type),
    ),

    alias_declaration: ($) => seq(
      "alias",
      field("name", $.type_identifier),
      optional(field("type_parameters", $.type_parameters)),
      "=",
      field("target", $._type),
    ),

    import_declaration: ($) => seq(
      optional("unsafe"),
      "import",
      field("module", $.type_identifier),
      optional(seq("exposing", "[", optional(field("exposed", $.exposed_names)), "]")),
      optional(seq("as", field("alias", $.type_identifier))),
    ),

    exposed_names: ($) => choice(
      seq(
        $.identifier,
        repeat(seq(",", $.identifier)),
      ),
      "..",
    ),

    test_declaration: ($) => seq(
      "test",
      field("name", $.string),
      "=",
      field("body", $._expression),
    ),

    expect_declaration: ($) => seq(
      "expect",
      field("condition", $._expression),
    ),

    _expression: ($) => choice(
      $.binary_expression,
      $.unary_expression,
      $.call_expression,
      $.method_call_expression,
      $.field_access_expression,
      $._primary_expression,
    ),

    call_expression: ($) => prec.left(8, seq(
      field("function", $._expression),
      field("arguments", $.arguments),
    )),

    method_call_expression: ($) => prec.left(9, seq(
      field("receiver", $._expression),
      ".",
      field("method", $.identifier),
      field("arguments", $.arguments),
    )),

    field_access_expression: ($) => prec.left(8, seq(
      field("record", $._expression),
      ".",
      field("field", $.identifier),
    )),

    binary_expression: ($) => choice(
      prec.left(1, seq(field("left", $._expression), field("operator", "or"), field("right", $._expression))),
      prec.left(2, seq(field("left", $._expression), field("operator", "and"), field("right", $._expression))),
      prec.left(3, seq(field("left", $._expression), field("operator", "=="), field("right", $._expression))),
      prec.left(3, seq(field("left", $._expression), field("operator", "!="), field("right", $._expression))),
      prec.left(4, seq(field("left", $._expression), field("operator", "<"), field("right", $._expression))),
      prec.left(4, seq(field("left", $._expression), field("operator", ">"), field("right", $._expression))),
      prec.left(4, seq(field("left", $._expression), field("operator", "<="), field("right", $._expression))),
      prec.left(4, seq(field("left", $._expression), field("operator", ">="), field("right", $._expression))),
      prec.left(5, seq(field("left", $._expression), field("operator", "+"), field("right", $._expression))),
      prec.left(5, seq(field("left", $._expression), field("operator", "-"), field("right", $._expression))),
      prec.left(6, seq(field("left", $._expression), field("operator", "*"), field("right", $._expression))),
      prec.left(6, seq(field("left", $._expression), field("operator", "/"), field("right", $._expression))),
      prec.left(6, seq(field("left", $._expression), field("operator", "%"), field("right", $._expression))),
    ),

    unary_expression: ($) => choice(
      prec.left(7, seq(field("operator", "-"), field("argument", $._expression))),
      prec.left(7, seq(field("operator", "not"), field("argument", $._expression))),
    ),

    _primary_expression: ($) => choice(
      $.integer,
      $.float,
      $.string,
      $.interpolated_string,
      $.boolean,
      $.dollar_identifier,
      $.identifier,
      $.type_identifier,
      $.tag_expression,
      $.list_expression,
      $.parenthesized_expression,
      $.lambda_expression,
      $.block,
      $.record_expression,
      $.if_expression,
      $.match_expression,
      $.handle_expression,
      $.anonymous_method_expression,
      $.return_expression,
      $.crash_expression,
      $.par_expression,
    ),

    // --- Literals ---
    integer: ($) => /[1-9][0-9_]*|0/,

    float: ($) => /[1-9][0-9_]*\.[0-9][0-9_]*|0\.[0-9][0-9_]*/,

    string: ($) => seq(
      '"',
      repeat(choice(/[^\\"\n]+/, $.escape_sequence)),
      '"',
    ),

    interpolated_string: ($) => seq(
      field("open", choice(
        alias($._string_start, '"'),
        alias($._string_start_r, 'r"'),
        alias($._string_start_triple, '"""'),
      )),
      repeat(choice(
        alias($._string_content, $.string_content),
        seq(
          alias($._interpolation_start, '${'),
          field("expression", $._expression),
          alias($._interpolation_end, '}'),
        ),
      )),
      field("close", alias($._string_end, '"')),
    ),

    escape_sequence: ($) => token(seq("\\", /[nrt"\\]/)),

    boolean: ($) => choice("true", "false"),

    // --- Identifiers ---
    identifier: ($) => token(choice(
      /[_a-z][_a-zA-Z0-9]*/,
      /`[a-zA-Z_][a-zA-Z0-9_]*`/,
    )),

    // --- Identifiers (continued) ---
    type_identifier: ($) => /[A-Z][a-zA-Z0-9]*/,

    dollar_identifier: ($) => seq("$", $.identifier),

    // --- Expressions ---
    tag_expression: ($) => prec(9, seq(
      optional("@"),
      field("name", $.type_identifier),
      field("arguments", $.arguments),
    )),

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

    // --- Lambda ---
    lambda_expression: ($) => choice(
      $.pipe_lambda,
      $.paren_lambda,
    ),

    pipe_lambda: ($) => seq(
      "|",
      optional(seq(
        optional($.type_parameters),
        optional(field("parameters", $.lambda_parameters)),
      )),
      "|",
      optional(seq("->", optional($.effect_row), field("return_type", $._type))),
      field("body", $._expression),
    ),

    lambda_parameters: ($) => seq(
      $.lambda_parameter,
      repeat(seq(",", $.lambda_parameter)),
    ),

    lambda_parameter: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("type", $._type))),
    ),

    type_parameters: ($) => seq(
      "<",
      $.identifier,
      repeat(seq(",", $.identifier)),
      ">",
    ),

    paren_lambda: ($) => seq(
      "(",
      optional(field("parameters", $.lambda_parameters)),
      ")",
      optional(seq(
        "->",
        optional($.effect_row),
        field("return_type", $._type),
      )),
      field("body", $._expression),
    ),

    effect_row: ($) => seq(
      "-[",
      optional(seq($.type_identifier, repeat(seq("|", $.type_identifier)))),
      "]->",
    ),

    // --- Block ---
    block: ($) => seq(
      "{",
      repeat($._statement),
      optional($._expression),
      "}",
    ),

    _statement: ($) => $._expression,

    // --- Record ---
    record_expression: ($) => seq(
      "{",
      optional(seq("..", field("spread", $._expression), optional(","))),
      optional(field("fields", $.record_fields)),
      "}",
    ),

    record_fields: ($) => seq(
      $.record_field,
      repeat(seq(",", $.record_field)),
      optional(","),
    ),

    record_field: ($) => seq(
      field("name", $.identifier),
      ":",
      field("value", $._expression),
    ),

    // --- If ---
    if_expression: ($) => prec.right(seq(
      "if",
      field("condition", $._expression),
      field("consequence", $._expression),
      optional(seq("else", field("alternative", $._expression))),
    )),

    // --- Match ---
    match_expression: ($) => seq(
      "match",
      field("scrutinee", $._expression),
      "{",
      optional(field("arms", $.match_arms)),
      "}",
    ),

    match_arms: ($) => seq(
      $.match_arm,
      repeat(seq("|", $.match_arm)),
      optional("|"),
    ),

    match_arm: ($) => seq(
      field("pattern", $._pattern),
      optional(seq("if", field("guard", $._expression))),
      "=>",
      field("body", $._expression),
    ),

    // --- Handle ---
    handle_expression: ($) => seq(
      choice("handle", "intercept"),
      field("effect", $.type_identifier),
      "in",
      field("body", $._expression),
      "with",
      "{",
      field("arms", $.handler_arms),
      "}",
    ),

    handler_arms: ($) => repeat1($.handler_arm),

    handler_arm: ($) => seq(
      ".",
      field("name", $.identifier),
      optional(seq("!",
        "(",
        field("resume_param", $.identifier),
        optional(seq(",", field("extra_params", $.identifier_list))),
        ")",
      )),
      "=>",
      field("body", $._expression),
    ),

    identifier_list: ($) => seq(
      $.identifier,
      repeat(seq(",", $.identifier)),
    ),

    // --- Return/Crash ---
    return_expression: ($) => seq("return", $._expression),

    crash_expression: ($) => seq("crash", $._expression),

    anonymous_method_expression: ($) => prec(9, seq(
      ".",
      field("name", $.identifier),
      optional(field("arguments", $.arguments)),
    )),

    // --- Patterns ---
    _pattern: ($) => choice(
      $.wildcard_pattern,
      $.or_pattern,
      $.tag_pattern,
      $.record_pattern,
      $.list_pattern,
      $.integer,
      $.string,
      $.boolean,
      $.type_identifier,
      $.identifier,
    ),

    wildcard_pattern: ($) => "_",

    or_pattern: ($) => prec.right(seq(
      field("left", $._pattern),
      "|",
      field("right", $._pattern),
    )),

    tag_pattern: ($) => seq(
      optional("@"),
      field("name", $.type_identifier),
      optional(field("arguments", $.pattern_arguments)),
    ),

    pattern_arguments: ($) => seq(
      "(",
      optional(seq($._pattern, repeat(seq(",", $._pattern)))),
      ")",
    ),

    record_pattern: ($) => seq(
      "{",
      optional(seq(field("fields", $.record_pattern_fields), optional(","))),
      optional(seq("..", optional(field("rest", $.identifier)))),
      "}",
    ),

    record_pattern_fields: ($) => seq(
      $.record_pattern_field,
      repeat(seq(",", $.record_pattern_field)),
    ),

    record_pattern_field: ($) => seq(
      field("name", $.identifier),
      optional(seq(":", field("pattern", $._pattern))),
    ),

    list_pattern: ($) => seq(
      "[",
      optional(seq($._pattern, repeat(seq(",", $._pattern)))),
      "]",
    ),

    // --- Types ---
    _type: ($) => choice(
      $.type_identifier,
      $.function_type,
      $.tag_union_type,
      $.record_type,
      $.applied_type,
      $.wildcard_type,
      $.type_variable,
    ),

    function_type: ($) => seq(
      optional(seq("(", optional(seq($._type, repeat(seq(",", $._type)))), ")")),
      optional($.effect_row),
      "->",
      $._type,
    ),

    tag_union_type: ($) => seq(
      "[",
      $.tag_union_variant,
      repeat(seq("|", $.tag_union_variant)),
      optional(seq("|", $.wildcard_type)),
      optional(seq("|", "..", optional(field("rest", $.identifier)))),
      "]",
    ),

    tag_union_variant: ($) => seq(
      field("name", $.type_identifier),
      optional(field("arguments", $.type_arguments)),
    ),

    record_type: ($) => seq(
      "{",
      optional(seq($.record_type_field, repeat(seq(",", $.record_type_field)), optional(","))),
      optional(seq(",", "..", optional(field("rest", $.identifier)))),
      "}",
    ),

    record_type_field: ($) => seq(
      field("name", $.identifier),
      ":",
      field("type", $._type),
    ),

    applied_type: ($) => seq(
      field("name", $.type_identifier),
      field("arguments", $.type_arguments),
    ),

    type_arguments: ($) => seq(
      "(",
      optional(seq($._type, repeat(seq(",", $._type)))),
      ")",
    ),

    wildcard_type: ($) => "_",

    type_variable: ($) => alias($.identifier, "type_variable"),

    type_annotation: ($) => alias($._type, "type_annotation"),

    // --- Newtype ---
    newtype_declaration: ($) => seq(
      "@",
      field("name", $.type_identifier),
      optional(seq(
        "(",
        optional(seq($.identifier, repeat(seq(",", $.identifier)))),
        ")",
      )),
      optional(seq(
        "is",
        $.type_identifier,
        repeat(seq(",", $.type_identifier)),
      )),
      optional($.derives_clause),
      ":",
      optional("pub"),
      field("inner_type", $._type),
    ),

    derives_clause: ($) => seq(
      "derives",
      $.type_identifier,
      repeat(seq(",", $.type_identifier)),
    ),

    // --- Par ---
    par_expression: ($) => choice(
      seq(
        "par",
        "for",
        field("var", $.identifier),
        "in",
        field("iterable", $._expression),
        field("body", $.block),
      ),
      seq(
        "par",
        field("expressions", $.par_block),
      ),
    ),

    par_block: ($) => seq(
      "{",
      optional(seq($._expression, repeat(seq(",", $._expression)))),
      "}",
    ),

    // --- Where clause ---
    where_clause: ($) => seq(
      "where",
      $.where_constraint,
      repeat(seq(",", $.where_constraint)),
    ),

    where_constraint: ($) => seq(
      field("type_param", $.identifier),
      "is",
      field("trait", $.type_identifier),
    ),

  },
});
