import ARJArchive
import ArgumentParser
import Foundation

private func runWriteStub(letter: String, name: String, options: ArchiveOperationOptions) throws {
    try options.validateArchiveArgument()
    throw ARJCLIError.exit(
        .fatalError,
        message: "command '\(letter)' (\(name)) is not implemented yet (write/modify support is pending in Stage 4)"
    )
}

struct AddCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add files to archive (ARJ: a)",
        discussion: "Minimal write-mode implementation (Stage 5, iteration 1)."
    )
    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let base = URL(fileURLWithPath: options.baseDirectory ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let inputs = try collectAddInputs(baseDirectory: base, masks: masks, recursive: options.recursive, excludes: options.excludes)
        if inputs.isEmpty {
            throw ARJCLIError.exit(.warning, message: "no files matched for add")
        }
        let result = try applyWriterChanges(
            options: options,
            changes: [.add(inputs)]
        )
        print("Added: \(result.entriesAdded), Replaced: \(result.entriesReplaced), Skipped: \(result.entriesSkipped)")
    }

    func collectAddInputs(
        baseDirectory: URL,
        masks: [String],
        recursive: Bool,
        excludes: [String]
    ) throws -> [ARJAddInput] {
        let fm = FileManager.default
        var candidates: [URL] = []
        let masksToUse = masks.isEmpty ? ["*"] : masks
        var explicit: [URL] = []

        for raw in masksToUse {
            let absolute = URL(fileURLWithPath: raw)
            if fm.fileExists(atPath: absolute.path) {
                explicit.append(absolute)
                continue
            }
            let relative = baseDirectory.appendingPathComponent(raw)
            if fm.fileExists(atPath: relative.path) {
                explicit.append(relative)
            }
        }

        if recursive {
            let enumerator = fm.enumerator(at: baseDirectory, includingPropertiesForKeys: [.isRegularFileKey])
            while let item = enumerator?.nextObject() as? URL {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    candidates.append(item)
                }
            }
        } else {
            for name in try fm.contentsOfDirectory(atPath: baseDirectory.path) {
                let url = baseDirectory.appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                    candidates.append(url)
                }
            }
        }
        candidates.append(contentsOf: explicit)

        var result: [ARJAddInput] = []
        var seen = Set<String>()
        for url in candidates {
            let relative = relativePath(for: url, baseDirectory: baseDirectory)
                .replacingOccurrences(of: "\\", with: "/")
            let matchesMask = masksToUse.contains { ARJGlob.matches(relative, pattern: $0) || ARJGlob.matches(url.lastPathComponent, pattern: $0) }
            let excluded = excludes.contains { ARJGlob.matches(relative, pattern: $0) || ARJGlob.matches(url.lastPathComponent, pattern: $0) }
            if matchesMask && !excluded && seen.insert(relative).inserted {
                result.append(ARJAddInput(sourceURL: url, archivePath: relative))
            }
        }
        return result
    }

    private func relativePath(for url: URL, baseDirectory: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        let standardizedBase = baseDirectory.standardizedFileURL
        let basePath = standardizedBase.path.hasSuffix("/") ? standardizedBase.path : standardizedBase.path + "/"
        if standardizedURL.path.hasPrefix(basePath) {
            return String(standardizedURL.path.dropFirst(basePath.count))
        }
        return standardizedURL.lastPathComponent
    }
}

struct DeleteCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete files from archive (ARJ: d)",
        discussion: "Minimal write-mode implementation (Stage 5, iteration 1)."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws {
        try options.validateArchiveArgument()
        var positionalMasks = options.masks
        if let base = options.baseDirectory, !base.isEmpty {
            positionalMasks.insert(base, at: 0)
        }
        let masks = try ARJFilter.resolvedMasks(masks: positionalMasks, listfiles: options.listfiles)
        if masks.isEmpty {
            throw ARJCLIError.exit(.userParameterError, message: "delete requires at least one mask")
        }
        let result = try applyWriterChanges(
            options: options,
            changes: [.delete(ARJDeleteSelector(masks: masks, excludes: options.excludes))]
        )
        if result.entriesDeleted == 0 {
            throw ARJCLIError.exit(.warning, message: "no entries matched delete mask(s)")
        }
        print("Deleted: \(result.entriesDeleted), Not matched: 0")
    }
}

