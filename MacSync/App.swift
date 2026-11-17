import SwiftUI

@main
struct MacSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 840, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Quick Look") {
                    // Spacebar handled in ContentView
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}
