import SwiftUI
import AppKit

@main
struct MacDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download...") {
                    // Handled inside window toolbar
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start local extension HTTP bridge on port 45678
        LocalApiServer.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalApiServer.shared.stop()
        Task { @MainActor in
            DownloadManager.shared.pauseAll()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
