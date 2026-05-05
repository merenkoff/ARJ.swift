import Foundation

public struct ARJEntry: Sendable, Equatable {
    public let name: String
    public let compressedSize: UInt32
    public let originalSize: UInt32
    public let compressionMethod: ARJCompressionMethod
    public let fileType: UInt8
    public let hostOS: ARJHostOS
    public let crc32: UInt32
    public let isEncrypted: Bool
}
