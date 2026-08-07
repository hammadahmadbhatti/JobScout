import SwiftUI
import JobScoutCore

@main
struct JobScoutApp: App {
    @StateObject private var state = AppState()

    init() {
        // When launched bare from `swift run` (not from the .app bundle),
        // promote the process to a regular app so the window fronts.
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
