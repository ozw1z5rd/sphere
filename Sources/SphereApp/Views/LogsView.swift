import SwiftUI

/// Dedicated log window: last 200 rows of a selected database-backed log.
struct LogsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $model.activeLog) {
                    ForEach(LogKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                Text("\(model.logLines(for: model.activeLog).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    model.reloadLogs()
                    model.refreshActivityCounts()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(10)

            Divider()

            SystemLogView(
                lines: model.logLines(for: model.activeLog),
                emptyMessage: emptyMessage
            )
        }
        .frame(minWidth: 900, minHeight: 420)
        .onAppear {
            model.reloadLogs()
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch model.activeLog {
        case .fileAccess: return "No access events yet."
        case .network: return "No requests recorded."
        case .tools: return "No tool activity yet."
        case .clipboard: return "No clipboard activity yet."
        }
    }
}
