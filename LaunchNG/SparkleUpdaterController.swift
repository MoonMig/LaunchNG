import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller. Only ever
/// touched from the real GUI launch path -- accessing `.shared` for the
/// first time is what starts Sparkle's own background check schedule, so
/// nothing in the CLI/TUI runtime modes may reference this type.
@MainActor
final class SparkleUpdaterController {
    static let shared = SparkleUpdaterController()

    let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
