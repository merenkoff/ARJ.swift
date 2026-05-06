import Foundation

struct ARJParsedEntry {
    let entry: ARJEntry
    let dataRange: Range<Int>
    let passwordModifier: UInt8
}

struct ARJArchiveInfo: Sendable, Equatable {
    let archiveName: String
    let comment: String?
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

    mutating func parseArchiveInfo() throws -> ARJArchiveInfo {
        guard data.count >= 4 else { throw ARJError.unexpectedEOF }
        return try parseMainHeader()
    }

    mutating func parseEntriesDetailed() throws -> [ARJParsedEntry] {
        guard data.count >= 4 else { throw ARJError.unexpectedEOF }
        _ = try parseMainHeader()

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

            let parsed = try decodeFileHeader(from: basicHeader)

            let extraHeaderSize = try readUInt16()
            if extraHeaderSize > 0 {
                _ = try readBytes(count: Int(extraHeaderSize))
                _ = try readUInt32() // Extended header CRC.
            }

            let dataStart = cursor
            let dataCount = Int(parsed.entry.compressedSize)
            try advance(count: dataCount)
            let dataEnd = cursor
            result.append(
                ARJParsedEntry(
                    entry: parsed.entry,
                    dataRange: dataStart..<dataEnd,
                    passwordModifier: parsed.passwordModifier
                )
            )
        }

        return result
    }

    private mutating func parseMainHeader() throws -> ARJArchiveInfo {
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

        let stringsData = basicHeader.suffix(from: firstHeaderSize)
        let parts = stringsData.split(separator: 0, omittingEmptySubsequences: false)

        let archiveName: String
        if let first = parts.first, !first.isEmpty {
            archiveName = decodeString(first) ?? ""
        } else {
            archiveName = ""
        }

        var comment: String? = nil
        if parts.count >= 2 {
            let second = parts[parts.index(parts.startIndex, offsetBy: 1)]
            if !second.isEmpty {
                if let decoded = decodeString(second), !decoded.isEmpty {
                    comment = decoded
                }
            }
        }

        let extraHeaderSize = try readUInt16()
        if extraHeaderSize > 0 {
            _ = try readBytes(count: Int(extraHeaderSize))
            _ = try readUInt32()
        }

        return ARJArchiveInfo(archiveName: archiveName, comment: comment)
    }

    private struct DecodedFileHeader {
        let entry: ARJEntry
        let passwordModifier: UInt8
    }

    private func decodeFileHeader(from basicHeader: Data) throws -> DecodedFileHeader {
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
        let hostOSRaw = basicHeader[3]
        let passwordModifier = basicHeader[7]

        let rawTime = readLittleEndianUInt32(in: basicHeader, at: 0x08)
        let compressedSize = readLittleEndianUInt32(in: basicHeader, at: 0x0C)
        let originalSize = readLittleEndianUInt32(in: basicHeader, at: 0x10)
        let crc32 = readLittleEndianUInt32(in: basicHeader, at: 0x14)

        let stringsData = basicHeader.suffix(from: firstHeaderSize)
        let parts = stringsData.split(separator: 0, omittingEmptySubsequences: false)
        guard let first = parts.first else { throw ARJError.malformedHeader }
        guard let name = decodeString(first) else { throw ARJError.malformedHeader }

        let hostOS = ARJHostOS(rawHostOS: hostOSRaw)
        let modified = decodeModifiedDate(rawTime: rawTime, hostOS: hostOS)
        let isDirectory = fileType == 3 || name.hasSuffix("/") || name.hasSuffix("\\")

        let entry = ARJEntry(
            name: name,
            compressedSize: compressedSize,
            originalSize: originalSize,
            compressionMethod: ARJCompressionMethod(rawMethod: method),
            fileType: fileType,
            hostOS: hostOS,
            crc32: crc32,
            isEncrypted: (flags & 0x01) != 0,
            modified: modified,
            isDirectory: isDirectory
        )
        return DecodedFileHeader(entry: entry, passwordModifier: passwordModifier)
    }

    private func decodeModifiedDate(rawTime: UInt32, hostOS: ARJHostOS) -> Date {
        switch hostOS {
        case .unix, .next:
            return Date(timeIntervalSince1970: TimeInterval(rawTime))
        default:
            return decodeDOSDate(rawTime: rawTime)
        }
    }

    private func decodeDOSDate(rawTime: UInt32) -> Date {
        let timeBits = UInt32(rawTime & 0x0000_FFFF)
        let dateBits = UInt32((rawTime >> 16) & 0x0000_FFFF)

        let seconds = Int((timeBits & 0x1F) * 2)
        let minutes = Int((timeBits >> 5) & 0x3F)
        let hour = Int((timeBits >> 11) & 0x1F)
        let day = Int(dateBits & 0x1F)
        let month = Int((dateBits >> 5) & 0x0F)
        let year = Int(((dateBits >> 9) & 0x7F) + 1980)

        if rawTime == 0 {
            return Date(timeIntervalSince1970: 0)
        }

        var components = DateComponents()
        components.year = year
        components.month = month == 0 ? 1 : month
        components.day = day == 0 ? 1 : day
        components.hour = hour
        components.minute = minutes
        components.second = seconds
        components.timeZone = TimeZone(secondsFromGMT: 0)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func decodeString<Bytes: Sequence>(_ bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        let data = Data(bytes)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
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
