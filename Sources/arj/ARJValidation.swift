import Foundation

extension ArchiveOperationOptions {
    func validateArchiveArgument() throws {
        guard !archive.isEmpty else {
            throw ARJCLIError.exit(.userParameterError, message: "missing archive name")
        }
    }

    func validateExtractPathSwitches(command: String) throws {
        let selectedCount = [stripPaths, keepPaths, keepRelativePaths].filter { $0 }.count
        guard selectedCount <= 1 else {
            throw ARJCLIError.exit(
                .userParameterError,
                message: "conflicting path switches for \(command): use only one of -e, -p, -p1"
            )
        }
    }
}
