import SwiftUI

@main
struct SphereDesktopApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Sphere") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Sphere") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .newItem) {
                Button("New Session") { model.newSession() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Install Module…") { model.installModuleFile() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Window("About Sphere", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 470, height: 620)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 700, height: 560)
        }
    }
}
