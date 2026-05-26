#!/usr/bin/env bash
set -euo pipefail

echo "=== Unit Tests ==="

run_test() {
  echo "  [$1]"
  odin test "$1" -collection:camp=src && echo "  PASS $1" || echo "  FAIL $1"
}

run_test src
run_test src/base
run_test src/diagnostics
run_test src/frontend
run_test src/semantics
run_test src/mono
run_test src/ir
run_test src/codegen
run_test src/build
run_test src/format

echo "=== Odin Format Check ==="
bad_files=$(find src -name '*.odin' -print0 | while IFS= read -r -d "" f; do
  if ! odinfmt -stdin < "$f" | diff - "$f" > /dev/null 2>&1; then
    printf '%s\n' "$f"
  fi
done)
if [ -n "$bad_files" ]; then
  echo "FAIL: the following files need odin formatting:" >&2
  echo "$bad_files" >&2
  exit 1
fi
echo "All .odin files are properly formatted"

echo "=== Build ==="
odin build src -collection:camp=src -out:camp
odin build src/e2e -collection:camp=src -out:camp-e2e

echo "=== Camp Format Check ==="
./camp fmt --check stdlib/ tests/e2e/

echo "=== E2E Tests ==="
CAMP_BIN="$PWD/camp" ./camp-e2e

echo "=== Tree-Sitter ==="
(cd tree-sitter && tree-sitter generate)
(cd tree-sitter && tree-sitter test)
failed=$(find tests/e2e -name '*.camp' -print0 | while IFS= read -r -d "" f; do
  if tree-sitter parse "$f" 2>&1 | grep -q 'ERROR'; then
    printf '%s\n' "$f"
  fi
done)
if [ -n "$failed" ]; then
  echo "FAIL: parse errors in:" >&2
  echo "$failed" >&2
  exit 1
fi
echo "All .camp files parse successfully"

echo "=== All Checks Passed ==="
