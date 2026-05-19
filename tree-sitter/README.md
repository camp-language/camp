# tree-sitter-camp

Tree-sitter grammar for the [Camp](https://github.com/camp-language/camp) programming language.

## Usage

```sh
just tree-sitter-test      # run corpus tests
just tree-sitter-validate  # parse all e2e .camp files
just lint-tree-sitter      # both (pre-commit)
```

## Development

1. Edit `grammar.js`
2. Run `tree-sitter generate`
3. Run `tree-sitter test`
4. Add tests to `test/corpus/`

## Keeping in Sync with the Compiler

When the compiler's parser changes:

1. Run `just tree-sitter-validate` — any syntax changes will produce ERROR nodes
2. Update `grammar.js` to match
3. Run `tree-sitter test -u` to update corpus expected outputs
4. Review the diff of test changes to confirm they match the new syntax

## TODO

- [ ] Heavy sync mechanism: snapshot-based drift detection — regenerate all corpus expected outputs from real `.camp` files and commit them. Any change to either side produces a diff.
- [ ] String interpolation `"{x} is the answer"` — currently lexed as a plain string; needs external scanner for proper `{expr}` inside string support
