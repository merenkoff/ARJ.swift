import Foundation

extension ArchiveOperationOptions {
    func validateArchiveArgument() throws {
        guard !archive.isEmpty else {
            throw ARJCLIError.exit(.userParameterError, message: "missing archive name")
        }
    }
}
