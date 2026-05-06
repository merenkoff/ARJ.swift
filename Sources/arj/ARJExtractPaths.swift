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
        case .structured:
            relativePath = entry.normalizedPath
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
        /// `x` default
        case structured
    }
}
