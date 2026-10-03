import Foundation

/// Creates new ARJ archives or rewrites existing ones.
///
/// ```swift
/// var writer = ARJWriter(comment: "Backup")
/// try writer.addFile(named: "docs/readme.txt", data: readme)
/// try writer.addFile(named: "secret.txt", data: secret, password: "hunter2")
/// try writer.write(to: URL(fileURLWithPath: "backup.arj"))
/// ```
///
/// Entries taken over from an existing archive (`init(updating:)`) are copied byte for byte:
/// their payloads are never decompressed or re-encrypted, so keeping, renaming or deleting
/// entries works without passwords and preserves the original compression.
public struct ARJWriter: Sendable {
    /// What to do when an added entry has the same path as an entry already in the archive.
    public enum ExistingEntryPolicy: Sendable, Equatable {
        /// Replace the existing entry, keeping its position.
        case replace
        /// Keep the existing entry and ignore the new one.
        case skip
        /// Throw `ARJError.entryAlreadyExists`.
        case fail
    }

    public enum AddResult: Sendable, Equatable {
        case added
        case replaced
        case skipped
    }

    private struct Item: Sendable {
        var entry: ARJEntry
        /// Fixed part, name and comment; the CRC is computed when the archive is serialized.
        var basicHeader: Data
        var extendedHeaders: [Data]
        var payload: Data
    }

    /// Host OS recorded for entries added from now on; it selects the timestamp format (Unix time for
    /// `.unix`/`.next`, DOS date/time otherwise) and the meaning of `fileMode`.
    public var hostOS: ARJHostOS

    /// Archive modification time written into the main header; `nil` means the time of serialization.
    public var modificationDate: Date?

    private var items: [Item] = []
    private var mainFixedHeader: [UInt8]
    private var mainExtendedHeaders: [Data]
    private var archiveNameBytes: Data
    private var commentBytes: Data
    /// Bytes preceding the archive (self-extractor stub) that are written back unchanged.
    private var prefix: Data
    /// Set for archives whose main header is (re)built from scratch.
    private var creationDate: Date?

    /// Starts an empty archive.
    public init(archiveName: String = "", comment: String? = nil, hostOS: ARJHostOS = .dos) {
        self.hostOS = hostOS
        mainFixedHeader = Self.makeMainFixedHeader(hostOS: hostOS)
        mainExtendedHeaders = []
        archiveNameBytes = Data(archiveName.utf8)
        commentBytes = Data()
        prefix = Data()
        creationDate = Date()
        self.comment = comment
    }

    /// Starts from the contents of an existing archive.
    public init(updating archive: ARJArchive) throws {
        let (main, parsedEntries, data) = try archive.parsedArchive()
        hostOS = main.hostOS == .unknown ? .dos : main.hostOS
        prefix = data.prefix(main.prefixLength)
        mainExtendedHeaders = main.header.extendedHeaders.map(\.data)

        if main.header.fixedSize >= ARJFormat.minimumFirstHeaderSize {
            mainFixedHeader = Array(main.header.basicHeader.prefix(main.header.fixedSize))
            archiveNameBytes = main.header.nameBytes
            commentBytes = main.header.commentBytes
            creationDate = nil
        } else {
            // Malformed main header without a proper fixed part: rebuild it.
            mainFixedHeader = Self.makeMainFixedHeader(hostOS: hostOS)
            archiveNameBytes = Data()
            commentBytes = Data()
            creationDate = Date()
        }

        items = parsedEntries.map { parsed in
            Item(
                entry: parsed.entry,
                basicHeader: parsed.header.basicHeader,
                extendedHeaders: parsed.header.extendedHeaders.map(\.data),
                payload: data[parsed.dataRange]
            )
        }
    }

    public var archiveName: String {
        get { ARJFormat.decodeString(archiveNameBytes) ?? "" }
        set { archiveNameBytes = Self.headerStringBytes(newValue) }
    }

    public var comment: String? {
        get {
            guard !commentBytes.isEmpty else { return nil }
            return ARJFormat.decodeString(commentBytes)
        }
        set { commentBytes = Self.headerStringBytes(newValue ?? "") }
    }

