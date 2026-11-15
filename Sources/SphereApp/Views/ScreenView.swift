import SwiftUI
import SphereCore
import SphereScreen

struct ScreenView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.requestScreenPermission()
                } label: {
                    Label("Request Screen Recording", systemImage: "lock.shield")
                }
                Button {
                    model.refreshWindows()
                } label: {
                    Label("Refresh windows", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text(model.screenStatus.isEmpty ? "Per-window consent is enforced by Sphere" : model.screenStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Windows")
                        .font(.headline)
                        .padding(8)
                    if model.windows.isEmpty {
                        Text("Press “Refresh windows”. The first call triggers the macOS Screen Recording prompt.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.windows) { window in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(window.title.isEmpty ? window.appName : window.title)
                                        .lineLimit(1)
                                    Text(window.appName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    model.allow(window)
                                } label: {
                                    Label("Allow", systemImage: "checkmark.shield")
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    model.captureWindow(window)
                                } label: {
                                    Label("Capture", systemImage: "camera")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(minWidth: 380)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Allowed windows")
                        .font(.headline)
                        .padding(8)
                    if model.screenGrants.isEmpty {
                        Text("No windows allowed yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.screenGrants) { grant in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(grant.windowTitle ?? grant.appName)
                                        .lineLimit(1)
                                    Text("\(grant.bundleId ?? L10n.t("unknown")) · \(L10n.t("captures:")) \(grant.captureCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    model.revoke(grant)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Divider()

                    if let image = model.capturePreview {
                        Text("Last capture")
                            .font(.headline)
                            .padding(8)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 280)
                            .padding(8)
                    }
                }
                .frame(minWidth: 320)
            }
        }
    }
}
