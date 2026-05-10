import ArgumentParser
import Foundation

private func runWriteStub(letter: String, name: String, options: ArchiveOperationOptions) throws {
    try options.validateArchiveArgument()
    throw ARJCLIError.exit(
        .fatalError,
        message: "command '\(letter)' (\(name)) is not implemented yet (write/modify support is pending in Stage 4)"
    )
}

struct AddStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add files to archive (ARJ: a) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "a", name: "add", options: options) }
}

struct DeleteStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete files from archive (ARJ: d) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "d", name: "delete", options: options) }
}

struct UpdateStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update files in archive (ARJ: u) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "u", name: "update", options: options) }
}

struct FreshenStubCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "freshen",
        abstract: "Freshen files in archive (ARJ: f) — not yet implemented",
        discussion: "Write support for this command is planned for Stage 4 of development."
    )
    @OptionGroup var options: ArchiveOperationOptions
    func run() throws { try runWriteStub(letter: "f", name: "freshen", options: options) }
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
