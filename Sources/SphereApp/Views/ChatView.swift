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
                            if visibleMessages.isEmpty && !model.isBusy {
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
                            if model.isBusy {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Generating…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .id("generating")
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ScrollBottomObserver(isAtBottom: $isAtBottom))
                    }
                    .onChange(of: model.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.isBusy) { _ in
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
            if model.isBusy {
                proxy.scrollTo("generating", anchor: .bottom)
            }
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

    @State private var isCollapsed = false
    @State private var isSelectable = false
    @State private var isCopied = false
    @State private var copyGeneration = 0

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
                if !message.content.isEmpty {
                    Button {
                        copyPlainText()
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(isCopied ? Text("Copied") : Text("Copy text"))
                }
                if message.role == .assistant, !message.content.isEmpty {
                    Spacer(minLength: 6)
                    Button {
                        isSelectable.toggle()
                    } label: {
                        Image(systemName: isSelectable ? "textformat" : "text.cursor")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(isSelectable ? Text("Show Markdown") : Text("Selectable text"))
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(isCollapsed ? Text("Expand response") : Text("Collapse response"))
                }
            }
            if !message.content.isEmpty {
                if isCollapsed {
                    Text(plainContent)
                        .font(model.messageFont(for: message.role))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if message.role == .assistant, isSelectable {
                    Text(plainContent)
                        .font(model.messageFont(for: message.role))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(background)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    content
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(background)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            if !message.attachments.isEmpty && !isCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            AttachmentChip(attachment: attachment)
                        }
                    }
                }
            }
        }
        .contextMenu {
            if !message.content.isEmpty {
                Button("Copy text") { copyPlainText() }
                if message.role == .assistant {
                    Button("Copy Markdown") { copyMarkdown() }
                }
            }
            if message.role == .assistant, !message.content.isEmpty {
                Button(isSelectable ? "Show Markdown" : "Selectable text") {
                    isSelectable.toggle()
                }
                Button(isCollapsed ? "Expand response" : "Collapse response") {
                    isCollapsed.toggle()
                }
            }
            if let onSpeak {
                Divider()
                Button("Read this message", action: onSpeak)
            }
        }
    }

    private var plainContent: String {
        message.role == .assistant
            ? MarkdownPlainText.plainText(from: message.content)
            : message.content
    }

    private func copyPlainText() {
        copyToPasteboard(plainContent)
    }

    private func copyMarkdown() {
        copyToPasteboard(message.content)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        isCopied = true
        copyGeneration += 1
        let generation = copyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copyGeneration == generation {
                isCopied = false
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

            HStack(spacing: 6) {
                Text("#\(session.number)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(session.updatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
