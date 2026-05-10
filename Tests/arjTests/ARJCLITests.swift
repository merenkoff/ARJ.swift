import Foundation
import XCTest

final class ARJCLITests: XCTestCase {
    func testListMultiFile() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        let (out, err, status) = try run(bin, arguments: ["l", fixture.path])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("beta.bin"), out)
        XCTAssertTrue(out.contains("gamma.dat"), out)
    }

    func testTestCommand() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("method1.arj")
        let (_, err, status) = try run(bin, arguments: ["t", fixture.path])
        XCTAssertEqual(status, 0, "stderr: \(err)")
    }

    func testExtractCreatesFile() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("method1.arj")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (_, err, status) = try run(
            bin,
            arguments: ["x", fixture.path, "-ht\(tmp.path)", "-y"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
        XCTAssertFalse(contents.isEmpty)
    }

    func testMissingArchiveExits6Or7() throws {
        let bin = try binaryURL()
        let (_, _, status) = try run(bin, arguments: ["l", "/no/such/archive.arj"])
        XCTAssertTrue(status == 6 || status == 7)
    }

    func testNonArjFileExits9() throws {
        let bin = try binaryURL()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("not-arj-\(UUID().uuidString).bin")
        try Data("not an arj file".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (_, _, status) = try run(bin, arguments: ["t", tmp.path])
        XCTAssertEqual(status, 9)
    }

    func testAddAddsFileToArchive() throws {
        let bin = try binaryURL()
        let sourceArchive = try fixtureURL("method1.arj")
        let archiveCopy = FileManager.default.temporaryDirectory.appendingPathComponent("add-\(UUID().uuidString).arj")
        try FileManager.default.copyItem(at: sourceArchive, to: archiveCopy)
        defer { try? FileManager.default.removeItem(at: archiveCopy) }

        let inputDir = FileManager.default.temporaryDirectory.appendingPathComponent("add-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inputDir) }
        let fileURL = inputDir.appendingPathComponent("new.txt")
        try Data("new payload".utf8).write(to: fileURL)

        let (_, err, status) = try run(bin, arguments: ["a", archiveCopy.path, inputDir.path, "*.txt", "-r"])
        XCTAssertEqual(status, 0, "stderr: \(err)")

        let (listOut, _, listStatus) = try run(bin, arguments: ["l", archiveCopy.path])
        XCTAssertEqual(listStatus, 0)
        XCTAssertTrue(listOut.contains("new.txt"), listOut)
    }

    func testEncryptedWithoutPasswordExits3() throws {
        let bin = try binaryURL()
        let archiveURL = try makeEncryptedFixture(password: "secret", payloadText: "top secret")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let (_, _, status) = try run(bin, arguments: ["t", archiveURL.path])
        XCTAssertEqual(status, 3)
    }

    func testEncryptedWrongPasswordExits3() throws {
        let bin = try binaryURL()
        let archiveURL = try makeEncryptedFixture(password: "secret", payloadText: "top secret")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let (_, _, status) = try run(bin, arguments: ["t", archiveURL.path, "-gwrong"])
        XCTAssertEqual(status, 3)
    }

    func testCommentWithZFileUpdatesComment() throws {
        let bin = try binaryURL()
        let sourceArchive = try fixtureURL("method1.arj")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("comment-\(UUID().uuidString).arj")
        try FileManager.default.copyItem(at: sourceArchive, to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("comment-\(UUID().uuidString).txt")
        try Data("new comment".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let (writeOut, err, status) = try run(bin, arguments: ["c", fixture.path, "-z\(tempFile.path)"])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(writeOut.contains("updated") || writeOut.contains("unchanged"), writeOut)

        let (readOut, _, readStatus) = try run(bin, arguments: ["c", fixture.path])
        XCTAssertEqual(readStatus, 0)
        XCTAssertTrue(readOut.contains("new comment"), readOut)
    }

    func testDeleteRemovesMatchingEntries() throws {
        let bin = try binaryURL()
        let sourceArchive = try fixtureURL("multi_file.arj")
        let archiveCopy = FileManager.default.temporaryDirectory.appendingPathComponent("delete-\(UUID().uuidString).arj")
        try FileManager.default.copyItem(at: sourceArchive, to: archiveCopy)
        defer { try? FileManager.default.removeItem(at: archiveCopy) }

        let (_, err, status) = try run(bin, arguments: ["d", archiveCopy.path, "*.bin"])
        XCTAssertEqual(status, 0, "stderr: \(err)")

        let (out, _, listStatus) = try run(bin, arguments: ["l", archiveCopy.path])
        XCTAssertEqual(listStatus, 0)
        XCTAssertFalse(out.contains("beta.bin"), out)
    }

    func testListAcceptsWorkDirSwitchAsNoOp() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (out, err, status) = try run(bin, arguments: ["l", fixture.path, "-w\(tmp.path)"])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"), out)
    }

    func testVerboseListMatchesSnapshot() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        let snapshot = try String(contentsOf: verboseSnapshotURL(), encoding: .utf8)
        let (out, err, status) = try run(bin, arguments: ["v", fixture.path])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertEqual(normalizeNewlines(out), normalizeNewlines(snapshot))
    }

    // MARK: - Tests for !listfile and -x<mask> filtering

    func testListfileBasicExclusion() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        // Create a temporary listfile with one filename
        let listfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString).txt")
        try "alpha.txt\n".write(to: listfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listfileURL) }
        
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(listfileURL.path)"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"), "Should list alpha.txt from listfile")
        XCTAssertFalse(out.contains("beta.bin"), "Should not list beta.bin (not in listfile)")
        XCTAssertFalse(out.contains("gamma.dat"), "Should not list gamma.dat (not in listfile)")
    }

    func testListfileMultipleEntries() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let listfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString).txt")
        try "alpha.txt\nbeta.bin\n".write(to: listfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listfileURL) }
        
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(listfileURL.path)"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"))
        XCTAssertTrue(out.contains("beta.bin"))
        XCTAssertFalse(out.contains("gamma.dat"), "Should not list gamma.dat")
    }

    func testListfileMissingFileExits() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        let nonExistentListfile = "/tmp/nonexistent-list-\(UUID().uuidString).txt"
        
        let (_, _, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(nonExistentListfile)"]
        )
        XCTAssertNotEqual(status, 0, "Should fail when listfile does not exist")
    }

    func testExcludeMaskBasic() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "-x*.bin"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"))
        XCTAssertFalse(out.contains("beta.bin"), "Should exclude *.bin files")
        XCTAssertTrue(out.contains("gamma.dat"))
    }

    func testExcludeMaskMultiple() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "-x*.bin", "-x*.dat"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"))
        XCTAssertFalse(out.contains("beta.bin"))
        XCTAssertFalse(out.contains("gamma.dat"))
    }

    func testExcludeMaskWithListfile() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let listfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString).txt")
        try "alpha.txt\nbeta.bin\ngamma.dat\n".write(to: listfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listfileURL) }
        
        // Include all from listfile, but exclude *.bin
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(listfileURL.path)", "-x*.bin"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"))
        XCTAssertFalse(out.contains("beta.bin"), "Should be excluded by -x*.bin")
        XCTAssertTrue(out.contains("gamma.dat"))
    }

    func testListfileWithWildcardMask() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let listfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString).txt")
        try "*.t*\n".write(to: listfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listfileURL) }
        
        let (out, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(listfileURL.path)"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("alpha.txt"), "Should match *.t* pattern")
    }

    func testExtractWithExcludeMask() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Extract all except *.bin
        let (_, err, status) = try run(
            bin,
            arguments: ["x", fixture.path, "-ht\(tmp.path)", "-x*.bin", "-y"]
        )
        XCTAssertEqual(status, 0, "stderr: \(err)")
        
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
        XCTAssertTrue(contents.contains { $0.contains("alpha") }, "Should extract alpha.txt")
        XCTAssertFalse(contents.contains { $0.contains("beta.bin") }, "Should not extract beta.bin")
    }

    func testListfileWithComments() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("multi_file.arj")
        
        let listfileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-\(UUID().uuidString).txt")
        let content = """
        alpha.txt
        # This is a comment
        beta.bin
        """
        try content.write(to: listfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listfileURL) }
        
        let (_, err, status) = try run(
            bin,
            arguments: ["l", fixture.path, "!\(listfileURL.path)"]
        )
        // Comments in listfile should either be ignored or cause them to be treated as filenames
        // Depending on ARJ behavior, adjust assertion accordingly
        XCTAssertEqual(status, 0, "stderr: \(err)")
    }

    func testExtractPathSwitchConflictExits7() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("method1.arj")
        let (_, err, status) = try run(bin, arguments: ["x", fixture.path, "-e", "-p"])
        XCTAssertEqual(status, 7, "stderr: \(err)")
    }

    func testExtractKeepRelativePathsStripsAbsolutePrefixes() throws {
        let bin = try binaryURL()
        let archive = try makeFixtureArchive(
            entries: [
                FixtureEntry(
                    fileName: "/usr/local/bin/tool.txt",
                    payload: [UInt8]("tool".utf8),
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0,
                    crc32: crc32([UInt8]("tool".utf8)),
                    modifiedDOS: 0,
                    passwordModifier: 0,
                    originalSize: 4
                ),
                FixtureEntry(
                    fileName: "C:\\temp\\docs\\readme.txt",
                    payload: [UInt8]("readme".utf8),
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0,
                    crc32: crc32([UInt8]("readme".utf8)),
                    modifiedDOS: 0,
                    passwordModifier: 0,
                    originalSize: 6
                ),
            ]
        )
        defer { try? FileManager.default.removeItem(at: archive) }

        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let (_, err, status) = try run(bin, arguments: ["x", archive.path, "-p1", "-ht\(outDir.path)", "-y"])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("usr/local/bin/tool.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("temp/docs/readme.txt").path))
    }

    func testExtractKeepFullPathsPreservesAbsolutePrefixesSafely() throws {
        let bin = try binaryURL()
        let archive = try makeFixtureArchive(
            entries: [
                FixtureEntry(
                    fileName: "/usr/local/bin/tool.txt",
                    payload: [UInt8]("tool".utf8),
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0,
                    crc32: crc32([UInt8]("tool".utf8)),
                    modifiedDOS: 0,
                    passwordModifier: 0,
                    originalSize: 4
                ),
                FixtureEntry(
                    fileName: "C:\\temp\\docs\\readme.txt",
                    payload: [UInt8]("readme".utf8),
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0,
                    crc32: crc32([UInt8]("readme".utf8)),
                    modifiedDOS: 0,
                    passwordModifier: 0,
                    originalSize: 6
                ),
            ]
        )
        defer { try? FileManager.default.removeItem(at: archive) }

        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let (_, err, status) = try run(bin, arguments: ["x", archive.path, "-p", "-ht\(outDir.path)", "-y"])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("_root/usr/local/bin/tool.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("drive_c/temp/docs/readme.txt").path))
    }

    func testSearchFindsWindowsCyrillicEncodedText() throws {
        let bin = try binaryURL()
        let text = "Привет ARJ"
        guard let encoded = text.data(using: .windowsCP1251) else {
            throw XCTSkip("windowsCP1251 not supported on this platform")
        }
        let archive = try makeFixtureArchive(
            entries: [
                FixtureEntry(
                    fileName: "notes.txt",
                    payload: [UInt8](encoded),
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0,
                    crc32: crc32([UInt8](encoded)),
                    modifiedDOS: 0,
                    passwordModifier: 0,
                    originalSize: UInt32(encoded.count)
                ),
            ]
        )
        defer { try? FileManager.default.removeItem(at: archive) }

        let (out, err, status) = try run(bin, arguments: ["w", archive.path, "привет"])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("notes.txt"), out)
    }

    func testCommentOutputIncludesHeaderWhenCommentMissing() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("method1.arj")
        let (out, err, status) = try run(bin, arguments: ["c", fixture.path])
        XCTAssertEqual(status, 0, "stderr: \(err)")
        XCTAssertTrue(out.contains("Archive comment:"), out)
        XCTAssertTrue(out.contains("<none>"), out)
    }

    // MARK: - Helpers

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func binaryURL() throws -> URL {
        let url = packageRoot().appendingPathComponent(".build/debug/arj")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            return url
        }
        let release = packageRoot().appendingPathComponent(".build/arm64-apple-macosx/release/arj")
        if FileManager.default.fileExists(atPath: release.path) {
            return release
        }
        throw XCTSkip("Build arj first with swift build")
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let url = packageRoot()
            .appendingPathComponent("Tests/ARJArchiveTests/Fixtures")
            .appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    private func verboseSnapshotURL() -> URL {
        packageRoot()
            .appendingPathComponent("Tests/arjTests/Snapshots")
            .appendingPathComponent("verbose_multi_file.txt")
    }

    private func run(_ executable: URL, arguments: [String]) throws -> (String, String, Int32) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err, process.terminationStatus)
    }

    private func makeEncryptedFixture(password: String, payloadText: String) throws -> URL {
        let payload = [UInt8](payloadText.utf8)
        let modifier: UInt8 = 0x42
        let encryptedPayload = xorEncrypt(payload, password: password, modifier: modifier)
        let crc = crc32(payload)

        let bytes = minimalArchive(
            entries: [
                FixtureEntry(
                    fileName: "secret.txt",
                    payload: encryptedPayload,
                    method: 0,
                    fileType: 0,
                    hostOS: 0,
                    flags: 0x01,
                    crc32: crc,
                    modifiedDOS: 0,
                    passwordModifier: modifier,
                    originalSize: UInt32(payload.count)
                ),
            ]
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("enc-\(UUID().uuidString).arj")
        try Data(bytes).write(to: url)
        return url
    }

    private func makeFixtureArchive(entries: [FixtureEntry]) throws -> URL {
        let bytes = minimalArchive(entries: entries)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).arj")
        try Data(bytes).write(to: url)
        return url
    }

    private func xorEncrypt(_ payload: [UInt8], password: String, modifier: UInt8) -> [UInt8] {
        let passwordBytes = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: payload.count)
        for index in 0..<payload.count {
            let key = modifier &+ passwordBytes[index % passwordBytes.count]
            output[index] = payload[index] ^ key
        }
        return output
    }

    private func minimalArchive(entries: [FixtureEntry]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += [0x60, 0xEA]
        bytes += [0x1E, 0x00]
        bytes += Array(repeating: 0, count: 30)
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00]

        for entry in entries {
            let fileHeader = minimalFileHeader(
                fileName: entry.fileName,
                compressedSize: UInt32(entry.payload.count),
                originalSize: entry.originalSize,
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
            bytes += [0x00, 0x00, 0x00, 0x00]
            bytes += [0x00, 0x00]
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
        crc32: UInt32,
        modifiedDOS: UInt32,
        passwordModifier: UInt8
    ) -> [UInt8] {
        var fixed = Array(repeating: UInt8(0), count: 30)
        fixed[0] = 30
        fixed[1] = 11
        fixed[2] = 1
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
        strings.append(0)
        strings.append(0)
        return fixed + strings
    }

    private func littleEndianWord(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0x00FF), UInt8((value >> 8) & 0x00FF)]
    }

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
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

        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            let lookup = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[lookup]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FixtureEntry {
    let fileName: String
    let payload: [UInt8]
    let method: UInt8
    let fileType: UInt8
    let hostOS: UInt8
    let flags: UInt8
    let crc32: UInt32
    let modifiedDOS: UInt32
    let passwordModifier: UInt8
    let originalSize: UInt32
}
