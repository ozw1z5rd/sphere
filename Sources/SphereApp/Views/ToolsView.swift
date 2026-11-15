import SwiftUI
import SphereCore

/// Main-window tab that lets the user enable or disable each tool exposed to
/// the model. Every tool is enabled by default.
struct ToolsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Task { await model.refreshTools() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                Text(L10n.format("%d of %d tools enabled", enabledCount, model.tools.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button("Enable all") { model.setAllToolsEnabled(true) }
                Button("Disable all") { model.setAllToolsEnabled(false) }
            }
            .padding(10)

            Divider()

            Text("All tools are enabled by default. Disable any tool you do not want the AI to use.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            HSplitView {
                Group {
                    if model.tools.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No tools available.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.tools) { tool in
                                        ToolAccessRow(tool: tool)
                                            .environmentObject(model)
                                    }
                                } header: {
                                    Text(displayName(for: group.module))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 420, idealWidth: 520)

                clipboardPanel
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity)
            }
        }
        .onAppear {
            Task { await model.refreshTools() }
        }
    }

    private var clipboardPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Label("Clipboard activity", systemImage: "doc.on.clipboard")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(model.clipboardEvents.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            SystemLogView(
                lines: model.clipboardEvents.map { event in
                    LogLine(
                        id: event.id,
                        timestamp: event.timestamp,
                        status: event.operation.uppercased(),
                        statusColor: event.allowed ? .green : .red,
                        message: event.detail ?? "-"
                    )
                },
                emptyMessage: "No clipboard activity yet."
            )
        }
        .background(.background)
    }

    private var enabledCount: Int {
        model.tools.filter { model.isToolEnabled($0.name) }.count
    }

    private var groups: [ToolGroup] {
        Dictionary(grouping: model.tools, by: \.moduleId)
            .map { module, tools in
                ToolGroup(
                    module: module,
                    tools: tools.sorted { $0.originalName < $1.originalName }
                )
            }
            .sorted { $0.module < $1.module }
    }

    private func displayName(for module: String) -> String {
        switch module {
        case "sphere.filesystem": return "Filesystem"
        case "sphere.web": return "Web"
        case "sphere.git": return "Git"
        case "sphere.system": return "System"
        case "sphere.exec": return "Exec"
        default: return module
        }
    }
}

private struct ToolGroup: Identifiable {
    let module: String
    let tools: [ToolDefinition]
    var id: String { module }
}

private struct ToolAccessRow: View {
    @EnvironmentObject var model: AppModel
    let tool: ToolDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.originalName)
                    .font(.callout.weight(.medium))
                Text(tool.name)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if tool.moduleId == "sphere.exec" {
                    Text("Enable sandboxed exec in Settings → Tools to use this tool.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { model.isToolEnabled(tool.name) },
                set: { model.setToolEnabled(tool.name, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 3)
    }
}
