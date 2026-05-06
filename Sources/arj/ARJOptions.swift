import ArgumentParser
import Foundation

struct ArchiveOperationOptions: ParsableArguments {
    @Option(name: .long, help: "Path to the ARJ archive")
    var archive: String = ""

    @Option(name: .customLong("base-dir"), help: "Base or destination directory (2nd positional)")
    var baseDirectory: String?

    @Option(name: .customLong("listfile"), help: "List file with file paths or masks")
    var listfiles: [String] = []

    @Option(name: .customLong("mask"), help: "Filename mask (glob)")
    var masks: [String] = []

    @Option(name: .customLong("password"), help: "Password (-g)")
    var password: String?

    @Option(name: .customLong("target-dir"), help: "Target directory (-ht)")
    var targetDirectory: String?

    @Option(name: .customLong("work-dir"), help: "Work directory (-w)")
    var workDirectory: String?

    @Option(name: .customLong("comment-file"), help: "Comment file (-z)")
    var commentFile: String?

    @Option(name: .customLong("compression-method"), help: "Compression method (-m0..4)")
    var compressionMethod: Int?

    @Flag(name: .customLong("yes"), help: "Assume yes (-y)")
    var assumeYes: Bool = false

    @Flag(name: .customLong("no-progress"), help: "No progress indicator (-i)")
    var noProgress: Bool = false

    @Flag(name: .customLong("overwrite-prompt"), help: "Prompt before overwriting (-o)")
    var overwritePrompt: Bool = false

    @Flag(name: .customLong("strip-paths"), help: "Strip paths when extracting (-e)")
    var stripPaths: Bool = false

    @Flag(name: .customLong("keep-paths"), help: "Keep full paths (-p)")
    var keepPaths: Bool = false

    @Flag(name: .customLong("keep-relative-paths"), help: "Keep relative paths (-p1)")
    var keepRelativePaths: Bool = false

    @Flag(name: .customLong("recursive"), help: "Recurse (-r)")
    var recursive: Bool = false

    @Flag(name: .customLong("crc-test"), help: "CRC test (-jt)")
    var crcTest: Bool = false

    @Flag(name: .customLong("lowercase-names"), help: "Lowercase names (-_)")
    var lowercaseNames: Bool = false

    @Option(name: .customLong("exclude"), help: "Exclude mask (-x)")
    var excludes: [String] = []

    /// Effective output root for extract commands (`-ht` or 2nd positional or cwd).
    var extractDestinationPath: String {
        targetDirectory ?? baseDirectory ?? FileManager.default.currentDirectoryPath
    }
}
