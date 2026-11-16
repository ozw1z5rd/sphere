import XCTest
@testable import SphereCore

final class SessionNumberingTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        return database
    }

    func testSessionNumbersAreProgressiveAndNotReused() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)

        let first = try sessions.createSession()
        let second = try sessions.createSession()
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(second.number, 2)
        XCTAssertEqual(try sessions.sessions().map(\.number).sorted(), [1, 2])

        try sessions.deleteSession(id: first.id)
        let third = try sessions.createSession()
        XCTAssertEqual(third.number, 3)
    }

    func testAccessEventsCarrySessionNumber() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)
        let permissions = PermissionStore(database: database)
        let engine = PermissionEngine(store: permissions)
        let session = try sessions.createSession()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-attr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try permissions.addPathGrant(PathGrant(path: root.path, mode: .readWrite, recursive: true))

        _ = try engine.require(
            moduleId: "test",
            sessionId: session.id,
            path: root.appendingPathComponent("file.txt").path,
            operation: .read
        )

        let event = try XCTUnwrap(permissions.accessEvents(limit: 1).first)
        XCTAssertEqual(event.sessionId, session.id)
        XCTAssertEqual(event.sessionNumber, 1)
    }

    func testNetworkAndClipboardEventsCarrySessionNumber() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)
        let network = NetworkStore(database: database)
        let clipboard = ClipboardStore(database: database)
        let session = try sessions.createSession()

        try network.recordEvent(NetworkEvent(sessionId: session.id, url: "https://example.com", host: "example.com", allowed: true))
        try clipboard.record(ClipboardEvent(sessionId: session.id, operation: "read", detail: "ok"))

        XCTAssertEqual(try network.events(limit: 1).first?.sessionNumber, 1)
        XCTAssertEqual(try clipboard.events(limit: 1).first?.sessionNumber, 1)
        XCTAssertEqual(try network.count(sessionId: session.id), 1)
        XCTAssertEqual(try clipboard.count(sessionId: session.id, operation: "read", allowedOnly: true), 1)
    }

    func testToolCallsCarrySessionNumberAndLimit() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)
        let session = try sessions.createSession()

        for index in 0..<205 {
            try sessions.recordToolCall(
                ToolCallRecord(
                    sessionId: session.id,
                    moduleId: "test",
                    toolName: "tool_\(index)",
                    startedAt: Date().addingTimeInterval(Double(index))
                )
            )
        }

        XCTAssertEqual(try sessions.toolCallCount(sessionId: session.id), 205)
        let recent = try sessions.toolCalls(limit: 200)
        XCTAssertEqual(recent.count, 200)
        XCTAssertEqual(recent.first?.toolName, "tool_204")
        XCTAssertEqual(recent.first?.sessionNumber, 1)
    }

    func testAccessLogLimitIs200() throws {
        let database = try makeDatabase()
        let permissions = PermissionStore(database: database)
        for index in 0..<205 {
            try permissions.recordAccess(
                AccessEvent(
                    moduleId: "test",
                    path: "/tmp/\(index)",
                    operation: .read,
                    allowed: true,
                    timestamp: Date().addingTimeInterval(Double(index))
                )
            )
        }
        XCTAssertEqual(try permissions.accessEvents(limit: 200).count, 200)
    }
}
