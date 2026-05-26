{ pkgs, ... }:

let
  unit_tests = ''
    run_test() { echo "  [$1]"; odin test "$1" -collection:camp=src && echo "  PASS $1" || echo "  FAIL $1"; }
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
  '';

  check_fmt_odin = ''
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
  '';

  check_fmt_camp = ''
    ./camp fmt --check stdlib/ tests/e2e/
  '';
in
{
  packages = [
    pkgs.odin
    pkgs.ols
    pkgs.tree-sitter
  ];

  git-hooks.hooks = {
    test = {
      enable = true;
      name = "devenv test";
      entry = "devenv test";
      pass_filenames = false;
      stages = [ "push" ];
      language = "system";
    };
  };

  tasks = {
    "build:compiler" = {
      description = "Build the Camp compiler";
      exec = "odin build src -collection:camp=src -out:camp";
    };

    "build:e2e" = {
      description = "Build the E2E test runner";
      exec = "odin build src/e2e -collection:camp=src -out:camp-e2e";
    };

    "test:unit" = {
      description = "Run all unit tests (Odin test)";
      exec = unit_tests;
    };

    "test:e2e" = {
      description = "Run E2E tests";
      after = [ "build:compiler" "build:e2e" ];
      exec = ''CAMP_BIN="$PWD/camp" ./camp-e2e'';
    };

    "fmt:check-odin" = {
      description = "Check .odin file formatting";
      exec = check_fmt_odin;
    };

    "fmt:check-camp" = {
      description = "Check .camp file formatting";
      after = [ "build:compiler" ];
      exec = check_fmt_camp;
    };

    "fmt:odin" = {
      description = "Format all .odin files in src/";
      exec = "find src -name '*.odin' -exec odinfmt -w {} +";
    };

    "fmt:camp" = {
      description = "Format all .camp files";
      after = [ "build:compiler" ];
      exec = "./camp fmt";
    };

    "tree-sitter:generate" = {
      description = "Generate the tree-sitter parser";
      exec = "tree-sitter generate";
      cwd = "tree-sitter";
    };

    "tree-sitter:test" = {
      description = "Run tree-sitter parser tests";
      after = [ "tree-sitter:generate" ];
      exec = "tree-sitter test";
      cwd = "tree-sitter";
    };

    "tree-sitter:validate" = {
      description = "Validate all .camp files parse without errors";
      after = [ "tree-sitter:generate" ];
      exec = ''
        set -euo pipefail
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
      '';
    };

    "update:snapshots" = {
      description = "Update E2E test snapshots";
      after = [ "build:compiler" "build:e2e" ];
      exec = ''CAMP_BIN="$PWD/camp" ./camp-e2e --update'';
    };

    "misc:clean" = {
      description = "Clean build/test artifacts";
      exec = ''
        git clean -fdX tests/e2e/
        rm -f /tmp/camp-cmd-stdout-* /tmp/camp-cmd-stderr-* /tmp/camp-e2e-*
      '';
    };
  };

  enterTest = builtins.concatStringsSep "\n" [
    "set -uo pipefail"
    ""
    "echo '=== Unit Tests ==='"
    unit_tests
    ""
    "echo '=== Odin Format Check ==='"
    check_fmt_odin
    ""
    "echo '=== Build ==='"
    "odin build src -collection:camp=src -out:camp"
    "odin build src/e2e -collection:camp=src -out:camp-e2e"
    ""
    "echo '=== Camp Format Check ==='"
    check_fmt_camp
    ""
    "echo '=== E2E Tests ==='"
    ''CAMP_BIN="$PWD/camp" ./camp-e2e''
    ""
    "echo '=== Tree-Sitter ==='"
    "(cd tree-sitter && tree-sitter generate)"
    "(cd tree-sitter && tree-sitter test)"
    ''
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
    ''
    ""
    "echo '=== All Checks Passed ==='"
  ];
}
