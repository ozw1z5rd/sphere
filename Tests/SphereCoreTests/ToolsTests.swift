import XCTest
@testable import SphereCore
@testable import SphereTools
@testable import SphereMCP

final class ToolHelpersTests: XCTestCase {
    func testJSONPathSelector() throws {
        let value = JSONValue.object([
            "dependencies": .array([
                .object(["url": .string("https://example.com/a.git"), "version": .string("1.0.0")]),
                .object(["url": .string("https://example.com/b.git")]),
            ]),
            "name": .string("Sphere"),
        ])

        XCTAssertEqual(try StructuredData.select(value, selector: "name"), .string("Sphere"))
        XCTAssertEqual(
            try StructuredData.select(value, selector: "dependencies[1].url"),
            .string("https://example.com/b.git")
        )
        XCTAssertThrowsError(try StructuredData.select(value, selector: "dependencies[9].url"))
    }

    func testLineSlice() {
        let text = "one\ntwo\nthree\nfour"
        XCTAssertEqual(FilesystemBroker.lineSlice(text, start: 2, end: 3), "     2\ttwo\n     3\tthree")
    }

    func testMagicByteSniffing() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(FileSniffer.sniff(png).kind, "png")
        XCTAssertTrue(FileSniffer.sniff(png).isBinary)
        XCTAssertEqual(FileSniffer.sniff(Data("hello world".utf8)).kind, "text")
    }

    func testUnifiedPatch() throws {
        let original = "one\ntwo\nthree\n"
        let patch = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """
        let result = try UnifiedPatch.apply(patch, to: original)
        XCTAssertEqual(result.hunks, 1)
        XCTAssertEqual(result.text, "one\nTWO\nthree\n")
    }

    func testGitIgnoreMatching() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-gitignore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        *.log
        build/
        !keep.log
        """.write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let matcher = GitIgnoreMatcher(root: root)
        XCTAssertTrue(matcher.isIgnored(relativePath: "app.log", isDirectory: false))
        XCTAssertFalse(matcher.isIgnored(relativePath: "keep.log", isDirectory: false))
        XCTAssertTrue(matcher.isIgnored(relativePath: "build", isDirectory: true))
        XCTAssertTrue(matcher.isIgnored(relativePath: "build/out.o", isDirectory: false))
        XCTAssertFalse(matcher.isIgnored(relativePath: "src/main.swift", isDirectory: false))
    }

    func testYAMLParser() throws {
        let yaml = """
        name: Sphere
        dependencies:
          - url: https://example.com/a.git
            version: 1.0
          - url: https://example.com/b.git
        """
        var parser = YAMLParser(text: yaml)
        let value = try parser.parse()
        XCTAssertEqual(try StructuredData.select(value, selector: "name"), .string("Sphere"))
        XCTAssertEqual(try StructuredData.select(value, selector: "dependencies[0].version"), .number(1.0))
        XCTAssertEqual(
            try StructuredData.select(value, selector: "dependencies[1].url"),
            .string("https://example.com/b.git")
        )
    }

    func testDuckDuckGoResultParsing() {
        let html = """
        <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa&amp;rut=x">Example <b>A</b></a>
        <a class="result__snippet" href="#">An <b>example</b> snippet &amp; more</a>
        """
        let results = WebToolProvider.parseDuckDuckGo(html, limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Example A")
        XCTAssertEqual(results.first?.url, "https://example.com/a")
        XCTAssertEqual(results.first?.snippet, "An example snippet & more")
    }

    func testExecRunsAllowlistedCommandInSandbox() async throws {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let store = PermissionStore(database: database)
        let engine = PermissionEngine(store: store)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-exec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try store.addPathGrant(PathGrant(path: root.path, mode: .readOnly, recursive: true))

        let audit = AuditLog(fileURL: root.appendingPathComponent("audit.log"))
        let exec = ExecToolProvider(engine: engine, audit: audit, enabled: true, allowlist: ["ls"])
        let outcome = try await exec.invoke(
            tool: "exec",
            arguments: .object([
                "argv": .array([.string("ls")]),
                "cwd": .string(root.path),
            ]),
            sessionId: nil
        )
        XCTAssertFalse(outcome.isError)
        XCTAssertTrue(outcome.text.contains("exit: 0"))

        let disabled = ExecToolProvider(engine: engine, audit: audit, enabled: false, allowlist: ["ls"])
        do {
            _ = try await disabled.invoke(
                tool: "exec",
                arguments: .object([
                    "argv": .array([.string("ls")]),
                    "cwd": .string(root.path),
                ]),
                sessionId: nil
            )
            XCTFail("expected disabled exec to throw")
        } catch {
            // expected
        }
    }

    func testExecAllowlistAndReadOnlyDetection() {
        XCTAssertTrue(ExecToolProvider.isAllowed(argv: ["git", "status"], allowlist: ["git status", "ls"]))
        XCTAssertFalse(ExecToolProvider.isAllowed(argv: ["git", "push"], allowlist: ["git status", "ls"]))
        XCTAssertTrue(ExecToolProvider.isReadOnly(argv: ["git", "diff", "--stat"]))
        XCTAssertFalse(ExecToolProvider.isReadOnly(argv: ["swift", "build"]))
        XCTAssertTrue(ExecToolProvider.sandboxProfile(grantedRoot: URL(fileURLWithPath: "/tmp/x"), allowWrites: true).contains("deny network*"))
        XCTAssertFalse(ExecToolProvider.sandboxProfile(grantedRoot: URL(fileURLWithPath: "/tmp/x"), allowWrites: false).contains("subpath \"/tmp/x\""))
    }
}

