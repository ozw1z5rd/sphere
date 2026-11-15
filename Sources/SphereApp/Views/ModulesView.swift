import SwiftUI
import UniformTypeIdentifiers
import SphereCore

struct ModulesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.installModuleFile()
                } label: {
                    Label("Install module…", systemImage: "plus")
                }
                Button {
                    model.revealPluginsFolder()
                } label: {
                    Label("Reveal plugins folder", systemImage: "folder")
                }
                Button {
                    model.refreshAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text("Drag a .spheremodule file here to install")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            if model.modules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                    Text("No modules installed")
                        .font(.headline)
                    Text("Download a .spheremodule file and drag it here. Modules are self-describing: they contain their own module.json.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.modules) { module in
                        ModuleRow(module: module)
                            .environmentObject(model)
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    model.installModule(url: url)
                }
            }
        }
        return true
    }
}

private struct ModuleRow: View {
    @EnvironmentObject var model: AppModel
    let module: InstalledModule

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(module.manifest.name).font(.headline)
                    Text("v\(module.manifest.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(module.manifest.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let description = module.manifest.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let filesystem = module.manifest.permissions.filesystem {
                    Label(
                        "filesystem \(filesystem.mode.rawValue) · \(filesystem.paths.count) path(s)",
                        systemImage: "folder"
                    )
                    .font(.caption)
                }
                if module.manifest.permissions.screen != nil {
                    Label("screen access", systemImage: "rectangle.on.rectangle")
                        .font(.caption)
                }
                if module.manifest.permissions.network {
                    Label("network", systemImage: "network")
                        .font(.caption)
                }
                if module.manifest.permissions.process {
                    Label("process", systemImage: "terminal")
                        .font(.caption)
                }
            }

            Spacer()

            Toggle("Enabled", isOn: Binding(
                get: { module.enabled },
                set: { model.setModule(module, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch module.manifest.kind {
        case .mcp: return "shippingbox"
        case .knowledge: return "books.vertical"
        case .tool: return "wrench.and.screwdriver"
        }
    }
}
