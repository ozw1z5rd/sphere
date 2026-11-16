import SwiftUI
import AppKit
import SphereCore
import SphereSpeech

struct SettingsView: View {
    var body: some View {
        TabView {
            ScrollView {
                GeneralSection().padding(16)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            ScrollView {
                ToolsSection().padding(16)
            }
            .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }

            ScrollView {
                ProviderSection().padding(16)
            }
            .tabItem { Label("Provider", systemImage: "cpu") }

            ScrollView {
                SpeechSection().padding(16)
            }
            .tabItem { Label("Voce", systemImage: "speaker.wave.2") }

            ScrollView {
                AppearanceSection().padding(16)
            }
            .tabItem { Label("Aspetto", systemImage: "textformat") }

            ScrollView {
                DiagnosticsSection().padding(16)
            }
            .tabItem { Label("Diagnostica", systemImage: "stethoscope") }

            ScrollView {
                KnowledgeSection().padding(16)
            }
            .tabItem { Label("Knowledge", systemImage: "books.vertical") }

            ScrollView {
                StorageSection().padding(16)
            }
            .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .padding(.top, 8)
    }
}

private struct GeneralSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox("Language") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Language", selection: Binding(
                    get: { model.config.language ?? "system" },
                    set: { model.setLanguage($0 == "system" ? nil : $0) }
                )) {
                    Text("System (default)").tag("system")
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Interface language. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

private struct ToolsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var allowlistText = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Sandboxed exec") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable sandboxed exec", isOn: Binding(
                        get: { model.config.execEnabled },
                        set: { enabled in
                            model.setExecEnabled(enabled)
                            saved = false
                        }
                    ))

                    Text("Exec runs inside a granted directory with no network access and writes limited to the granted root. Commands that can write require a read-write grant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("Allowed command prefixes (one per line). argv is passed directly, without a shell.")
                        .font(.caption.weight(.semibold))

                    TextEditor(text: $allowlistText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    HStack(spacing: 8) {
                        Button("Save allowlist") {
                            model.setExecAllowlist(parsedAllowlist)
                            saved = true
                        }
                        if saved {
                            Text("Saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Built-in tools") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.builtInTools, id: \.self) { tool in
                        Text(tool)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
        .onAppear {
            allowlistText = model.effectiveExecAllowlist.joined(separator: "\n")
        }
    }

    private var parsedAllowlist: [String] {
        allowlistText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static let builtInTools = [
        "sphere.filesystem: fs_read, fs_write, fs_list, fs_glob, fs_grep, fs_stat, fs_read_bytes, fs_edit, fs_select, image_inspect",
        "sphere.git: git (status, diff, log, show, blame)",
        "sphere.system: system_info, clipboard_read, clipboard_write",
        "sphere.web: web_fetch, web_search",
        "sphere.exec: exec (sandboxed)",
    ]
}

private struct ProviderSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox("LLM provider") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.config.providers.enumerated()), id: \.element.id) { index, provider in
                    ProviderRow(index: index, provider: provider)
                        .environmentObject(model)
                    if model.config.activeProviderId == provider.id {
                        ProviderEditor(index: index, provider: provider)
                            .environmentObject(model)
                    }
                }
            }
            .padding(6)
        }
    }
}

