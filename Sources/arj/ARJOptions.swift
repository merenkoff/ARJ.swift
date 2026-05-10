import ArgumentParser
import Foundation

struct ArchiveOperationOptions: ParsableArguments {
    @Option(name: .long, help: "Path to the ARJ archive (positional arg 1)")
    var archive: String = ""

    @Option(name: .customLong("base-dir"), help: "Base or destination directory (positional arg 2)")
    var baseDirectory: String?

    @Option(name: .customLong("listfile"), help: "Read file/mask list from file (!<path>). One entry per line; lines starting with # are comments")
    var listfiles: [String] = []

    @Option(name: .customLong("mask"), help: "Filename mask/glob pattern (positional args 3+). Supports * and ? wildcards")
    var masks: [String] = []

    @Option(name: .customLong("password"), help: "Password for encrypted archives (-g<password>)")
    var password: String?

    @Option(name: .customLong("target-dir"), help: "Target directory for extraction (-ht<dir>). Use instead of positional arg 2")
    var targetDirectory: String?

    @Option(name: .customLong("work-dir"), help: "Work directory for temporary files (-w<dir>). Mostly ignored in read-only mode")
    var workDirectory: String?

    @Option(name: .customLong("comment-file"), help: "Comment file path (-z<file>). Used in write mode to set archive comment")
    var commentFile: String?

    @Option(name: .customLong("compression-method"), help: "Compression method 0-4 (-m0..4). 0=stored, 1=packed, 2=squeezed, 3=crunched, 4=squashed (write mode)")
    var compressionMethod: Int?

    @Flag(name: .customLong("yes"), help: "Assume yes for all prompts (-y). Skip overwrite confirmations")
    var assumeYes: Bool = false

    @Flag(name: .customLong("no-progress"), help: "Suppress progress indicator (-i)")
    var noProgress: Bool = false

    @Flag(name: .customLong("overwrite-prompt"), help: "Prompt before overwriting existing files (-o)")
    var overwritePrompt: Bool = false

    @Flag(name: .customLong("strip-paths"), help: "Strip all paths during extraction (-e). Extract all files to target directory")
    var stripPaths: Bool = false

    @Flag(name: .customLong("keep-paths"), help: "Keep full paths when extracting (-p). Preserve directory structure from archive")
    var keepPaths: Bool = false

    @Flag(name: .customLong("keep-relative-paths"), help: "Keep relative paths when extracting (-p1). Strip leading absolute path components")
    var keepRelativePaths: Bool = false

    @Flag(name: .customLong("recursive"), help: "Recurse into subdirectories (-r). Include all files in subdirectories")
    var recursive: Bool = false

    @Flag(name: .customLong("crc-test"), help: "CRC test mode (-jt). Verify file integrity without extracting")
    var crcTest: Bool = false

    @Flag(name: .customLong("lowercase-names"), help: "Convert extracted filenames to lowercase (-_)")
    var lowercaseNames: Bool = false

    @Option(name: .customLong("exclude"), help: "Exclude files matching pattern (-x<mask>). Glob patterns: *.bin, file?.dat, [abc].txt. Can be used multiple times")
    var excludes: [String] = []

    /// Effective output root for extract commands (`-ht` or 2nd positional or cwd).
    var extractDestinationPath: String {
        targetDirectory ?? baseDirectory ?? FileManager.default.currentDirectoryPath
    }
}
