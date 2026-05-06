import ARJArchive
import Foundation

/// ARJ-compatible process exit codes (errorlevels).
enum ARJExitCode: Int32 {
    case success = 0
    case warning = 1
    case fatalError = 2
    case crcOrPasswordError = 3
    case securityError = 4
    case diskFullOrWriteError = 5
    case cannotOpen = 6
    case userParameterError = 7
    case outOfMemory = 8
    case notArjArchive = 9
    case xmsMemoryError = 10
    case userCtrlC = 11
    case tooManyChapters = 12

    func exit(message: String? = nil) -> Never {
        if let message {
            FileHandle.standardError.write(Data("arj: \(message)\n".utf8))
        }
        Darwin.exit(rawValue)
    }
}

enum ARJCLIError: Error {
    case exit(ARJExitCode, message: String? = nil)
}

extension ARJCLIError {
    func exitProcess() -> Never {
        switch self {
        case let .exit(code, message):
            code.exit(message: message)
        }
    }
}

enum ARJErrorMapper {
    static func exitCode(for error: Error) -> ARJExitCode {
        guard let arj = error as? ARJError else {
            return .fatalError
        }
        switch arj {
        case .fileReadFailed, .unexpectedEOF:
            return .cannotOpen
        case .invalidArchiveSignature, .invalidHeaderSize, .invalidHeaderCRC, .malformedHeader:
            return .notArjArchive
        case .wrongPassword, .passwordRequired, .crcMismatch:
            return .crcOrPasswordError
        case .unsupportedEncryptedArchive, .unsupportedCompressionMethod, .cCoreFailure:
            return .fatalError
        case .entryNotFound:
            return .warning
        }
    }

    static func message(for error: Error) -> String {
        if let arj = error as? ARJError {
            switch arj {
            case let .fileReadFailed(path):
                return "cannot read file: \(path)"
            case .invalidArchiveSignature:
                return "invalid archive signature"
            case .unexpectedEOF:
                return "unexpected end of archive"
            case let .invalidHeaderSize(size):
                return "invalid header size: \(size)"
            case .invalidHeaderCRC:
                return "invalid header CRC"
            case .malformedHeader:
                return "malformed header"
            case .unsupportedEncryptedArchive:
                return "encrypted archive uses unsupported algorithm (GOST)"
            case let .unsupportedCompressionMethod(method):
                return "unsupported compression method: \(method.rawValue)"
            case .entryNotFound:
                return "entry not found"
            case .cCoreFailure:
                return "decoder failure"
            case .passwordRequired:
                return "password required"
            case .wrongPassword:
                return "wrong password or CRC error"
            case .crcMismatch:
                return "CRC error"
            }
        }
        return String(describing: error)
    }
}
