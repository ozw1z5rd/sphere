import SwiftUI
import SphereCore

struct FileAccessView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.addFolderGrant(mode: .readWrite)
                } label: {
                    Label("Grant folder (RW)…", systemImage: "folder.badge.plus")
                }
                Button {
                    model.addFolderGrant(mode: .readOnly)
                } label: {
                    Label("Grant folder (RO)…", systemImage: "folder")
                }
                Button {
                    model.refreshAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text("All file access is mediated by the built-in filesystem broker")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Granted paths")
                        .font(.headline)
                        .padding(8)
                    if model.grants.isEmpty {
                        Text("No paths granted yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(model.grants) { grant in
                                GrantRow(grant: grant)
                                    .environmentObject(model)
                            }
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 460)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Access log")
                        .font(.headline)
                        .padding(8)
                    SystemLogView(lines: accessLines, emptyMessage: "No access events yet.")
                }
                .frame(minWidth: 480, idealWidth: 680, maxWidth: .infinity)
                .layoutPriority(1)
            }
        }
    }
}

private extension FileAccessView {
    var accessLines: [LogLine] {
        model.accessEvents.map { event in
            var detail = "\(event.operation.rawValue.uppercased()) \(event.path) · module=\(event.moduleId)"
            if let extra = event.detail, !extra.isEmpty {
                detail += " · \(extra)"
            }
            return LogLine(
                id: event.id,
                timestamp: event.timestamp,
                status: event.allowed ? "ALLOW" : "DENY",
                statusColor: event.allowed ? .green : .red,
                message: detail
            )
        }
    }
}

private struct GrantRow: View {
    @EnvironmentObject var model: AppModel
    let grant: PathGrant

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(grant.path)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(L10n.format("read %d · write %d · %@", grant.readCount, grant.writeCount, L10n.t(grant.scope.rawValue)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { grant.mode },
                set: { model.setGrantMode(grant, mode: $0) }
            )) {
                Text("RO").tag(FileAccessMode.readOnly)
                Text("RW").tag(FileAccessMode.readWrite)
            }
            .labelsHidden()
            .frame(width: 70)

            Button {
                model.revealGrant(grant)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                model.removeGrant(grant)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}
