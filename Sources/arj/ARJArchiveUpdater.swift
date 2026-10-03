import ARJArchive
import Foundation

struct ARJAddInput {
    var sourceURL: URL
    var archivePath: String
}

struct ARJDeleteSelector {
    var masks: [String]
    var excludes: [String]

    func matches(_ entry: ARJEntry) -> Bool {
        ARJFilter.shouldInclude(entry: entry, masks: masks, excludes: excludes)
    }
}

/// How `.add` treats inputs whose path already exists in the archive (ARJ `a`, `u` and `f` semantics).
enum ARJAddMode {
    /// Add new files; replace existing entries only when `replaceExisting` is set.
    case add(replaceExisting: Bool)
    /// Add new files and replace entries older than the file on disk.
    case update
    /// Only replace existing entries older than the file on disk.
    case freshen
}

enum ARJWriterChange {
    case add([ARJAddInput], mode: ARJAddMode)
    case delete(ARJDeleteSelector)
    /// Strips directory components from the names of matching entries (ARJ `r`).
    case removePaths(ARJDeleteSelector)
    case setArchiveComment(String?)
}

struct ARJWriterResult {
    var entriesAdded = 0
    var entriesReplaced = 0
    var entriesSkipped = 0
    var entriesDeleted = 0
    var entriesRenamed = 0
    var commentChanged = false
    /// Source files that ended up in the archive (added or replaced).
    var archivedSources: [URL] = []
}

/// CLI adapter over `ARJArchive.ARJWriter`: applies a list of changes and rewrites the archive atomically.
enum ARJArchiveUpdater {
    static func apply(
        archivePath: String,
        createIfMissing: Bool,
        changes: [ARJWriterChange],
        password: String?,
        compressionMethod: Int?
    ) throws -> ARJWriterResult {
        let method = try compressionMethodSwitch(compressionMethod)
        var writer: ARJWriter
        if FileManager.default.fileExists(atPath: archivePath) {
            writer = try ARJWriter(updating: ARJArchive(path: archivePath))
        } else if createIfMissing {
            writer = ARJWriter(archiveName: URL(fileURLWithPath: archivePath).lastPathComponent, hostOS: .unix)
        } else {
            throw ARJError.fileReadFailed(path: archivePath)
        }

        var result = ARJWriterResult()
        for change in changes {
            switch change {
            case let .add(inputs, mode):
                for input in inputs {
                    try add(input, mode: mode, method: method, password: password, to: &writer, result: &result)
                }
            case let .delete(selector):
                result.entriesDeleted += writer.removeEntries(where: selector.matches)
            case let .removePaths(selector):
                for entry in writer.entries where selector.matches(entry) {
                    let baseName = String(entry.normalizedPath.split(separator: "/").last ?? "")
                    guard !baseName.isEmpty, baseName != entry.normalizedPath else { continue }
                    do {
                        try writer.renameEntry(named: entry.name, to: baseName)
                        result.entriesRenamed += 1
                    } catch ARJError.entryAlreadyExists {
                        result.entriesSkipped += 1
                    }
                }
            case let .setArchiveComment(newValue):
                let normalized = normalizeComment(newValue)
                if writer.comment != normalized {
                    writer.comment = normalized
                    result.commentChanged = true
                }
            }
        }

        try writer.write(to: URL(fileURLWithPath: archivePath))
        return result
    }

    private static func add(
        _ input: ARJAddInput,
        mode: ARJAddMode,
        method: ARJCompressionMethod,
        password: String?,
        to writer: inout ARJWriter,
        result: inout ARJWriterResult
    ) throws {
        let existing = writer.entries.first { $0.normalizedPath == input.archivePath }
        let policy: ARJWriter.ExistingEntryPolicy
        switch mode {
        case let .add(replaceExisting):
            policy = replaceExisting ? .replace : .skip
        case .update, .freshen:
            if let existing, !isSource(input.sourceURL, newerThan: existing) {
                result.entriesSkipped += 1
                return
            }
            if existing == nil, case .freshen = mode {
                result.entriesSkipped += 1
                return
            }
            policy = .replace
        }

        switch try writer.addFile(at: input.sourceURL, named: input.archivePath, method: method, password: password, ifExists: policy) {
        case .added:
            result.entriesAdded += 1
            result.archivedSources.append(input.sourceURL)
        case .replaced:
            result.entriesReplaced += 1
            result.archivedSources.append(input.sourceURL)
        case .skipped:
            result.entriesSkipped += 1
        }
    }

    /// ARJ timestamps have 2-second (DOS) or 1-second (Unix) resolution.
    private static func isSource(_ url: URL, newerThan entry: ARJEntry) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let modified = attributes?[.modificationDate] as? Date else { return true }
        let resolution: TimeInterval = (entry.hostOS == .unix || entry.hostOS == .next) ? 1 : 2
        return modified.timeIntervalSince(entry.modified) >= resolution
    }

    private static func compressionMethodSwitch(_ value: Int?) throws -> ARJCompressionMethod {
        guard let value else { return .compressedMost }
        guard (0...4).contains(value), let method = ARJCompressionMethod(rawValue: UInt8(value)) else {
            throw ARJCLIError.exit(.fatalError, message: "unsupported compression method -m\(value) (use -m0..-m4)")
        }
        return method
    }

    /// Stores the comment the way ARJ does: LF line endings, every line terminated (including the last).
    private static func normalizeComment(_ comment: String?) -> String? {
        guard let comment else { return nil }
        let trimmed = comment
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? nil : trimmed + "\n"
    }
}
