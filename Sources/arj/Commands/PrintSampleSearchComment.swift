import ARJArchive
import ArgumentParser
import Darwin
import Foundation

struct PrintCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "print",
        abstract: "Output file contents to stdout without modification (ARJ: p)",
        discussion: """
        Extract and print file contents to standard output. Useful for viewing text files or piping to other programs.
        
        Usage: arj p <archive> [file/pattern]
        
        Examples:
          arj p archive.arj file.txt                  # Print file.txt
          arj p archive.arj *.txt                     # Print all .txt files concatenated
          arj p archive.arj file.txt | less           # View with pager
          arj p archive.arj -g<password> secret.txt   # From encrypted archive
          arj p archive.arj !files.txt                # Print files listed in files.txt
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
            let data = try archive.extract(entry: entry, password: options.password)
            FileHandle.standardOutput.write(data)
        }
    }
}

struct SampleCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sample",
        abstract: "View file contents with automatic paging support (ARJ: s)",
        discussion: """
        Extract and display file contents, automatically using 'less' pager if running in terminal.
        Falls back to direct output if pager unavailable (e.g., piped to file/command).
        
        Usage: arj s <archive> [file/pattern]
        
        Examples:
          arj s archive.arj file.txt                  # Auto-page if terminal
          arj s archive.arj *.txt                     # View all .txt files
          arj s archive.arj file.txt > out.txt        # Redirect (no paging)
          arj s archive.arj -g<password> readme.txt   # From encrypted archive
        """
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
        abstract: "Search for text pattern within archive files (ARJ: w)",
        discussion: """
        Search for a string pattern in archive files and display matches with context.
        Useful for finding text across multiple files without extracting.
        
        Usage: arj w <archive> <pattern> [file/mask...]
        
        Examples:
          arj w archive.arj \"TODO\"                   # Search for TODO
          arj w archive.arj \"error\" *.log            # Search in .log files
          arj w archive.arj \"test\" -x*.bak          # Exclude .bak from search
          arj w archive.arj \"secret\" -g<password>   # Search in encrypted files
        """
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

        let pattern = searchPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            throw ARJCLIError.exit(.userParameterError, message: "missing search pattern")
        }
        let needles = encodedNeedles(for: pattern)

        for entry in filtered {
            let data = try archive.extract(entry: entry, password: options.password)
            if containsPattern(data: data, pattern: pattern, needles: needles) {
                print(entry.name)
            }
        }
    }

    private func containsPattern(data: Data, pattern: String, needles: [Data]) -> Bool {
        let textEncodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian, .windowsCP1251, .isoLatin1]
        for encoding in textEncodings {
            if let text = String(data: data, encoding: encoding), text.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        for needle in needles where !needle.isEmpty {
            if data.range(of: needle) != nil {
                return true
            }
        }
        return false
    }

    private func encodedNeedles(for pattern: String) -> [Data] {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
            .windowsCP1251,
        ]
        return encodings.compactMap { pattern.data(using: $0) }
    }
}

struct CommentCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Display archive comment or prepare to change it (ARJ: c)",
        discussion: """
        Show the archive comment or prepare to change it (writing not yet implemented).
        
        Usage: arj c <archive> [-z<file>]
        
        Examples:
          arj c archive.arj                           # Display archive comment
          arj c archive.arj -zcomment.txt             # Set comment (not implemented)
        
        Note: Setting/modifying comments (-z flag) requires write support, currently not implemented.
        """
    )

    @OptionGroup var options: ArchiveOperationOptions

    func run() throws {
        try options.validateArchiveArgument()
        if let commentFile = options.commentFile {
            let commentText = try String(contentsOfFile: commentFile, encoding: .utf8)
            let result = try applyWriterChanges(
                options: options,
                changes: [.setArchiveComment(commentText)]
            )
            if result.commentChanged {
                print("Archive comment updated")
            } else {
                print("Archive comment unchanged")
            }
            return
        }

        let archive = try ARJArchive(path: options.archive)
        print("Archive comment:")
        if let comment = archive.archiveComment, !comment.isEmpty {
            print(comment)
        } else {
            print("<none>")
        }
    }
}
