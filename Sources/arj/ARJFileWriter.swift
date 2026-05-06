import Darwin
import Foundation

enum ARJFileWriter {
    /// Writes `data` to `url`, creating parent directories. Returns whether a warning occurred (skipped existing).
    @discardableResult
    static func write(
        data: Data,
        to url: URL,
        assumeYes: Bool,
        overwritePrompt: Bool
    ) throws -> Bool {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        if fm.fileExists(atPath: url.path) {
            if assumeYes {
                try data.write(to: url)
                return false
            }
            if overwritePrompt {
                let tty = isatty(STDIN_FILENO) != 0
                if tty {
                    FileHandle.standardError.write(Data("overwrite \(url.path)? [y/N] ".utf8))
                    guard let line = readLine()?.lowercased(), line == "y" || line == "yes" else {
                        return true
                    }
                } else {
                    return true
                }
            } else {
                return true
            }
        }

        try data.write(to: url)
        return false
    }
}
