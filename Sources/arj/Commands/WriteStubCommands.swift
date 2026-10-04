import ARJArchive
import ArgumentParser
import Foundation

private func runWriteStub(letter: String, name: String, options: ArchiveOperationOptions) throws {
    try options.validateArchiveArgument()
    throw ARJCLIError.exit(
        .fatalError,
        message: "command '\(letter)' (\(name)) is not implemented yet"
    )
}

struct AddCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add files to archive (ARJ: a)",
        discussion: """
        Adds files to the archive, creating it if it does not exist. Existing entries are replaced
        unless -o is given without -y.

        Usage: arj a <archive> [base_dir] [files/masks...]

        Examples:
          arj a backup.arj docs *.txt -r          # Add .txt files from docs/ recursively (method 1)
          arj a backup.arj . -m4 -x*.tmp          # Fastest compression, skip *.tmp
          arj a backup.arj . secret.txt -gpass    # Garble added files with a password
        """
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
            createIfMissing: true,
            changes: [.add(inputs, mode: .add(replaceExisting: options.assumeYes || !options.overwritePrompt))]
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
        discussion: """
        Removes matching entries. Remaining entries are copied as-is, so no password is needed.

        Usage: arj d <archive> <files/masks...>
        """
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

/// Applies `changes` to the archive named in `options` and rewrites it atomically.
func applyWriterChanges(
    options: ArchiveOperationOptions,
    createIfMissing: Bool = false,
    changes: [ARJWriterChange]
) throws -> ARJWriterResult {
    try ARJArchiveUpdater.apply(
        archivePath: options.archive,
        createIfMissing: createIfMissing,
        changes: changes,
        password: options.password,
        compressionMethod: options.compressionMethod
    )
}

struct UpdateCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update/add files in archive (ARJ: u)",
        discussion: "Adds new files and replaces entries that are older than the file on disk. Creates the archive if needed."
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
            createIfMissing: true,
            changes: [.add(inputs, mode: .update)]
        )
        print("Updated: \(result.entriesReplaced), Added: \(result.entriesAdded), Skipped: \(result.entriesSkipped)")
    }
}

struct FreshenCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "freshen",
        abstract: "Freshen existing files in archive (ARJ: f)",
        discussion: "Replaces entries that already exist in the archive and are older than the file on disk."
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
            changes: [.add(inputs, mode: .freshen)]
        )
        print("Freshened: \(result.entriesReplaced), Added: \(result.entriesAdded), Skipped: \(result.entriesSkipped)")
    }
}

struct MoveCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move files to archive (ARJ: m)",
        discussion: """
        Adds files like `a` (creating the archive if needed) and deletes each source file
        once the archive has been written successfully.

        Usage: arj m <archive> [base_dir] [files/masks...]
        """
    )
    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let base = URL(fileURLWithPath: options.baseDirectory ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let inputs = try AddCommand().collectAddInputs(baseDirectory: base, masks: masks, recursive: options.recursive, excludes: options.excludes)
        if inputs.isEmpty {
            throw ARJCLIError.exit(.warning, message: "no files matched for move")
        }
        let result = try applyWriterChanges(
            options: options,
            createIfMissing: true,
            changes: [.add(inputs, mode: .add(replaceExisting: options.assumeYes || !options.overwritePrompt))]
        )
        for source in result.archivedSources {
            try FileManager.default.removeItem(at: source)
        }
        print("Moved: \(result.archivedSources.count), Skipped: \(result.entriesSkipped)")
    }
}

struct GarbleStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "garble",
        abstract: "Encrypt/re-encrypt files (ARJ: g) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "g", name: "garble", options: options) }
}

struct RemovePathsCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "remove-paths",
        abstract: "Remove paths from filenames in archive (ARJ: r)",
        discussion: """
        Renames matching entries to their base names. Entries whose base name is already
        taken are left unchanged.

        Usage: arj r <archive> [files/masks...]
        """
    )
    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        var positionalMasks = options.masks
        if let base = options.baseDirectory, !base.isEmpty {
            positionalMasks.insert(base, at: 0)
        }
        let masks = try ARJFilter.resolvedMasks(masks: positionalMasks, listfiles: options.listfiles)
        let result = try applyWriterChanges(
            options: options,
            changes: [.removePaths(ARJDeleteSelector(masks: masks, excludes: options.excludes))]
        )
        print("Renamed: \(result.entriesRenamed), Skipped: \(result.entriesSkipped)")
    }
}

struct RenameStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename files in archive (ARJ: n) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "n", name: "rename", options: options) }
}

struct OrderStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "order",
        abstract: "Reorder files in archive (ARJ: o) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "o", name: "order", options: options) }
}

struct BatchStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Batch processing (ARJ: b) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "b", name: "batch", options: options) }
}

struct IntegrityStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "integrity",
        abstract: "Integrity/recovery (ARJ: i) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "i", name: "integrity", options: options) }
}

struct JoinStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Join split volumes (ARJ: j) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "j", name: "join", options: options) }
}

struct BackupStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Backup cleanup (ARJ: k) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "k", name: "backup", options: options) }
}

struct RecoverStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Recover corrupt archive (ARJ: q) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "q", name: "recover", options: options) }
}

struct CopyStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy/verify archive (ARJ: y) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "y", name: "copy", options: options) }
}

struct AddChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "add-chapter",
        abstract: "Add chapter/volume (ARJ: ac) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "ac", name: "add-chapter", options: options) }
}

struct ConvertChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "convert-chapter",
        abstract: "Convert chapter/volume (ARJ: cc) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "cc", name: "convert-chapter", options: options) }
}

struct DeleteChapterStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-chapter",
        abstract: "Delete chapter/volume (ARJ: dc) — not yet implemented",
        discussion: "Not implemented yet; the command exits with code 2."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "dc", name: "delete-chapter", options: options) }
}
