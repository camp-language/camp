---
# camp-vwcv
title: e2e harness fails to create /tmp/camp-e2e test dirs in sandboxed environments (os.make_directory_all Permission_Denied)
status: todo
type: bug
priority: high
created_at: 2026-06-21T03:00:00Z
updated_at: 2026-06-27T23:21:00Z
---

## Symptom

In this development sandbox, `./camp-e2e` reports `setup: could not copy test directory: Not_Exist` for ALL 177 e2e tests. Root cause: `os.make_directory_all("/tmp/camp-e2e/<cat>/<name>/src")` (src/e2e/runner.odin:127 and :180) returns **Permission_Denied**, even though `os.exists(path)` is true and a shell `mkdir -p` of the same path succeeds. Consequently `copy_dir_recursive` → `os.copy_file` fails with Not_Exist (destination parent dir absent), so every test fails at setup.

A standalone Odin repro of `os.make_directory_all("/tmp/camp-e2e/.../src")` reproduces `Permission_Denied`, while `mkdir -p` from the shell works. The pre-existing `expected.toml` snapshots contain `/tmp/camp-e2e/...` paths, proving the harness worked in some prior environment.

## Workaround used in camp-jrga

Pre-create the `/tmp/camp-e2e/<category>/<name>/src` directory tree with a shell loop BEFORE running `./camp-e2e`:
```
rm -rf /tmp/camp-e2e
find tests/e2e -mindepth 2 -maxdepth 2 -type d ! -name '.*' | \
  while read d; do mkdir -p "/tmp/camp-e2e/${d#tests/e2e/}/src"; done
CAMP_BIN="$(pwd)/camp" ./camp-e2e
```
When the dest dirs already exist, `make_directory_all`'s Permission_Denied is ignored (its return value is not checked at runner.odin:127 and :180) and `os.copy_file` succeeds.

## Real fix direction

- Check the return value of `os.make_directory_all` at src/e2e/runner.odin:127 and :180 and surface a clear error (currently silently ignored).
- Investigate why `os.make_directory_all` returns Permission_Denied in this sandbox for `/tmp/camp-e2e/...` when shell `mkdir -p` works — possibly an Odin `core:os` `make_directory_all` path-component stat issue, or a sandbox syscall filter on `mkdirat`. May be environment-specific and not reproducible on the project owner's machine.

## Scope note

This is an ENVIRONMENT issue, not a compiler bug. It blocks running the e2e harness locally in this sandbox but does not affect the tests themselves (which pass once the tmp dirs are pre-created) or the compiler. Recorded as a bean so the workaround + investigation are not lost. camp-jrga's test rewrites were verified using the pre-create workaround.

## Files

- src/e2e/runner.odin:127 (copy_dir_recursive — `os.make_directory_all(dst)` return ignored)
- src/e2e/runner.odin:180 (run_test setup — `os.make_directory_all(tmp_base)` return ignored)