private final class StubToolProvider: ToolProvider {
    let moduleId = "stub"
    let providerName = "Stub"

    func definitions() -> [ToolDefinition] {
        [
            ToolDefinition(name: "stub_one", originalName: "one", moduleId: moduleId, description: "one"),
            ToolDefinition(name: "stub_two", originalName: "two", moduleId: moduleId, description: "two"),
        ]
    }

    func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome {
        ToolOutcome(text: tool)
    }
}

private final class CustomToolProvider: ToolProvider {
    let moduleId: String
    let providerName: String
    let toolName: String
    let result: String

    init(moduleId: String, toolName: String, result: String) {
        self.moduleId = moduleId
        self.providerName = moduleId
        self.toolName = toolName
        self.result = result
    }

    func definitions() -> [ToolDefinition] {
        [ToolDefinition(name: toolName, originalName: toolName, moduleId: moduleId, description: toolName)]
    }

    func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome {
        ToolOutcome(text: result)
    }
}

private final class SessionCapturingProvider: ToolProvider {
    let moduleId = "capture"
    let providerName = "Capture"

    func definitions() -> [ToolDefinition] {
        [ToolDefinition(name: "capture_tool", originalName: "tool", moduleId: moduleId, description: "tool")]
    }

    func invoke(tool: String, arguments: JSONValue, sessionId: String?) async throws -> ToolOutcome {
        ToolOutcome(text: sessionId ?? "nil")
    }
}

final class ToolRouterTests: XCTestCase {
    func testDisabledToolsAreHiddenAndBlocked() async throws {
        let router = ToolRouter(
            host: MCPModuleHost(),
            providers: [StubToolProvider()],
            disabledTools: ["stub_one"]
        )

        let visible = await router.definitions()
        XCTAssertEqual(visible.map(\.name), ["stub_two"])

        let all = await router.definitions(includingDisabled: true)
        XCTAssertEqual(all.map(\.name).sorted(), ["stub_one", "stub_two"])

        do {
            _ = try await router.invoke(name: "stub_one", arguments: .object([:]))
            XCTFail("disabled tool should be blocked")
        } catch {
            // expected
        }

        let outcome = try await router.invoke(name: "stub_two", arguments: .object([:]))
        XCTAssertEqual(outcome.text, "two")
    }

    func testAllToolsEnabledByDefault() async {
        let router = ToolRouter(host: MCPModuleHost(), providers: [StubToolProvider()])
        let visible = await router.definitions()
        XCTAssertEqual(visible.count, 2)
    }

    func testDenyPolicyHidesToolFromCatalog() async {
        let router = ToolRouter(
            host: MCPModuleHost(),
            providers: [StubToolProvider()],
            policy: ["stub_one": "deny"]
        )
        let visible = await router.definitions()
        XCTAssertEqual(visible.map(\.name), ["stub_two"])
        let all = await router.definitions(includingDisabled: true)
        XCTAssertEqual(all.map(\.name), ["stub_two"])

        do {
            _ = try await router.invoke(name: "stub_one", arguments: .object([:]))
            XCTFail("denied tool should be blocked")
        } catch {
            // expected
        }
    }

    func testAskPolicyHidesToolWithoutApprovalHandler() async {
        let router = ToolRouter(
            host: MCPModuleHost(),
            providers: [StubToolProvider()],
            policy: ["stub_one": "ask"]
        )
        let visible = await router.definitions()
        XCTAssertEqual(visible.map(\.name), ["stub_two"])
    }

    func testRouterPassesSessionIdToProvider() async throws {
        let router = ToolRouter(host: MCPModuleHost(), providers: [SessionCapturingProvider()])
        let outcome = try await router.invoke(name: "capture_tool", arguments: .object([:]), sessionId: "session-1")
        XCTAssertEqual(outcome.text, "session-1")
    }

    func testCollisionKeepsFirstProviderAndInvokeUsesIt() async throws {
        let first = CustomToolProvider(moduleId: "first", toolName: "dup", result: "first")
        let second = CustomToolProvider(moduleId: "second", toolName: "dup", result: "second")
        let router = ToolRouter(host: MCPModuleHost(), providers: [first, second])

        let definitions = await router.definitions(includingDisabled: true)
        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions.first?.moduleId, "first")

        let outcome = try await router.invoke(name: "dup", arguments: .object([:]))
        XCTAssertEqual(outcome.text, "first")
    }

    func testEnablingDisabledToolRestoresIt() async {
        let router = ToolRouter(
            host: MCPModuleHost(),
            providers: [StubToolProvider()],
            disabledTools: ["stub_one", "stub_two"]
        )
        let before = await router.definitions()
        XCTAssertTrue(before.isEmpty)
        await router.setDisabledTools([])
        let after = await router.definitions()
        XCTAssertEqual(after.count, 2)
    }
}

final class ClipboardStoreTests: XCTestCase {
    func testRecordAndCountBySession() throws {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let store = ClipboardStore(database: database)

        try store.record(ClipboardEvent(sessionId: "a", operation: "read", detail: "5 chars"))
        try store.record(ClipboardEvent(sessionId: "a", operation: "write", detail: "7 chars"))
        try store.record(ClipboardEvent(sessionId: "b", operation: "read", detail: nil))
        try store.record(ClipboardEvent(sessionId: "a", operation: "read", detail: nil, allowed: false))

        XCTAssertEqual(try store.count(), 4)
        XCTAssertEqual(try store.count(sessionId: "a"), 3)
        XCTAssertEqual(try store.count(sessionId: "a", allowedOnly: true), 2)
        let events = try store.events(sessionId: "a")
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.operation, "read")
        XCTAssertTrue(events.allSatisfy { $0.sessionId == "a" })
    }
}
