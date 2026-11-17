import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        } else if let execPath = Bundle.main.executablePath {
            let resPath = URL(fileURLWithPath: execPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/AppIcon.icns")
            if let image = NSImage(contentsOf: resPath) {
                NSApp.applicationIconImage = image
            }
        }
    }
}

@main
struct MacSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
