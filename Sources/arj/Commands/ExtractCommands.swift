import ARJArchive
import ArgumentParser
import Foundation

struct ExtractFlatCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "extract-flat",
        abstract: "Extract files without preserving directory structure (ARJ: e)",
        discussion: """
        Extract all files to a single directory, stripping all path information.
        
        Usage: arj e <archive> [destination] [files/masks...]
        
        Examples:
          arj e archive.arj /tmp                      # Extract all to /tmp
          arj e archive.arj /tmp *.txt                # Extract only .txt files
          arj e archive.arj -ht/tmp                   # Using -ht flag instead
          arj e archive.arj -ht/tmp -x*.bak -y        # Exclude .bak, no prompts
          arj e archive.arj -g<password> -y           # Encrypted archive
        
        Options:
          -y                    Skip overwrite prompts (assume yes)
          -ht<dir>              Target extraction directory
          -x<mask>              Exclude files matching pattern
          !<file>               Only extract files listed in file
          -g<password>          Password for encrypted archives
          -o                    Prompt before overwriting
        """
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateExtractPathSwitches(command: "e")
        try ExtractRunner.run(options: options, mode: .flat)
    }
}

struct ExtractCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract files preserving directory structure (ARJ: x)",
        discussion: """
        Extract all files preserving their directory structure from the archive.
        
        Usage: arj x <archive> [destination] [files/masks...]
        
        Examples:
          arj x archive.arj /tmp                      # Extract with paths to /tmp
          arj x archive.arj /tmp -e                   # Strip all paths after extraction
          arj x archive.arj -ht/tmp -p                # Keep full paths
          arj x archive.arj -ht/tmp -p1               # Keep relative paths
          arj x archive.arj -ht/tmp -x*.bak -y        # Exclude *.bak
          arj x archive.arj -g<password>              # Encrypted archive
        
        Path options:
          (default)             Keep relative paths from archive
          -p                    Keep full absolute paths from archive
          -p1                   Keep relative paths
          -e                    Strip all paths (files to target dir only)
          -_                    Convert names to lowercase
        
        Filter options:
          -x<mask>              Exclude files matching pattern
          !<file>               Only extract files listed in file
          -g<password>          Password
          -y                    Skip prompts
          -o                    Prompt before overwriting
        """
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateExtractPathSwitches(command: "x")
        let mode: ARJExtractPaths.ExtractMode
        if options.stripPaths {
            mode = .structuredStripPaths
        } else if options.keepPaths {
            mode = .structuredKeepFullPaths
        } else {
            mode = .structuredKeepRelativePaths
        }
        try ExtractRunner.run(options: options, mode: mode)
    }
}

private enum ExtractRunner {
    static func run(options: ArchiveOperationOptions, mode: ARJExtractPaths.ExtractMode) throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: false)

        var hadWarning = false
        for entry in filtered {
            if !options.noProgress {
                FileHandle.standardError.write(Data("Extracting \(entry.name)\n".utf8))
            }
            let data = try archive.extract(entry: entry, password: options.password)
            let url = ARJExtractPaths.outputPath(for: entry, options: options, mode: mode)
            let skipped = try ARJFileWriter.write(
                data: data,
                to: url,
                assumeYes: options.assumeYes,
                overwritePrompt: options.overwritePrompt
            )
            if skipped {
                hadWarning = true
                if !options.noProgress {
                    FileHandle.standardError.write(Data("Skipped existing \(url.path)\n".utf8))
                }
            }
        }

        if hadWarning {
            throw ARJCLIError.exit(.warning, message: nil)
        }
    }
}
