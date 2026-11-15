import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SphereRuntime
import SphereCore
import SphereLLM
import SphereTools
import SphereScreen
import SphereKnowledge
import SphereSpeech

@MainActor
public final class AppModel: ObservableObject {
    public let runtime: SphereRuntime?

    @Published public var startupError: String?
    @Published public var config: AppConfig

    @Published public var sessions: [Session] = []
    @Published public var currentSessionId: String?
    @Published public var messages: [ChatMessage] = []
    @Published public var toolCalls: [ToolCallRecord] = []
    @Published public var streamingText = ""
    @Published public var input = ""
    @Published public var attachments: [ChatAttachment] = []
    @Published public var isBusy = false
    @Published public var sessionUsage: SessionUsage = .zero
    @Published public var accessSummary: AccessSummary = .empty

    @Published public var modules: [InstalledModule] = []
    @Published public var grants: [PathGrant] = []
    @Published public var accessEvents: [AccessEvent] = []

    @Published public var screenGrants: [ScreenGrant] = []
    @Published public var windows: [WindowInfo] = []
    @Published public var screenStatus = ""
    @Published public var capturePreview: NSImage?

    @Published public var networkRules: [NetworkRule] = []
    @Published public var networkEvents: [NetworkEvent] = []
    @Published public var networkSummary: NetworkSummary = .empty
    @Published public var networkStatus = ""

    @Published public var errorMessage: String?
    @Published public var apiKeyDraft = ""
    public let speech = SpeechService()
    @Published public var isSpeaking = false
    @Published public var isSpeechPaused = false
    @Published public var availableModels: [LLMModel] = []
    @Published public var isLoadingModels = false
    @Published public var modelListStatus = ""
    @Published public var diagnosticsStatus = ""

    public init() {
        do {
            let runtime = try SphereRuntime()
            self.runtime = runtime
            self.config = runtime.config
        } catch {
            self.runtime = nil
            self.config = AppConfig()
            self.startupError = error.localizedDescription
        }
        speech.onSpeakingChanged = { [weak self] speaking, paused in
            self?.isSpeaking = speaking
            self?.isSpeechPaused = paused
        }

        refreshAll()
        Task { [weak self] in
            await self?.runtime?.startEnabledModules()
            self?.refreshAll()
            self?.loadModelsForActive()
        }
    }

    // MARK: - Refresh

    public func refreshAll() {
        guard let runtime else { return }
        sessions = (try? runtime.sessions.sessions()) ?? []
        modules = (try? runtime.modules.all()) ?? []
        grants = (try? runtime.permissions.pathGrants()) ?? []
        accessEvents = (try? runtime.permissions.accessEvents(limit: 200)) ?? []
        screenGrants = (try? runtime.permissions.screenGrants()) ?? []
        reloadMessages()
        refreshStatus()
        refreshNetwork()
    }

    public func reloadMessages() {
        guard let runtime, let sessionId = currentSessionId else {
            messages = []
            toolCalls = []
            return
        }
        messages = (try? runtime.sessions.messages(sessionId: sessionId)) ?? []
        toolCalls = (try? runtime.sessions.toolCalls(sessionId: sessionId)) ?? []
    }

    public func reloadToolCalls() {
        guard let runtime, let sessionId = currentSessionId else {
            toolCalls = []
            return
        }
        toolCalls = (try? runtime.sessions.toolCalls(sessionId: sessionId)) ?? []
    }

    // MARK: - Sessions

