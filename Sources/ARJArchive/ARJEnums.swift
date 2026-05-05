import Foundation

public enum ARJCompressionMethod: UInt8, Sendable, Equatable {
    case stored = 0
    case compressedMost = 1
    case compressed = 2
    case compressedFaster = 3
    case compressedFastest = 4
    case unknown = 255

    init(rawMethod: UInt8) {
        self = ARJCompressionMethod(rawValue: rawMethod) ?? .unknown
    }
}

public enum ARJHostOS: UInt8, Sendable, Equatable {
    case dos = 0
    case primos = 1
    case unix = 2
    case amiga = 3
    case macos = 4
    case os2 = 5
    case appleGS = 6
    case atari = 7
    case next = 8
    case vaxVMS = 9
    case windows95 = 10
    case windowsNT = 11
    case unknown = 255

    init(rawHostOS: UInt8) {
        self = ARJHostOS(rawValue: rawHostOS) ?? .unknown
    }
}
