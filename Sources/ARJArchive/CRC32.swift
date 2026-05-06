import Foundation

enum CRC32 {
    private static let table: [UInt32] = {
        let polynomial: UInt32 = 0xEDB8_8320
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                if (value & 1) != 0 {
                    value = (value >> 1) ^ polynomial
                } else {
                    value >>= 1
                }
            }
            table[index] = value
        }
        return table
    }()

    static func compute<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            let lookupIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[lookupIndex]
        }
        return crc ^ 0xFFFF_FFFF
    }
}
