import Foundation

/// A header exactly as stored: the basic header, its CRC and the chain of extended headers that follows it.
struct ARJHeaderBlock: Sendable {
    struct ExtendedHeader: Sendable {
        let data: Data
        let storedCRC: UInt32
    }

    /// Basic header bytes from `first_hdr_size` through the comment terminator (zero-based).
    let basicHeader: Data
    let storedCRC: UInt32
    let extendedHeaders: [ExtendedHeader]

    /// Length of the fixed part, clamped to the basic header size for malformed input.
    var fixedSize: Int {
        min(Int(basicHeader[0]), basicHeader.count)
    }

    /// Null-terminated name and comment that follow the fixed part.
    var nameBytes: Data {
        strings.first ?? Data()
    }

    var commentBytes: Data {
        let parts = strings
        return parts.count > 1 ? parts[1] : Data()
    }

    var hasValidCRCs: Bool {
        CRC32.compute(basicHeader) == storedCRC
            && extendedHeaders.allSatisfy { CRC32.compute($0.data) == $0.storedCRC }
    }

    private var strings: [Data] {
        basicHeader.suffix(from: fixedSize)
            .split(separator: 0, maxSplits: 2, omittingEmptySubsequences: false)
            .map { Data($0) }
    }
}

struct ARJParsedEntry: Sendable {
    let entry: ARJEntry
    let header: ARJHeaderBlock
    let dataRange: Range<Int>
    let passwordModifier: UInt8
}

struct ARJParsedMainHeader: Sendable {
    /// Bytes preceding the main header, e.g. a self-extractor stub.
    let prefixLength: Int
    let header: ARJHeaderBlock
    let archiveName: String
    let comment: String?
    let hostOS: ARJHostOS
    let encryptionVersion: UInt8
}

struct ARJParser {
    private let data: Data
    private var cursor: Int = 0

    /// `data` must be zero-based (`startIndex == 0`).
    init(data: Data) {
        self.data = data
    }

    /// Locates and parses the main header, leaving the cursor at the first file header.
    mutating func parseMainHeader() throws -> ARJParsedMainHeader {
        guard data.count >= 4 else { throw ARJError.unexpectedEOF }
        cursor = Self.embeddedMainHeaderOffset(in: data) ?? 0
        let prefixLength = cursor

        guard try readUInt16() == ARJFormat.headerID else {
            throw ARJError.invalidArchiveSignature
        }
        let basicHeaderSize = try readUInt16()
        guard basicHeaderSize >= ARJFormat.minimumFirstHeaderSize,
              basicHeaderSize <= ARJFormat.maximumBasicHeaderSize
        else {
            throw ARJError.invalidHeaderSize(basicHeaderSize)
        }
        cursor -= 4
        guard let header = try readHeaderBlock() else {
            throw ARJError.malformedHeader
        }

        let basic = header.basicHeader
        guard Int(basic[ARJFormat.Offset.firstHeaderSize]) <= basic.count else {
            throw ARJError.malformedHeader
        }
        let comment = ARJFormat.decodeString(header.commentBytes).flatMap { $0.isEmpty ? nil : $0 }
        let encryptionVersion = header.fixedSize > ARJFormat.Offset.encryptionVersion
            ? basic[ARJFormat.Offset.encryptionVersion]
            : 0

        return ARJParsedMainHeader(
            prefixLength: prefixLength,
            header: header,
            archiveName: ARJFormat.decodeString(header.nameBytes) ?? "",
            comment: comment,
            hostOS: ARJHostOS(rawHostOS: basic[ARJFormat.Offset.hostOS]),
            encryptionVersion: encryptionVersion
        )
    }

    /// Parses local file headers up to the end-of-archive marker. Call after `parseMainHeader()`.
    mutating func parseEntries() throws -> [ARJParsedEntry] {
        var result: [ARJParsedEntry] = []
        while let header = try readHeaderBlock() {
            let decoded = try decodeFileHeader(header)
            let dataStart = cursor
            try advance(count: Int(decoded.entry.compressedSize))
            result.append(
                ARJParsedEntry(
                    entry: decoded.entry,
                    header: header,
                    dataRange: dataStart..<cursor,
                    passwordModifier: decoded.passwordModifier
                )
            )
        }
        return result
    }