    /// Entries in archive order, as they will be written.
    public var entries: [ARJEntry] {
        items.map(\.entry)
    }

    // MARK: - Adding

    /// Adds a file entry, compressing `data` with `method` (falling back to `.stored` when that does not
    /// make it smaller) and garbling it with `password` if one is given.
    @discardableResult
    public mutating func addFile(
        named name: String,
        data: Data,
        modified: Date = Date(),
        method: ARJCompressionMethod = .compressedMost,
        password: String? = nil,
        comment: String? = nil,
        fileMode: UInt16? = nil,
        ifExists policy: ExistingEntryPolicy = .replace
    ) throws -> AddResult {
        let path = try Self.validatedPath(name)
        if password != nil {
            try prepareForGarbledEntry()
        }
        let hostOS = hostOS
        return try insert(path: path, policy: policy) {
            try Self.makeItem(
                path: path,
                data: data,
                isDirectory: false,
                modified: modified,
                method: method,
                password: password,
                comment: comment,
                fileMode: fileMode,
                hostOS: hostOS
            )
        }
    }

    /// Adds the regular file at `url`, taking its modification date and permissions from the file system.
    /// The entry is named `name` or, by default, the file's last path component.
    @discardableResult
    public mutating func addFile(
        at url: URL,
        named name: String? = nil,
        method: ARJCompressionMethod = .compressedMost,
        password: String? = nil,
        comment: String? = nil,
        ifExists policy: ExistingEntryPolicy = .replace
    ) throws -> AddResult {
        let path = url.path
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ARJError.fileReadFailed(path: path)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = attributes?[.modificationDate] as? Date ?? Date()
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
        return try addFile(
            named: name ?? url.lastPathComponent,
            data: data,
            modified: modified,
            method: method,
            password: password,
            comment: comment,
            fileMode: permissions.map { Self.fileMode(fromPermissions: $0, isDirectory: false, hostOS: hostOS) },
            ifExists: policy
        )
    }

    /// Adds a directory entry (ARJ file type 3).
    @discardableResult
    public mutating func addDirectory(
        named name: String,
        modified: Date = Date(),
        comment: String? = nil,
        fileMode: UInt16? = nil,
        ifExists policy: ExistingEntryPolicy = .replace
    ) throws -> AddResult {
        let path = try Self.validatedPath(name)
        let hostOS = hostOS
        return try insert(path: path, policy: policy) {
            try Self.makeItem(
                path: path,
                data: Data(),
                isDirectory: true,
                modified: modified,
                method: .stored,
                password: nil,
                comment: comment,
                fileMode: fileMode,
                hostOS: hostOS
            )
        }
    }

    // MARK: - Removing and renaming

    /// Removes every entry matching `shouldRemove`; returns how many were removed.
    @discardableResult
    public mutating func removeEntries(where shouldRemove: (ARJEntry) throws -> Bool) rethrows -> Int {
        let before = items.count
        try items.removeAll { try shouldRemove($0.entry) }
        return before - items.count
    }

    /// Removes the entry with the given path; returns `false` when there is none.
    @discardableResult
    public mutating func removeEntry(named name: String) -> Bool {
        let path = ARJFormat.normalizedEntryPath(name)
        return removeEntries { ARJFormat.normalizedEntryPath($0.name) == path } > 0
    }

