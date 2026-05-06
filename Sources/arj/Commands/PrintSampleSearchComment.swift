import ARJArchive
import ArgumentParser
import Darwin
import Foundation

struct PrintCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "print",
        abstract: "Print file contents to stdout (ARJ: p)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: false)

        for entry in filtered {
            let data = try archive.extract(entry: entry, password: options.password)
            FileHandle.standardOutput.write(data)
        }
    }
}

struct SampleCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sample",
        abstract: "Print with paging when possible (ARJ: s)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: false)

        var combined = Data()
        for entry in filtered {
            let data = try archive.extract(entry: entry, password: options.password)
            combined.append(data)
        }

        if isatty(STDOUT_FILENO) != 0 {
            let lessPath = "/usr/bin/less"
            if FileManager.default.fileExists(atPath: lessPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: lessPath)
                process.arguments = ["-"]
                let input = Pipe()
                process.standardInput = input
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: combined)
                input.fileHandleForWriting.closeFile()
                process.waitUntilExit()
                return
            }
        }

        FileHandle.standardOutput.write(combined)
    }
}

struct SearchCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search for a byte pattern in archive members (ARJ: w)"
    )

    @OptionGroup var options: ArchiveOperationOptions

    @Option(name: .customLong("search-pattern"), help: "Search string / pattern")
    var searchPattern: String = ""

    func run() throws {
        try options.validateArchiveArgument()
        let archive = try ARJArchive(path: options.archive)
        let entries = try archive.entries()
        let masks = try ARJFilter.resolvedMasks(masks: options.masks, listfiles: options.listfiles)
        let filtered = ARJFilter.filterEntries(entries, masks: masks, excludes: options.excludes, includeDirectories: false)

        let needles: [Data] = [
            Data(searchPattern.utf8),
            searchPattern.data(using: .isoLatin1),
        ].compactMap { $0 }

        guard !needles.isEmpty, !searchPattern.isEmpty else {
            return
        }

        for entry in filtered {
            let data = try archive.extract(entry: entry, password: options.password)
            for needle in needles where !needle.isEmpty {
                if data.range(of: needle) != nil {
                    print(entry.name)
                    break
                }
            }
        }
    }
}

struct CommentCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Show or change archive comment (ARJ: c) — write not implemented"
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        if options.commentFile != nil {
            throw ARJCLIError.exit(
                .fatalError,
                message: "command 'c' (comment) with -z is not implemented yet (write support is pending)"
            )
        }

        let archive = try ARJArchive(path: options.archive)
        if let comment = archive.archiveComment {
            print(comment)
        }
    }
}
