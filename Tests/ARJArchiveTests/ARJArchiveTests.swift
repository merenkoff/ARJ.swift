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
                originalSize: UInt32(entry.payload.count),
                method: entry.method,
                fileType: entry.fileType,
                hostOS: entry.hostOS,
                flags: entry.flags
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
        flags: UInt8
    ) -> [UInt8] {
        var fixed = Array(repeating: UInt8(0), count: 30)
        fixed[0] = 30 // first header size
        fixed[1] = 11 // arj_nbr
        fixed[2] = 1 // arj_x_nbr
        fixed[3] = hostOS
        fixed[4] = flags
        fixed[5] = method
        fixed[6] = fileType
        fixed[7] = 0 // password modifier

        fixed[12] = UInt8(truncatingIfNeeded: compressedSize)
        fixed[13] = UInt8(truncatingIfNeeded: compressedSize >> 8)
        fixed[14] = UInt8(truncatingIfNeeded: compressedSize >> 16)
        fixed[15] = UInt8(truncatingIfNeeded: compressedSize >> 24)

        fixed[16] = UInt8(truncatingIfNeeded: originalSize)
        fixed[17] = UInt8(truncatingIfNeeded: originalSize >> 8)
        fixed[18] = UInt8(truncatingIfNeeded: originalSize >> 16)
        fixed[19] = UInt8(truncatingIfNeeded: originalSize >> 24)

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
}
