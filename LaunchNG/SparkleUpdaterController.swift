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

    // MARK: - SPUStandardUserDriverDelegate

    /// LaunchNG's own window normally floats above everything (it can even
    /// sit above the menu bar) so it stays reachable as a launcher -- which
    /// also means it renders in front of Sparkle's own alert/progress
    /// windows, which use a standard window level. Sparkle calls this right
    /// before showing any such window, specifically so the host app can get
    /// its own UI out of the way first.
    nonisolated func standardUserDriverWillShowModalAlert() {
        sparkleDebugLog("standardUserDriverWillShowModalAlert fired, isMainThread=\(Thread.isMainThread)")
        // Dispatching async here (even to the main queue) was the bug: by
        // the time that queued block actually ran, Sparkle had already
        // presented its window on this same turn -- confirmed in the debug
        // log, where our "before hideWindow()" line printed *after*
        // standardUserDriverDidShowModalAlert had already fired. Sparkle
        // calls this synchronously on the main thread specifically so the
        // hide can happen before it proceeds, so do it inline, right here.
        MainActor.assumeIsolated {
            let windowVisible = AppDelegate.shared?.launchpadWindow?.isVisible ?? false
            let windowLevel = AppDelegate.shared?.launchpadWindow?.level.rawValue ?? -1
            let isSetting = AppDelegate.shared?.appStore.isSetting ?? false
            sparkleDebugLog("before hideWindow(): windowVisible=\(windowVisible) windowLevel=\(windowLevel) isSetting=\(isSetting)")
            // Settings is a SwiftUI sheet attached to the main window.
            // hideWindow() only clears isSetting once its own fade-out
            // animation finishes, which left the sheet's separate child
            // window still on top of Sparkle's alert in the meantime.
            // Close it immediately instead of waiting for that animation.
            AppDelegate.shared?.appStore.isSetting = false
            AppDelegate.shared?.hideWindow()
        }
    }

    nonisolated func standardUserDriverDidShowModalAlert() {
        sparkleDebugLog("standardUserDriverDidShowModalAlert fired")
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
