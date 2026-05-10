import ARJArchive
import Foundation

enum ARJExtractPaths {
    /// Resolves the on-disk path for an extracted file.
    static func outputPath(
        for entry: ARJEntry,
        options: ArchiveOperationOptions,
        mode: ExtractMode
    ) -> URL {
        let root = URL(fileURLWithPath: options.extractDestinationPath, isDirectory: true)
        let relativePath: String
        switch mode {
        case .flat:
            relativePath = URL(fileURLWithPath: entry.normalizedPath).lastPathComponent
        case .structuredStripPaths:
            relativePath = URL(fileURLWithPath: entry.normalizedPath).lastPathComponent
        case .structuredKeepRelativePaths:
            relativePath = relativePathForExtraction(from: entry.normalizedPath)
        case .structuredKeepFullPaths:
            relativePath = fullPathForExtraction(from: entry.normalizedPath)
        }
        var name = relativePath
        if options.lowercaseNames {
            name = name.lowercased()
        }
        return root.appendingPathComponent(name, isDirectory: false)
    }

    enum ExtractMode {
        /// `e` command
        case flat
        /// `x` with `-e`
        case structuredStripPaths
        /// `x` default and `-p1`
        case structuredKeepRelativePaths
        /// `x` with `-p`
        case structuredKeepFullPaths
    }

    private static func relativePathForExtraction(from normalizedPath: String) -> String {
        var path = normalizedPath.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("/") {
            path.removeFirst()
        }

        if path.count >= 3 {
            let chars = Array(path)
            if chars[1] == ":", chars[2] == "/" {
                path = String(path.dropFirst(3))
            }
        }

        return path
    }

    private static func fullPathForExtraction(from normalizedPath: String) -> String {
        let path = normalizedPath.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("/") {
            return "_root/" + String(path.drop(while: { $0 == "/" }))
        }
        if path.count >= 3 {
            let chars = Array(path)
            if chars[1] == ":", chars[2] == "/" {
                let drive = String(chars[0]).lowercased()
                let remainder = String(path.dropFirst(3))
                return "drive_\(drive)/\(remainder)"
            }
        }
        return path
    }
}
