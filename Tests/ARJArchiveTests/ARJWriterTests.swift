import Foundation
import XCTest
@testable import ARJArchive

final class ARJWriterTests: XCTestCase {
    private let compressedMethods: [ARJCompressionMethod] = [.compressedMost, .compressed, .compressedFaster, .compressedFastest]

    // MARK: - Codec

    func testEncoderRoundTripsAllMethodsWithoutFallback() throws {
        for (label, payload) in sampleInputs() where !payload.isEmpty {
            for method in compressedMethods {
                let capacity = payload.count + payload.count / 4 + 64
                let compressed = try XCTUnwrap(
                    try ARJCodec.compress(payload, method: method, capacity: capacity),
                    "\(label) m\(method.rawValue) did not fit"
                )
                let decoded = try ARJCodec.decode(compressed, method: method, originalSize: payload.count)
                XCTAssertEqual(decoded, payload, "\(label) m\(method.rawValue) round trip mismatch")
            }
        }
    }

    func testEncoderReportsInsufficientCapacity() throws {
        let random = randomData(count: 4096, seed: 7)
        for method in compressedMethods {
            XCTAssertNil(try ARJCodec.compress(random, method: method, capacity: random.count - 1))
        }
    }

    func testCompressibleDataUsesRequestedMethod() throws {
        let text = textData(count: 50_000)
        for method in compressedMethods {
            var writer = ARJWriter()
            try writer.addFile(named: "text.txt", data: text, method: method)
            let archive = ARJArchive(data: try writer.makeData())
            let entry = try XCTUnwrap(try archive.entries().first)
            XCTAssertEqual(entry.compressionMethod, method)
            XCTAssertLessThan(entry.compressedSize, entry.originalSize / 3)
            XCTAssertEqual(try archive.extract(entry: entry), text)
        }
    }

    func testIncompressibleDataFallsBackToStored() throws {
        let random = randomData(count: 10_000, seed: 3)
        var writer = ARJWriter()
        try writer.addFile(named: "random.bin", data: random, method: .compressedMost)
        let entry = try XCTUnwrap(writer.entries.first)
        XCTAssertEqual(entry.compressionMethod, .stored)
        XCTAssertEqual(entry.compressedSize, entry.originalSize)
        XCTAssertEqual(try ARJArchive(data: try writer.makeData()).extract(named: "random.bin"), random)
    }

    func testUnknownMethodIsRejected() {
        var writer = ARJWriter()
        XCTAssertThrowsError(try writer.addFile(named: "a", data: Data("abcabcabc".utf8), method: .unknown)) { error in
            XCTAssertEqual(error as? ARJError, .unsupportedCompressionMethod(.unknown))
        }
    }

    // MARK: - Creating archives

    func testRoundTripAllMethodsAndSizes() throws {
        for method in [ARJCompressionMethod.stored] + compressedMethods {
            var writer = ARJWriter(archiveName: "test.arj", comment: "comment")
            let inputs = sampleInputs()
            for (label, payload) in inputs {
                try writer.addFile(named: "dir/\(label).bin", data: payload, method: method)
            }
            let archive = ARJArchive(data: try writer.makeData())
            XCTAssertEqual(archive.archiveName, "test.arj")
            XCTAssertEqual(archive.archiveComment, "comment")
            XCTAssertNoThrow(try archive.validateHeaderCRCs())

            let entries = try archive.entries()
            XCTAssertEqual(entries.map(\.name), inputs.map { "dir/\($0.0).bin" })
            XCTAssertEqual(entries, writer.entries)
            for (entry, input) in zip(entries, inputs) {
                XCTAssertEqual(try archive.extract(entry: entry), input.1, "\(entry.name) m\(method.rawValue)")
            }
        }
    }

