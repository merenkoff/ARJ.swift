import CARJCore
import Foundation

/// Swift front end for the C codec plus the XOR "garble" used by password-protected entries.
enum ARJCodec {
    struct Encoded {
        let method: ARJCompressionMethod
        let payload: Data
    }

    /// Compresses `data` with `method`, falling back to `.stored` when compression does not shrink the data.
    /// Every compressed result is decoded again and compared, so a codec defect can only cost ratio, never data.
    static func encode(_ data: Data, method: ARJCompressionMethod) throws -> Encoded {
        switch method {
        case .stored:
            return Encoded(method: .stored, payload: data)
        case .unknown:
            throw ARJError.unsupportedCompressionMethod(method)
        case .compressedMost, .compressed, .compressedFaster, .compressedFastest:
            break
        }

        // Anything that does not end up strictly smaller is stored instead.
        guard data.count > 1, let compressed = try compress(data, method: method, capacity: data.count - 1) else {
            return Encoded(method: .stored, payload: data)
        }
        guard let roundTrip = try? decode(compressed, method: method, originalSize: data.count), roundTrip == data else {
            return Encoded(method: .stored, payload: data)
        }
        return Encoded(method: method, payload: compressed)
    }

    /// Raw compression; returns `nil` when the output would exceed `capacity` bytes.
    static func compress(_ data: Data, method: ARJCompressionMethod, capacity: Int) throws -> Data? {
        var output = Data(count: max(capacity, 1))
        var written = 0
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                arj_core_encode(
                    method.rawValue,
                    input.bindMemory(to: UInt8.self).baseAddress,
                    input.count,
                    out.bindMemory(to: UInt8.self).baseAddress,
                    capacity,
                    &written
                )
            }
        }
        switch status {
        case ARJ_CORE_OK:
            output.count = written
            return output
        case ARJ_CORE_BUFFER_TOO_SMALL:
            return nil
        case ARJ_CORE_UNSUPPORTED_METHOD:
            throw ARJError.unsupportedCompressionMethod(method)
        default:
            throw ARJError.cCoreFailure
        }
    }

    /// Decodes a payload into exactly `originalSize` bytes (CRC is checked by the caller).
    /// Fails when the payload cannot produce that many bytes, e.g. a stored entry whose sizes disagree.
    static func decode(_ payload: Data, method: ARJCompressionMethod, originalSize: Int) throws -> Data {
        var output = Data(count: originalSize)
        var written = 0
        let status = payload.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                arj_core_decode(
                    method.rawValue,
                    input.bindMemory(to: UInt8.self).baseAddress,
                    input.count,
                    out.bindMemory(to: UInt8.self).baseAddress,
                    originalSize,
                    &written
                )
            }
        }
        if status == ARJ_CORE_UNSUPPORTED_METHOD {
            throw ARJError.unsupportedCompressionMethod(method)
        }
        guard status == ARJ_CORE_OK, written == originalSize else {
            throw ARJError.cCoreFailure
        }
        return output
    }

    /// ARJ "garble": XOR with `password[i % n] + modifier`. The operation is its own inverse.
    static func garble(_ input: Data, password: [UInt8], modifier: UInt8) -> Data {
        guard !password.isEmpty else { return input }
        var output = Data(count: input.count)
        let passwordCount = password.count
        input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                guard
                    let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return }
                for index in 0..<input.count {
                    outputBase[index] = inputBase[index] ^ (modifier &+ password[index % passwordCount])
                }
            }
        }
        return output
    }
}
