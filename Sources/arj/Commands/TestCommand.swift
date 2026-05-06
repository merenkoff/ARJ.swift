import ARJArchive
import ArgumentParser
import Foundation

struct TestCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test archive integrity (ARJ: t)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: false)

        for entry in filtered {
            if !options.noProgress {
                FileHandle.standardError.write(Data("Testing \(entry.name)\n".utf8))
            }
            _ = try archive.extract(entry: entry, password: options.password)
        }
    }
}