    func testDirectoryEntries() throws {
        var writer = ARJWriter()
        try writer.addDirectory(named: "docs/")
        try writer.addFile(named: "docs/readme.txt", data: Data("hi".utf8))
        let entries = try ARJArchive(data: try writer.makeData()).entries()
        XCTAssertEqual(entries.map(\.name), ["docs", "docs/readme.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[0].fileType, 3)
        XCTAssertEqual(entries[0].fileMode, 0x10)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertEqual(entries[1].fileMode, 0x20)
    }

    func testDOSTimestampsHaveTwoSecondResolution() throws {
        let date = utcDate(2024, 5, 6, 12, 34, 57)
        var writer = ARJWriter(hostOS: .dos)
        try writer.addFile(named: "a.txt", data: Data("a".utf8), modified: date)
        let entry = try XCTUnwrap(try ARJArchive(data: try writer.makeData()).entries().first)
        XCTAssertEqual(entry.hostOS, .dos)
        XCTAssertEqual(entry.modified, utcDate(2024, 5, 6, 12, 34, 56))
    }

    func testUnixTimestampsAndModes() throws {
        let date = Date(timeIntervalSince1970: 1_705_312_801)
        var writer = ARJWriter(hostOS: .unix)
        try writer.addFile(named: "a.sh", data: Data("echo".utf8), modified: date, fileMode: 0o100755)
        try writer.addDirectory(named: "bin", modified: date)
        let entries = try ARJArchive(data: try writer.makeData()).entries()
        XCTAssertEqual(entries[0].hostOS, .unix)
        XCTAssertEqual(entries[0].modified, date)
        XCTAssertEqual(entries[0].fileMode, 0o100755)
        XCTAssertEqual(entries[1].fileMode, 0o040755)
    }

    func testDOSTimestampsAreClampedToRange() {
        XCTAssertEqual(ARJTimestamp.decodeDOS(ARJTimestamp.encodeDOS(utcDate(1975, 1, 1, 0, 0, 0))), utcDate(1980, 1, 1, 0, 0, 0))
        XCTAssertEqual(ARJTimestamp.decodeDOS(ARJTimestamp.encodeDOS(utcDate(2150, 1, 1, 0, 0, 0))), utcDate(2107, 12, 31, 23, 59, 58))
    }

    func testEntryComments() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "a.txt", data: Data("a".utf8), comment: "first file")
        try writer.addFile(named: "b.txt", data: Data("b".utf8))
        let entries = try ARJArchive(data: try writer.makeData()).entries()
        XCTAssertEqual(entries.map(\.comment), ["first file", nil])
    }

    func testArchiveCommentCanBeChangedAndCleared() throws {
        var writer = ARJWriter(comment: "old")
        writer.comment = "new\nline\n"
        XCTAssertEqual(ARJArchive(data: try writer.makeData()).archiveComment, "new\nline\n")
        writer.comment = nil
        XCTAssertNil(ARJArchive(data: try writer.makeData()).archiveComment)
    }

