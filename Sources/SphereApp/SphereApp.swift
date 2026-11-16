import SwiftUI

@main
struct SphereDesktopApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Sphere") {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, model.appLocale)
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
                .environment(\.locale, model.appLocale)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 470, height: 640)

        Window("Logs", id: "logs") {
            LogsView()
                .environmentObject(model)
                .environment(\.locale, model.appLocale)
        }
        .defaultSize(width: 1000, height: 560)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, model.appLocale)
                .frame(width: 700, height: 560)
        }
    }
}
