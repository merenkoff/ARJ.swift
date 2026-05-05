import Foundation

struct ARJParsedEntry {
    let entry: ARJEntry
    let dataRange: Range<Int>
}

struct ARJParser {
    private static let headerID: UInt16 = 0xEA60
    private static let firstHeaderMinSize = 30

    private let data: Data
    private var cursor: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func parseEntries() throws -> [ARJEntry] {
        try parseEntriesDetailed().map(\.entry)
    }

    mutating func parseEntriesDetailed() throws -> [ARJParsedEntry] {
        guard data.count >= 4 else { throw ARJError.unexpectedEOF }
        try parseMainHeader()

        var result: [ARJParsedEntry] = []
        while true {
            let marker = try readUInt16()
            if marker != Self.headerID {
                throw ARJError.invalidArchiveSignature
            }

            let basicHeaderSize = try readUInt16()
            if basicHeaderSize == 0 {
                break // End-of-archive marker.
            }

            let basicHeader = try readBytes(count: Int(basicHeaderSize))
            _ = try readUInt32() // Header CRC (not validated yet).

            let entry = try decodeFileHeader(from: basicHeader)

            let extraHeaderSize = try readUInt16()
            if extraHeaderSize > 0 {
                _ = try readBytes(count: Int(extraHeaderSize))
                _ = try readUInt32() // Extended header CRC.
            }

            let dataStart = cursor
            let dataCount = Int(entry.compressedSize)
            try advance(count: dataCount)
            let dataEnd = cursor
            result.append(ARJParsedEntry(entry: entry, dataRange: dataStart..<dataEnd))
        }

        return result
    }

    private mutating func parseMainHeader() throws {
        let marker = try readUInt16()
        guard marker == Self.headerID else {
            throw ARJError.invalidArchiveSignature
        }

        let basicHeaderSize = try readUInt16()
        if basicHeaderSize == 0 || basicHeaderSize < Self.firstHeaderMinSize {
            throw ARJError.invalidHeaderSize(basicHeaderSize)
        }

        let basicHeader = try readBytes(count: Int(basicHeaderSize))
        _ = try readUInt32() // Header CRC (reserved for strict validation phase).

        guard basicHeader.count >= Self.firstHeaderMinSize else {
            throw ARJError.malformedHeader
        }

        let firstHeaderSize = Int(basicHeader[0])
        guard firstHeaderSize <= basicHeader.count else {
            throw ARJError.malformedHeader
        }

        let extraHeaderSize = try readUInt16()
        if extraHeaderSize > 0 {
            _ = try readBytes(count: Int(extraHeaderSize))
            _ = try readUInt32()
        }
    }

    private func decodeFileHeader(from basicHeader: Data) throws -> ARJEntry {
        guard basicHeader.count >= Self.firstHeaderMinSize else {
            throw ARJError.malformedHeader
        }

        let firstHeaderSize = Int(basicHeader[0])
        guard firstHeaderSize <= basicHeader.count else {
            throw ARJError.malformedHeader
        }

        let flags = basicHeader[4]
        let method = basicHeader[5]
        let fileType = basicHeader[6]
        let hostOS = basicHeader[3]

        let compressedSize = readLittleEndianUInt32(in: basicHeader, at: 0x0C)
        let originalSize = readLittleEndianUInt32(in: basicHeader, at: 0x10)
        let crc32 = readLittleEndianUInt32(in: basicHeader, at: 0x14)

        let stringsData = basicHeader.suffix(from: firstHeaderSize)
        let parts = stringsData.split(separator: 0, omittingEmptySubsequences: false)
        guard let first = parts.first else { throw ARJError.malformedHeader }
        guard let name = String(data: first, encoding: .utf8) ?? String(data: first, encoding: .isoLatin1) else {
            throw ARJError.malformedHeader
        }

        return ARJEntry(
            name: name,
            compressedSize: compressedSize,
            originalSize: originalSize,
            compressionMethod: ARJCompressionMethod(rawMethod: method),
            fileType: fileType,
            hostOS: ARJHostOS(rawHostOS: hostOS),
            crc32: crc32,
            isEncrypted: (flags & 0x01) != 0
        )
    }

    private func readLittleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
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
