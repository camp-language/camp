format:
    #!/usr/bin/env sh
    for f in $(find src -name '*.odin'); do
      odinfmt "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done

format-check:
    #!/usr/bin/env sh
    for f in $(find src -name '*.odin'); do
      odinfmt "$f" > "$f.tmp"
      if ! diff "$f" "$f.tmp" > /dev/null; then
        echo "FAIL: $f is not formatted" && rm "$f.tmp" && exit 1
      fi
      rm "$f.tmp"
    done
    echo "All .odin files properly formatted"

build:
    odin build src -collection:camp=src -out:camp

build-e2e:
    odin build src/e2e -collection:camp=src -out:camp-e2e

test-unit:
    odin test src -collection:camp=src

test-e2e: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e

tree-sitter-generate:
    -cd tree-sitter && tree-sitter generate

tree-sitter-test: tree-sitter-generate
    -cd tree-sitter && tree-sitter test

tree-sitter-validate: tree-sitter-generate
    #!/usr/bin/env sh
    for f in tests/e2e/**/*.camp; do
      if tree-sitter parse "$$f" 2>&1 | grep -q 'ERROR'; then
        echo "FAIL: $$f has parse errors" && exit 1
      fi
    done
    echo "All .camp files parse successfully"
lint-tree-sitter: tree-sitter-test tree-sitter-validate

test: test-unit test-e2e lint-tree-sitter

check: format-check build build-e2e test

update-snapshots: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e --update



clean:
    git clean -fdX tests/e2e/
    -rm -f /tmp/camp-cmd-stdout-* /tmp/camp-cmd-stderr-* /tmp/camp-e2e-*
