import AppKit
import Foundation
import Sparkle

// TEMPORARY: file-based logging to verify Sparkle's delegate hooks actually
// fire and in what order -- NSLog isn't reaching the unified log for this
// process in testing. Remove once the update-flow investigation is done.
private func sparkleDebugLog(_ message: String) {
    let line = "\(Date().timeIntervalSince1970) \(message)\n"
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LaunchNG/sparkle-debug.log")
    DispatchQueue.global(qos: .utility).async {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}

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
    /// standard window level. The fix is *not* to hide or close anything --
    /// the user explicitly does not want the main window disappearing --
    /// just to temporarily drop its window level so Sparkle's window can
    /// render above it, restoring the level once Sparkle is done. Called
    /// synchronously, inline (never dispatched async -- deferring this to a
    /// later main-queue turn was an earlier bug: by the time a queued block
    /// ran, Sparkle had already shown and finished presenting its window on
    /// the same turn).
    @MainActor
    private func stepAside(reason: String) {
        guard let window = AppDelegate.shared?.launchpadWindow else { return }
        sparkleDebugLog("stepAside(\(reason)): windowLevel=\(window.level.rawValue) -> normal")
        window.level = .normal
    }

    @MainActor
    private func stepBack(reason: String) {
        guard let window = AppDelegate.shared?.launchpadWindow else { return }
        sparkleDebugLog("stepBack(\(reason)): windowLevel=\(window.level.rawValue) -> floating")
        window.level = .floating
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Only actually fires for the plain NSAlert-based "no update found" /
    /// error alerts (SPUStandardUserDriver's -showAlert:secondaryAction:) --
    /// NOT for the rich "update available" window, which is a separate
    /// SUUpdateAlert window shown via showUpdateFoundWithAppcastItem: and
    /// goes through standardUserDriverWillHandleShowingUpdate below instead.
    /// Confirmed by reading Sparkle's own SPUStandardUserDriver.m after this
    /// hook alone produced no diagnostic output across several real update
    /// checks. Kept for the alert case it does cover.
    nonisolated func standardUserDriverWillShowModalAlert() {
        sparkleDebugLog("standardUserDriverWillShowModalAlert fired, isMainThread=\(Thread.isMainThread)")
        MainActor.assumeIsolated {
            stepAside(reason: "willShowModalAlert")
        }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        sparkleDebugLog("standardUserDriverDidShowModalAlert fired")
        MainActor.assumeIsolated {
            stepBack(reason: "didShowModalAlert")
        }
    }

    /// The actual hook for the "update available" window: called right
    /// before SUUpdateAlert is shown for a user-initiated check (per
    /// SPUStandardUserDriver.m's showUpdateFoundWithAppcastItem:). Not
    /// called when bringing an already-shown alert back into focus.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        sparkleDebugLog("standardUserDriverWillHandleShowingUpdate fired, handleShowingUpdate=\(handleShowingUpdate) userInitiated=\(state.userInitiated)")
        MainActor.assumeIsolated {
            stepAside(reason: "willHandleShowingUpdate")
        }
    }

    /// Called once Sparkle's update session ends (dismissed, skipped,
    /// errored, or installed) -- the matching restore point for stepAside(),
    /// regardless of which of the hooks above triggered it.
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        sparkleDebugLog("standardUserDriverWillFinishUpdateSession fired")
        MainActor.assumeIsolated {
            stepBack(reason: "willFinishUpdateSession")
        }
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle's actual install-and-relaunch is driven by a separate XPC
    /// installer tool, not by calling NSApp.terminate() on this process in a
    /// way that reliably round-trips through our own applicationShouldTerminate
    /// override -- so closing an open Settings sheet there (as attempted
    /// previously) isn't guaranteed to run before Sparkle proceeds. This is
    /// the hook Sparkle documents specifically for "let the app clean up
    /// before I terminate/relaunch it": returning true here and calling
    /// installHandler only once Settings has actually closed.
    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        sparkleDebugLog("shouldPostponeRelaunchForUpdate fired, requesting postpone")
        DispatchQueue.main.async {
            guard let appStore = AppDelegate.shared?.appStore else {
                sparkleDebugLog("no appStore found, calling installHandler immediately")
                installHandler()
                return
            }
            sparkleDebugLog("isSetting=\(appStore.isSetting)")
            guard appStore.isSetting else {
                sparkleDebugLog("settings not open, calling installHandler immediately")
                installHandler()
                return
            }
            appStore.isSetting = false
            sparkleDebugLog("set isSetting=false, waiting 0.3s before installHandler")
            // Let the sheet's own dismissal animation actually finish before
            // handing control back to Sparkle's relaunch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                sparkleDebugLog("calling installHandler now")
                installHandler()
            }
        }
        return true
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        sparkleDebugLog("updaterWillRelaunchApplication fired")
    }
}
