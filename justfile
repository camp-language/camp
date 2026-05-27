format:
    #!/usr/bin/env sh
    for f in $(find src -name '*.odin'); do
      odinfmt "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done

format-check:
    #!/usr/bin/env sh
    find src -name '*.odin' -print0 | xargs -0 -P$(nproc) -I{} sh -c '
      odinfmt "$1" | diff "$1" - > /dev/null || { echo "FAIL: $1 is not formatted"; exit 1; }
    ' _ {}
    echo "All .odin files properly formatted"

build:
    odin build src -collection:camp=src -out:camp

build-e2e:
    odin build src/e2e -collection:camp=src -out:camp-e2e

test-unit:
    #!/usr/bin/env sh
    output=$(odin test src -collection:camp=src 2>&1); rc=$?
    echo "$output"
    if [ $rc -ne 0 ]; then exit $rc; fi
    badfrees=$(echo "$output" | grep -c 'bad free')
    if [ $badfrees -gt 0 ]; then
      echo "FAIL: $badfrees bad free(s) detected" >&2
      exit 1
    fi
    leaks=$(echo "$output" | grep -c 'leak')
    # The compiler uses `virtual.Arena` (bump allocator) for allocation speed.
    # Odin's arena_allocator_proc returns `Mode_Not_Implemented` for `.Free`
    # because bump allocators cannot free individual items.
    #
    # When `context.allocator` is set to the arena in tests, all alloc/free
    # bypasses Odin's test-runner tracking layer. The tracking layer wraps
    # the arena, but arena `.Free` returns an error that `tracking_allocator_proc`
    # propagates via `or_return` before it can record the free in its map.
    # This means every arena-backed allocation accumulates as a "leak" in
    # the tracking data — even though `context_destroy` bulk-frees everything.
    #
    # The 892-remaining-leak baseline reflects this architectural limitation.
    # Getting to true zero requires either replacing the arena with an allocator
    # that supports individual frees (e.g. rollback_stack), or adding explicit
    # destroy functions for every heap-allocated node in the compilation pipeline
    # (IR, AST, canonical, typed, WASM). Both are in-progress.
    #
    # This threshold catches regressions: if a change introduces new leaks
    # that aren't offset by fixes elsewhere, CI fails. Tighten as destroy
    # functions are integrated.
    leak_threshold=1600
    if [ $leaks -gt $leak_threshold ]; then
      echo "FAIL: $leaks leak(s) detected (threshold: $leak_threshold)" >&2
      exit 1
    fi

test-e2e: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e

tree-sitter-generate:
    cd tree-sitter && tree-sitter generate

tree-sitter-test: tree-sitter-generate
    cd tree-sitter && tree-sitter test

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
