import AppKit

/// AppKit is required here: SwiftUI has no launch hook that runs regardless of whether a window
/// opens, and a document app can start with nothing but the open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let defaultAppFlow = DefaultAppFlow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The tests run hosted in this app, and a modal alert would block them forever.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await defaultAppFlow.promptAtLaunchIfNeeded() }
    }

    /// The welcome window takes the place of the system's open panel, which only chooses files.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
}
