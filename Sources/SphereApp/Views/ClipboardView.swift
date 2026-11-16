import SwiftUI
import AppKit
import SphereCore

/// Clipboard access controls and the global clipboard activity log.
struct ClipboardView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("clipboard.preview.enabled") private var showPreview = false
    @State private var previewText = ""
    @State private var previewTypes: [String] = []

    private var readToolName: String {
        ToolDefinition.namespaced(moduleId: "sphere.system", toolName: "clipboard_read")
    }

    private var writeToolName: String {
        ToolDefinition.namespaced(moduleId: "sphere.system", toolName: "clipboard_write")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.reloadClipboardEvents()
                    if showPreview { refreshPreview() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                Text(L10n.format("%d clipboard accesses in this session", model.clipboardAccessCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(10)

            Divider()

            HSplitView {
                controls
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                log
                    .frame(minWidth: 480, idealWidth: 680, maxWidth: .infinity)
                    .layoutPriority(1)
            }
        }
        .onAppear {
            model.reloadClipboardEvents()
            if showPreview { refreshPreview() }
        }
        .onChange(of: showPreview) { enabled in
            if enabled {
                refreshPreview()
            } else {
                previewText = ""
                previewTypes = []
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Clipboard control") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Allow AI to read clipboard", isOn: Binding(
                        get: { model.isToolEnabled(readToolName) },
                        set: { model.setToolEnabled(readToolName, enabled: $0) }
                    ))
                    Toggle("Allow AI to write clipboard", isOn: Binding(
                        get: { model.isToolEnabled(writeToolName) },
                        set: { model.setToolEnabled(writeToolName, enabled: $0) }
                    ))

                    Text("Clipboard access is system-wide. These switches control the built-in clipboard tools.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text(L10n.format(
                        "Session reads: %d · writes: %d",
                        model.clipboardReadCount,
                        model.clipboardWriteCount
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Clipboard preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show clipboard preview", isOn: $showPreview)
                    Text("The preview is local and is not logged as an AI access.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if showPreview {
                        HStack {
                            Text("Preview")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Refresh preview") { refreshPreview() }
                        }
                        if previewText.isEmpty {
                            Text("No text on the clipboard.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                Text(previewText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 140)
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if !previewTypes.isEmpty {
                            Text(previewTypes.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Spacer()
        }
        .padding(12)
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Clipboard activity")
                    .font(.headline)
                Spacer()
                Text("\(model.clipboardEvents.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            SystemLogView(lines: model.clipboardLogLines, emptyMessage: "No clipboard activity yet.")
        }
    }

    private func refreshPreview() {
        let pasteboard = NSPasteboard.general
        previewTypes = (pasteboard.types ?? []).map(\.rawValue)
        guard let text = pasteboard.string(forType: .string) else {
            previewText = ""
            return
        }
        let limit = 2_000
        previewText = text.count > limit ? String(text.prefix(limit)) + "\n… truncated" : text
    }
}
