import SwiftUI
import SphereCore

/// Per-session audit of tool executions, kept out of the chat transcript.
struct ToolActivityView: View {
    let calls: [ToolCallRecord]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if calls.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Nessuna attività tool in questa sessione")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(calls) { call in
                            ToolCallCard(call: call)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("Attività tool", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
            Spacer()
            Text("\(calls.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct ToolCallCard: View {
    let call: ToolCallRecord
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(call.toolName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(call.startedAt, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(call.moduleId)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if expanded {
                section("Argomenti", text: call.argumentsJSON)
                if let result = call.resultJSON {
                    section(call.status == .failed ? "Errore" : "Risultato", text: result)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var statusIcon: String {
        switch call.status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .denied: return "lock.fill"
        }
    }

    private var statusColor: Color {
        switch call.status {
        case .pending, .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .denied: return .orange
        }
    }
}
