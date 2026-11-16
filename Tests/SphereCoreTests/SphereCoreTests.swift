import XCTest
@testable import SphereCore
@testable import SphereLLM

final class ManifestTests: XCTestCase {
    func testMinimalManifestDecodesWithDefaults() throws {
        let json = """
        { "id": "com.example.ping", "name": "Ping", "version": "1.0.0" }
        """
        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.kind, .mcp)
        XCTAssertFalse(manifest.permissions.network)
        XCTAssertFalse(manifest.autoStart)
    }

    func testMCPManifestRequiresTransport() {
        let manifest = ModuleManifest(id: "com.example.ping", name: "Ping", version: "1.0.0")
        XCTAssertThrowsError(try manifest.validate())
    }

    func testValidMCPManifest() throws {
        let manifest = ModuleManifest(
            id: "com.example.ping",
            name: "Ping",
            version: "1.0.0",
            transport: ModuleTransport(command: ["node", "server.js"])
        )
        XCTAssertNoThrow(try manifest.validate())
    }

    func testInvalidIdentifierRejected() {
        let manifest = ModuleManifest(
            id: "com example/ping",
            name: "Ping",
            version: "1.0.0",
            transport: ModuleTransport(command: ["node"])
        )
        XCTAssertThrowsError(try manifest.validate())
    }
}

final class PathPolicyTests: XCTestCase {
    func testExactAndRecursiveCoverage() {
        let grant = PathGrant(path: "/Users/test/Projects", mode: .readOnly, recursive: true)
        let policy = PathPolicy(grants: [grant])

        XCTAssertTrue(policy.evaluate(path: "/Users/test/Projects/a.txt", operation: .read).isAllowed)
        XCTAssertTrue(policy.evaluate(path: "/Users/test/Projects/sub/b.txt", operation: .read).isAllowed)
        XCTAssertFalse(policy.evaluate(path: "/Users/test/Other/c.txt", operation: .read).isAllowed)
    }

    func testNonRecursiveOnlyCoversPrefixBoundary() {
        let grant = PathGrant(path: "/Users/test/Projects", mode: .readOnly, recursive: false)
        let policy = PathPolicy(grants: [grant])

        XCTAssertTrue(policy.evaluate(path: "/Users/test/Projects", operation: .read).isAllowed)
        XCTAssertFalse(policy.evaluate(path: "/Users/test/Projects/a.txt", operation: .read).isAllowed)
    }

    func testReadOnlyGrantBlocksWrites() {
        let grant = PathGrant(path: "/Users/test/Projects", mode: .readOnly, recursive: true)
        let policy = PathPolicy(grants: [grant])

        XCTAssertTrue(policy.evaluate(path: "/Users/test/Projects/a.txt", operation: .read).isAllowed)
        XCTAssertFalse(policy.evaluate(path: "/Users/test/Projects/a.txt", operation: .write).isAllowed)
    }

    func testReadWriteGrantAllowsWrites() {
        let grant = PathGrant(path: "/Users/test/Projects", mode: .readWrite, recursive: true)
        let policy = PathPolicy(grants: [grant])
        XCTAssertTrue(policy.evaluate(path: "/Users/test/Projects/a.txt", operation: .write).isAllowed)
    }
}

