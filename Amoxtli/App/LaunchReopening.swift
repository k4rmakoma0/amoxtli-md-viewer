import Foundation
import Observation

/// Decides once, before any window exists, whether the last file or folder takes the welcome
/// window's place, and hands it over once to whatever opens it.
@Observable
final class LaunchReopening {
    let plan: LaunchPlan
    /// Until the last item is back on screen, or something else opened instead. From then on, the
    /// app behaves as if it had started normally: clicking the Dock icon with no windows open
    /// shows the welcome window.
    private(set) var isReopening: Bool
    @ObservationIgnored private var isHandedOver = false

    init(recents: RecentItemsModel, preferences: LaunchPreferences = LaunchPreferences(), isEnabled: Bool) {
        guard isEnabled, preferences.reopensLastItem, let last = recents.list.last else {
            plan = .welcome
            isReopening = false
            return
        }
        let location = recents.locate(last)
        // It's gone, so the welcome window shouldn't offer it either.
        if location == .missing {
            recents.remove(last)
        }
        plan = LaunchPlan(last: last, location: location)
        isReopening = plan != .welcome
    }

    var presentsWelcome: Bool { !isReopening }

    /// A folder comes back in a folder window opened at launch, which then takes the folder.
    var presentsFolderWindow: Bool {
        guard isReopening, case .folder = plan else { return false }
        return true
    }

    /// The file to open, once. Reopening goes on until `finishReopeningFile`, so the welcome
    /// window stays away while the file loads.
    func takeFile() -> URL? {
        guard isReopening, !isHandedOver, case .file(let url) = plan else { return nil }
        isHandedOver = true
        return url
    }

    /// The folder for the window opened at launch, once.
    func takeFolder() -> Data? {
        guard isReopening, !isHandedOver, case .folder(let bookmark) = plan else { return nil }
        isHandedOver = true
        isReopening = false
        return bookmark
    }

    /// A launch that opens a file from Finder, or windows the system restores, isn't one to bring
    /// the last item back to.
    func finishLaunching(isDefault: Bool) {
        if !isDefault {
            isReopening = false
        }
    }

    /// Called once the file's window is up, or it won't be.
    func finishReopeningFile() {
        isReopening = false
    }
}
