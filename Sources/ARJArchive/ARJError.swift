import Foundation

public enum ARJError: Error, Sendable, Equatable {
    case fileReadFailed(path: String)
    case invalidArchiveSignature
    case unexpectedEOF
    case invalidHeaderSize(UInt16)
    case invalidHeaderCRC
    case malformedHeader
    case unsupportedEncryptedArchive
    case unsupportedCompressionMethod(ARJCompressionMethod)
    case entryNotFound
    case cCoreFailure
    case passwordRequired
    case wrongPassword
    /// Decoded payload CRC32 does not match the header (non-encrypted entries).
    case crcMismatch
}