private struct ProviderRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let provider: ProviderConfig

    var body: some View {
        HStack(alignment: .top) {
            Button {
                model.selectProvider(provider.id)
            } label: {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name).font(.headline)
                Text("\(provider.kind.rawValue) · \(provider.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var selected: Bool {
        model.config.activeProviderId == provider.id
    }
}

private struct ProviderEditor: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let provider: ProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Base URL", text: stringBinding(\.baseURL))
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Model", text: stringBinding(\.model))
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.loadModels(for: provider)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Text("Load available models from the provider"))
                .disabled(model.isLoadingModels)
                Button("Test") {
                    model.loadModels(for: provider)
                }
                .disabled(model.isLoadingModels)
                .help(Text("Check the connection and authentication with the provider"))
                if model.isLoadingModels {
                    ProgressView().controlSize(.small)
                }
            }

            if !model.availableModels.isEmpty {
                Picker("Modelli disponibili", selection: Binding(
                    get: { provider.model },
                    set: { model.selectModel($0) }
                )) {
                    ForEach(model.availableModels) { available in
                        Text(available.label).tag(available.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if !model.modelListStatus.isEmpty {
                Text(model.modelListStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Parametri di generazione") {
                VStack(alignment: .leading, spacing: 6) {
                    ParameterRow(label: "Temperature", placeholder: "0.2", hint: "0–2", text: doubleBinding(\.temperature))
                    ParameterRow(label: "Top P", placeholder: "1.0", hint: "0–1", text: doubleBinding(\.topP))
                    ParameterRow(label: "Top K", placeholder: "40", hint: "Anthropic", text: intBinding(\.topK))
                    ParameterRow(label: "Max tokens", placeholder: "4096", hint: "", text: intBinding(\.maxTokens))
                    ParameterRow(label: "Frequency penalty", placeholder: "0", hint: "OpenAI", text: doubleBinding(\.frequencyPenalty))
                    ParameterRow(label: "Presence penalty", placeholder: "0", hint: "OpenAI", text: doubleBinding(\.presencePenalty))
                    ParameterRow(label: "Seed", placeholder: "42", hint: "OpenAI", text: intBinding(\.seed))
                    ParameterRow(label: "Stop sequences", placeholder: "a, b", hint: L10n.t("comma-separated"), text: stopBinding)
                }
                .padding(.top, 6)
            }

            HStack {
                SecureField("API key (stored in secrets.json)", text: $model.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save key") {
                    model.saveAPIKey(for: provider)
                }
                .disabled(model.apiKeyDraft.isEmpty)
                Button("Delete key") {
                    model.deleteAPIKey(for: provider)
                }
            }

            Text(keyStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Save configuration") {
                model.saveConfig()
            }
        }
        .padding(.leading, 24)
        .onAppear {
            if model.availableModels.isEmpty {
                model.loadModels(for: provider)
            }
        }
    }

    private var keyStatus: String {
        if let key = model.runtime?.apiKey(for: provider), !key.isEmpty {
            return L10n.t("API key: configured")
        }
        return L10n.t("API key: not set (not required for local Ollama/LM Studio)")
    }

    private func setProvider(_ mutate: (inout ProviderConfig) -> Void) {
        var updated = model.config
        guard updated.providers.indices.contains(index) else { return }
        mutate(&updated.providers[index])
        model.config = updated
    }

    private func stringBinding(_ keyPath: WritableKeyPath<ProviderConfig, String>) -> Binding<String> {
        Binding(
            get: { model.config.providers[index][keyPath: keyPath] },
            set: { value in setProvider { $0[keyPath: keyPath] = value } }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<ProviderConfig, Double?>) -> Binding<String> {
        Binding(
            get: { Self.format(model.config.providers[index][keyPath: keyPath]) },
            set: { value in setProvider { $0[keyPath: keyPath] = Self.parseDouble(value) } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<ProviderConfig, Int?>) -> Binding<String> {
        Binding(
            get: {
                model.config.providers[index][keyPath: keyPath].map(String.init) ?? ""
            },
            set: { value in setProvider { $0[keyPath: keyPath] = Self.parseInt(value) } }
        )
    }

    private var stopBinding: Binding<String> {
        Binding(
            get: { model.config.providers[index].stopSequences?.joined(separator: ", ") ?? "" },
            set: { value in
                let items = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                setProvider { $0.stopSequences = items.isEmpty ? nil : items }
            }
        )
    }

    private static func parseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private static func parseInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }
}

private struct ParameterRow: View {
    let label: String
    let placeholder: String
    let hint: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 130, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            if !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpeechSection: View {
    @EnvironmentObject var model: AppModel
    @State private var voices: [SpeechVoice] = []

    var body: some View {
        GroupBox("Voce (text-to-speech)") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Abilita sintesi vocale", isOn: Binding(
                    get: { model.config.speechEnabled },
                    set: { model.setSpeechEnabled($0) }
                ))

                Toggle("Leggi automaticamente le risposte dell'AI", isOn: Binding(
                    get: { model.config.speechAutoSpeak },
                    set: { model.setSpeechAutoSpeak($0) }
                ))
                .disabled(!model.config.speechEnabled)

                Picker("Voce", selection: Binding(
                    get: { model.config.speechVoiceIdentifier ?? "" },
                    set: { model.setSpeechVoice($0.isEmpty ? nil : $0) }
                )) {
                    Text("Sistema (default)").tag("")
                    ForEach(voices) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }

                HStack {
                    Text("Velocità")
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { model.config.speechRate },
                        set: { model.setSpeechRate($0) }
                    ), in: 0.3...0.7)
                    Text(String(format: "%.2f", model.config.speechRate))
                        .monospacedDigit()
                        .frame(width: 36)
                }

                HStack {
                    Button("Prova voce") { model.testVoice() }
                    Button("Ferma") { model.stopSpeaking() }
                    Button("Aggiorna voci") { voices = SpeechService.availableVoices() }
                }

                Text("La sintesi vocale si può disattivare anche dalla casella “Voce” nell'header della chat. Per voci Enhanced/Premium: Impostazioni di Sistema → Accessibilità → Contenuto letto → Voci di sistema. Sphere usa AVSpeechSynthesizer, lo stesso motore di /usr/bin/say.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .onAppear {
                if voices.isEmpty {
                    voices = SpeechService.availableVoices()
                }
            }
        }
    }
}

