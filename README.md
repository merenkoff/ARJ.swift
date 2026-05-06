# ARJ.swift
## ARJArchive

Swift library for reading ARJ archives.

Current status:

- Parse archive structure and list entries (with metadata: modified date, directory flag, normalized path, compression ratio)
- Read archive comment from the main header
- Extract stored (uncompressed) entries
- Decompress methods 1...4 via embedded C decoder
- Decrypt XOR-encrypted entries when a password is supplied
- Typed errors for missing/wrong password and unsupported features
- CRC mismatch on decoded (non-encrypted) payloads surfaces as `ARJError.crcMismatch`

## Command-line tool (`arj`, macOS)

The package builds an **ARJ-style** executable (`arj`) that wraps the library. It accepts classic one-letter commands and many common ARJ switches; internally these are normalized and parsed with [swift-argument-parser](https://github.com/apple/swift-argument-parser).

Build and run:

```bash
swift build -c release
.build/release/arj --help          # overview
.build/release/arj l archive.arj   # list
.build/release/arj l --help        # long options for `l` (after preprocessing)
```

Examples:

```bash
arj l archive.arj
arj v archive.arj
arj t archive.arj
arj x archive.arj -htout/
arj e archive.arj '*.txt' -gsecret
arj w archive.arj 'search text'
```

| Command | Status |
|--------|--------|
| **l** list, **v** verbose list, **t** test, **e** extract (flat), **x** extract (paths), **p** print, **s** sample, **w** search, **c** comment (show) | Implemented (read-only) |
| **a** add, **d** delete, **u** update, **f** freshen, **m** move, **g** garble, **r** remove-paths, **n** rename, **o** order, **b** batch, **i** integrity, **j** join, **k** backup, **q** recover, **y** copy, **ac**/**cc**/**dc** chapters | Stubs (exit code 2, message explains write support is pending) |
| **c** with **-z** (set comment file) | Stub (write) |

Process exit codes **0…12** follow classic ARJ errorlevels where applicable.

## Installation (Swift Package Manager)

Add this package URL to your `Package.swift` dependencies. The library product is `ARJArchive`; the executable product is `arj`.

## Usage

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let entries = try archive.entries()

for entry in entries {
    print(entry.name, entry.compressionMethod, entry.originalSize)
    print("modified:", entry.modified)
    print("isDirectory:", entry.isDirectory)
    print("normalizedPath:", entry.normalizedPath)
    if let ratio = entry.compressionRatio {
        print("ratio:", ratio)
    }
}

if let comment = archive.archiveComment {
    print("archive comment:", comment)
}
```

Extract by entry:

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let entry = try archive.entries().first { $0.name == "hello.txt" }
if let entry {
    let data = try archive.extract(entry: entry)
    // Use file data.
}
```

Extract by name:

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let data = try archive.extract(named: "hello.txt")
```

Extract an encrypted entry with a password:

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")

do {
    let data = try archive.extract(named: "secret.txt", password: "hunter2")
    // Use decrypted data.
} catch ARJError.passwordRequired {
    // Entry is encrypted but no password was supplied.
} catch ARJError.wrongPassword {
    // Password did not match (CRC32 of decrypted output mismatched).
} catch ARJError.crcMismatch {
    // Decoded data CRC32 did not match the header (non-encrypted entry).
}
```

Extract all stored entries:

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let files = try archive.extractAllStored()
// files["name.ext"] -> Data
```

Soft lookup (no throw):

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let maybeData = archive.extractFirstStored(named: "hello.txt")

if let entry = try archive.entries().first {
    let maybeDataByEntry = archive.extractFirstStored(entry: entry)
}
```

## Notes

- Compression methods 0...4 are supported via the bundled C decoder.
- Methods outside that range throw `ARJError.unsupportedCompressionMethod`.
- XOR-style password protection is supported via the `password:` argument on
  `extract(entry:password:)` / `extract(named:password:)`. CRC32 mismatch on a
  decrypted payload surfaces as `ARJError.wrongPassword`.
- GOST-encrypted archives are still rejected as `ARJError.unsupportedEncryptedArchive`.
- `extractAllStored()` and `extractFirstStored(...)` skip encrypted entries.

## License

This project is licensed under the OwnNet Source License 1.0. See `LICENSE`.
For the Open Internet 4.0 manifesto, visit https://own-net.com/.
