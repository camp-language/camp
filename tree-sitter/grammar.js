/**
 * @file Camp grammar for tree-sitter
 * @author smores
 * @license MIT
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

export default grammar({
  name: "camp",

  rules: {
    // TODO: add the actual grammar rules
    source_file: $ => "hello"
  }
});
