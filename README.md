<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,35:161b22,70:1f6feb,100:58a6ff&height=220&section=header&text=ARJ.swift&fontSize=58&fontColor=ffffff&fontAlignY=38&desc=Modern%20ARJ%20archive%20toolkit%20for%20Swift&descAlignY=60&descSize=18&descColor=c9d1d9&animation=fadeIn" />
  <b>Read · Create · Extract · Inspect · Test · Automate</b>
</p>
<p align="center">
  Native Swift library and ARJ-compatible CLI for working with classic ARJ archives on modern systems.
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/macOS-supported-black?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/Linux-supported-2ea043?style=flat-square&logo=linux" />
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen?style=flat-square" />
  <img src="https://img.shields.io/badge/CLI-ARJ%20compatible-1f6feb?style=flat-square" />
  <img src="https://img.shields.io/badge/License-OwnNet%201.0-8b5cf6?style=flat-square" />
</p>
<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-cli-usage">CLI Usage</a> •
  <a href="#-library-usage">Library Usage</a> •
  <a href="#-testing">Testing</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

---

Why ARJ.swift?

ARJ archives still appear in:

* retro software collections
* DOS backup systems
* abandonware distributions
* industrial software environments
* digital preservation workflows
* legacy archive migrations

ARJ.swift brings native ARJ support to modern Swift environments with:

* clean Swift APIs
* modern CLI ergonomics
* archive inspection tools
* extraction and validation support
* compatibility-focused behavior

---

✨ Features

Archive Support

* ✅ Parse ARJ archive structures (including self-extracting archives)
* ✅ Read archive and per-file comments
* ✅ Compression methods 0...4 — decoding and encoding
* ✅ Create archives and update existing ones (add, replace, delete, rename, comment)
* ✅ CRC32 validation of data and headers
* ✅ XOR-encrypted ("garbled") archives — read and write
* ✅ Typed Swift errors
* ✅ Entry metadata: timestamps, file modes, directories, path normalization
* ✅ Byte-for-byte interoperable with ARJ 3.10

Command-Line Tool

* ✅ List archive contents
* ✅ Verbose archive inspection
* ✅ Extract with path modes
* ✅ Wildcard filtering
* ✅ Search inside archives
* ✅ Integrity testing
* ✅ Password support
* ✅ ARJ-style commands and switches

Developer Experience

* ✅ Swift Package Manager support
* ✅ Structured error handling
* ✅ CLI preprocessing layer
* ✅ Comprehensive tests
* ✅ Cross-platform support
* ✅ Native Swift APIs

---

🏗 Architecture

ARJ.swift consists of multiple layers:

| Component | Description |
|---|---|
|ARJArchive | Native Swift archive API |
|arj | Classic ARJ-compatible CLI frontend |
|Embedded C decoder | Legacy decompression backend |
|Argument preprocessing layer | Normalizes ARJ-style CLI syntax |
|Extraction engine | Handles paths, filters, validation |

---

📦 Installation

Homebrew

