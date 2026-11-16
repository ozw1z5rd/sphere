import SwiftUI
import SphereCore

struct NetworkView: View {
    @EnvironmentObject var model: AppModel
    @State private var newValue = ""
    @State private var newKind: NetworkRuleKind = .url

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Internet", systemImage: "globe")
                    .font(.headline)
                Spacer()
                Text(L10n.format(
                    "requests %d · allowed %d · blocked %d",
                    model.networkSummary.total,
                    model.networkSummary.allowed,
                    model.networkSummary.blocked
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    model.refreshNetwork()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(10)

            Divider()

            HStack(spacing: 8) {
                TextField("URL, domain or IP/CIDR to block", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newKind) {
                    ForEach(NetworkRuleKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Button("Add") {
                    model.addNetworkRule(value: newValue, kind: newKind)
                    newValue = ""
                }
                .disabled(newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)

            if !model.networkStatus.isEmpty {
                Text(model.networkStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Blocked URLs / domains / IPs")
                        .font(.headline)
                        .padding(8)
                    if model.networkRules.isEmpty {
                        Text("No rules. Internet requests are allowed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(model.networkRules) { rule in
                                NetworkRuleRow(rule: rule)
                                    .environmentObject(model)
                            }
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 460)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent requests")
                        .font(.headline)
                        .padding(8)
                    SystemLogView(lines: model.networkLogLines, emptyMessage: "No requests recorded.")
                }
                .frame(minWidth: 480, idealWidth: 680, maxWidth: .infinity)
                .layoutPriority(1)
            }
        }
        .onAppear {
            model.refreshNetwork()
        }
    }
}


private struct NetworkRuleRow: View {
    @EnvironmentObject var model: AppModel
    let rule: NetworkRule

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.kind.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                    Text(rule.value)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Text(L10n.format("blocks: %d", rule.blockedCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Attiva", isOn: Binding(
                get: { rule.enabled },
                set: { model.setNetworkRule(rule, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            Button(role: .destructive) {
                model.removeNetworkRule(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct NetworkEventRow: View {
    let event: NetworkEvent

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: event.allowed ? "checkmark.circle" : "hand.raised.fill")
                .foregroundStyle(event.allowed ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.url)
                    .font(.caption)
                    .lineLimit(2)
                Text("\(event.host) · \(event.timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
