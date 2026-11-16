import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let startupError = model.startupError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Sphere could not start")
                        .font(.headline)
                    Text(startupError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    TabView {
                        ChatView()
                            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                        ModulesView()
                            .tabItem { Label("Modules", systemImage: "shippingbox") }
                        FileAccessView()
                            .tabItem { Label("File Access", systemImage: "folder.badge.gearshape") }
                        ScreenView()
                            .tabItem { Label("Screen", systemImage: "rectangle.on.rectangle") }
                        NetworkView()
                            .tabItem { Label("Network", systemImage: "globe") }
                        ToolsView()
                            .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                        ClipboardView()
                            .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                    }
                    .padding(.top, 4)

                    Divider()
                    StatusBarView()
                }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
