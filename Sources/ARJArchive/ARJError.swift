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
    /// Writing the archive to disk failed.
    case fileWriteFailed(path: String)
    /// An entry with this path already exists and the writer was asked not to replace it.
    case entryAlreadyExists(String)
    /// The entry name is empty after normalization.
    case invalidEntryName(String)
    /// Name and comment do not fit into the 2600-byte ARJ header limit.
    case headerTooLarge
    /// ARJ stores sizes as 32-bit values; the entry is 4 GiB or larger.
    case entryTooLarge
}
