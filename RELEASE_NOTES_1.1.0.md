## ARJ.swift 1.1.0

### CLI (`arj` executable)

- New SwiftPM product **`arj`**: macOS console utility with ARJ-style `arj <cmd> [-switches] <archive> [base_dir] [masks…]` workflow.
- **Read commands:** `l`, `v`, `t`, `e`, `x`, `p`, `s`, `w`, `c` (show comment only).
- **Write-related commands** (`a`, `d`, `u`, `f`, `m`, `g`, `r`, `n`, `o`, `b`, `i`, `j`, `k`, `q`, `y`, `ac`, `cc`, `dc`) are registered as **stubs** (exit **2**, clear message).
- ARJ-compatible **exit codes 0…12** where applicable; **SIGINT** → **11**.
- `arj -h` / `arj --help` — overview; `arj <cmd> --help` — per-command long options (after argv preprocessing).

### Library

- **`ARJError.crcMismatch`**: thrown when decompressed/stored payload CRC32 does not match the file header (non-encrypted entries). Previously mismatches were ignored for non-encrypted data.

### Tests

- **`arjTests`**: integration tests invoking the built `arj` binary on existing fixtures.
- Unit test for **CRC mismatch** on a synthetic stored entry.

### License

Licensed under the **OwnNet Source License 1.0**. See `LICENSE`.
