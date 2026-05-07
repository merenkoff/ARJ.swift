<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:1a1a2e,100:0f3460&height=180&section=header&text=ARJ.swift&fontSize=56&fontColor=58a6ff&fontAlignY=38&desc=Swift%20library%20for%20reading%20ARJ%20archives&descAlignY=58&descSize=16&descColor=8b949e&animation=fadeIn" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-lightgrey?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/License-OwnNet%201.0-blue?style=flat-square" />
  <img src="https://img.shields.io/github/stars/merenkoff/ARJ.swift?style=flat-square&color=58a6ff" />
</p>

<p align="center">
  <a href="#-installation">Installation</a> &nbsp;·&nbsp;
  <a href="#-library-usage">Library Usage</a> &nbsp;·&nbsp;
  <a href="#%EF%B8%8F-command-line-tool">CLI Tool</a> &nbsp;·&nbsp;
  <a href="#-notes">Notes</a>
</p>

---

## What is ARJ.swift?

A Swift library for reading and extracting **ARJ archives** — the classic compression format from the DOS era. Includes a command-line tool (`arj`) for macOS.

```
Parse · List · Extract · Decompress · Decrypt
```

### ✅ Current status

| Feature | Status |
|---|---|
| Parse archive structure & list entries | ✅ |
| Archive comment from main header | ✅ |
| Extract stored (uncompressed) entries | ✅ |
| Decompress methods 1…4 via C decoder | ✅ |
| XOR-encrypted entries (password) | ✅ |
| Typed errors (missing/wrong password, unsupported) | ✅ |
| CRC mismatch on decoded payloads | ✅ |
| Write operations (add, delete, update…) | 🚧 Stubs |

---

## 📦 Installation

### Homebrew (prebuilt CLI)

```bash
brew install merenkoff/arj/arj
```

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/merenkoff/ARJ.swift.git", from: "1.0.0")
]
```

The library product is `ARJArchive`; the executable product is `arj`.

---

## 📖 Library Usage

### Basic — list entries

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

### Extract by entry or name

```swift
// By entry
let entry = try archive.entries().first { $0.name == "hello.txt" }
if let entry {
    let data = try archive.extract(entry: entry)
}

// By name
let data = try archive.extract(named: "hello.txt")
```

### Extract encrypted entries

```swift
do {
    let data = try archive.extract(named: "secret.txt", password: "hunter2")
} catch ARJError.passwordRequired {
    // Entry is encrypted but no password was supplied
} catch ARJError.wrongPassword {
    // Password did not match (CRC32 mismatch on decrypted output)
} catch ARJError.crcMismatch {
    // Decoded data CRC32 did not match the header (non-encrypted entry)
}
```

### Bulk extraction

```swift
// Extract all stored entries
let files = try archive.extractAllStored()
// files["name.ext"] -> Data

// Soft lookup — no throw
let maybeData = archive.extractFirstStored(named: "hello.txt")

if let entry = try archive.entries().first {
    let maybeDataByEntry = archive.extractFirstStored(entry: entry)
}
```

---

## 🖥️ Command-line tool

The package builds an **ARJ-style** executable (`arj`) that wraps the library. It accepts classic one-letter commands and many common ARJ switches, parsed internally with [swift-argument-parser](https://github.com/apple/swift-argument-parser).

```bash
swift build -c release
.build/release/arj --help          # overview
.build/release/arj l archive.arj   # list
.build/release/arj l --help        # long options for `l`
```

### Examples

```bash
arj l archive.arj                  # list entries
arj v archive.arj                  # verbose list
arj t archive.arj                  # test integrity
arj x archive.arj -htout/          # extract with paths
arj e archive.arj '*.txt' -gsecret # extract with password
arj w archive.arj 'search text'    # search inside archive
```

### Supported commands

| Command | Status |
|---|---|
| `l` list · `v` verbose list · `t` test · `e` extract (flat) · `x` extract (paths) · `p` print · `s` sample · `w` search · `c` comment | ✅ Implemented |
| `a` add · `d` delete · `u` update · `f` freshen · `m` move and others | 🚧 Stubs (exit code 2) |

Process exit codes **0…12** follow classic ARJ errorlevels where applicable.

---

## 📝 Notes

- Compression methods **0…4** are supported via the bundled C decoder
- Methods outside that range throw `ARJError.unsupportedCompressionMethod`
- **XOR-style** password protection is supported via the `password:` argument
- **GOST-encrypted** archives are rejected as `ARJError.unsupportedEncryptedArchive`
- `extractAllStored()` and `extractFirstStored(...)` skip encrypted entries

---

## License

Licensed under the **OwnNet Source License 1.0**. See `LICENSE` for details.  
For the Open Internet 4.0 manifesto, visit [own-net.com](https://own-net.com/).

---

<p align="center">
  Made with ♥ by <a href="https://github.com/merenkoff">merenkoff</a>
</p>

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f3460,50:1a1a2e,100:0d1117&height=100&section=footer" />
</p>