func applyWriterChanges(
    options: ArchiveOperationOptions,
    forceReplaceExisting: Bool? = nil,
    changes: [ARJWriterChange]
) throws -> ARJWriterResult {
    let inputURL = URL(fileURLWithPath: options.archive)
    let tempURL = inputURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp.arj")
    let result = try ARJWriter.apply(
        inputArchivePath: inputURL.path,
        outputArchivePath: tempURL.path,
        changes: changes,
        password: options.password,
        options: ARJWriterOptions(
            compressionMethod: options.compressionMethod,
            replaceExistingEntries: forceReplaceExisting ?? (options.assumeYes || !options.overwritePrompt)
        )
    )
    try FileManager.default.removeItemIfExists(at: inputURL)
    try FileManager.default.moveItem(at: tempURL, to: inputURL)
    return result
}

extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}

struct UpdateCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update/add files in archive (ARJ: u)",
        discussion: "Updates existing files and adds missing ones."
    )
    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let base = URL(fileURLWithPath: options.baseDirectory ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let inputs = try AddCommand().collectAddInputs(baseDirectory: base, masks: masks, recursive: options.recursive, excludes: options.excludes)
        if inputs.isEmpty {
            throw ARJCLIError.exit(.warning, message: "no files matched for update")
        }
        let result = try applyWriterChanges(
            options: options,
            forceReplaceExisting: true,
            changes: [.add(inputs)]
        )
        print("Updated: \(result.entriesReplaced), Added: \(result.entriesAdded), Skipped: \(result.entriesSkipped)")
    }
}

struct FreshenCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "freshen",
        abstract: "Freshen existing files in archive (ARJ: f)",
        discussion: "Updates only files that already exist in the archive."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws {
        try options.validateArchiveArgument()
        let base = URL(fileURLWithPath: options.baseDirectory ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let allInputs = try AddCommand().collectAddInputs(baseDirectory: base, masks: masks, recursive: options.recursive, excludes: options.excludes)
        if allInputs.isEmpty {
            throw ARJCLIError.exit(.warning, message: "no files matched for freshen")
        }

        let archive = try ARJArchive(path: options.archive)
        let existing = Set(try archive.entries().map(\.normalizedPath))
        let inputs = allInputs.filter { existing.contains($0.archivePath) }
        if inputs.isEmpty {
            throw ARJCLIError.exit(.warning, message: "no existing archive entries matched for freshen")
        }

        let result = try applyWriterChanges(
            options: options,
            forceReplaceExisting: true,
            changes: [.add(inputs)]
        )
        print("Freshened: \(result.entriesReplaced), Added: \(result.entriesAdded), Skipped: \(result.entriesSkipped)")
    }
}

struct MoveStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move files in archive (ARJ: m) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "m", name: "move", options: options) }
}

struct GarbleStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "garble",
        abstract: "Encrypt/re-encrypt files (ARJ: g) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "g", name: "garble", options: options) }
}

struct RemovePathsStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "remove-paths",
        abstract: "Remove paths from archive (ARJ: r) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "r", name: "remove-paths", options: options) }
}

struct RenameStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename files in archive (ARJ: n) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "n", name: "rename", options: options) }
}

struct OrderStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "order",
        abstract: "Reorder files in archive (ARJ: o) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "o", name: "order", options: options) }
}

struct BatchStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Batch processing (ARJ: b) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "b", name: "batch", options: options) }
}

struct IntegrityStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "integrity",
        abstract: "Integrity/recovery (ARJ: i) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "i", name: "integrity", options: options) }
}

struct JoinStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Join split volumes (ARJ: j) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "j", name: "join", options: options) }
}

struct BackupStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Backup cleanup (ARJ: k) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "k", name: "backup", options: options) }
}

struct RecoverStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Recover corrupt archive (ARJ: q) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "q", name: "recover", options: options) }
}

struct CopyStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy/verify archive (ARJ: y) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "y", name: "copy", options: options) }
}

struct AddChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "add-chapter",
        abstract: "Add chapter/volume (ARJ: ac) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "ac", name: "add-chapter", options: options) }
}

struct ConvertChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "convert-chapter",
        abstract: "Convert chapter/volume (ARJ: cc) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "cc", name: "convert-chapter", options: options) }
}

struct DeleteChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-chapter",
        abstract: "Delete chapter/volume (ARJ: dc) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "dc", name: "delete-chapter", options: options) }
}
