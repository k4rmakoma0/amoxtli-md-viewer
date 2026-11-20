import AppKit

/// AppKit is required here: SwiftUI has no launch hook that runs regardless of whether a window
/// opens, and a document app can start with nothing but the open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let defaultAppFlow = DefaultAppFlow()
    let recents: RecentItemsModel
    let launch: LaunchReopening

    override init() {
        let recents = RecentItemsModel()
        self.recents = recents
        // The tests run hosted in this app, and must not open the person's last file.
        launch = LaunchReopening(recents: recents, isEnabled: !Self.isRunningTests)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        reopenLastFile()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        launch.finishLaunching(isDefault: isDefaultLaunch)
        // A modal alert would block the tests forever.
        guard !Self.isRunningTests else { return }
        Task { await defaultAppFlow.promptAtLaunchIfNeeded() }
    }

    /// Files edited in another app while Amoxtli was in the background show their new version.
    func applicationDidBecomeActive(_ notification: Notification) {
        ExternalDocumentChanges().reloadChanged(NSDocumentController.shared.documents)
    }

    /// The welcome window takes the place of the system's open panel, which only chooses files.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// SwiftUI picks the windows to show at launch before `applicationDidFinishLaunching`, and
    /// shows the open panel if none is up. A SwiftUI app isn't asked
    /// `applicationShouldOpenUntitledFile` then, so the file opens here, early enough to take the
    /// welcome window's place. If the launch opens a file from Finder too, both stay open.
    private func reopenLastFile() {
        guard let file = launch.takeFile() else { return }
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { [launch] _, _, error in
            if let error {
                NSDocumentController.shared.presentError(error)
            }
            launch.finishReopeningFile()
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
