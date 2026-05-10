import ARJArchive
import ArgumentParser
import Foundation

struct TestCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Verify archive integrity without extracting (ARJ: t)",
        discussion: """
        Test all files in archive for corruption by extracting them in memory without writing to disk.
        
        Usage: arj t <archive> [files/masks...]
        
        Examples:
          arj t archive.arj                    # Test all files
          arj t archive.arj *.txt              # Test only .txt files
          arj t archive.arj -x*.bak            # Test all except .bak
          arj t archive.arj -g<password>       # Test encrypted archive
          arj t archive.arj -jt                # CRC test mode
        
        Exit codes:
          0          All files OK
          3          Password error (encrypted files)
          9          Not an ARJ archive
          Other      Corruption or I/O error detected
        """
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