final class StoreTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        return database
    }

    func testAccessCountersUpdate() throws {
        let database = try makeDatabase()
        let store = PermissionStore(database: database)
        let engine = PermissionEngine(store: store)

        let grant = PathGrant(path: "/tmp/sphere-test", mode: .readWrite, recursive: true)
        try store.addPathGrant(grant)

        let readDecision = try engine.authorize(moduleId: "com.test", path: "/tmp/sphere-test/a.txt", operation: .read)
        XCTAssertTrue(readDecision.allowed)

        let writeDecision = try engine.authorize(moduleId: "com.test", path: "/tmp/sphere-test/a.txt", operation: .write)
        XCTAssertTrue(writeDecision.allowed)

        let grants = try store.pathGrants()
        XCTAssertEqual(grants.first?.readCount, 1)
        XCTAssertEqual(grants.first?.writeCount, 1)
    }

    func testDeniedAccessIsAuditedButNotCounted() throws {
        let database = try makeDatabase()
        let store = PermissionStore(database: database)
        let engine = PermissionEngine(store: store)

        let decision = try engine.authorize(moduleId: "com.test", path: "/etc/hosts", operation: .read)
        XCTAssertFalse(decision.allowed)

        let events = try store.accessEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events.first?.allowed ?? true)
        XCTAssertTrue(try store.pathGrants().isEmpty)
    }

    func testModuleRegistryRoundTrip() throws {
        let database = try makeDatabase()
        let registry = ModuleRegistry(database: database)
        let manifest = ModuleManifest(
            id: "com.test.mod",
            name: "Test",
            version: "0.1.0",
            transport: ModuleTransport(command: ["node"])
        )
        try registry.upsert(InstalledModule(manifest: manifest, installPath: "/tmp/mod", enabled: true))

        let loaded = try registry.find(id: "com.test.mod")
        XCTAssertEqual(loaded?.manifest.name, "Test")
        XCTAssertEqual(loaded?.enabled, true)
        XCTAssertEqual(try registry.enabledModules().count, 1)
    }
}

