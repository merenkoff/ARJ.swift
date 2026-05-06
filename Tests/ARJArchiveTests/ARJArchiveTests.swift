import XCTest
@testable import ARJArchive

final class ARJArchiveTests: XCTestCase {
    func testThrowsOnInvalidSignature() {
        let archive = ARJArchive(data: Data([0x00, 0x00, 0x00, 0x00]))
        XCTAssertThrowsError(try archive.entries())
    }

    func testParsesArchiveWithNoEntries() throws {
        let archive = ARJArchive(data: Data(minimalArchive()))
        let entries = try archive.entries()
        XCTAssertEqual(entries, [])
    }

    func testExtractsStoredEntry() throws {
        let payload = Array("hello arj".utf8)
        let archive = ARJArchive(data: Data(minimalArchive(singleStoredEntryPayload: payload)))

        let entries = try archive.entries()
        XCTAssertEqual(entries.count, 1)

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.name, "hello.txt")
        XCTAssertEqual(entry.compressionMethod, .stored)
        XCTAssertEqual(entry.hostOS, .dos)

        let extracted = try archive.extract(entry: entry)
        XCTAssertEqual(Array(extracted), payload)
    }

    func testExtractByName() throws {
        let payload = Array("named payload".utf8)
        let archive = ARJArchive(data: Data(minimalArchive(singleStoredEntryPayload: payload)))

        let extracted = try archive.extract(named: "hello.txt")
        XCTAssertEqual(Array(extracted), payload)
    }

    func testExtractAllStored() throws {
        let first = ARJFixtureEntry(
            fileName: "first.txt",
            payload: Array("first".utf8),
            method: 0,
            fileType: 0,
            hostOS: 0,
            flags: 0
        )
        let second = ARJFixtureEntry(
            fileName: "second.txt",
            payload: Array("second".utf8),
            method: 0,
            fileType: 0,
            hostOS: 0,
            flags: 0
        )
        let unsupported = ARJFixtureEntry(
            fileName: "compressed.bin",
            payload: [0x01, 0x02, 0x03],
            method: 2,
            fileType: 0,
            hostOS: 0,
            flags: 0
        )
        let encrypted = ARJFixtureEntry(
            fileName: "secret.txt",
            payload: Array("secret".utf8),
            method: 0,
            fileType: 0,
            hostOS: 0,
            flags: 0x01
        )

        let archive = ARJArchive(
            data: Data(minimalArchive(entries: [first, second, unsupported, encrypted]))
        )

        let extracted = try archive.extractAllStored()
        XCTAssertEqual(extracted.count, 2)
        XCTAssertEqual(Array(try XCTUnwrap(extracted["first.txt"])), first.payload)
        XCTAssertEqual(Array(try XCTUnwrap(extracted["second.txt"])), second.payload)
        XCTAssertNil(extracted["compressed.bin"])
        XCTAssertNil(extracted["secret.txt"])
    }

    func testExtractFirstStoredByNameReturnsData() {
        let payload = Array("soft api".utf8)
        let archive = ARJArchive(data: Data(minimalArchive(singleStoredEntryPayload: payload)))

        let extracted = archive.extractFirstStored(named: "hello.txt")
        XCTAssertEqual(Array(extracted ?? Data()), payload)
    }

    func testExtractFirstStoredByNameReturnsNilWhenNotFound() {
        let payload = Array("soft api".utf8)
        let archive = ARJArchive(data: Data(minimalArchive(singleStoredEntryPayload: payload)))

        XCTAssertNil(archive.extractFirstStored(named: "missing.txt"))
    }

    func testExtractFirstStoredByEntryReturnsData() throws {
        let payload = Array("entry soft api".utf8)
        let archive = ARJArchive(data: Data(minimalArchive(singleStoredEntryPayload: payload)))
        let entry = try XCTUnwrap(try archive.entries().first)

        let extracted = archive.extractFirstStored(entry: entry)
        XCTAssertEqual(Array(extracted ?? Data()), payload)
    }

    func testFixtureMethod1To4Extraction() throws {
        let expectedPayload = Data(
            Array(repeating: Array("goarj-fixture-compatibility-block-0123456789\n".utf8), count: 400).flatMap { $0 }
        )
        let fixtures: [(name: String, method: ARJCompressionMethod)] = [
            ("method1", .compressedMost),
            ("method2", .compressed),
            ("method3", .compressedFaster),
            ("method4", .compressedFastest),
        ]

        for fixture in fixtures {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: fixture.name, withExtension: "arj", subdirectory: "Fixtures")
            )
            let archive = try ARJArchive(path: url.path)
            let entries = try archive.entries()
            XCTAssertEqual(entries.count, 1, "Unexpected entry count in \(fixture.name).arj")

            let entry = try XCTUnwrap(entries.first)
            XCTAssertEqual(entry.compressionMethod, fixture.method, "Unexpected method in \(fixture.name).arj")

            let extracted = try archive.extract(entry: entry)
            XCTAssertEqual(extracted, expectedPayload, "Payload mismatch in \(fixture.name).arj")
        }
    }

    func testFixtureMultiFileExtractNamed() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "multi_file", withExtension: "arj", subdirectory: "Fixtures"))
        let archive = try ARJArchive(path: url.path)
        let entries = try archive.entries()
        XCTAssertEqual(entries.count, 3)

        let extractedBeta = try archive.extract(named: "beta.bin")
        let extractedGamma = try archive.extract(named: "gamma.dat")
        XCTAssertEqual(extractedBeta.count, 26)
        XCTAssertEqual(extractedGamma.count, 48)
    }

    func testFixtureMixedMethodsExtractAllStoredAndNamed() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mixed_methods", withExtension: "arj", subdirectory: "Fixtures"))
        let archive = try ARJArchive(path: url.path)

        // This fixture has only compressed entries, so extractAllStored should return none.
        let stored = try archive.extractAllStored()
        XCTAssertTrue(stored.isEmpty)

        // But extract(named:) should work for each method1...4 entry.
        let names = ["method1.txt", "method2.txt", "method3.txt", "method4.txt"]
        for name in names {
            let data = try archive.extract(named: name)
            XCTAssertEqual(data.count, 48)
        }
    }

    // MARK: - Metadata tests

    func testEntryModifiedDOSDateParsed() throws {
        // 2024-05-06 12:34:56 UTC → DOS date/time:
        // year offset = 2024 - 1980 = 44 → 0b0101100
        // month = 5 → 0b0101
        // day = 6 → 0b00110
        // hour = 12 → 0b01100
        // minute = 34 → 0b100010
        // second/2 = 28 → 0b11100
        // date word = (year << 9) | (month << 5) | day
        //           = (44 << 9) | (5 << 5) | 6 = 22528 | 160 | 6 = 22694
        // time word = (hour << 11) | (minute << 5) | (second/2)
        //           = (12 << 11) | (34 << 5) | 28 = 24576 | 1088 | 28 = 25692
        // raw = (date << 16) | time = (22694 << 16) | 25692
        let timeWord: UInt32 = (12 << 11) | (34 << 5) | 28
        let dateWord: UInt32 = (44 << 9) | (5 << 5) | 6
        let dosTimestamp = (dateWord << 16) | timeWord

        let payload = Array("dos-time".utf8)
        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "dos.txt",
                            payload: payload,
                            method: 0,
                            fileType: 0,
                            hostOS: 0, // DOS host
                            flags: 0,
                            modifiedDOS: dosTimestamp
                        )
                    ]
                )
            )
        )

        let entry = try XCTUnwrap(try archive.entries().first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: entry.modified
        )
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 6)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 34)
        XCTAssertEqual(components.second, 56)
    }

    func testEntryModifiedUnixEpochParsed() throws {
        // 2024-01-15 10:00:00 UTC → 1705312800
        let unixTimestamp: UInt32 = 1_705_312_800
        let payload = Array("unix-time".utf8)
        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "unix.txt",
                            payload: payload,
                            method: 0,
                            fileType: 0,
                            hostOS: 2, // Unix host
                            flags: 0,
                            modifiedDOS: unixTimestamp
                        )
                    ]
                )
            )
        )

        let entry = try XCTUnwrap(try archive.entries().first)
        XCTAssertEqual(entry.hostOS, .unix)
        XCTAssertEqual(entry.modified.timeIntervalSince1970, TimeInterval(unixTimestamp), accuracy: 0.001)
    }

    func testEntryIsDirectoryFromFileType() throws {
        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "subdir/",
                            payload: [],
                            method: 0,
                            fileType: 3, // ARJT_DIR
                            hostOS: 0,
                            flags: 0
                        )
                    ]
                )
            )
        )

        let entry = try XCTUnwrap(try archive.entries().first)
        XCTAssertTrue(entry.isDirectory)
        XCTAssertEqual(entry.normalizedPath, "subdir")
    }

    func testEntryNormalizedPathConvertsBackslashes() throws {
        let payload = Array("path".utf8)
        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "dir\\sub\\file.txt",
                            payload: payload,
                            method: 0,
                            fileType: 0,
                            hostOS: 0,
                            flags: 0
                        )
                    ]
                )
            )
        )

        let entry = try XCTUnwrap(try archive.entries().first)
        XCTAssertEqual(entry.normalizedPath, "dir/sub/file.txt")
        XCTAssertFalse(entry.isDirectory)
    }

    func testFixtureMethod1To4HasNonZeroModified() throws {
        let fixtures = ["method1", "method2", "method3", "method4"]
        for fixture in fixtures {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: fixture, withExtension: "arj", subdirectory: "Fixtures")
            )
            let archive = try ARJArchive(path: url.path)
            let entry = try XCTUnwrap(try archive.entries().first)
            XCTAssertGreaterThan(
                entry.modified.timeIntervalSince1970,
                0,
                "Modified timestamp should not be epoch in \(fixture).arj"
            )
        }
    }

    func testArchiveCommentNilForExistingFixtures() throws {
        let fixtures = ["method1", "multi_file", "mixed_methods"]
        for fixture in fixtures {
            let url = try XCTUnwrap(
                Bundle.module.url(forResource: fixture, withExtension: "arj", subdirectory: "Fixtures")
            )
            let archive = try ARJArchive(path: url.path)
            let comment = archive.archiveComment
            XCTAssertTrue(
                comment == nil || comment?.isEmpty == true,
                "Expected no comment in \(fixture).arj, got \(String(describing: comment))"
            )
        }
    }

    // MARK: - Password tests

    func testEncryptedStoredXorRoundtrip() throws {
        let payload = Array("super secret payload".utf8)
        let crc = CRC32.compute(payload)
        let password = "hello"
        let modifier: UInt8 = 0x42
        let encryptedPayload = xorEncrypt(payload, password: password, modifier: modifier)

        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "secret.txt",
                            payload: encryptedPayload,
                            method: 0,
                            fileType: 0,
                            hostOS: 0,
                            flags: 0x01,
                            crc32: crc,
                            passwordModifier: modifier,
                            originalSize: UInt32(payload.count)
                        )
                    ]
                )
            )
        )

        let extracted = try archive.extract(named: "secret.txt", password: password)
        XCTAssertEqual(Array(extracted), payload)
    }

    func testEncryptedWrongPasswordThrowsWrongPassword() throws {
        let payload = Array("secret".utf8)
        let crc = CRC32.compute(payload)
        let modifier: UInt8 = 0x10
        let encryptedPayload = xorEncrypt(payload, password: "correct", modifier: modifier)

        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "secret.txt",
                            payload: encryptedPayload,
                            method: 0,
                            fileType: 0,
                            hostOS: 0,
                            flags: 0x01,
                            crc32: crc,
                            passwordModifier: modifier,
                            originalSize: UInt32(payload.count)
                        )
                    ]
                )
            )
        )

        XCTAssertThrowsError(try archive.extract(named: "secret.txt", password: "wrong")) { error in
            XCTAssertEqual(error as? ARJError, .wrongPassword)
        }
    }

    func testEncryptedNoPasswordThrowsPasswordRequired() throws {
        let payload = Array("secret".utf8)
        let crc = CRC32.compute(payload)
        let encrypted = xorEncrypt(payload, password: "any", modifier: 0)

        let archive = ARJArchive(
            data: Data(
                minimalArchive(
                    entries: [
                        ARJFixtureEntry(
                            fileName: "secret.txt",
                            payload: encrypted,
                            method: 0,
                            fileType: 0,
                            hostOS: 0,
                            flags: 0x01,
                            crc32: crc,
                            passwordModifier: 0,
                            originalSize: UInt32(payload.count)
                        )
                    ]
                )
            )
        )

        XCTAssertThrowsError(try archive.extract(named: "secret.txt")) { error in
            XCTAssertEqual(error as? ARJError, .passwordRequired)
        }
    }

    // MARK: - Helpers

    private func xorEncrypt(_ payload: [UInt8], password: String, modifier: UInt8) -> [UInt8] {
        let passwordBytes = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: payload.count)
        for index in 0..<payload.count {
            let key = modifier &+ passwordBytes[index % passwordBytes.count]
            output[index] = payload[index] ^ key
        }
        return output
    }

    private func minimalArchive() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += [0x60, 0xEA] // HEADER_ID
        bytes += [0x1E, 0x00] // basic header size = 30
        bytes += Array(repeating: 0, count: 30)
        bytes += [0x00, 0x00, 0x00, 0x00] // header CRC placeholder
        bytes += [0x00, 0x00] // ext header size
        bytes += [0x60, 0xEA] // next header marker
        bytes += [0x00, 0x00] // zero size means archive end
        return bytes
    }

    private func minimalArchive(singleStoredEntryPayload payload: [UInt8]) -> [UInt8] {
        minimalArchive(
            entries: [
                ARJFixtureEntry(
                    fileName: "hello.txt",
                    payload: payload,
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0
                )
            ]
        )
    }

    private func minimalArchive(entries: [ARJFixtureEntry]) -> [UInt8] {
        var bytes = minimalArchive()
        bytes.removeLast(4) // remove end marker, we'll append file headers before it

        for entry in entries {
            let fileHeader = minimalFileHeader(
                fileName: entry.fileName,
                compressedSize: UInt32(entry.payload.count),
                originalSize: entry.originalSize ?? UInt32(entry.payload.count),
                method: entry.method,
                fileType: entry.fileType,
                hostOS: entry.hostOS,
                flags: entry.flags,
                crc32: entry.crc32,
                modifiedDOS: entry.modifiedDOS,
                passwordModifier: entry.passwordModifier
            )

            bytes += [0x60, 0xEA]
            bytes += littleEndianWord(UInt16(fileHeader.count))
            bytes += fileHeader
            bytes += [0x00, 0x00, 0x00, 0x00] // file header CRC placeholder
            bytes += [0x00, 0x00] // ext header size
            bytes += entry.payload
        }

        bytes += [0x60, 0xEA]
        bytes += [0x00, 0x00]
        return bytes
    }

    private func minimalFileHeader(
        fileName: String,
        compressedSize: UInt32,
        originalSize: UInt32,
        method: UInt8,
        fileType: UInt8,
        hostOS: UInt8,
        flags: UInt8,
        crc32: UInt32 = 0,
        modifiedDOS: UInt32 = 0,
        passwordModifier: UInt8 = 0
    ) -> [UInt8] {
        var fixed = Array(repeating: UInt8(0), count: 30)
        fixed[0] = 30 // first header size
        fixed[1] = 11 // arj_nbr
        fixed[2] = 1 // arj_x_nbr
        fixed[3] = hostOS
        fixed[4] = flags
        fixed[5] = method
        fixed[6] = fileType
        fixed[7] = passwordModifier

        fixed[8] = UInt8(truncatingIfNeeded: modifiedDOS)
        fixed[9] = UInt8(truncatingIfNeeded: modifiedDOS >> 8)
        fixed[10] = UInt8(truncatingIfNeeded: modifiedDOS >> 16)
        fixed[11] = UInt8(truncatingIfNeeded: modifiedDOS >> 24)

        fixed[12] = UInt8(truncatingIfNeeded: compressedSize)
        fixed[13] = UInt8(truncatingIfNeeded: compressedSize >> 8)
        fixed[14] = UInt8(truncatingIfNeeded: compressedSize >> 16)
        fixed[15] = UInt8(truncatingIfNeeded: compressedSize >> 24)

        fixed[16] = UInt8(truncatingIfNeeded: originalSize)
        fixed[17] = UInt8(truncatingIfNeeded: originalSize >> 8)
        fixed[18] = UInt8(truncatingIfNeeded: originalSize >> 16)
        fixed[19] = UInt8(truncatingIfNeeded: originalSize >> 24)

        fixed[20] = UInt8(truncatingIfNeeded: crc32)
        fixed[21] = UInt8(truncatingIfNeeded: crc32 >> 8)
        fixed[22] = UInt8(truncatingIfNeeded: crc32 >> 16)
        fixed[23] = UInt8(truncatingIfNeeded: crc32 >> 24)

        var strings = Array(fileName.utf8)
        strings.append(0) // filename terminator
        strings.append(0) // empty comment terminator

        return fixed + strings
    }

    private func littleEndianWord(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0x00FF), UInt8((value >> 8) & 0x00FF)]
    }
}

private struct ARJFixtureEntry {
    let fileName: String
    let payload: [UInt8]
    let method: UInt8
    let fileType: UInt8
    let hostOS: UInt8
    let flags: UInt8
    let crc32: UInt32
    let modifiedDOS: UInt32
    let passwordModifier: UInt8
    let originalSize: UInt32?

    init(
        fileName: String,
        payload: [UInt8],
        method: UInt8,
        fileType: UInt8,
        hostOS: UInt8,
        flags: UInt8,
        crc32: UInt32 = 0,
        modifiedDOS: UInt32 = 0,
        passwordModifier: UInt8 = 0,
        originalSize: UInt32? = nil
    ) {
        self.fileName = fileName
        self.payload = payload
        self.method = method
        self.fileType = fileType
        self.hostOS = hostOS
        self.flags = flags
        self.crc32 = crc32
        self.modifiedDOS = modifiedDOS
        self.passwordModifier = passwordModifier
        self.originalSize = originalSize
    }
}
