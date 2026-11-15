import SwiftUI
import SphereCore

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            StatusItem(label: "TOK", value: tokenText, help: tokenHelp)
            StatusItem(icon: "dollarsign.circle", value: costText, help: "Costo stimato della sessione")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatusItem(
                    icon: "clock",
                    value: elapsedText(now: context.date),
                    help: "Tempo dall'inizio della sessione"
                )
            }
            StatusItem(icon: "folder", value: "\(model.accessSummary.total)", help: accessHelp)
            Spacer()
            if let provider = model.activeProviderLabel {
                Text(provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var tokenText: String {
        model.sessionUsage.totalTokens.formatted()
    }

    private var tokenHelp: String {
        "prompt \(model.sessionUsage.promptTokens.formatted()) · completion \(model.sessionUsage.completionTokens.formatted())"
    }

    private var costText: String {
        String(format: "$%.4f", model.sessionUsage.costUSD)
    }

    private var accessHelp: String {
        "read \(model.accessSummary.reads) · write \(model.accessSummary.writes) · negati \(model.accessSummary.denied)"
    }

    private func elapsedText(now: Date) -> String {
        guard let start = model.currentSession?.createdAt else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct StatusItem: View {
    var icon: String? = nil
    var label: String? = nil
    let value: String
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            if let label {
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