    /// Renames an entry without touching its payload.
    public mutating func renameEntry(named name: String, to newName: String) throws {
        let path = ARJFormat.normalizedEntryPath(name)
        let newPath = try Self.validatedPath(newName)
        guard let index = indexOfEntry(path: path) else {
            throw ARJError.entryNotFound
        }
        if newPath != path, indexOfEntry(path: newPath) != nil {
            throw ARJError.entryAlreadyExists(newPath)
        }

        var item = items[index]
        let old = ARJParsedHeaderView(basicHeader: item.basicHeader)
        var fixed = old.fixedPart
        fixed.setLittleEndian(Self.filespecPosition(of: newPath), at: ARJFormat.Offset.filespecPosition)
        if !ARJTimestamp.usesUnixTime(item.entry.hostOS) {
            fixed[ARJFormat.Offset.flags] |= ARJFormat.Flag.pathSymbol
        }
        item.basicHeader = try Self.makeBasicHeader(fixed: fixed, name: Data(newPath.utf8), comment: old.commentBytes)
        let entry = item.entry
        item.entry = ARJEntry(
            name: newPath,
            compressedSize: entry.compressedSize,
            originalSize: entry.originalSize,
            compressionMethod: entry.compressionMethod,
            fileType: entry.fileType,
            hostOS: entry.hostOS,
            crc32: entry.crc32,
            isEncrypted: entry.isEncrypted,
            modified: entry.modified,
            isDirectory: entry.isDirectory,
            comment: entry.comment,
            fileMode: entry.fileMode
        )
        items[index] = item
    }

    // MARK: - Output

    /// Serializes the archive.
    public func makeData() throws -> Data {
        var fixed = mainFixedHeader
        if let creationDate {
            fixed[ARJFormat.Offset.hostOS] = hostOS.rawValue
            fixed.setLittleEndian(ARJTimestamp.encode(creationDate, hostOS: hostOS), at: ARJFormat.Offset.archiveCreated)
        }
        let mainHostOS = ARJHostOS(rawHostOS: fixed[ARJFormat.Offset.hostOS])
        fixed.setLittleEndian(
            ARJTimestamp.encode(modificationDate ?? Date(), hostOS: mainHostOS),
            at: ARJFormat.Offset.archiveModified
        )

        // A rewritten archive no longer matches any security envelope.
        fixed[ARJFormat.Offset.flags] &= ~(ARJFormat.Flag.garbled | ARJFormat.Flag.oldSecured | ARJFormat.Flag.secured)
        fixed.setLittleEndian(UInt32(0), at: ARJFormat.Offset.archiveSize)
        fixed.setLittleEndian(UInt32(0), at: ARJFormat.Offset.securityEnvelopePosition)
        fixed.setLittleEndian(UInt16(0), at: ARJFormat.Offset.securityEnvelopeLength)
        if items.contains(where: { $0.entry.isEncrypted }) {
            fixed[ARJFormat.Offset.flags] |= ARJFormat.Flag.garbled
            if fixed[ARJFormat.Offset.encryptionVersion] < ARJFormat.firstUnsupportedEncryptionVersion {
                fixed[ARJFormat.Offset.encryptionVersion] = ARJFormat.standardEncryptionVersion
            }
        }

        var output = Data()
        output.append(prefix)
        Self.appendHeader(
            to: &output,
            basicHeader: try Self.makeBasicHeader(fixed: fixed, name: archiveNameBytes, comment: commentBytes),
            extendedHeaders: mainExtendedHeaders
        )
        for item in items {
            Self.appendHeader(to: &output, basicHeader: item.basicHeader, extendedHeaders: item.extendedHeaders)
            output.append(item.payload)
        }
        output.append(contentsOf: [0x60, 0xEA, 0x00, 0x00])
        return output
    }

