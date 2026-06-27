---
# camp-dxqh
title: 'Process! codegen handler: bridge spawn!/wait!/read!/write!/close!/run! to WASIX proc_spawn/wait/fd_read/fd_write/fd_close'
status: completed
type: task
priority: high
created_at: 2026-06-14T19:14:55Z
updated_at: 2026-06-14T19:14:55Z
---

## Revised Design (streaming included)

### Effect operations to wire:
- spawn!(Command) → ProcessHandle — WASIX proc_spawn, returns handle with optional pipe fds
- wait!(ProcessHandle) → I32 — WASIX wait, blocks until exit
- read!(Handle) → Bytes — WASI fd_read on pipe fd
- write!(Handle, Bytes) — WASI fd_write on pipe fd
- close!(Handle) — WASI fd_close on pipe fd
- run!(Command) → ProcessResult — convenience: spawn+wait+capture all

### Types:
- Handle: opaque fd wrapper (heap-allocated i32)
- ProcessHandle: { pid, stdin?, stdout?, stderr? } — Option(Handle) based on StdioMode (Capture → Some)
- ProcessResult: { exit_code, stdout, stderr } — all Bytes, use Process.to_str() for Str
- ProcessError: [SpawnFailed(Str) | TimedOut | IoError(Str)]
- StdioMode: [Inherit | Capture | Null]

### WASIX module: wasix_snapshot_preview1
- Imports already defined in emit_wasix_imports (conditional)

### Key behaviors:
- wait! auto-closes all pipe handles before returning (POSIX: pipes dead after child exits)
- close! is for early cleanup only (e.g., signal EOF on stdin)
- run! respects StdioMode: Capture → output captured, Inherit/Null → empty Bytes
- ProcessResult uses Bytes (consistent with read!). to_str() helper decodes to Str.
