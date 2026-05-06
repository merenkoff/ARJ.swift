import Foundation
import CARJCore

public struct ARJArchive: Sendable {
    private let data: Data
    private let info: ARJArchiveInfo?

    public init(path: String) throws {
        guard let fileData = FileManager.default.contents(atPath: path) else {
            throw ARJError.fileReadFailed(path: path)
        }
        self.init(data: fileData)
    }

    public init(data: Data) {
        self.data = data
        var parser = ARJParser(data: data)
        self.info = try? parser.parseArchiveInfo()
    }

    public var archiveComment: String? {
        info?.comment
    }

    public var archiveName: String {
        info?.archiveName ?? ""
    }

    public func entries() throws -> [ARJEntry] {
        var parser = ARJParser(data: data)
        return try parser.parseEntries()
    }

    public func extract(entry: ARJEntry, password: String? = nil) throws -> Data {
        let parsed = try parsedEntry(for: entry)
        return try extractData(from: parsed, password: password)
    }

    public func extract(named name: String, password: String? = nil) throws -> Data {
        let parsedEntries = try allParsedEntries()
        guard let parsed = parsedEntries.first(where: { $0.entry.name == name }) else {
            throw ARJError.entryNotFound
        }
        return try extractData(from: parsed, password: password)
    }

    public func extractFirstStored(named name: String) -> Data? {
        guard let parsedEntries = try? allParsedEntries() else {
            return nil
        }
        guard let parsed = parsedEntries.first(where: { $0.entry.name == name }) else {
            return nil
        }
        return try? extractData(from: parsed, password: nil)
    }

    public func extractFirstStored(entry: ARJEntry) -> Data? {
        guard let parsed = try? parsedEntry(for: entry) else {
            return nil
        }
        return try? extractData(from: parsed, password: nil)
    }

    public func extractAllStored() throws -> [String: Data] {
        let parsedEntries = try allParsedEntries()
        var result: [String: Data] = [:]

        for parsed in parsedEntries where parsed.entry.compressionMethod == .stored && !parsed.entry.isEncrypted {
            result[parsed.entry.name] = data.subdata(in: parsed.dataRange)
        }

        return result
    }

    private func allParsedEntries() throws -> [ARJParsedEntry] {
        var parser = ARJParser(data: data)
        return try parser.parseEntriesDetailed()
    }

    private func parsedEntry(for entry: ARJEntry) throws -> ARJParsedEntry {
        let parsedEntries = try allParsedEntries()
        guard let parsed = parsedEntries.first(where: { $0.entry == entry }) else {
            throw ARJError.entryNotFound
        }
        return parsed
    }

    private func extractData(from parsed: ARJParsedEntry, password: String?) throws -> Data {
        if parsed.entry.isEncrypted && password == nil {
            throw ARJError.passwordRequired
        }

        var compressedData = data.subdata(in: parsed.dataRange)
        if parsed.entry.isEncrypted, let password = password {
            let passwordBytes = Array(password.utf8)
            guard !passwordBytes.isEmpty else {
                throw ARJError.passwordRequired
            }
            compressedData = applyXOR(
                input: compressedData,
                password: passwordBytes,
                modifier: parsed.passwordModifier
            )
        }

        let outputSize = Int(parsed.entry.originalSize)
        var output = Data(count: outputSize)
        var writtenSize: Int = 0

        let status = compressedData.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                arj_core_decode(
                    parsed.entry.compressionMethod.rawValue,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    compressedData.count,
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    outputSize,
                    &writtenSize
                )
            }
        }

        if status == ARJ_CORE_UNSUPPORTED_METHOD {
            throw ARJError.unsupportedCompressionMethod(parsed.entry.compressionMethod)
        }

        guard status == ARJ_CORE_OK else {
            if parsed.entry.isEncrypted {
                throw ARJError.wrongPassword
            }
            throw ARJError.cCoreFailure
        }

        if writtenSize < output.count {
            output.removeSubrange(writtenSize..<output.count)
        }

        let computedCRC = CRC32.compute(output)
        if computedCRC != parsed.entry.crc32 {
            if parsed.entry.isEncrypted {
                throw ARJError.wrongPassword
            }
            // For non-encrypted entries we keep current behaviour and return the data;
            // CRC integrity validation is out of scope for this revision.
        }

        return output
    }

    private func applyXOR(input: Data, password: [UInt8], modifier: UInt8) -> Data {
        var output = Data(count: input.count)
        let passwordCount = password.count
        input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                guard
                    let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return }
                for index in 0..<input.count {
                    let passwordByte = password[index % passwordCount]
                    let keyByte = modifier &+ passwordByte
                    outputBase[index] = inputBase[index] ^ keyByte
                }
            }
        }
        return output
    }
}
