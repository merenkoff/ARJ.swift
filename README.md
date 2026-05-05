# ARJArchive

Swift library for reading ARJ archives.

Current status:

- Parse archive structure and list entries
- Extract stored (uncompressed) entries
- Detect unsupported encrypted/compressed entries via typed errors

## Installation (Swift Package Manager)

Add this package URL to your `Package.swift` dependencies.

## Usage

```swift
import ARJArchive

let archive = try ARJArchive(path: "/path/to/archive.arj")
let entries = try archive.entries()

for entry in entries {
    print(entry.name, entry.compressionMethod, entry.originalSize)
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

- Only `stored` entries are currently extractable.
- Other ARJ methods will throw `ARJError.unsupportedCompressionMethod`.
- Encrypted entries will throw `ARJError.unsupportedEncryptedArchive`.
