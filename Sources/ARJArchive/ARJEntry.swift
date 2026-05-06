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
    public let modified: Date
    public let isDirectory: Bool

    public var normalizedPath: String {
        var converted = name.replacingOccurrences(of: "\\", with: "/")
        while converted.hasSuffix("/") {
            converted.removeLast()
        }
        return converted
    }

    public var compressionRatio: Double? {
        guard originalSize > 0 else { return nil }
        return Double(compressedSize) / Double(originalSize)
    }
}