```bash
brew install merenkoff/arj/arj
```

Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/merenkoff/ARJ.swift.git", from: "1.0.0")
]
```

Products:

* ARJArchive — Swift library
* arj — command-line executable

Build From Source

```bash
git clone https://github.com/merenkoff/ARJ.swift
cd ARJ.swift
swift build -c release
```

Binary location:

```bash
.build/release/arj
```

---

🖥 CLI Usage

Build & Run

```bash
swift build -c release
.build/release/arj --help
```

---

Listing Archives

```bash
# List archive contents
arj l backup.arj
# Verbose listing
arj v backup.arj
# Exclude files
arj l backup.arj -x*.bak
# Use include list
arj l backup.arj !include.txt
```

---

Extracting Files

```bash
# Extract preserving paths
arj x backup.arj -htout/
# Flat extraction
arj e backup.arj -htout/
# Keep full paths
arj x backup.arj -htout/ -p
# Keep relative paths
arj x backup.arj -htout/ -p1
# Strip all paths
arj x backup.arj -htout/ -e
```

---

Creating & Updating Archives

```bash
# Create (or extend) an archive, method 1 by default
arj a backup.arj docs '*.txt' -r
# Fastest method, garble added files with a password
arj a backup.arj . '*.log' -m4 -gsecret
# Store without compression
arj a backup.arj . data.bin -m0
# Add new files and replace older entries
arj u backup.arj docs '*' -r
# Delete entries (no password needed, other entries are copied as-is)
arj d backup.arj '*.tmp'
# Set the archive comment
arj c backup.arj -zcomment.txt
```

---

Search & Validation

```bash
# Test archive integrity
arj t backup.arj
# Search inside archive
arj w backup.arj "config"
# Extract encrypted files
arj e backup.arj '*.txt' -gsecret
```

---

Advanced Filtering

```bash
# Multiple excludes
arj l archive.arj -x*.bin -x*.tmp
# Extract with filters
arj x archive.arj -ht/tmp -x*.bak -y
```

---

📚 Command Reference

| Command | Status | Description |
|---|---|---|
|l | ✅ | List files |
|v | ✅ | Verbose list |
|t | ✅ | Test integrity |
|e | ✅ | Extract flat |
|x | ✅ | Extract with paths |
|p | ✅ | Print file contents |
|s | ✅ | View with pager |
|w | ✅ | Search text |
|c | ✅ | Show archive comment / set it with -z<file> |
|a | ✅ | Add files (creates the archive if needed) |
|d | ✅ | Delete files |
|u | ✅ | Update files (new and newer) |
|f | ✅ | Freshen files (newer only) |
|m | ✅ | Move files into the archive |
|r | ✅ | Remove paths from names |
|g | 🚧 | Garble/encrypt |
|n | 🚧 | Rename files |
|o | 🚧 | Reorder files |
|b | 🚧 | Batch mode |
|i | 🚧 | Integrity data |
|j | 🚧 | Join split archives |
|k | 🚧 | Backup cleanup |
|q | 🚧 | Recover archive |
|y | 🚧 | Copy/verify archive |

Commands marked 🚧 return exit code 2.

---

⚙️ CLI Features

Filtering

-x<mask>     Exclude by wildcard mask
!<file>      Read masks/files from list

Examples:

-x*.bin
-x*.tmp
-xfile?.dat

Supports:

* wildcard patterns
* multiple exclude masks
* include lists
* comment lines in list files

---

Extraction Modes

Option    Description
-ht<dir>    Target extraction directory
-p    Preserve absolute paths
-p1    Preserve relative paths
-e    Strip all paths
-y    Skip overwrite prompts
-_    Lowercase filenames

---

Other Options

Option    Description
-g<password>    Password for encrypted archives
-w<dir>    Work directory
-i    Disable progress indicator
-o    Prompt before overwrite
-r    Recursive processing
-jt    CRC test mode

---

📖 Library Usage

Open Archive

```swift
import ARJArchive
let archive = try ARJArchive(path: "/path/to/archive.arj")
let entries = try archive.entries()
```

---

List Entries

```swift
for entry in entries {
    print(entry.name, entry.compressionMethod, entry.originalSize)
    print("modified:", entry.modified)
    print("isDirectory:", entry.isDirectory)
    print("normalizedPath:", entry.normalizedPath)
    if let ratio = entry.compressionRatio {
        print("ratio:", ratio)
    }
}
```

---

Read Archive Comment

```swift
if let comment = archive.archiveComment {
    print("archive comment:", comment)
}
```

---

Extract by Entry

```swift
let entry = try archive.entries().first {
    $0.name == "hello.txt"
}
if let entry {
    let data = try archive.extract(entry: entry)
}
```

---

Extract by Name

```swift
let data = try archive.extract(named: "hello.txt")
```

---

Password-Protected Entries

```swift
do {
    let data = try archive.extract(
        named: "secret.txt",
        password: "hunter2"
    )
} catch ARJError.passwordRequired {
    // Entry is encrypted but no password was supplied
} catch ARJError.wrongPassword {
    // Password did not match (CRC32 mismatch on decrypted output)
} catch ARJError.crcMismatch {
    // Decoded data CRC32 did not match the header (non-encrypted entry)
}
```

---

Header Integrity

```swift
// Verifies the CRC32 of every header (payload CRCs are checked by extract).
try archive.validateHeaderCRCs()
```

---

Creating Archives

```swift
var writer = ARJWriter(comment: "Nightly backup")   // host OS .dos by default
try writer.addDirectory(named: "docs")
try writer.addFile(named: "docs/readme.txt", data: readme)                 // method 1 (best)
try writer.addFile(named: "logs/today.log", data: log, method: .compressedFastest)
try writer.addFile(named: "secret.txt", data: secret, password: "hunter2") // XOR garble
try writer.addFile(at: URL(fileURLWithPath: "/etc/hosts"), named: "etc/hosts")
try writer.write(to: URL(fileURLWithPath: "backup.arj"))                    // atomic
let bytes = try writer.makeData()                                          // or keep it in memory
```

Data that does not shrink is stored (method 0) automatically, like ARJ does.

---

Updating Archives

```swift
let archive = try ARJArchive(path: "backup.arj")
var writer = try ARJWriter(updating: archive)