private struct AppearanceSection: View {
    @EnvironmentObject var model: AppModel
    @State private var fonts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Font messaggi utente") {
                fontControls(
                    selected: Binding(
                        get: { model.config.userFontName ?? "" },
                        set: { model.setUserFontName($0.isEmpty ? nil : $0) }
                    ),
                    size: Binding(
                        get: { model.config.userFontSize },
                        set: { model.setUserFontSize($0) }
                    )
                )
            }

            GroupBox("Font messaggi AI") {
                fontControls(
                    selected: Binding(
                        get: { model.config.assistantFontName ?? "" },
                        set: { model.setAssistantFontName($0.isEmpty ? nil : $0) }
                    ),
                    size: Binding(
                        get: { model.config.assistantFontSize },
                        set: { model.setAssistantFontSize($0) }
                    )
                )
            }
        }
        .onAppear {
            if fonts.isEmpty {
                fonts = NSFontManager.shared.availableFonts.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
            }
        }
    }

    private func fontControls(selected: Binding<String>, size: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Font", selection: selected) {
                Text("Sistema (default)").tag("")
                ForEach(fonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            HStack {
                Text("Dimensione")
                    .frame(width: 80, alignment: .leading)
                Slider(value: size, in: 9...28, step: 1)
                Text("\(Int(size.wrappedValue)) pt")
                    .monospacedDigit()
                    .frame(width: 44)
            }

            Text("Anteprima: The quick brown fox — 12345")
                .font(makeFont(selected.wrappedValue, size.wrappedValue))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(6)
    }

    private func makeFont(_ name: String, _ size: Double) -> Font {
        name.isEmpty ? .system(size: size) : .custom(name, size: size)
    }
}

private struct DiagnosticsSection: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GroupBox("Diagnostica") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Log completo HTTP (include i body delle richieste)", isOn: Binding(
                    get: { model.config.debugHTTPLogging },
                    set: { model.setDebugHTTPLogging($0) }
                ))
                Text("API key e header sensibili sono sempre oscurati. Gli errori HTTP vengono registrati anche con il log completo disattivato.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Apri log HTTP") { model.openLog(named: "http.log") }
                    Button("Apri log Keychain") { model.openLog(named: "keychain.log") }
                    Button("Apri cartella Logs") { model.revealLogsFolder() }
                }
                HStack {
                    Button("Apri log accessi file") { openLog(.fileAccess) }
                    Button("Apri log rete") { openLog(.network) }
                }
                HStack {
                    Button("Apri log uso tool") { openLog(.tools) }
                    Button("Apri log clipboard") { openLog(.clipboard) }
                }
                HStack {
                    Button("Importa chiavi dal Keychain") { model.importKeysFromKeychain() }
                    Text("Le API key ora sono in secrets.json (0600); il Keychain serve solo per l'import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.diagnosticsStatus.isEmpty {
                    Text(model.diagnosticsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Per un 401/403: controlla nel log HTTP se l'header Authorization/x-api-key è presente e leggi il body di errore del provider. Nel log Keychain vedi se la chiave è stata trovata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func openLog(_ kind: LogKind) {
        model.activeLog = kind
        openWindow(id: "logs")
    }
}

private struct KnowledgeSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox("Knowledge base") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plugin interface defined. The current build ships an in-memory stub; a local RAG implementation arrives in Phase 2.")
                    .font(.callout)
                if let knowledge = model.runtime?.knowledge {
                    Text(L10n.format("Active provider: %@", knowledge.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

private struct StorageSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox("Storage") {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppPaths.applicationSupport.path)
                    .font(.callout)
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal data folder") { model.revealDataFolder() }
                    Button("Reveal plugins folder") { model.revealPluginsFolder() }
                }
                Text("Everything is per-user. No administrator rights are required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}