    /// Finds the main header of an archive embedded after a stub (self-extracting archives).
    /// Returns `nil` when the data starts with a header ID or no valid main header is found.
    static func embeddedMainHeaderOffset(in data: Data) -> Int? {
        if data.count >= 2, data[0] == 0x60, data[1] == 0xEA {
            return nil
        }
        return data.withUnsafeBytes { raw -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            while offset + 4 <= bytes.count {
                defer { offset += 1 }
                guard bytes[offset] == 0x60, bytes[offset + 1] == 0xEA else { continue }
                let size = Int(bytes[offset + 2]) | (Int(bytes[offset + 3]) << 8)
                let start = offset + 4
                let end = start + size
                guard size >= ARJFormat.minimumFirstHeaderSize,
                      size <= ARJFormat.maximumBasicHeaderSize,
                      end + 4 <= bytes.count,
                      bytes[start + ARJFormat.Offset.fileType] == ARJFormat.FileType.mainHeader
                else { continue }
                let storedCRC = UInt32(bytes[end])
                    | (UInt32(bytes[end + 1]) << 8)
                    | (UInt32(bytes[end + 2]) << 16)
                    | (UInt32(bytes[end + 3]) << 24)
                if CRC32.compute(UnsafeBufferPointer(rebasing: bytes[start..<end])) == storedCRC {
                    return offset
                }
            }
            return nil
        }
    }

    /// Reads one header block; returns `nil` at the end-of-archive marker.
    private mutating func readHeaderBlock() throws -> ARJHeaderBlock? {
        guard try readUInt16() == ARJFormat.headerID else {
            throw ARJError.invalidArchiveSignature
        }
        let basicHeaderSize = try readUInt16()
        if basicHeaderSize == 0 {
            return nil
        }
        guard basicHeaderSize <= ARJFormat.maximumBasicHeaderSize else {
            throw ARJError.invalidHeaderSize(basicHeaderSize)
        }
        let basicHeader = try readBytes(count: Int(basicHeaderSize))
        let storedCRC = try readUInt32()

        var extendedHeaders: [ARJHeaderBlock.ExtendedHeader] = []
        while true {
            let size = try readUInt16()
            if size == 0 { break }
            let extended = try readBytes(count: Int(size))
            extendedHeaders.append(.init(data: extended, storedCRC: try readUInt32()))
        }
        return ARJHeaderBlock(basicHeader: basicHeader, storedCRC: storedCRC, extendedHeaders: extendedHeaders)
    }

    private struct DecodedFileHeader {
        let entry: ARJEntry
        let passwordModifier: UInt8
    }

    private func decodeFileHeader(_ header: ARJHeaderBlock) throws -> DecodedFileHeader {
        let basic = header.basicHeader
        guard basic.count >= ARJFormat.minimumFirstHeaderSize,
              Int(basic[ARJFormat.Offset.firstHeaderSize]) <= basic.count
        else {
            throw ARJError.malformedHeader
        }
        guard let name = ARJFormat.decodeString(header.nameBytes) else {
            throw ARJError.malformedHeader
        }

        let flags = basic[ARJFormat.Offset.flags]
        let fileType = basic[ARJFormat.Offset.fileType]
        let hostOS = ARJHostOS(rawHostOS: basic[ARJFormat.Offset.hostOS])
        let comment = ARJFormat.decodeString(header.commentBytes).flatMap { $0.isEmpty ? nil : $0 }

        let entry = ARJEntry(
            name: name,
            compressedSize: basic.littleEndianUInt32(at: ARJFormat.Offset.compressedSize),
            originalSize: basic.littleEndianUInt32(at: ARJFormat.Offset.originalSize),
            compressionMethod: ARJCompressionMethod(rawMethod: basic[ARJFormat.Offset.method]),
            fileType: fileType,
            hostOS: hostOS,
            crc32: basic.littleEndianUInt32(at: ARJFormat.Offset.fileCRC),
            isEncrypted: (flags & ARJFormat.Flag.garbled) != 0,
            modified: ARJTimestamp.decode(basic.littleEndianUInt32(at: ARJFormat.Offset.fileModified), hostOS: hostOS),
            isDirectory: fileType == ARJFormat.FileType.directory || name.hasSuffix("/") || name.hasSuffix("\\"),
            comment: comment,
            fileMode: basic.littleEndianUInt16(at: ARJFormat.Offset.fileMode)
        )
        return DecodedFileHeader(entry: entry, passwordModifier: basic[ARJFormat.Offset.passwordModifier])
    }

    private mutating func readUInt16() throws -> UInt16 {
        try readBytes(count: 2).littleEndianUInt16(at: 0)
    }

    private mutating func readUInt32() throws -> UInt32 {
        try readBytes(count: 4).littleEndianUInt32(at: 0)
    }

    private mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0 else { throw ARJError.malformedHeader }
        guard cursor + count <= data.count else { throw ARJError.unexpectedEOF }
        defer { cursor += count }
        return data.subdata(in: cursor..<(cursor + count))
    }

    private mutating func advance(count: Int) throws {
        guard count >= 0 else { throw ARJError.malformedHeader }
        guard cursor + count <= data.count else { throw ARJError.unexpectedEOF }
        cursor += count
    }
}
