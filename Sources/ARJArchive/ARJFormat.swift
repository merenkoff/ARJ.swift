import Foundation

/// On-disk layout constants shared by the reader and the writer.
enum ARJFormat {
    static let headerID: UInt16 = 0xEA60
    static let minimumFirstHeaderSize = 30
    static let maximumBasicHeaderSize = 2600

    /// Version written into new headers (ARJ 2.50+ layout) and the minimum version needed to extract.
    static let archiverVersion: UInt8 = 11
    static let minimumExtractVersion: UInt8 = 1

    /// Fixed part of the main header written for new archives: 30 standard bytes + 4 bytes of extra data.
    static let mainHeaderFixedSize = 34
    /// Fixed part of the local file header written for new entries.
    static let fileHeaderFixedSize = 30

    enum FileType {
        static let binary: UInt8 = 0
        static let text: UInt8 = 1
        static let mainHeader: UInt8 = 2
        static let directory: UInt8 = 3
        static let volumeLabel: UInt8 = 4
        static let chapterLabel: UInt8 = 5
    }

    enum Flag {
        /// File header: payload is garbled (XOR password). Main header: archive contains garbled files.
        static let garbled: UInt8 = 0x01
        /// Main header only.
        static let oldSecured: UInt8 = 0x02
        static let volume: UInt8 = 0x04
        static let extFile: UInt8 = 0x08
        /// Path separators were translated to `/`.
        static let pathSymbol: UInt8 = 0x10
        static let backup: UInt8 = 0x20
        /// Main header only.
        static let secured: UInt8 = 0x40
    }

    /// Byte offsets inside the fixed part of a basic header.
    enum Offset {
        static let firstHeaderSize = 0
        static let archiverVersion = 1
        static let minimumVersion = 2
        static let hostOS = 3
        static let flags = 4
        static let method = 5
        static let securityVersion = 5
        static let fileType = 6
        static let passwordModifier = 7
        static let fileModified = 8
        static let archiveCreated = 8
        static let archiveModified = 12
        static let compressedSize = 12
        static let archiveSize = 16
        static let originalSize = 16
        static let securityEnvelopePosition = 20
        static let fileCRC = 20
        static let filespecPosition = 24
        static let securityEnvelopeLength = 26
        static let fileMode = 26
        static let encryptionVersion = 28
    }

    /// Main header encryption versions 0 and 1 denote the classic XOR "garble"; 2+ are GOST variants.
    static let firstUnsupportedEncryptionVersion: UInt8 = 2
    static let standardEncryptionVersion: UInt8 = 1

    static func decodeString<Bytes: Sequence>(_ bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        let data = Data(bytes)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Converts an archive path to the `/`-separated form stored in headers, dropping empty and `.` components.
    static func normalizedEntryPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .joined(separator: "/")
    }
}

/// ARJ stores modification times as MS-DOS date/time for most hosts and as Unix time for Unix-like hosts.
enum ARJTimestamp {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func usesUnixTime(_ hostOS: ARJHostOS) -> Bool {
        hostOS == .unix || hostOS == .next
    }

    static func decode(_ raw: UInt32, hostOS: ARJHostOS) -> Date {
        usesUnixTime(hostOS) ? Date(timeIntervalSince1970: TimeInterval(raw)) : decodeDOS(raw)
    }

    static func encode(_ date: Date, hostOS: ARJHostOS) -> UInt32 {
        usesUnixTime(hostOS) ? encodeUnix(date) : encodeDOS(date)
    }

    /// DOS timestamps carry no time zone; ARJ.swift reads and writes them as UTC.
    static func decodeDOS(_ raw: UInt32) -> Date {
        if raw == 0 {
            return Date(timeIntervalSince1970: 0)
        }
        let timeBits = raw & 0xFFFF
        let dateBits = (raw >> 16) & 0xFFFF

        var components = DateComponents()
        components.year = Int((dateBits >> 9) & 0x7F) + 1980
        let month = Int((dateBits >> 5) & 0x0F)
        let day = Int(dateBits & 0x1F)
        components.month = month == 0 ? 1 : month
        components.day = day == 0 ? 1 : day
        components.hour = Int((timeBits >> 11) & 0x1F)
        components.minute = Int((timeBits >> 5) & 0x3F)
        components.second = Int((timeBits & 0x1F) * 2)
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return utcCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Encodes `date` with 2-second precision, clamped to the DOS range 1980-01-01...2107-12-31.
    static func encodeDOS(_ date: Date) -> UInt32 {
        let parts = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, year >= 1980 else {
            return (UInt32((1 << 5) | 1) << 16)
        }
        guard year <= 2107 else {
            return (UInt32((127 << 9) | (12 << 5) | 31) << 16) | UInt32((23 << 11) | (59 << 5) | 29)
        }
        let dateBits = (UInt32(year - 1980) << 9) | (UInt32(parts.month ?? 1) << 5) | UInt32(parts.day ?? 1)
        let timeBits = (UInt32(parts.hour ?? 0) << 11) | (UInt32(parts.minute ?? 0) << 5) | UInt32((parts.second ?? 0) / 2)
        return (dateBits << 16) | timeBits
    }

    static func encodeUnix(_ date: Date) -> UInt32 {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        if seconds <= 0 { return 0 }
        if seconds >= TimeInterval(UInt32.max) { return UInt32.max }
        return UInt32(seconds)
    }
}

extension Data {
    /// Reads a little-endian value at a zero-based `offset` from `startIndex`.
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

extension Array where Element == UInt8 {
    mutating func setLittleEndian(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    mutating func setLittleEndian(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