try writer.addFile(named: "docs/readme.txt", data: newReadme)            // replaces in place
try writer.addFile(named: "notes.txt", data: notes, ifExists: .skip)      // or .fail
writer.removeEntries { $0.name.hasSuffix(".tmp") }
try writer.renameEntry(named: "docs/readme.txt", to: "README.txt")
writer.comment = "Updated\n"

try writer.write(to: URL(fileURLWithPath: "backup.arj"))
```

Existing entries are copied byte for byte — they are never decompressed or re-encrypted,
so editing an archive needs no passwords and keeps the original compression.

---

Bulk Extraction

```swift
let files = try archive.extractAllStored()
let maybeData = archive.extractFirstStored(named: "hello.txt")

if let entry = try archive.entries().first {
    let maybeDataByEntry = archive.extractFirstStored(entry: entry)
}
```

---

🧪 Testing

Run all tests:

```bash
swift test
```

Run CLI-specific tests:

```bash
swift test --filter ARJCLITests
```

Build and test:

```bash
swift build && swift test
```

---

Test Coverage

* CLI preprocessing
* Wildcard filtering
* Path handling modes
* Password validation
* Encryption handling
* Exit code compatibility
* Help and usage validation
* Extraction logic
* Encoder round trips for methods 1...4 (including without the stored fallback)
* Archive creation and in-place editing
* Header CRCs, extended headers, self-extracting archives
* Corrupted-archive robustness

---

🚦 Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Warning (e.g. nothing matched) |
| 2 | Fatal error / command not implemented |
| 5 | Cannot write archive |
| 3 | Password error / encryption issues |
| 6 | File not found |
| 7 | File I/O error |
| 9 | Not an ARJ archive |
| 11 | User aborted |

Compatible with classic ARJ errorlevels where applicable.

---

🗺 Roadmap

Completed

* ✅ Stage 1 — Stabilization
* ✅ Stage 2 — CLI correctness & DX
* ✅ Stage 3 — Read-mode feature parity
* ✅ Stage 4 — Write architecture preparation
* ✅ Stage 5 — Write support: encoder for methods 1...4, `ARJWriter`, `a/u/f/m/d/r/c` commands

Next

* 🚧 Multi-volume archives and chapters
* 🚧 Remaining write commands (`g`, `n`, `o`, `y`, ...)

---

📝 Notes

* Compression methods 0...4 are supported via the embedded C codec (decoder and encoder)
* Unsupported compression methods throw ARJError.unsupportedCompressionMethod
* XOR-style encryption is supported via the password: argument
* GOST-encrypted archives are rejected as ARJError.unsupportedEncryptedArchive
* extractAllStored() skips encrypted entries
* DOS timestamps carry no time zone; ARJ.swift reads and writes them as UTC.
  Archives created with `hostOS: .unix` store exact Unix timestamps and permission bits instead
* Header strings are written as UTF-8; names in existing archives keep their original bytes

---

📄 License

<p align="center">
Licensed under the OwnNet Source License 1.0. See LICENSE for details.<br>
Open Internet 4.0 manifesto: https://own-net.com/
</p>

---

<p align="center">
  Built with ♥ by <a href="https://github.com/merenkoff">merenkoff</a>
</p>
<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:58a6ff,50:1f6feb,100:0d1117&height=120&section=footer" />
</p>
