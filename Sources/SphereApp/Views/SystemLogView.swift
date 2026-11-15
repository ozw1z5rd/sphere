import SwiftUI

struct LogLine: Identifiable {
    let id: String
    let timestamp: Date
    let status: String
    let statusColor: Color
    let message: String
}

/// Console-style log view: timestamp first, then status, then details.
/// Rows use a monospaced font and alternating background like the macOS log.
struct SystemLogView: View {
    let lines: [LogLine]
    let emptyMessage: LocalizedStringKey

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let timeWidth: CGFloat = 178
    private let statusWidth: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            header

            if lines.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            row(line, striped: index.isMultiple(of: 2) == false)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("TIME")
                .frame(width: timeWidth, alignment: .leading)
            Text("STATUS")
                .frame(width: statusWidth, alignment: .leading)
            Text("DETAILS")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08))
    }

    private func row(_ line: LogLine, striped: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timestampFormatter.string(from: line.timestamp))
                .frame(width: timeWidth, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(line.status)
                .frame(width: statusWidth, alignment: .leading)
                .foregroundStyle(line.statusColor)
                .fontWeight(.bold)

            Text(line.message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(striped ? Color.secondary.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .frame(height: 0.5)
        }
    }
}
