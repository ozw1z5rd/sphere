import XCTest
@testable import SphereCore
@testable import SphereTools

final class ToolsIntegrationTests: XCTestCase {
    private func makeBroker() throws -> (FilesystemBroker, URL) {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let store = PermissionStore(database: database)
        try store.addPathGrant(PathGrant(path: "/tmp", mode: .readWrite, recursive: true))
        let engine = PermissionEngine(store: store)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try store.addPathGrant(PathGrant(path: root.path, mode: .readWrite, recursive: true))
        let broker = FilesystemBroker(engine: engine, audit: AuditLog(fileURL: root.appendingPathComponent("audit.log")))
        return (broker, root)
    }

    func testStatReadBytesSelectAndImageInspect() async throws {
        let (broker, root) = try makeBroker()
        defer { try? FileManager.default.removeItem(at: root) }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=")!
        try png.write(to: root.appendingPathComponent("logo.png"))
        try """
        {"providers": [{"name": "deepseek", "model": "deepseek-chat"}], "count": 2}
        """.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let stat = try await broker.invoke(tool: "fs_stat", arguments: .object(["path": .string(root.appendingPathComponent("logo.png").path)]), sessionId: nil)
        XCTAssertTrue(stat.text.contains("detected: png"))
        XCTAssertTrue(stat.text.contains("mode:"))

        let bytes = try await broker.invoke(tool: "fs_read_bytes", arguments: .object([
            "path": .string(root.appendingPathComponent("logo.png").path),
            "length": .number(8),
        ]), sessionId: nil)
        XCTAssertTrue(bytes.text.contains("hex: 89504e470d0a1a0a"))

        let selected = try await broker.invoke(tool: "fs_select", arguments: .object([
            "path": .string(root.appendingPathComponent("config.json").path),
            "selector": .string("providers[0].model"),
        ]), sessionId: nil)
        XCTAssertTrue(selected.text.contains("deepseek-chat"))

        let image = try await broker.invoke(tool: "image_inspect", arguments: .object([
            "path": .string(root.appendingPathComponent("logo.png").path),
        ]), sessionId: nil)
        XCTAssertTrue(image.text.contains("dimensions: 1×1 px"))
        XCTAssertTrue(image.text.contains("format: public.png"))
    }

    func testGrepSkipsBinaryAndGitIgnoredFiles() async throws {
        let (broker, root) = try makeBroker()
        defer { try? FileManager.default.removeItem(at: root) }

        try "hello world\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "hello ignored\n".write(to: root.appendingPathComponent("ignored.txt"), atomically: true, encoding: .utf8)
        try "*.txt\n!a.txt\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02, 0x68, 0x65, 0x6C, 0x6C, 0x6F]).write(to: root.appendingPathComponent("blob.bin"))

        let outcome = try await broker.invoke(tool: "fs_grep", arguments: .object([
            "path": .string(root.path),
            "pattern": .string("hello"),
            "respect_gitignore": .bool(true),
        ]), sessionId: nil)
        XCTAssertTrue(outcome.text.contains("a.txt"))
        XCTAssertFalse(outcome.text.contains("ignored.txt"), outcome.text)
        XCTAssertTrue(outcome.text.contains("skipped"), outcome.text)
        XCTAssertTrue(outcome.text.contains("blob.bin"))
    }

    func testGitStatusAndLogInSandbox() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git is not installed")
        }
        let (_, root) = try makeBroker()
        defer { try? FileManager.default.removeItem(at: root) }

        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try git(["init", "-q"])
        try git(["config", "user.email", "test@example.com"])
        try git(["config", "user.name", "Test"])
        try "hello\n".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try git(["add", "file.txt"])
        try git(["commit", "-q", "-m", "initial"])

        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let permissionStore = PermissionStore(database: database)
        try permissionStore.addPathGrant(PathGrant(path: root.path, mode: .readOnly, recursive: true))
        let provider = GitToolProvider(
            engine: PermissionEngine(store: permissionStore),
            audit: AuditLog(fileURL: root.appendingPathComponent("git-audit.log"))
        )

        let status = try await provider.invoke(tool: "git", arguments: .object([
            "operation": .string("status"),
            "path": .string(root.path),
        ]), sessionId: nil)
        XCTAssertFalse(status.isError, status.text)
        XCTAssertTrue(status.text.contains("##"))

        let log = try await provider.invoke(tool: "git", arguments: .object([
            "operation": .string("log"),
            "path": .string(root.path),
        ]), sessionId: nil)
        XCTAssertTrue(log.text.contains("initial"))
    }

    func testEditReplaceAndPatch() async throws {
        let (broker, root) = try makeBroker()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("edit.txt")
        try "alpha\nbeta\ngamma\n".write(to: file, atomically: true, encoding: .utf8)

        let replaced = try await broker.invoke(tool: "fs_edit", arguments: .object([
            "path": .string(file.path),
            "mode": .string("replace"),
            "old": .string("beta"),
            "new": .string("BETA"),
        ]), sessionId: nil)
        XCTAssertFalse(replaced.isError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "alpha\nBETA\ngamma\n")

        let patch = """
        --- a/edit.txt
        +++ b/edit.txt
        @@ -1,3 +1,3 @@
         alpha
        -BETA
        +beta
         gamma
        """
        let patched = try await broker.invoke(tool: "fs_edit", arguments: .object([
            "path": .string(file.path),
            "mode": .string("patch"),
            "patch": .string(patch),
        ]), sessionId: nil)
        XCTAssertFalse(patched.isError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "alpha\nbeta\ngamma\n")
    }
}
