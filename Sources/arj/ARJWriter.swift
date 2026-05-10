import ARJArchive
import Foundation

struct ARJWriterOptions {
    var compressionMethod: Int?
    var replaceExistingEntries: Bool
}

struct ARJAddInput {
    var sourceURL: URL
    var archivePath: String
}

struct ARJDeleteSelector {
    var masks: [String]
    var excludes: [String]
}

enum ARJWriterChange {
    case add([ARJAddInput])
    case delete(ARJDeleteSelector)
    case setArchiveComment(String?)
}

struct ARJWriterResult {
    var entriesAdded: Int
    var entriesReplaced: Int
    var entriesSkipped: Int
    var entriesDeleted: Int
    var commentChanged: Bool
}

enum ARJWriter {
    static func apply(
        inputArchivePath: String,
        outputArchivePath: String,
        changes: [ARJWriterChange],
        password: String?,
        options: ARJWriterOptions
    ) throws -> ARJWriterResult {
        if let method = options.compressionMethod, method != 0 {
            throw ARJCLIError.exit(.fatalError, message: "write mode currently supports only -m0")
        }

        let archive = try ARJArchive(path: inputArchivePath)
        let entries = try archive.entries()

        var snapshot = try entries
            .filter { !$0.isDirectory }
            .map { entry in
                StoredEntry(
                    name: entry.normalizedPath,
                    data: try archive.extract(entry: entry, password: password)
                )
            }
        var comment = archive.archiveComment

        var added = 0
        var replaced = 0
        var skipped = 0
        var deleted = 0
        var commentChanged = false

        for change in changes {
            switch change {
            case let .add(inputs):
                for input in inputs {
                    let data = try Data(contentsOf: input.sourceURL)
                    let normalized = normalizeArchivePath(input.archivePath)
                    if let idx = snapshot.firstIndex(where: { $0.name == normalized }) {
                        if options.replaceExistingEntries {
                            snapshot[idx] = StoredEntry(name: normalized, data: data)
                            replaced += 1
                        } else {
                            skipped += 1
                        }
                    } else {
                        snapshot.append(StoredEntry(name: normalized, data: data))
                        added += 1
                    }
                }
            case let .delete(selector):
                let before = snapshot.count
                snapshot.removeAll { entry in
                    let candidates = [entry.name, entry.name.replacingOccurrences(of: "\\", with: "/")]
                    let matchesMask = selector.masks.contains { mask in
                        candidates.contains { ARJGlob.matches($0, pattern: mask) }
                    }
                    let excluded = selector.excludes.contains { pattern in
                        candidates.contains { ARJGlob.matches($0, pattern: pattern) }
                    }
                    return matchesMask && !excluded
                }
                deleted += (before - snapshot.count)
            case let .setArchiveComment(newValue):
                let normalized = normalizeComment(newValue)
                if comment != normalized {
                    comment = normalized
                    commentChanged = true
                }
            }
        }

        let bytes = serializeStoredArchive(entries: snapshot, comment: comment)
        try Data(bytes).write(to: URL(fileURLWithPath: outputArchivePath), options: .atomic)

        return ARJWriterResult(
            entriesAdded: added,
            entriesReplaced: replaced,
            entriesSkipped: skipped,
            entriesDeleted: deleted,
            commentChanged: commentChanged
        )
    }

    private struct StoredEntry {
        var name: String
        var data: Data
    }

    private static func normalizeArchivePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private static func normalizeComment(_ comment: String?) -> String? {
        guard let comment else { return nil }
        let trimmed = comment.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func serializeStoredArchive(entries: [StoredEntry], comment: String?) -> [UInt8] {
        var bytes: [UInt8] = []

        let mainHeader = makeMainHeader(comment: comment)
        bytes += [0x60, 0xEA]
        bytes += littleEndianWord(UInt16(mainHeader.count))
        bytes += mainHeader
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00]

        for entry in entries {
            let fileHeader = makeFileHeader(fileName: entry.name, payload: entry.data)
            bytes += [0x60, 0xEA]
            bytes += littleEndianWord(UInt16(fileHeader.count))
            bytes += fileHeader
            bytes += [0x00, 0x00, 0x00, 0x00]
            bytes += [0x00, 0x00]
            bytes += entry.data
        }

        bytes += [0x60, 0xEA]
        bytes += [0x00, 0x00]
        return bytes
    }

    private static func makeMainHeader(comment: String?) -> [UInt8] {
        var fixed = Array(repeating: UInt8(0), count: 30)
        fixed[0] = 30
        fixed[1] = 11
        fixed[2] = 1

        var strings: [UInt8] = []
        strings.append(0) // archive name
        if let comment {
            strings += Array(comment.utf8)
        }
        strings.append(0)
        return fixed + strings
    }

    private static func makeFileHeader(fileName: String, payload: Data) -> [UInt8] {
        var fixed = Array(repeating: UInt8(0), count: 30)
        fixed[0] = 30
        fixed[1] = 11
        fixed[2] = 1
        fixed[3] = 0
        fixed[4] = 0
        fixed[5] = 0
        fixed[6] = 0
        fixed[7] = 0

        let size = UInt32(payload.count)
        fixed[12] = UInt8(truncatingIfNeeded: size)
        fixed[13] = UInt8(truncatingIfNeeded: size >> 8)
        fixed[14] = UInt8(truncatingIfNeeded: size >> 16)
        fixed[15] = UInt8(truncatingIfNeeded: size >> 24)
        fixed[16] = fixed[12]
        fixed[17] = fixed[13]
        fixed[18] = fixed[14]
        fixed[19] = fixed[15]

        let crc = crc32(payload)
        fixed[20] = UInt8(truncatingIfNeeded: crc)
        fixed[21] = UInt8(truncatingIfNeeded: crc >> 8)
        fixed[22] = UInt8(truncatingIfNeeded: crc >> 16)
        fixed[23] = UInt8(truncatingIfNeeded: crc >> 24)

        var strings = Array(fileName.utf8)
        strings.append(0)
        strings.append(0)
        return fixed + strings
    }

    private static func littleEndianWord(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0x00FF), UInt8((value >> 8) & 0x00FF)]
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let polynomial: UInt32 = 0xEDB8_8320
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                if (value & 1) != 0 {
                    value = (value >> 1) ^ polynomial
                } else {
                    value >>= 1
                }
            }
            table[index] = value
        }

        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let lookup = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[lookup]
        }
        return crc ^ 0xFFFF_FFFF
    }
}
