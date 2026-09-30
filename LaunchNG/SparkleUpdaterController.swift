import AppKit
import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller. Only ever
/// touched from the real GUI launch path -- accessing `.shared` for the
/// first time is what starts Sparkle's own background check schedule, so
/// nothing in the CLI/TUI runtime modes may reference this type.
@MainActor
final class SparkleUpdaterController: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = SparkleUpdaterController()

    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // `userDriverDelegate`/`updaterDelegate` are construction-time-only
        // parameters (ivars, not settable properties), so `self` can only be
        // passed here, after super.init() has already produced a complete
        // instance.
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - Shared window-leveling

    /// LaunchNG's own window normally floats above everything (it can even
    /// sit above the menu bar) so it stays reachable as a launcher -- which
    /// also means it renders in front of Sparkle's own windows, which use a
    /// standard window level. Rather than hiding or closing anything, this
    /// just temporarily drops the window level so Sparkle's window can
    /// render above it, restoring the level once Sparkle is done. Called
    /// synchronously, inline (never dispatched async -- Sparkle shows its
    /// window on the same turn, so a queued block would run too late).
    @MainActor
    private func stepAside() {
        AppDelegate.shared?.launchpadWindow?.level = .normal
    }

    @MainActor
    private func stepBack() {
        AppDelegate.shared?.launchpadWindow?.level = .floating
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Fires for the plain NSAlert-based "no update found" / error alerts.
    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { stepAside() }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        MainActor.assumeIsolated { stepBack() }
    }

    /// The hook for the rich "update available" window (a separate
    /// SUUpdateAlert, shown via a different code path than the plain alert
    /// above). Not called when bringing an already-shown alert back into
    /// focus.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { stepAside() }
    }

    /// Called once Sparkle's update session ends (dismissed, skipped,
    /// errored, or installed) -- the matching restore point for stepAside(),
    /// regardless of which hook above triggered it.
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { stepBack() }
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle's actual install-and-relaunch is driven by a separate XPC
    /// installer tool, not by calling NSApp.terminate() on this process in a
    /// way that reliably round-trips through our own applicationShouldTerminate
    /// override -- so closing an open Settings sheet there isn't guaranteed
    /// to run before Sparkle proceeds. This is the hook Sparkle documents
    /// specifically for "let the app clean up before I terminate/relaunch
    /// it": returning true here and calling installHandler only once
    /// Settings has actually closed.
    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        DispatchQueue.main.async {
            guard let appStore = AppDelegate.shared?.appStore, appStore.isSetting else {
                installHandler()
                return
            }
            appStore.isSetting = false
            // Let the sheet's own dismissal animation actually finish before
            // handing control back to Sparkle's relaunch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                installHandler()
            }
        }
        return true
    }
}
