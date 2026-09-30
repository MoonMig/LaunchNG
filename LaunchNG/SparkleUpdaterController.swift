import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller. Only ever
/// touched from the real GUI launch path -- accessing `.shared` for the
/// first time is what starts Sparkle's own background check schedule, so
/// nothing in the CLI/TUI runtime modes may reference this type.
@MainActor
final class SparkleUpdaterController: NSObject, SPUStandardUserDriverDelegate {
    static let shared = SparkleUpdaterController()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // `userDriverDelegate` is a construction-time-only parameter (an
        // ivar, not a settable property), so `self` can only be passed here,
        // after super.init() has already produced a complete instance.
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// LaunchNG's own window normally floats above everything (it can even
    /// sit above the menu bar) so it stays reachable as a launcher -- which
    /// also means it renders in front of Sparkle's own alert/progress
    /// windows, which use a standard window level. Sparkle calls this right
    /// before showing any such window, specifically so the host app can get
    /// its own UI out of the way first.
    nonisolated func standardUserDriverWillShowModalAlert() {
        DispatchQueue.main.async {
            AppDelegate.shared?.hideWindow()
        }
    }
}
