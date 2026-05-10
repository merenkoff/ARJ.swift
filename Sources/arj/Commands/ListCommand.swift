import ARJArchive
import ArgumentParser
import Foundation

struct ListCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List archive contents (ARJ: l)",
        discussion: """
        List all files in archive, optionally filtered by masks or listfile.
        
        Usage: arj l <archive> [base_dir] [files/masks...]
        
        Examples:
          arj l archive.arj                    # List all
          arj l archive.arj -x*.bak            # Exclude *.bak files
          arj l archive.arj !filter.txt        # Only files listed in filter.txt
          arj l archive.arj -g<password>       # List encrypted archive
        """
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