    func testPathsAreNormalized() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "\\dir\\.\\sub//file.txt", data: Data("x".utf8))
        XCTAssertEqual(writer.entries.first?.name, "dir/sub/file.txt")
        for invalid in ["", "/", "./", "\\"] {
            XCTAssertThrowsError(try writer.addFile(named: invalid, data: Data())) { error in
                XCTAssertEqual(error as? ARJError, .invalidEntryName(invalid))
            }
        }
    }

    func testHeaderSizeLimit() throws {
        var writer = ARJWriter()
        let longName = String(repeating: "n", count: 2600)
        XCTAssertThrowsError(try writer.addFile(named: longName, data: Data())) { error in
            XCTAssertEqual(error as? ARJError, .headerTooLarge)
        }
        writer.comment = String(repeating: "c", count: 2600)
        XCTAssertThrowsError(try writer.makeData()) { error in
            XCTAssertEqual(error as? ARJError, .headerTooLarge)
        }
    }

    func testHeaderCRCValidationDetectsCorruption() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "file.txt", data: Data("payload".utf8))
        var bytes = try writer.makeData()
        XCTAssertNoThrow(try ARJArchive(data: bytes).validateHeaderCRCs())

        // Flip a byte in the second header's file name.
        let nameRange = try XCTUnwrap(bytes.range(of: Data("file.txt".utf8)))
        bytes[nameRange.lowerBound] ^= 0x20
        let corrupted = ARJArchive(data: bytes)
        XCTAssertNoThrow(try corrupted.entries())
        XCTAssertThrowsError(try corrupted.validateHeaderCRCs()) { error in
            XCTAssertEqual(error as? ARJError, .invalidHeaderCRC)
        }
    }

    // MARK: - Passwords

    func testPasswordProtectedEntries() throws {
        let text = textData(count: 5_000)
        for method in [ARJCompressionMethod.stored] + compressedMethods {
            var writer = ARJWriter()
            try writer.addFile(named: "secret.txt", data: text, method: method, password: "hunter2")
            try writer.addFile(named: "plain.txt", data: Data("plain".utf8), method: method)
            let archive = ARJArchive(data: try writer.makeData())

            XCTAssertEqual(try archive.parsedArchive().main.encryptionVersion, 1, "ARJ 3.10 marks XOR archives with version 1")
            let secret = try XCTUnwrap(try archive.entries().first)
            XCTAssertTrue(secret.isEncrypted)
            XCTAssertEqual(try archive.extract(entry: secret, password: "hunter2"), text)
            XCTAssertThrowsError(try archive.extract(entry: secret)) { error in
                XCTAssertEqual(error as? ARJError, .passwordRequired)
            }
            XCTAssertThrowsError(try archive.extract(entry: secret, password: "wrong")) { error in
                XCTAssertEqual(error as? ARJError, .wrongPassword)
            }
            XCTAssertEqual(try archive.extract(named: "plain.txt"), Data("plain".utf8))
        }
    }

    func testEmptyPasswordIsRejected() {
        var writer = ARJWriter()
        XCTAssertThrowsError(try writer.addFile(named: "a", data: Data("a".utf8), password: "")) { error in
            XCTAssertEqual(error as? ARJError, .passwordRequired)
        }
    }

    func testGOSTArchivesAreRejected() throws {
        let payload = Array("secret".utf8)
        let bytes = rawArchive(
            mainFixed: mainFixedHeader(encryptionVersion: 2),
            entries: [RawEntry(name: "gost.txt", payload: payload, flags: 0x01, crc: CRC32.compute(payload))]
        )
        let archive = ARJArchive(data: bytes)
        XCTAssertThrowsError(try archive.extract(named: "gost.txt", password: "pw")) { error in
            XCTAssertEqual(error as? ARJError, .unsupportedEncryptedArchive)
        }

        var writer = try ARJWriter(updating: archive)
        XCTAssertThrowsError(try writer.addFile(named: "xor.txt", data: Data("x".utf8), password: "pw")) { error in
            XCTAssertEqual(error as? ARJError, .unsupportedEncryptedArchive)
        }
        try writer.addFile(named: "plain.txt", data: Data("x".utf8))
        XCTAssertEqual(try ARJArchive(data: try writer.makeData()).extract(named: "plain.txt"), Data("x".utf8))
    }

    // MARK: - Editing

    func testExistingEntryPolicies() throws {
        var writer = ARJWriter()
        XCTAssertEqual(try writer.addFile(named: "a.txt", data: Data("one".utf8)), .added)
        try writer.addFile(named: "b.txt", data: Data("b".utf8))
        XCTAssertEqual(try writer.addFile(named: "a.txt", data: Data("two".utf8), ifExists: .skip), .skipped)
        XCTAssertThrowsError(try writer.addFile(named: "./a.txt", data: Data("x".utf8), ifExists: .fail)) { error in
            XCTAssertEqual(error as? ARJError, .entryAlreadyExists("a.txt"))
        }
        XCTAssertEqual(try writer.addFile(named: "a.txt", data: Data("three".utf8)), .replaced)

        let archive = ARJArchive(data: try writer.makeData())
        XCTAssertEqual(try archive.entries().map(\.name), ["a.txt", "b.txt"])
        XCTAssertEqual(try archive.extract(named: "a.txt"), Data("three".utf8))
    }

    func testRemoveAndRenameEntries() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "keep/a.txt", data: Data("a".utf8), comment: "note")
        try writer.addFile(named: "drop/b.tmp", data: Data("b".utf8))
        try writer.addFile(named: "drop/c.tmp", data: Data("c".utf8))
        try writer.addFile(named: "d.txt", data: Data("d".utf8))

        XCTAssertEqual(writer.removeEntries { $0.name.hasSuffix(".tmp") }, 2)
        XCTAssertTrue(writer.removeEntry(named: "d.txt"))
        XCTAssertFalse(writer.removeEntry(named: "d.txt"))

        try writer.renameEntry(named: "keep/a.txt", to: "renamed/a.txt")
        XCTAssertThrowsError(try writer.renameEntry(named: "missing", to: "x")) { error in
            XCTAssertEqual(error as? ARJError, .entryNotFound)
        }
        try writer.addFile(named: "other.txt", data: Data())
        XCTAssertThrowsError(try writer.renameEntry(named: "other.txt", to: "renamed/a.txt")) { error in
            XCTAssertEqual(error as? ARJError, .entryAlreadyExists("renamed/a.txt"))
        }

        let archive = ARJArchive(data: try writer.makeData())
        XCTAssertNoThrow(try archive.validateHeaderCRCs())
        let entry = try XCTUnwrap(try archive.entries().first)
        XCTAssertEqual(entry.name, "renamed/a.txt")
        XCTAssertEqual(entry.comment, "note")
        XCTAssertEqual(try archive.extract(entry: entry), Data("a".utf8))
    }

    func testUpdatingCopiesExistingEntriesVerbatim() throws {
        for fixture in ["method1", "method4", "multi_file", "mixed_methods"] {
            let original = try fixtureArchive(fixture)
            var writer = try ARJWriter(updating: original)
            XCTAssertEqual(writer.entries, try original.entries())
            try writer.addFile(named: "added.txt", data: textData(count: 1_000))

            let updated = ARJArchive(data: try writer.makeData())
            XCTAssertNoThrow(try updated.validateHeaderCRCs())
            let before = try original.entries()
            let after = try updated.entries()
            XCTAssertEqual(Array(after.prefix(before.count)), before, fixture)
            for entry in before {
                XCTAssertEqual(try updated.extract(entry: entry), try original.extract(entry: entry), "\(fixture): \(entry.name)")
            }
            XCTAssertEqual(try updated.extract(named: "added.txt"), textData(count: 1_000))
        }
    }

    func testUpdatingEncryptedArchiveDoesNotNeedPassword() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "a.txt", data: textData(count: 3_000), password: "pw")
        try writer.addFile(named: "b.txt", data: Data("b".utf8), password: "pw")

        var editor = try ARJWriter(updating: ARJArchive(data: try writer.makeData()))
        XCTAssertTrue(editor.removeEntry(named: "b.txt"))
        try editor.renameEntry(named: "a.txt", to: "docs/a.txt")
        editor.comment = "edited"

        let archive = ARJArchive(data: try editor.makeData())
        XCTAssertEqual(archive.archiveComment, "edited")
        XCTAssertEqual(try archive.extract(named: "docs/a.txt", password: "pw"), textData(count: 3_000))
    }

    func testExtendedHeadersAreParsedAndPreserved() throws {
        let payload = Array("extended".utf8)
        let bytes = rawArchive(
            mainFixed: mainFixedHeader(),
            entries: [
                RawEntry(
                    name: "ext.txt",
                    payload: payload,
                    crc: CRC32.compute(payload),
                    extendedHeaders: [Array("first".utf8), Array("second".utf8)]
                ),
            ]
        )
        let archive = ARJArchive(data: bytes)
        XCTAssertEqual(try archive.extract(named: "ext.txt"), Data(payload))
        XCTAssertNoThrow(try archive.validateHeaderCRCs())

        let rewritten = try ARJWriter(updating: archive).makeData()
        let parsed = try ARJArchive(data: rewritten).parsedArchive()
        XCTAssertEqual(parsed.entries.first?.header.extendedHeaders.map(\.data), [Data("first".utf8), Data("second".utf8)])
    }

    func testSelfExtractingArchiveIsFoundAndStubPreserved() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "inside.txt", data: Data("inside".utf8))
        // A stub containing a stray header ID (with a plausible size but no valid CRC) must not confuse the scanner.
        var stub = Data("MZ stub ".utf8)
        stub.append(contentsOf: [0x60, 0xEA, 0x22, 0x00] + [UInt8](repeating: 2, count: 40))
        stub.append(Data(repeating: 0x90, count: 100))
        let sfx = stub + (try writer.makeData())

        let archive = ARJArchive(data: sfx)
        XCTAssertEqual(try archive.extract(named: "inside.txt"), Data("inside".utf8))

        var editor = try ARJWriter(updating: archive)
        try editor.addFile(named: "second.txt", data: Data("second".utf8))
        let rewritten = try editor.makeData()
        XCTAssertEqual(rewritten.prefix(stub.count), stub)
        XCTAssertEqual(try ARJArchive(data: rewritten).entries().map(\.name), ["inside.txt", "second.txt"])
    }

    func testUpdatingLegacyArchiveWithoutFixedMainHeader() throws {
        // Archives written by ARJ.swift 1.1 have an all-zero main header and zero header CRCs.
        var bytes: [UInt8] = [0x60, 0xEA, 0x1E, 0x00] + Array(repeating: 0, count: 30) + [0, 0, 0, 0, 0, 0]
        bytes += [0x60, 0xEA, 0x00, 0x00]
        var writer = try ARJWriter(updating: ARJArchive(data: Data(bytes)))
        try writer.addFile(named: "new.txt", data: Data("new".utf8))
        let archive = ARJArchive(data: try writer.makeData())
        XCTAssertNoThrow(try archive.validateHeaderCRCs())
        XCTAssertEqual(try archive.extract(named: "new.txt"), Data("new".utf8))
    }

    // MARK: - File system

    func testAddFileFromURLAndWriteToURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arj-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("tool.sh")
        try textData(count: 2_000).write(to: source)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified, .posixPermissions: 0o750], ofItemAtPath: source.path)

        var writer = ARJWriter(hostOS: .unix)
        try writer.addFile(at: source, named: "bin/tool.sh")
        let archiveURL = directory.appendingPathComponent("out.arj")
        try writer.write(to: archiveURL)

        let entry = try XCTUnwrap(try ARJArchive(path: archiveURL.path).entries().first)
        XCTAssertEqual(entry.name, "bin/tool.sh")
        XCTAssertEqual(entry.modified, modified)
        XCTAssertEqual(entry.fileMode, 0o100750)

        XCTAssertThrowsError(try writer.addFile(at: directory.appendingPathComponent("missing"))) { error in
            XCTAssertEqual(error as? ARJError, .fileReadFailed(path: directory.appendingPathComponent("missing").path))
        }
    }

    // MARK: - Reader

    func testArchiveFromDataSlice() throws {
        var writer = ARJWriter()
        try writer.addFile(named: "slice.txt", data: Data("slice".utf8))
        let padded = Data([1, 2, 3]) + (try writer.makeData())
        let slice = padded[3...]
        XCTAssertEqual(try ARJArchive(data: slice).extract(named: "slice.txt"), Data("slice".utf8))
    }

    func testConcurrentExtraction() throws {
        let archive = try fixtureArchive("method1")
        let entry = try XCTUnwrap(try archive.entries().first)
        let expected = try archive.extract(entry: entry)
        let failures = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            if (try? archive.extract(entry: entry)) != expected {
                failures.increment()
            }
        }
        XCTAssertEqual(failures.value, 0)
    }

    func testCorruptedArchivesNeverCrash() throws {
        var writer = ARJWriter(comment: "fuzz")
        for (index, method) in ([ARJCompressionMethod.stored] + compressedMethods).enumerated() {
            try writer.addFile(named: "file\(index).txt", data: textData(count: 3_000 + index * 500), method: method, password: index == 2 ? "pw" : nil)
        }
        try writer.addDirectory(named: "dir")
        let pristine = try writer.makeData()

        var generator = SplitMix(seed: 2024)
        for iteration in 0..<400 {
            var bytes = pristine
            for _ in 0...(generator.next() % 6) {
                let offset = Int(generator.next() % UInt64(bytes.count))
                bytes[offset] ^= UInt8(truncatingIfNeeded: generator.next() | 1)
            }
            if iteration % 7 == 0 {
                bytes = bytes.prefix(Int(generator.next() % UInt64(bytes.count)))
            }
            let archive = ARJArchive(data: bytes)
            _ = archive.archiveComment
            _ = try? archive.validateHeaderCRCs()
            for entry in (try? archive.entries()) ?? [] {
                _ = try? archive.extract(entry: entry, password: "pw")
            }
            if var editor = try? ARJWriter(updating: archive) {
                _ = try? editor.addFile(named: "new.txt", data: Data("new".utf8))
                _ = try? editor.makeData()
            }
        }
    }

    func testHeaderLargerThanFormatLimitIsRejected() {
        var bytes: [UInt8] = [0x60, 0xEA, 0x1E, 0x00] + Array(repeating: 0, count: 30) + [0, 0, 0, 0, 0, 0]
        bytes += [0x60, 0xEA, 0x29, 0x0A] // 2601-byte header
        bytes += Array(repeating: 0, count: 2700)
        XCTAssertThrowsError(try ARJArchive(data: Data(bytes)).entries()) { error in
            XCTAssertEqual(error as? ARJError, .invalidHeaderSize(2601))
        }
    }

    // MARK: - Helpers

    private func sampleInputs() -> [(String, Data)] {
        var mixed = textData(count: 120_000)
        mixed.append(randomData(count: 30_000, seed: 11))
        mixed.append(textData(count: 60_000))
        return [
            ("empty", Data()),
            ("one", Data([0x41])),
            ("two", Data([0x41, 0x41])),
            ("short", Data("abcabcabcab".utf8)),
            ("zeros", Data(repeating: 0, count: 70_000)),
            ("text", textData(count: 40_000)),
            ("random", randomData(count: 20_000, seed: 5)),
            ("mixed", mixed),
        ]
    }

    private func textData(count: Int) -> Data {
        let words = ["alpha ", "beta ", "gamma\n", "ARJ ", "archive ", "swift ", "compression ", "delta\n"]
        var generator = SplitMix(seed: 42)
        var result = Data()
        while result.count < count {
            result.append(contentsOf: words[Int(generator.next() % UInt64(words.count))].utf8)
        }
        return result.prefix(count)
    }

    private func randomData(count: Int, seed: UInt64) -> Data {
        var generator = SplitMix(seed: seed)
        return Data((0..<count).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func fixtureArchive(_ name: String) throws -> ARJArchive {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "arj", subdirectory: "Fixtures"))
        return try ARJArchive(path: url.path)
    }

    private struct RawEntry {
        var name: String
        var payload: [UInt8]
        var flags: UInt8 = 0
        var crc: UInt32
        var extendedHeaders: [[UInt8]] = []
    }

    private func mainFixedHeader(encryptionVersion: UInt8 = 0) -> [UInt8] {
        var fixed = [UInt8](repeating: 0, count: 34)
        fixed[0] = 34
        fixed[1] = 11
        fixed[2] = 1
        fixed[6] = 2
        fixed[28] = encryptionVersion
        return fixed
    }

    /// Builds an archive with correct header CRCs.
    private func rawArchive(mainFixed: [UInt8], entries: [RawEntry]) -> Data {
        var output = Data()
        func appendBlock(_ basic: [UInt8], extended: [[UInt8]]) {
            output.appendLittleEndian(UInt16(0xEA60))
            output.appendLittleEndian(UInt16(basic.count))
            output.append(contentsOf: basic)
            output.appendLittleEndian(CRC32.compute(basic))
            for header in extended {
                output.appendLittleEndian(UInt16(header.count))
                output.append(contentsOf: header)
                output.appendLittleEndian(CRC32.compute(header))
            }
            output.appendLittleEndian(UInt16(0))
        }

        appendBlock(mainFixed + [0, 0], extended: [])
        for entry in entries {
            var fixed = [UInt8](repeating: 0, count: 30)
            fixed[0] = 30
            fixed[1] = 11
            fixed[2] = 1
            fixed[4] = entry.flags
            fixed.setLittleEndian(UInt32(entry.payload.count), at: 12)
            fixed.setLittleEndian(UInt32(entry.payload.count), at: 16)
            fixed.setLittleEndian(entry.crc, at: 20)
            appendBlock(fixed + Array(entry.name.utf8) + [0, 0], extended: entry.extendedHeaders)
            output.append(contentsOf: entry.payload)
        }
        output.append(contentsOf: [0x60, 0xEA, 0x00, 0x00])
        return output
    }
}

private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
