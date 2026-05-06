import ARJArchive
import ArgumentParser
import Foundation

struct ExtractFlatCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "extract-flat",
        abstract: "Extract without paths (ARJ: e)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try ExtractRunner.run(options: options, mode: .flat)
    }
}

struct ExtractCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract with directory structure (ARJ: x)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        let mode: ARJExtractPaths.ExtractMode = options.stripPaths ? .structuredStripPaths : .structured
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