    /// Serializes the archive and writes it atomically to `url`.
    public func write(to url: URL) throws {
        let data = try makeData()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ARJError.fileWriteFailed(path: url.path)
        }
    }

    // MARK: - Private

    private func indexOfEntry(path: String) -> Int? {
        items.firstIndex { ARJFormat.normalizedEntryPath($0.entry.name) == path }
    }

    private mutating func insert(
        path: String,
        policy: ExistingEntryPolicy,
        makeItem: () throws -> Item
    ) throws -> AddResult {
        guard let index = indexOfEntry(path: path) else {
            items.append(try makeItem())
            return .added
        }
        switch policy {
        case .skip:
            return .skipped
        case .fail:
            throw ARJError.entryAlreadyExists(path)
        case .replace:
            items[index] = try makeItem()
            return .replaced
        }
    }

    /// XOR entries cannot be mixed with GOST-encrypted ones, which share the archive-wide encryption version.
    private mutating func prepareForGarbledEntry() throws {
        let offset = ARJFormat.Offset.encryptionVersion
        guard mainFixedHeader.count > offset,
              mainFixedHeader[offset] >= ARJFormat.firstUnsupportedEncryptionVersion
        else { return }
        if items.contains(where: { $0.entry.isEncrypted }) {
            throw ARJError.unsupportedEncryptedArchive
        }
        mainFixedHeader[offset] = ARJFormat.standardEncryptionVersion
    }

    private static func makeItem(
        path: String,
        data: Data,
        isDirectory: Bool,
        modified: Date,
        method: ARJCompressionMethod,
        password: String?,
        comment: String?,
        fileMode: UInt16?,
        hostOS: ARJHostOS
    ) throws -> Item {
        guard data.count <= Int(UInt32.max) else {
            throw ARJError.entryTooLarge
        }
        var passwordBytes: [UInt8]?
        if let password {
            guard !password.isEmpty else { throw ARJError.passwordRequired }
            passwordBytes = Array(password.utf8)
        }

        let encoded = try ARJCodec.encode(data, method: method)
        let rawTime = ARJTimestamp.encode(modified, hostOS: hostOS)
        var payload = encoded.payload
        var flags: UInt8 = ARJTimestamp.usesUnixTime(hostOS) ? 0 : ARJFormat.Flag.pathSymbol
        var passwordModifier: UInt8 = 0
        if let passwordBytes, !isDirectory {
            passwordModifier = UInt8(truncatingIfNeeded: rawTime)
            payload = ARJCodec.garble(payload, password: passwordBytes, modifier: passwordModifier)
            flags |= ARJFormat.Flag.garbled
        }

        let crc = CRC32.compute(data)
        let fileType = isDirectory ? ARJFormat.FileType.directory : ARJFormat.FileType.binary
        let mode = fileMode ?? defaultFileMode(isDirectory: isDirectory, hostOS: hostOS)

        var fixed = [UInt8](repeating: 0, count: ARJFormat.fileHeaderFixedSize)
        fixed[ARJFormat.Offset.firstHeaderSize] = UInt8(ARJFormat.fileHeaderFixedSize)
        fixed[ARJFormat.Offset.archiverVersion] = ARJFormat.archiverVersion
        fixed[ARJFormat.Offset.minimumVersion] = ARJFormat.minimumExtractVersion
        fixed[ARJFormat.Offset.hostOS] = hostOS.rawValue
        fixed[ARJFormat.Offset.flags] = flags
        fixed[ARJFormat.Offset.method] = encoded.method.rawValue
        fixed[ARJFormat.Offset.fileType] = fileType
        fixed[ARJFormat.Offset.passwordModifier] = passwordModifier
        fixed.setLittleEndian(rawTime, at: ARJFormat.Offset.fileModified)
        fixed.setLittleEndian(UInt32(payload.count), at: ARJFormat.Offset.compressedSize)
        fixed.setLittleEndian(UInt32(data.count), at: ARJFormat.Offset.originalSize)
        fixed.setLittleEndian(crc, at: ARJFormat.Offset.fileCRC)
        fixed.setLittleEndian(filespecPosition(of: path), at: ARJFormat.Offset.filespecPosition)
        fixed.setLittleEndian(mode, at: ARJFormat.Offset.fileMode)

        let commentBytes = headerStringBytes(comment ?? "")
        let basicHeader = try makeBasicHeader(fixed: fixed, name: Data(path.utf8), comment: commentBytes)
        let entry = ARJEntry(
            name: path,
            compressedSize: UInt32(payload.count),
            originalSize: UInt32(data.count),
            compressionMethod: encoded.method,
            fileType: fileType,
            hostOS: hostOS,
            crc32: crc,
            isEncrypted: (flags & ARJFormat.Flag.garbled) != 0,
            modified: ARJTimestamp.decode(rawTime, hostOS: hostOS),
            isDirectory: isDirectory,
            comment: commentBytes.isEmpty ? nil : ARJFormat.decodeString(commentBytes),
            fileMode: mode
        )
        return Item(entry: entry, basicHeader: basicHeader, extendedHeaders: [], payload: payload)
    }

    private static func makeMainFixedHeader(hostOS: ARJHostOS) -> [UInt8] {
        var fixed = [UInt8](repeating: 0, count: ARJFormat.mainHeaderFixedSize)
        fixed[ARJFormat.Offset.firstHeaderSize] = UInt8(ARJFormat.mainHeaderFixedSize)
        fixed[ARJFormat.Offset.archiverVersion] = ARJFormat.archiverVersion
        fixed[ARJFormat.Offset.minimumVersion] = ARJFormat.minimumExtractVersion
        fixed[ARJFormat.Offset.hostOS] = hostOS.rawValue
        fixed[ARJFormat.Offset.flags] = ARJFormat.Flag.pathSymbol
        fixed[ARJFormat.Offset.fileType] = ARJFormat.FileType.mainHeader
        return fixed
    }

    private static func makeBasicHeader(fixed: [UInt8], name: Data, comment: Data) throws -> Data {
        var header = Data(fixed)
        header.append(name)
        header.append(0)
        header.append(comment)
        header.append(0)
        guard header.count <= ARJFormat.maximumBasicHeaderSize else {
            throw ARJError.headerTooLarge
        }
        return header
    }

    private static func appendHeader(to output: inout Data, basicHeader: Data, extendedHeaders: [Data]) {
        output.appendLittleEndian(ARJFormat.headerID)
        output.appendLittleEndian(UInt16(basicHeader.count))
        output.append(basicHeader)
        output.appendLittleEndian(CRC32.compute(basicHeader))
        for extended in extendedHeaders {
            output.appendLittleEndian(UInt16(extended.count))
            output.append(extended)
            output.appendLittleEndian(CRC32.compute(extended))
        }
        output.appendLittleEndian(UInt16(0))
    }

    private static func validatedPath(_ name: String) throws -> String {
        let path = ARJFormat.normalizedEntryPath(name)
        guard !path.isEmpty, !path.utf8.contains(0) else {
            throw ARJError.invalidEntryName(name)
        }
        return path
    }

    /// Header strings are NUL-terminated, so embedded NULs are dropped.
    private static func headerStringBytes(_ string: String) -> Data {
        Data(string.utf8.filter { $0 != 0 })
    }

    /// Byte offset of the file name within the stored path.
    private static func filespecPosition(of path: String) -> UInt16 {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return 0 }
        return UInt16(clamping: path.utf8.distance(from: path.utf8.startIndex, to: slash) + 1)
    }

    private static func defaultFileMode(isDirectory: Bool, hostOS: ARJHostOS) -> UInt16 {
        if ARJTimestamp.usesUnixTime(hostOS) {
            return isDirectory ? 0o040755 : 0o100644
        }
        return isDirectory ? 0x10 : 0x20
    }

    private static func fileMode(fromPermissions permissions: UInt16, isDirectory: Bool, hostOS: ARJHostOS) -> UInt16 {
        if ARJTimestamp.usesUnixTime(hostOS) {
            return (isDirectory ? 0o040000 : 0o100000) | (permissions & 0o7777)
        }
        let readOnly: UInt16 = (permissions & 0o200) == 0 ? 0x01 : 0
        return defaultFileMode(isDirectory: isDirectory, hostOS: hostOS) | readOnly
    }
}

/// Splits a serialized basic header back into its parts (used when rewriting a header).
private struct ARJParsedHeaderView {
    let fixedPart: [UInt8]
    let commentBytes: Data

    init(basicHeader: Data) {
        let block = ARJHeaderBlock(basicHeader: basicHeader, storedCRC: 0, extendedHeaders: [])
        var fixed = Array(basicHeader.prefix(max(block.fixedSize, ARJFormat.minimumFirstHeaderSize)))
        fixed[ARJFormat.Offset.firstHeaderSize] = UInt8(fixed.count)
        fixedPart = fixed
        commentBytes = block.commentBytes
    }
}
