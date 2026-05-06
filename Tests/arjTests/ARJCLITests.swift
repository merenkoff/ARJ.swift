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

    func testAddStubExits2() throws {
        let bin = try binaryURL()
        let fixture = try fixtureURL("method1.arj")
        let (_, err, status) = try run(bin, arguments: ["a", fixture.path, "*", "-r"])
        XCTAssertEqual(status, 2)
        XCTAssertTrue(err.contains("not implemented"), err)
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
}
