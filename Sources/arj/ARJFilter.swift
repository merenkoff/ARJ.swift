import ARJArchive
import Foundation

enum ARJFilter {
    static func resolvedMasks(masks: [String], listfiles: [String]) throws -> [String] {
        var result = masks
        for listPath in listfiles {
            guard FileManager.default.fileExists(atPath: listPath) else {
                throw ARJCLIError.exit(.warning, message: "list file not found: \(listPath)")
            }
            let text = try String(contentsOfFile: listPath, encoding: .utf8)
            let lines = text.split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result.append(contentsOf: lines)
        }
        if result.isEmpty {
            return ["*"]
        }
        return result
    }

    static func filterEntries(
        _ entries: [ARJEntry],
        masks: [String],
        excludes: [String],
        includeDirectories: Bool
    ) -> [ARJEntry] {
        entries.filter { entry in
            if entry.isDirectory, !includeDirectories {
                return false
            }
            return shouldInclude(entry: entry, masks: masks, excludes: excludes)
        }
    }

    static func shouldInclude(entry: ARJEntry, masks: [String], excludes: [String]) -> Bool {
        let candidates = [entry.name, entry.normalizedPath]
        let matchesSomeMask = masks.contains { mask in
            candidates.contains { ARJGlob.matches($0, pattern: mask) }
        }
        let excluded = excludes.contains { pattern in
            candidates.contains { ARJGlob.matches($0, pattern: pattern) }
        }
        return matchesSomeMask && !excluded
    }
}
