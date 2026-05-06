## ARJ.swift 1.0

First public release of `ARJ.swift` — a Swift library for reading ARJ archives.

### What’s already working

- Parses ARJ archive structure and lists entries with metadata
- Reads archive comments from the main header
- Extracts `stored` (uncompressed) files
- Supports compression methods `0...4` via embedded C decoder
- Supports XOR-protected entries (with `password`) and validates output via CRC32
- Provides typed errors for:
  - missing password
  - wrong password
  - unsupported features

### API conveniences

- Extract by `entry` or by filename
- Soft lookup for stored entries without throwing (`extractFirstStored(...)`)
- `extractAllStored()` for quickly collecting all available stored files

### Current limitations

- GOST-encrypted archives are not yet supported
- Compression methods outside `0...4` return `unsupportedCompressionMethod`

### License

This project is licensed under the **OwnNet Source License 1.0**.  
See `LICENSE` for full terms.  
Open Internet 4.0 manifesto: [https://own-net.com/](https://own-net.com/)
