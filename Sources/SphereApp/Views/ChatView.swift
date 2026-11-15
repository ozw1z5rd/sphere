import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MarkdownUI
import SphereCore

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var isDropTargeted = false
    @State private var editingSessionId: String?
    @State private var isAtBottom = true
    @State private var showToolCalls = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(
                    get: { model.currentSessionId },
                    set: { id in
                        guard let id, let session = model.sessions.first(where: { $0.id == id }) else { return }
                        model.select(session: session)
                    }
                )) {
                    ForEach(model.sessions) { session in
                        SessionRow(
                            session: session,
                            isEditing: editingSessionId == session.id,
                            isSelected: model.currentSessionId == session.id,
                            onSelect: {
                                if model.currentSessionId != session.id {
                                    model.select(session: session)
                                }
                            },
                            onBeginRename: { beginRename(session) },
                            onCommit: { title in
                                if title != session.title {
                                    model.renameSession(session, to: title)
                                }
                                editingSessionId = nil
                            },
                            onCancel: { editingSessionId = nil }
                        )
                        .tag(session.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.deleteSession(session)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Rinomina") { beginRename(session) }
                            Button("Elimina", role: .destructive) {
                                model.deleteSession(session)
                            }
                        }
                    }
                }
                Divider()
                Button {
                    model.newSession()
                } label: {
                    Label("New session", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 170, idealWidth: 210, maxWidth: 260)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Label(model.activeProviderLabel ?? L10n.t("Nessun provider"), systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if model.modelChoices.count > 1 {
                        Picker("", selection: Binding(
                            get: { model.activeProviderConfig?.model ?? "" },
                            set: { model.selectModel($0) }
                        )) {
                            ForEach(model.modelChoices, id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                    Button {
                        model.loadModelsForActive()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Load models from the provider"))
                    if model.isLoadingModels {
                        ProgressView().controlSize(.small)
                    }

                    Button {
                        showToolCalls.toggle()
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderless)
                    .help(showToolCalls ? Text("Hide tool activity") : Text("Show tool activity"))

                    Toggle("Voce", isOn: Binding(
                        get: { model.config.speechEnabled },
                        set: { model.setSpeechEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help(Text("Enable or disable text-to-speech"))

                    if model.config.speechEnabled {
                        if model.isSpeaking {
                            Button {
                                model.toggleSpeechPause()
                            } label: {
                                Image(systemName: model.isSpeechPaused ? "play.circle" : "pause.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(model.isSpeechPaused ? Text("Resume reading") : Text("Pause"))
                            Button {
                                model.stopSpeaking()
                            } label: {
                                Image(systemName: "speaker.slash")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Stop reading"))
                        } else if let lastAssistant = model.messages.last(where: {
                            $0.role == .assistant && !$0.content.isEmpty
                        }) {
                            Button {
                                model.speakMessage(lastAssistant)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Read the last response"))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if visibleMessages.isEmpty && model.streamingText.isEmpty {
                                ContentUnavailableViewCompat(
                                    title: "Start a conversation",
                                    message: "Configure a provider in Settings, then ask Sphere anything."
                                )
                            }
                            ForEach(visibleMessages) { message in
                                MessageRow(
                                    message: message,
                                    onSpeak: message.role == .assistant
                                        ? { model.speakMessage(message) }
                                        : nil
                                )
                                .id(message.id)
                            }
                            if !model.streamingText.isEmpty {
                                MessageRow(
                                    message: ChatMessage(
                                        sessionId: model.currentSessionId ?? "",
                                        role: .assistant,
                                        content: model.streamingText
                                    )
                                )
                                .id("streaming")
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ScrollBottomObserver(isAtBottom: $isAtBottom))
                    }
                    .onChange(of: model.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.streamingText) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.currentSessionId) { _ in
                        isAtBottom = true
                    }
                }

                Divider()

                if !model.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.attachments) { attachment in
                                AttachmentChip(attachment: attachment) {
                                    model.removeAttachment(attachment)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextEditor(text: $model.input)
                        .font(.body)
                        .frame(minHeight: 54, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                            handleDrop(providers)
                        }
                        .onSubmit { sendMessage() }

                    VStack(spacing: 6) {
                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(
                            model.isBusy
                                || (model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && model.attachments.isEmpty)
                        )

                        Button {
                            model.pickAttachments()
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .help(Text("Attach files"))

                        if model.isBusy {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .padding(10)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }

            if showToolCalls {
                ToolActivityView(calls: model.toolCalls)
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 520)
            }
        }
    }

    private var visibleMessages: [ChatMessage] {
        model.messages.filter { message in
            message.role != .tool && (message.role != .assistant || !message.content.isEmpty)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    model.addAttachments(urls: [url])
                }
            }
        }
        return true
    }

    private func beginRename(_ session: Session) {
        editingSessionId = session.id
    }

    private func sendMessage() {
        isAtBottom = true
        model.send()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard isAtBottom else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("streaming", anchor: .bottom)
            if let last = visibleMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

struct MessageRow: View {
    @EnvironmentObject var model: AppModel
    let message: ChatMessage
    var onSpeak: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                if let onSpeak {
                    Button(action: onSpeak) {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Read this message"))
                }
            }
            if !message.content.isEmpty {
                content
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            AttachmentChip(attachment: attachment)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .assistant {
            Markdown(message.content)
                .markdownTheme(.gitHub)
                .markdownImageProvider(.asset)
                .markdownTextStyle {
                    if let name = model.config.assistantFontName, !name.isEmpty {
                        FontFamily(.custom(name))
                    } else {
                        FontFamily(.system())
                    }
                    FontSize(CGFloat(model.config.assistantFontSize))
                }
        } else {
            Text(message.content)
                .font(model.messageFont(for: message.role))
        }
    }

    private var label: LocalizedStringKey {
        switch message.role {
        case .system: return "system"
        case .user: return "you"
        case .assistant: return "sphere"
        case .tool: return "tool · \(message.name ?? "")"
        }
    }

    private var color: Color {
        switch message.role {
        case .system: return .secondary
        case .user: return .accentColor
        case .assistant: return .green
        case .tool: return .orange
        }
    }

    private var background: Color {
        switch message.role {
        case .user: return Color.accentColor.opacity(0.12)
        case .assistant: return Color.green.opacity(0.08)
        case .tool: return Color.orange.opacity(0.10)
        case .system: return Color.secondary.opacity(0.08)
        }
    }
}

struct ContentUnavailableViewCompat: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct SessionRow: View {
    let session: Session
    let isEditing: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onBeginRename: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EditableTitleField(
                text: session.title,
                isEditing: isEditing,
                isSelected: isSelected,
                onSelect: onSelect,
                onBeginEdit: onBeginRename,
                onCommit: onCommit,
                onCancel: onCancel
            )

            Text(session.updatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct AttachmentChip: View {
    let attachment: ChatAttachment
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(attachment.type)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help(attachment.path)
    }

    private var icon: String {
        if attachment.isImage { return "photo" }
        let type = attachment.type.lowercased()
        if type.contains("folder") { return "folder" }
        if type.contains("pdf") { return "doc.richtext" }
        if type.contains("code") || type.contains("source") { return "chevron.left.forwardslash.chevron.right" }
        if type.contains("text") { return "doc.text" }
        if type.contains("movie") || type.contains("video") { return "film" }
        if type.contains("audio") { return "waveform" }
        return "doc"
    }

    private var color: Color {
        if attachment.isImage { return .purple }
        let type = attachment.type.lowercased()
        if type.contains("pdf") { return .red }
        if type.contains("folder") { return .orange }
        if type.contains("code") || type.contains("source") { return .blue }
        return .accentColor
    }
}