    public func newSession() {
        guard let runtime else { return }
        do {
            let session = try runtime.sessions.createSession(providerId: config.activeProviderId, model: config.activeProvider?.model)
            sessions = try runtime.sessions.sessions()
            currentSessionId = session.id
            messages = []
            toolCalls = []
            refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(session: Session) {
        currentSessionId = session.id
        reloadMessages()
        refreshStatus()
    }

    public func renameSession(_ session: Session, to title: String) {
        guard let runtime else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try runtime.sessions.renameSession(id: session.id, title: trimmed)
            sessions = try runtime.sessions.sessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSession(_ session: Session) {
        guard let runtime else { return }
        do {
            try runtime.sessions.deleteSession(id: session.id)
            if currentSessionId == session.id {
                currentSessionId = nil
                messages = []
                toolCalls = []
                attachments = []
                sessionUsage = .zero
            }
            sessions = try runtime.sessions.sessions()
            if currentSessionId == nil, let next = sessions.first {
                select(session: next)
            } else {
                refreshStatus()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Chat

    public func send() {
        guard let runtime else { return }
        let typedText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendingAttachments = attachments
        guard !typedText.isEmpty || !sendingAttachments.isEmpty else { return }

        var modelText = typedText
        if !sendingAttachments.isEmpty {
            let lines = sendingAttachments
                .map { "- \($0.name) (\($0.type)): \($0.path)" }
                .joined(separator: "\n")
            modelText += (modelText.isEmpty ? "" : "\n\n") + "Attached files:\n\(lines)"
        }
        guard let providerConfig = runtime.activeProviderConfig else {
            errorMessage = "No LLM provider configured."
            return
        }
        guard let provider = runtime.provider(for: providerConfig) else {
            errorMessage = "Could not create provider '\(providerConfig.name)'."
            return
        }

        if currentSessionId == nil {
            newSession()
        }
        guard let sessionId = currentSessionId else { return }

        input = ""
        attachments = []
        isBusy = true
        streamingText = ""
        errorMessage = nil
        if isSpeaking {
            speech.stop()
        }

        let history: [LLMMessage] = messages
            .filter { $0.role != .system }
            .map { message in
                switch message.role {
                case .user:
                    return LLMMessage(role: .user, content: message.content)
                case .assistant:
                    return LLMMessage(
                        role: .assistant,
                        content: message.content,
                        toolCalls: message.toolCalls
                    )
                case .tool:
                    return LLMMessage(
                        role: .tool,
                        content: message.content,
                        toolCallId: message.toolCallId,
                        name: message.name
                    )
                case .system:
                    return LLMMessage(role: .system, content: message.content)
                }
            }

        Task { @MainActor in
            defer {
                isBusy = false
                streamingText = ""
                reloadMessages()
                refreshStatus()
            }
            do {
                let runner = runtime.makeRunner(provider: provider)
                let stream = runner.run(
                    sessionId: sessionId,
                    userText: modelText,
                    displayText: typedText,
                    attachments: sendingAttachments,
                    systemPrompt: SphereRuntime.defaultSystemPrompt,
                    history: history,
                    model: providerConfig.model,
                    options: GenerationOptions(provider: providerConfig)
                )
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        streamingText += delta
                    case .assistantMessage:
                        streamingText = ""
                        reloadMessages()
                    case .toolCallStarted:
                        reloadToolCalls()
                    case .toolCallFinished:
                        reloadToolCalls()
                        refreshStatus()
                    case .usage(let usage):
                        sessionUsage = usage
                        refreshAccessSummary()
                    case .completed(let finalText):
                        streamingText = ""
                        reloadMessages()
                        refreshStatus()
                        if config.speechEnabled && config.speechAutoSpeak && !finalText.isEmpty {
                            speak(finalText)
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func cancel() {
        isBusy = false
    }

    // MARK: - Status bar

    public var currentSession: Session? {
        guard let id = currentSessionId else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    public var activeProviderLabel: String? {
        guard let provider = runtime?.activeProviderConfig else { return nil }
        return "\(provider.name) · \(provider.model)"
    }

    public func refreshStatus() {
        guard let runtime else { return }
        if let id = currentSessionId {
            sessionUsage = (try? runtime.sessions.usage(sessionId: id)) ?? .zero
            accessSummary = (try? runtime.permissions.accessSummary(since: currentSession?.createdAt)) ?? .empty
        } else {
            sessionUsage = .zero
            accessSummary = (try? runtime.permissions.accessSummary(since: nil)) ?? .empty
        }
    }

    public func refreshAccessSummary() {
        guard let runtime else { return }
        accessSummary = (try? runtime.permissions.accessSummary(since: currentSession?.createdAt)) ?? .empty
    }

    // MARK: - Modules

    public func installModuleFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a .spheremodule, .sphereplug, .zip or module folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installModule(url: url)
    }

    public func installModule(url: URL) {
        guard let runtime else { return }
        do {
            let installed = try runtime.installModule(from: url)
            refreshAll()
            errorMessage = nil
            NotificationCenter.default.post(
                name: .sphereModuleInstalled,
                object: nil,
                userInfo: ["id": installed.id]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setModule(_ module: InstalledModule, enabled: Bool) {
        guard let runtime else { return }
        Task { @MainActor in
            do {
                try await runtime.setModuleEnabled(module, enabled: enabled)
                refreshAll()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func revealPluginsFolder() {
        do {
            try AppPaths.revealPluginsFolder()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - File access

    public func addFolderGrant(mode: FileAccessMode) {
        guard let runtime else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to grant to Sphere"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let grant = PathGrant(path: PathPolicy.normalize(url.path), mode: mode, recursive: true, scope: .persistent)
            try runtime.permissions.addPathGrant(grant)
            refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setGrantMode(_ grant: PathGrant, mode: FileAccessMode) {
        guard let runtime else { return }
        do {
            try runtime.permissions.updatePathGrantMode(id: grant.id, mode: mode)
            refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func removeGrant(_ grant: PathGrant) {
        guard let runtime else { return }
        do {
            try runtime.permissions.removePathGrant(id: grant.id)
            refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revealGrant(_ grant: PathGrant) {
        NSWorkspace.shared.open(URL(fileURLWithPath: grant.path))
    }

    // MARK: - Network access

    public func refreshNetwork() {
        guard let runtime else { return }
        networkRules = (try? runtime.networkStore.rules()) ?? []
        networkEvents = (try? runtime.networkStore.events(limit: 200)) ?? []
        networkSummary = (try? runtime.networkStore.summary()) ?? .empty
    }

    public func addNetworkRule(value rawValue: String, kind: NetworkRuleKind) {
        guard let runtime else { return }
        guard let normalized = NetworkPolicy.normalizeRuleValue(rawValue, kind: kind) else {
            networkStatus = "Valore non valido per \(kind.label)."
            return
        }
        do {
            try runtime.networkStore.addRule(NetworkRule(value: normalized, kind: kind))
            networkStatus = "Regola aggiunta: \(normalized)"
            refreshNetwork()
        } catch {
            networkStatus = error.localizedDescription
        }
    }

    public func removeNetworkRule(_ rule: NetworkRule) {
        guard let runtime else { return }
        do {
            try runtime.networkStore.removeRule(id: rule.id)
            networkStatus = "Regola rimossa: \(rule.value)"
            refreshNetwork()
        } catch {
            networkStatus = error.localizedDescription
        }
    }

    public func setNetworkRule(_ rule: NetworkRule, enabled: Bool) {
        guard let runtime else { return }
        do {
            try runtime.networkStore.setRuleEnabled(id: rule.id, enabled: enabled)
            refreshNetwork()
        } catch {
            networkStatus = error.localizedDescription
        }
    }

    // MARK: - Screen access

    public func requestScreenPermission() {
        guard let runtime else { return }
        let granted = runtime.screen.requestPermission()
        screenStatus = granted ? "Screen Recording permission granted." : "Screen Recording permission not granted."
    }

    public func refreshWindows() {
        guard let runtime else { return }
        Task { @MainActor in
            do {
                windows = try await runtime.screen.availableWindows()
                screenStatus = "Found \(windows.count) windows."
            } catch {
                screenStatus = "Could not list windows: \(error.localizedDescription)"
            }
        }
    }

    public func allow(_ window: WindowInfo, persistent: Bool = true) {
        guard let runtime else { return }
        do {
            try runtime.allowlist.allow(window: window, scope: persistent ? .persistent : .session)
            screenGrants = try runtime.permissions.screenGrants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revoke(_ grant: ScreenGrant) {
        guard let runtime else { return }
        do {
            try runtime.allowlist.revoke(grantId: grant.id)
            screenGrants = try runtime.permissions.screenGrants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func captureWindow(_ window: WindowInfo) {
        guard let runtime else { return }
        Task { @MainActor in
            do {
                guard try runtime.allowlist.isAllowed(window) else {
                    screenStatus = "Window not allowed. Allow it first."
                    return
                }
                let data = try await runtime.screen.captureWindow(window)
                capturePreview = NSImage(data: data)
                try? FileManager.default.createDirectory(at: AppPaths.captures, withIntermediateDirectories: true)
                let target = AppPaths.captures.appendingPathComponent("capture-\(window.id)-\(Int(Date().timeIntervalSince1970)).png")
                try? data.write(to: target)
                screenStatus = "Captured to \(target.path)"
            } catch {
                screenStatus = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Attachments

    public func addAttachments(urls: [URL]) {
        for url in urls {
            let path = url.path
            if attachments.contains(where: { $0.path == path }) { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            let contentType = values?.contentType
            let isDirectory = values?.isDirectory ?? false

            let type: String
            if isDirectory {
                type = "Folder"
            } else if let contentType, let description = contentType.localizedDescription {
                type = description
            } else if !url.pathExtension.isEmpty {
                type = url.pathExtension.uppercased()
            } else {
                type = "File"
            }

            attachments.append(
                ChatAttachment(
                    path: path,
                    name: url.lastPathComponent,
                    type: type,
                    isImage: contentType?.conforms(to: .image) ?? false
                )
            )
        }
        if attachments.count > 10 {
            attachments = Array(attachments.prefix(10))
        }
    }

    public func removeAttachment(_ attachment: ChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    public func pickAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Seleziona file da allegare al messaggio"
        guard panel.runModal() == .OK else { return }
        addAttachments(urls: panel.urls)
    }

    // MARK: - Fonts

    public func messageFont(for role: MessageRole) -> Font {
        switch role {
        case .user:
            return makeFont(name: config.userFontName, size: config.userFontSize)
        case .assistant:
            return makeFont(name: config.assistantFontName, size: config.assistantFontSize)
        case .system, .tool:
            return .system(size: 13)
        }
    }

    public func setUserFontName(_ name: String?) {
        config.userFontName = name
        saveConfig()
    }

    public func setUserFontSize(_ size: Double) {
        config.userFontSize = size
        saveConfig()
    }

    public func setAssistantFontName(_ name: String?) {
        config.assistantFontName = name
        saveConfig()
    }

    public func setAssistantFontSize(_ size: Double) {
        config.assistantFontSize = size
        saveConfig()
    }

    private func makeFont(name: String?, size: Double) -> Font {
        if let name, !name.isEmpty {
            return .custom(name, size: size)
        }
        return .system(size: size)
    }

    // MARK: - Speech

    public func setSpeechEnabled(_ value: Bool) {
        config.speechEnabled = value
        if !value {
            speech.stop()
        }
        saveConfig()
    }

    public func speak(_ text: String) {
        guard config.speechEnabled else { return }
        speech.speak(
            text,
            voiceIdentifier: config.speechVoiceIdentifier,
            rate: config.speechRate
        )
    }

    public func speakMessage(_ message: ChatMessage) {
        guard config.speechEnabled, message.role == .assistant else { return }
        speak(message.content)
    }

    public func stopSpeaking() {
        speech.stop()
    }

    public func toggleSpeechPause() {
        if speech.isPaused {
            speech.resume()
        } else {
            speech.pause()
        }
    }

    public func testVoice() {
        speak("Ciao, questa è la voce di Sphere.")
    }

    public func setSpeechAutoSpeak(_ value: Bool) {
        config.speechAutoSpeak = value
        saveConfig()
    }

    public func setSpeechVoice(_ identifier: String?) {
        config.speechVoiceIdentifier = identifier
        saveConfig()
    }

    public func setSpeechRate(_ value: Double) {
        config.speechRate = value
        saveConfig()
    }

    // MARK: - Settings

    public func selectProvider(_ id: String) {
        config.activeProviderId = id
        apiKeyDraft = ""
        availableModels = []
        modelListStatus = ""
        saveConfig()
        if let provider = config.providers.first(where: { $0.id == id }) {
            loadModels(for: provider)
        }
    }

    public var activeProviderConfig: ProviderConfig? {
        runtime?.activeProviderConfig
    }

    public var modelChoices: [String] {
        var ids = availableModels.map(\.id)
        if let current = activeProviderConfig?.model, !current.isEmpty, !ids.contains(current) {
            ids.insert(current, at: 0)
        }
        return ids
    }

    public func loadModelsForActive() {
        guard let provider = activeProviderConfig else { return }
        loadModels(for: provider)
    }

    public func loadModels(for provider: ProviderConfig) {
        guard let runtime else { return }
        isLoadingModels = true
        modelListStatus = "Caricamento modelli…"
        Task { @MainActor in
            defer { isLoadingModels = false }
            do {
                let models = try await runtime.listModels(for: provider)
                guard runtime.activeProviderConfig?.id == provider.id else { return }
                availableModels = models
                modelListStatus = models.isEmpty
                    ? "Nessun modello elencato dal provider."
                    : "\(models.count) modelli disponibili."
            } catch {
                guard runtime.activeProviderConfig?.id == provider.id else { return }
                availableModels = []
                modelListStatus = "Impossibile caricare i modelli: \(error.localizedDescription)"
            }
        }
    }

    public func selectModel(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = config
        let index = updated.providers.firstIndex(where: { $0.id == updated.activeProviderId })
            ?? updated.providers.indices.first
        guard let index else { return }
        updated.providers[index].model = trimmed
        config = updated
        saveConfig()
    }

    public func saveAPIKey(for provider: ProviderConfig) {
        guard !apiKeyDraft.isEmpty, let runtime else { return }
        do {
            try runtime.saveAPIKey(apiKeyDraft, for: provider)
            apiKeyDraft = ""
            errorMessage = nil
            loadModels(for: provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteAPIKey(for provider: ProviderConfig) {
        runtime?.deleteAPIKey(for: provider)
    }

    public func importKeysFromKeychain() {
        guard let runtime else { return }
        let imported = runtime.importKeysFromKeychain()
        diagnosticsStatus = imported == 0
            ? "Nessuna chiave importata dal Keychain (item assente o accesso negato)."
            : "Importate \(imported) chiavi dal Keychain nel file segreti."
        loadModelsForActive()
    }

    public func saveConfig() {
        guard let runtime else { return }
        do {
            try runtime.saveConfig(config)
            Task { await runtime.applyPolicy() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revealDataFolder() {
        NSWorkspace.shared.open(AppPaths.applicationSupport)
    }

    public func revealLogsFolder() {
        NSWorkspace.shared.open(AppPaths.logs)
    }

    public func openLog(named name: String) {
        let url = AppPaths.logs.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        NSWorkspace.shared.open(url)
    }

    public func setDebugHTTPLogging(_ enabled: Bool) {
        config.debugHTTPLogging = enabled
        saveConfig()
    }
}

extension Notification.Name {
    public static let sphereModuleInstalled = Notification.Name("SphereModuleInstalled")
}

private extension AppConfig {
    var activeProvider: ProviderConfig? {
        guard let id = activeProviderId else { return providers.first }
        return providers.first(where: { $0.id == id }) ?? providers.first
    }
}
