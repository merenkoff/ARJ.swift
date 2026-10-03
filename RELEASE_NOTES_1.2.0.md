## ARJ.swift 1.2.0

### Library — write support

- **`ARJWriter`**: create archives and edit existing ones (`init(updating:)`).
  - `addFile(named:data:…)`, `addFile(at:…)`, `addDirectory(named:…)` with per-entry method, password,
    comment, timestamp and file mode; `ExistingEntryPolicy` (`.replace`, `.skip`, `.fail`).
  - `removeEntries(where:)`, `removeEntry(named:)`, `renameEntry(named:to:)`, `archiveName`, `comment`.
  - `makeData()` / `write(to:)` (atomic). Header CRCs are always written correctly.
  - Entries taken over from an existing archive are copied byte for byte: no recompression and no
    password needed to keep, rename or delete encrypted entries. Self-extractor stubs are preserved.
- **Encoder for compression methods 1…4** in the embedded C core. Output is verified by decoding it
  again; data that does not shrink is stored (method 0). Archives are interoperable with ARJ 3.10
  in both directions (all methods, with and without passwords).
- **XOR garbling** of new entries (`password:`), compatible with ARJ `-g`.

### Library — reading

- `ARJEntry.comment` and `ARJEntry.fileMode`.
- `ARJArchive.validateHeaderCRCs()`.
- Chains of extended headers are parsed correctly (previously only one was read).
- Self-extracting archives: the main header is located after an executable stub.
- GOST-encrypted archives (main header encryption version ≥ 2) now throw `unsupportedEncryptedArchive`.
- Headers larger than the ARJ limit of 2600 bytes are rejected as `invalidHeaderSize`.
- The archive is parsed once at initialization instead of on every call.
- `ARJArchive(data:)` accepts `Data` slices.

### Fixes

- Decoder: a corrupted archive could make method 1–3 decoding read outside the dictionary
  buffer; pointers beyond the dictionary are now rejected.
- Decoder: corrupted sizes no longer cause runaway decoding (input over-read is bounded).
- Decoder: removed shared static state, so concurrent extraction from several threads is safe.
- Decoder: blocks with more than 32767 symbols are handled without signed overflow.

### New `ARJError` cases

`fileWriteFailed(path:)`, `entryAlreadyExists(_:)`, `invalidEntryName(_:)`, `headerTooLarge`, `entryTooLarge`.
Exhaustive `switch` statements over `ARJError` need these cases.

### CLI (`arj`)

- `a`, `u`, `f`, `d`, `c -z` now use `ARJWriter`: `-m0`…`-m4` (default `-m1`), `-g` garbles added files,
  `a`/`u` create missing archives, `u`/`f` only replace entries older than the file on disk,
  and `d` no longer needs the password of encrypted archives. Comments are stored ARJ-style
  (LF line endings, trailing newline).
- New commands: `m` (move files into the archive) and `r` (remove paths from names).
- The CLI now builds and runs on Linux.
