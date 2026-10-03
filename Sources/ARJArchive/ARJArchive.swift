import Foundation

public struct ARJArchive: Sendable {
    private let data: Data
    let mainHeader: ARJParsedMainHeader?
    private let parsedEntries: Result<[ARJParsedEntry], ARJError>

    public init(path: String) throws {
        guard let fileData = FileManager.default.contents(atPath: path) else {
            throw ARJError.fileReadFailed(path: path)
        }
        self.init(data: fileData)
    }

    public init(data: Data) {
        // The parser and the stored ranges use zero-based offsets.
        let data = data.startIndex == 0 ? data : Data(data)
        self.data = data

        var parser = ARJParser(data: data)
        do {
            let main = try parser.parseMainHeader()
            mainHeader = main
            do {
                parsedEntries = .success(try parser.parseEntries())
            } catch {
                parsedEntries = .failure(Self.arjError(error))
            }
        } catch {
            mainHeader = nil
            parsedEntries = .failure(Self.arjError(error))
        }
    }

    public var archiveComment: String? {
        mainHeader?.comment
    }

    public var archiveName: String {
        mainHeader?.archiveName ?? ""
    }

    public func entries() throws -> [ARJEntry] {
        try parsedEntries.get().map(\.entry)
    }

    public func extract(entry: ARJEntry, password: String? = nil) throws -> Data {
        let parsed = try parsedEntry(for: entry)
        return try extractData(from: parsed, password: password)
    }

    public func extract(named name: String, password: String? = nil) throws -> Data {
        guard let parsed = try parsedEntries.get().first(where: { $0.entry.name == name }) else {
            throw ARJError.entryNotFound
        }
        return try extractData(from: parsed, password: password)
    }

    public func extractFirstStored(named name: String) -> Data? {
        guard let parsed = try? parsedEntries.get().first(where: { $0.entry.name == name }) else {
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
        var result: [String: Data] = [:]
        for parsed in try parsedEntries.get()
            where parsed.entry.compressionMethod == .stored && !parsed.entry.isEncrypted {
            result[parsed.entry.name] = data.subdata(in: parsed.dataRange)
        }
        return result
    }

    /// Verifies the CRC32 of the main header and of every file header (including extended headers).
    /// Payload CRCs are checked separately by `extract`.
    public func validateHeaderCRCs() throws {
        let entries = try parsedEntries.get()
        guard let mainHeader, mainHeader.header.hasValidCRCs else {
            throw ARJError.invalidHeaderCRC
        }
        for parsed in entries where !parsed.header.hasValidCRCs {
            throw ARJError.invalidHeaderCRC
        }
    }

    // MARK: - Internal access for ARJWriter

    func parsedArchive() throws -> (main: ARJParsedMainHeader, entries: [ARJParsedEntry], data: Data) {
        let entries = try parsedEntries.get()
        guard let mainHeader else { throw ARJError.malformedHeader }
        return (mainHeader, entries, data)
    }

    // MARK: - Private

    private static func arjError(_ error: Error) -> ARJError {
        (error as? ARJError) ?? .malformedHeader
    }

    private func parsedEntry(for entry: ARJEntry) throws -> ARJParsedEntry {
        guard let parsed = try parsedEntries.get().first(where: { $0.entry == entry }) else {
            throw ARJError.entryNotFound
        }
        return parsed
    }

    private func extractData(from parsed: ARJParsedEntry, password: String?) throws -> Data {
        let entry = parsed.entry
        if entry.isEncrypted,
           let version = mainHeader?.encryptionVersion,
           version >= ARJFormat.firstUnsupportedEncryptionVersion {
            throw ARJError.unsupportedEncryptedArchive
        }
        if entry.isEncrypted && password == nil {
            throw ARJError.passwordRequired
        }
        if entry.compressionMethod == .stored && entry.compressedSize != entry.originalSize {
            throw ARJError.crcMismatch
        }

        var payload = data.subdata(in: parsed.dataRange)
        if entry.isEncrypted, let password {
            let passwordBytes = Array(password.utf8)
            guard !passwordBytes.isEmpty else {
                throw ARJError.passwordRequired
            }
            payload = ARJCodec.garble(payload, password: passwordBytes, modifier: parsed.passwordModifier)
        }

        let output: Data
        do {
            output = try ARJCodec.decode(payload, method: entry.compressionMethod, originalSize: Int(entry.originalSize))
        } catch ARJError.cCoreFailure where entry.isEncrypted {
            throw ARJError.wrongPassword
        }

        if CRC32.compute(output) != entry.crc32 {
            throw entry.isEncrypted ? ARJError.wrongPassword : ARJError.crcMismatch
        }
        return output
    }
}