final class ConfigTests: XCTestCase {
    func testMergeBuiltInProvidersAddsDeepSeek() {
        var config = AppConfig(providers: [.ollama()], activeProviderId: "existing")
        XCTAssertTrue(config.mergeBuiltInProviders())

        let names = Set(config.providers.map(\.name))
        XCTAssertTrue(names.contains("DeepSeek"))
        XCTAssertTrue(names.contains("OpenAI"))
        XCTAssertTrue(names.contains("Anthropic"))
        XCTAssertEqual(config.activeProviderId, "existing")

        let deepSeek = config.providers.first { $0.name == "DeepSeek" }
        XCTAssertEqual(deepSeek?.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(deepSeek?.model, "deepseek-flash")
        XCTAssertEqual(deepSeek?.kind, .openAICompatible)

        XCTAssertFalse(config.mergeBuiltInProviders(), "second merge must be a no-op")
    }

    func testAppConfigDecodesSpeechDefaults() throws {
        let json = """
        {"providers":[{"id":"x","name":"P","kind":"openAICompatible","baseURL":"http://localhost/v1","model":"m"}]}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.speechEnabled)
        XCTAssertFalse(config.speechAutoSpeak)
        XCTAssertNil(config.speechVoiceIdentifier)
        XCTAssertEqual(config.speechRate, 0.5, accuracy: 0.0001)
        XCTAssertNil(config.userFontName)
        XCTAssertEqual(config.userFontSize, 13, accuracy: 0.0001)
        XCTAssertNil(config.assistantFontName)
        XCTAssertEqual(config.assistantFontSize, 13, accuracy: 0.0001)
    }

    func testProviderConfigDecodesWithoutNewOptionalParameters() throws {
        let json = """
        {"id":"x","name":"P","kind":"openAICompatible","baseURL":"http://localhost/v1","model":"m"}
        """
        let provider = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
        XCTAssertEqual(provider.model, "m")
        XCTAssertNil(provider.topP)
        XCTAssertNil(provider.topK)
        XCTAssertNil(provider.frequencyPenalty)
        XCTAssertNil(provider.presencePenalty)
        XCTAssertNil(provider.stopSequences)
        XCTAssertNil(provider.seed)
    }
}

final class SessionTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        return database
    }

    func testRenameSession() throws {
        let database = try makeDatabase()
        let store = SessionStore(database: database)
        let session = try store.createSession(title: "Vecchio")

        try store.renameSession(id: session.id, title: "Nuovo nome")
        XCTAssertEqual(try store.sessions().first?.title, "Nuovo nome")
    }

    func testMessageToolCallsRoundTrip() throws {
        let database = try makeDatabase()
        let store = SessionStore(database: database)
        let session = try store.createSession()
        let call = LLMToolCall(
            id: "call_1",
            name: "sphere_filesystem_fs_list",
            arguments: .object(["path": .string("/tmp")])
        )

        try store.appendMessage(
            ChatMessage(
                sessionId: session.id,
                role: .assistant,
                content: "",
                toolCalls: [call]
            )
        )
        try store.appendMessage(
            ChatMessage(
                sessionId: session.id,
                role: .tool,
                content: "ok",
                toolCallId: "call_1",
                name: call.name
            )
        )

        let messages = try store.messages(sessionId: session.id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.toolCalls.count, 1)
        XCTAssertEqual(messages.first?.toolCalls.first?.id, "call_1")
        XCTAssertEqual(messages.first?.toolCalls.first?.name, call.name)
        XCTAssertEqual(messages.first?.toolCalls.first?.arguments, call.arguments)
    }

    func testDeleteSessionCascadesMessages() throws {
        let database = try makeDatabase()
        let store = SessionStore(database: database)
        let session = try store.createSession()
        try store.appendMessage(ChatMessage(sessionId: session.id, role: .user, content: "ciao"))

        try store.deleteSession(id: session.id)
        XCTAssertTrue(try store.sessions().isEmpty)
        XCTAssertTrue(try store.messages(sessionId: session.id).isEmpty)
    }
}

final class NetworkTests: XCTestCase {
    func testRuleNormalization() {
        XCTAssertEqual(
            NetworkPolicy.normalizeRuleValue("example.com/path", kind: .url),
            "https://example.com/path"
        )
        XCTAssertEqual(
            NetworkPolicy.normalizeRuleValue("https://example.com/x", kind: .url),
            "https://example.com/x"
        )
        XCTAssertEqual(
            NetworkPolicy.normalizeRuleValue("https://Sub.Example.com/x", kind: .domain),
            "sub.example.com"
        )
        XCTAssertEqual(NetworkPolicy.normalizeRuleValue("10.0.0.0/8", kind: .ip), "10.0.0.0/8")
        XCTAssertNotNil(NetworkPolicy.normalizeRuleValue("8.8.8.8", kind: .ip))
        XCTAssertNil(NetworkPolicy.normalizeRuleValue("not an ip", kind: .ip))
        XCTAssertNil(NetworkPolicy.normalizeRuleValue("10.0.0.0/99", kind: .ip))
    }

    func testMatchingHelpers() {
        XCTAssertTrue(NetworkPolicy.matchesURL("https://evil.com", "https://evil.com/path"))
        XCTAssertFalse(NetworkPolicy.matchesURL("https://evil.com", "https://good.com/evil.com"))
        XCTAssertTrue(NetworkPolicy.matchesDomain("evil.com", "api.evil.com"))
        XCTAssertFalse(NetworkPolicy.matchesDomain("evil.com", "notevil.com"))
        XCTAssertTrue(NetworkPolicy.matchesIP("10.0.0.0/8", host: "10.1.2.3", resolved: []))
        XCTAssertTrue(NetworkPolicy.matchesIP("8.8.8.8", host: "example.com", resolved: ["8.8.8.8"]))
        XCTAssertFalse(NetworkPolicy.matchesIP("8.8.4.4", host: "example.com", resolved: ["8.8.8.8"]))
    }

    func testNetworkStoreCountersAndSummary() throws {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let store = NetworkStore(database: database)

        let rule = NetworkRule(value: "evil.com", kind: .domain)
        try store.addRule(rule)

        try store.recordEvent(NetworkEvent(url: "https://evil.com/a", host: "evil.com", allowed: false, ruleId: rule.id))
        try store.recordEvent(NetworkEvent(url: "https://good.com/a", host: "good.com", allowed: true))
        try store.recordBlocked(ruleId: rule.id)

        let summary = try store.summary()
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.allowed, 1)
        XCTAssertEqual(summary.blocked, 1)

        let rules = try store.rules()
        XCTAssertEqual(rules.first?.blockedCount, 1)
        XCTAssertEqual(rules.first?.value, "evil.com")
    }

    func testPolicyBlocksBannedDomain() async throws {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let store = NetworkStore(database: database)
        try store.addRule(NetworkRule(value: "evil.com", kind: .domain))
        let policy = NetworkPolicy(store: store)

        let blocked = await policy.evaluate(url: URL(string: "https://api.evil.com/x")!)
        XCTAssertTrue(blocked.blocked)

        let allowed = await policy.evaluate(url: URL(string: "https://example.com/x")!)
        XCTAssertFalse(allowed.blocked)
    }
}

final class UsageTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        return database
    }

    func testSessionUsageAccumulates() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)
        let session = try sessions.createSession()

        let first = try sessions.recordUsage(
            sessionId: session.id,
            promptTokens: 100,
            completionTokens: 20,
            costUSD: 0.001
        )
        XCTAssertEqual(first.promptTokens, 100)
        XCTAssertEqual(first.completionTokens, 20)
        XCTAssertEqual(first.totalTokens, 120)

        let second = try sessions.recordUsage(
            sessionId: session.id,
            promptTokens: 50,
            completionTokens: 10,
            costUSD: 0.002
        )
        XCTAssertEqual(second.promptTokens, 150)
        XCTAssertEqual(second.completionTokens, 30)
        XCTAssertEqual(second.totalTokens, 180)
        XCTAssertEqual(second.costUSD, 0.003, accuracy: 0.000_001)
    }

    func testMessageAttachmentsRoundTrip() throws {
        let database = try makeDatabase()
        let sessions = SessionStore(database: database)
        let session = try sessions.createSession()

        let attachment = ChatAttachment(
            path: "/tmp/report.pdf",
            name: "report.pdf",
            type: "PDF document",
            isImage: false
        )
        try sessions.appendMessage(
            ChatMessage(
                sessionId: session.id,
                role: .user,
                content: "Analizza questo file",
                attachments: [attachment]
            )
        )

        let messages = try sessions.messages(sessionId: session.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.attachments.count, 1)
        XCTAssertEqual(messages.first?.attachments.first?.name, "report.pdf")
        XCTAssertEqual(messages.first?.attachments.first?.type, "PDF document")
        XCTAssertEqual(messages.first?.attachments.first?.path, "/tmp/report.pdf")
    }

    func testAccessSummaryCountsReadsWritesAndDenied() throws {
        let database = try makeDatabase()
        let store = PermissionStore(database: database)
        let engine = PermissionEngine(store: store)
        try store.addPathGrant(PathGrant(path: "/tmp/sphere-summary", mode: .readWrite, recursive: true))

        _ = try engine.authorize(moduleId: "com.test", path: "/tmp/sphere-summary/a.txt", operation: .read)
        _ = try engine.authorize(moduleId: "com.test", path: "/tmp/sphere-summary/a.txt", operation: .write)
        _ = try engine.authorize(moduleId: "com.test", path: "/etc/hosts", operation: .read)

        let all = try store.accessSummary(since: nil)
        XCTAssertEqual(all.total, 3)
        XCTAssertEqual(all.reads, 2)
        XCTAssertEqual(all.writes, 1)
        XCTAssertEqual(all.denied, 1)
    }
}

final class PricingTests: XCTestCase {
    func testKnownModelCost() {
        let cost = Pricing.cost(model: "gpt-4o-mini", promptTokens: 1_000_000, completionTokens: 1_000_000)
        XCTAssertEqual(cost ?? -1, 0.75, accuracy: 0.0001)
    }

    func testUnknownModelHasNoCost() {
        XCTAssertNil(Pricing.cost(model: "some-local-model", promptTokens: 10, completionTokens: 10))
    }

    func testDeepSeekCacheMissAndOutputCost() {
        let offPeak = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
        let cost = Pricing.cost(
            model: "deepseek-flash",
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            cacheHitTokens: 0,
            cacheMissTokens: 1_000_000,
            at: offPeak
        )
        XCTAssertEqual(cost ?? -1, 0.75, accuracy: 0.000_001)
    }

    func testDeepSeekCachedInputIsCheaper() {
        let offPeak = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
        let cost = Pricing.cost(
            model: "deepseek-flash",
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            cacheHitTokens: 1_000_000,
            cacheMissTokens: 0,
            at: offPeak
        )
        XCTAssertEqual(cost ?? -1, 0.603, accuracy: 0.000_001)
    }

    func testDeepSeekPeakMultiplier() {
        let offPeak = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
        let peak = ISO8601DateFormatter().date(from: "2026-11-16T02:00:00Z")!
        let off = Pricing.cost(model: "deepseek-flash", promptTokens: 1_000_000, completionTokens: 1_000_000, at: offPeak)
        let on = Pricing.cost(model: "deepseek-flash", promptTokens: 1_000_000, completionTokens: 1_000_000, at: peak)
        XCTAssertEqual((on ?? 0), (off ?? 0) * 2, accuracy: 0.000_001)
    }

    func testBackfillMissingCosts() throws {
        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let sessions = SessionStore(database: database)
        let session = try sessions.createSession(model: "gpt-4o-mini")
        _ = try sessions.recordUsage(
            sessionId: session.id,
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            costUSD: 0
        )
        XCTAssertEqual(try sessions.usage(sessionId: session.id).costUSD, 0, accuracy: 0.000_001)
        try sessions.backfillMissingCosts()
        XCTAssertEqual(try sessions.usage(sessionId: session.id).costUSD, 0.75, accuracy: 0.000_001)
    }
}

final class InstallerTests: XCTestCase {
    func testInstallFolderPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sphere-test-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let plugins = root.appendingPathComponent("plugins")
        let store = root.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = """
        {
          "id": "com.test.hello",
          "name": "Hello",
          "version": "1.0.0",
          "kind": "mcp",
          "transport": { "type": "stdio", "command": ["node", "${MODULE_DIR}/server.js"] }
        }
        """
        try Data(manifest.utf8).write(to: source.appendingPathComponent("module.json"))

        let database = try Database(path: Database.transient)
        try Migrations.migrate(database)
        let registry = ModuleRegistry(database: database)
        let installer = ModuleInstaller(registry: registry, pluginsDirectory: plugins, storeDirectory: store)

        let installed = try installer.install(from: source)
        XCTAssertEqual(installed.manifest.id, "com.test.hello")
        XCTAssertFalse(installed.enabled)

        let resolved = installed.manifest.resolvedTransport(installPath: installed.installPath)
        XCTAssertEqual(resolved?.command.last, "\(installed.installPath)/server.js")
        XCTAssertEqual(resolved?.cwd, installed.installPath)
    }
}

final class LLMHistoryTests: XCTestCase {
    func testDropsOrphanToolMessages() {
        let call = LLMToolCall(id: "call_1", name: "tool", arguments: .object([:]))
        let history: [LLMMessage] = [
            LLMMessage(role: .user, content: "leggi il file"),
            LLMMessage(role: .assistant, content: "fatto"),
            LLMMessage(role: .tool, content: "contenuto", toolCallId: "call_1"),
        ]

        let sanitized = LLMHistory.sanitized(history)
        XCTAssertEqual(sanitized.map(\.role), [.user, .assistant])
    }

    func testKeepsAnsweredToolCallsAndDropsUnansweredOnes() {
        let answered = LLMToolCall(id: "call_1", name: "a", arguments: .object([:]))
        let missing = LLMToolCall(id: "call_2", name: "b", arguments: .object([:]))
        let history: [LLMMessage] = [
            LLMMessage(role: .user, content: "fai"),
            LLMMessage(role: .assistant, content: "", toolCalls: [answered, missing]),
            LLMMessage(role: .tool, content: "ok", toolCallId: "call_1"),
            LLMMessage(role: .user, content: "bene"),
        ]

        let sanitized = LLMHistory.sanitized(history)
        XCTAssertEqual(sanitized.map(\.role), [.user, .assistant, .tool, .user])
        XCTAssertEqual(sanitized[1].toolCalls.map(\.id), ["call_1"])
        XCTAssertEqual(sanitized[2].toolCallId, "call_1")
    }
}
