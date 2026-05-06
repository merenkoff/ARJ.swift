import ARJArchive
import ArgumentParser
import Foundation

struct ListCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List files in an archive (ARJ: l)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let arj = try ARJArchive(path: options.archive)
        let entries = try arj.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: true)
        for entry in filtered {
            print("\(entry.name)\t\(entry.originalSize)")
        }
    }
}

