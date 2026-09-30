import AppKit
import QuartzCore
import LaunchNGContextMenuCore
import Combine
import SwiftUI

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Core Animation Grid View
/// A high-performance grid view built on Core Animation, with 120Hz ProMotion support
final class CAGridView: NSView, CALayerDelegate, NSDraggingSource {
    var backgroundLabelSample: BackgroundLabelContrast?
    var backgroundLabelColor: NSColor?
    var backgroundLabelShadow: BackgroundLabelContrast.Shadow = .none
    var backgroundLabelDarkAppearance: Bool?
    var backgroundLabelTints: [BackgroundLabelContrast.Tint] = []
    var presentedFolderID: String?
    var folderGlassHandoff: FolderGlassOverlay.PresentationHandoff?

    // MARK: - Properties

    var displayLink: CADisplayLink?
    var containerLayer: CALayer!
    var pageContainerLayer: CALayer!
    var iconLayers: [[CALayer]] = []  // [page][item]
    var usesLiquidGlassFolders = false {
        didSet { if oldValue != usesLiquidGlassFolders { syncFolderGlass() } }
    }
    var folderGlassOverlay: FolderGlassOverlay?
    var folderGlassAnimationDeadline: CFTimeInterval = 0
    var folderCreationHighlight: FolderCreationHighlight?
    var retiringFolderCreationHighlight: FolderCreationHighlight?

    // Grid configuration
    var columns: Int = 7 { didSet { rebuildLayers() } }
    var rows: Int = 5 { didSet { rebuildLayers() } }
    var iconSize: CGFloat = 72 {
        didSet {
            guard iconSize != oldValue else { return }
            clearIconCache()
            updateLayout()
        }
    }
    var columnSpacing: CGFloat = 24 { didSet { updateLayout() } }
    var rowSpacing: CGFloat = 36 { didSet { updateLayout() } }
    var labelFontSize: CGFloat = 12 { didSet { rebuildLayers() } }  // Default 12pt, a bit larger than before
    var labelFontWeight: NSFont.Weight = .medium { didSet { updateLabelFonts() } }
    var showLabels: Bool = true { didSet { updateLabelVisibility() } }
    var isLayoutLocked: Bool = false
    var folderDropZoneScale: CGFloat = CGFloat(AppStore.defaultFolderDropZoneScale)
    var folderPreviewScale: CGFloat = 1
    var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) { didSet { updateLayout() } }
    var pageSpacing: CGFloat = 0 { didSet { updateLayout() } }

    // Data source
    var itemsRevision = 0
    var items: [LaunchpadItem] = [] {
        didSet {
            itemsRevision &+= 1
            needsLayoutRefresh = true
            syncBatchSelectionWithItems()
            rebuildLayers(reusing: oldValue)
            if enableIconPreload {
                preloadIcons()
            }
        }
    }
    var needsLayoutRefresh = true

    // Paging
    var currentPage: Int = 0
    var itemsPerPage: Int { columns * rows }
    var pageCount: Int { max(1, (items.count + itemsPerPage - 1) / itemsPerPage) }
    /// pageCount, but trailing pages made up entirely of `.empty` placeholders
    /// (e.g. one reserved by an edge-drag "create new page" that was never
    /// actually dropped into) don't count. Mirrors LaunchpadView's
    /// `visiblePageCount`, which trims the same way for the page-indicator
    /// dots — this is what keeps ordinary scroll/swipe navigation (and the
    /// rubber-band boundary while it's in progress) from being able to reach
    /// those reserved pages at all, matching there being no dot for them.
    /// Layer creation and page navigation while a drop target is a page edge
    /// deliberately keep using the untrimmed `pageCount` instead — an active
    /// drag is exactly when reaching a reserved empty page is the point.
    var visiblePageCount: Int {
        guard itemsPerPage > 0 else { return pageCount }
        var count = pageCount
        while count > 1 {
            let start = (count - 1) * itemsPerPage
            let end = min(count * itemsPerPage, items.count)
            guard start < end else { break }
            guard items[start..<end].isEntirelyEmptyPlaceholders else { break }
            count -= 1
        }
        return count
    }
    /// The page count ordinary navigation (scroll/swipe, wheel paging, page-
    /// indicator dots, keyboard) should be clamped to. Drags get the full,
    /// untrimmed pageCount so an edge-drag can still reach/reveal a reserved
    /// empty page.
    var navigablePageCount: Int {
        (isDraggingItem || externalDragActive || isBatchDragging) ? pageCount : visiblePageCount
    }

    // Scroll state
    var scrollOffset: CGFloat = 0
    var targetScrollOffset: CGFloat = 0
    var scrollVelocity: CGFloat = 0
    var isScrollAnimating = false
    var layoutRevealPageMotion: LayoutRevealFeedback.PageMotion?
    var scrollSensitivity: Double = AppStore.defaultScrollSensitivity
    var reverseWheelPagingDirection: Bool = false
    var trackpadVerticalDirection: AppStore.TrackpadVerticalDirection = .natural
    var animationsEnabled: Bool = true
    var animationDuration: Double = 0.3
    var scrollAnimationStartTime: CFTimeInterval = 0
    var scrollAnimationStartOffset: CGFloat = 0
    var hoverMagnificationEnabled: Bool = false {
        didSet {
            if !hoverMagnificationEnabled {
                clearHover()
            }
        }
    }
    var hoverMagnificationScale: CGFloat = 1.2
    var activePressEffectEnabled: Bool = false
    var activePressScale: CGFloat = 0.92
    var isDragging = false
    var dragStartOffset: CGFloat = 0
    var accumulatedDelta: CGFloat = 0

    // Performance monitoring
    var lastFrameTime: CFAbsoluteTime = 0
    var frameCount: Int = 0
    var currentFPS: Double = 120
    var frameTimes: [Double] = []

    // Icon cache
    var iconCache: [String: CGImage] = [:]
    let iconCacheLock = NSLock()
    var enableIconPreload: Bool = false

    // Callbacks
    var onItemClicked: ((LaunchpadItem, Int) -> Void)?
    var onItemDoubleClicked: ((LaunchpadItem, Int) -> Void)?
    var onPageChanged: ((Int) -> Void)?
    var onFPSUpdate: ((Double) -> Void)?
    var onEmptyAreaClicked: (() -> Void)?
    var onContextMenuAction: ((AppContextMenuRoute) -> Void)?
    var onCreateFolder: ((AppInfo, AppInfo, Int) -> Void)?  // (dragged app, target app, position)
    var onMoveToFolder: ((AppInfo, FolderInfo) -> Void)?    // Move into an existing folder
    var onReorderItems: ((Int, Int) -> Void)?               // Reorder (fromIndex, toIndex)
    var onReorderAppBatch: (([String], Int) -> Void)?       // Batch reorder (in path order)
    var onRequestNewPage: (() -> Void)?                     // Request that a new page be created
    var contextMenuConfiguration = AppContextMenuConfiguration()
    var isContextMenuTracking: Bool = false
    var allowsBatchSelectionMode: Bool = true {
        didSet {
            if !allowsBatchSelectionMode {
                disableBatchSelectionMode()
            }
        }
    }
    var isBatchSelectionMode = false
    var batchSelectedAppPathsOrdered: [String] = []
    var batchSelectedAppPathSet: Set<String> = []
    var batchDraggingAppPathsOrdered: [String] = []
    var batchHiddenCompanionIndices: [Int] = []

    // Drag state
    var isDraggingItem = false
    var draggingIndex: Int?
    var draggingItem: LaunchpadItem?
    var draggingLayer: CALayer?
    var dragLanding: DragLanding?
    var folderMergeLanding: FolderMergeLanding?
    var folderDissolveTransition: FolderDissolveTransition?
    var dragStartPoint: CGPoint = .zero
    var dragCurrentPoint: CGPoint = .zero
    var dropTargetIndex: Int?
    var dragDropPreview: GridDropPreview = .none
    var pendingDropPreview: GridDropPreview?
    var longPressTimer: Timer?
    let longPressDuration: TimeInterval = 0.5
    var pressedIndex: Int?

    // Cross-page dragging
    var edgeDragTimer: Timer?
    var edgeDragTimerDirection: Int?
    let edgeDragThreshold: CGFloat = 60  // Width of the edge-detection zone
    let edgeDragDelay: TimeInterval = 0.4  // Delay before triggering a page flip

    // Live reorder during drag
    var currentHoverIndex: Int?
    var pendingHoverIndex: Int?
    var originalIconPositions: [Int: CGPoint] = [:]
    var hoverUpdateTimer: Timer?
    // Debounces .insert previews against fast multi-cell sweeps (merge
    // previews apply immediately instead — see requestDropPreview). Every
    // index change restarts this wait from zero, so it's also the de facto
    // dwell time needed to land an insert between two icons at all — too
    // long (150ms) made merge (instant) feel much more reliable than insert
    // for the same kind of deliberate, careful positioning; too short (50ms)
    // let a normal drag *through* a folder toward the next cell spend enough
    // time crossing the folder's own narrow insert sliver to trigger its
    // partial "make space" nudge on the way past, reading as the folder
    // grabbing/holding the pointer before finally stepping aside. 100ms is a
    // middle ground; if either failure mode reappears, this is the knob.
    let hoverUpdateDelay: TimeInterval = 0.1

    // Mouse-drag paging
    var isPageDragging = false
    var pageDragStartX: CGFloat = 0
    var pageDragStartOffset: CGFloat = 0

    // Event monitors
    var scrollEventMonitor: Any?
    var wasWindowVisible = false  // Tracks window visibility state

    // Mouse wheel paging state (only used for non-precise scrolling devices)
    var wheelAccumulatedDelta: CGFloat = 0
    var wheelLastDirection: Int = 0
    var wheelLastFlipAt: Date?
    let wheelFlipCooldown: TimeInterval = 0.15
    // Legacy reference:
    // var wheelSnapTimer: Timer?
    // let wheelSnapDelay: TimeInterval = 0.15  // How long after scrolling stops before snap triggers
    let debugScrollMismatch = false
    var externalDragActive = false
    var externalAppDragSessionActive = false
    var hoveredIndex: Int?
    var selectedIndex: Int?
    var hoverTrackingArea: NSTrackingArea?
    var isScrollEnabled: Bool = true
    var dockDragEnabled: Bool = true
    let externalAppDragOutset: CGFloat = 18
    var dockDragSide: AppStore.DockDragSide = .bottom
    var externalAppDragTriggerDistance: CGFloat = CGFloat(AppStore.defaultDockDragTriggerDistance)

    func logIfMismatch(_ tag: String, appPage: Int? = nil) {
        guard debugScrollMismatch else { return }
        guard bounds.width > 0 else { return }
        let pageStride = bounds.width + pageSpacing
        let expectedOffset = -CGFloat(currentPage) * pageStride
        let transformOffset = pageContainerLayer.transform.m41
        let offsetMismatch = abs(scrollOffset - expectedOffset) > 0.5
        let transformMismatch = abs(transformOffset - scrollOffset) > 0.5
        guard offsetMismatch || transformMismatch else { return }
        let appInfo = appPage.map { ", appPage=\($0)" } ?? ""
        // print("⚠️ [CAGrid #\(instanceId)] \(tag) mismatch: currentPage=\(currentPage)\(appInfo), scroll=\(scrollOffset), expected=\(expectedOffset), transform=\(transformOffset), boundsW=\(bounds.width), pageSpacing=\(pageSpacing)")
    }

    // Instance tracking
    private static var instanceCounter = 0
    let instanceId: Int

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        CAGridView.instanceCounter += 1
        self.instanceId = CAGridView.instanceCounter
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        CAGridView.instanceCounter += 1
        self.instanceId = CAGridView.instanceCounter
        super.init(coder: coder)
        setup()
    }

    deinit {
        // print("💀 [CAGrid #\(instanceId)] deinit - instance being destroyed!")
        displayLink?.invalidate()
        removeScrollEventMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    func setup() {
        NotificationCenter.default.addObserver(self, selector: #selector(folderWillDissolve(_:)),
                                               name: .launchpadFolderWillDissolve, object: nil)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Create the container layer
        containerLayer = CALayer()
        containerLayer.frame = bounds
        containerLayer.masksToBounds = false  // Don't clip, so content can extend past the bounds while swiping
        layer?.addSublayer(containerLayer)

        // Page container layer (used for the overall offset)
        pageContainerLayer = CALayer()
        pageContainerLayer.frame = bounds
        containerLayer.addSublayer(pageContainerLayer)

        // Disable implicit animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.commit()

        // Register for launchpad window notifications right at init time (so they're always received)
        NotificationCenter.default.addObserver(self, selector: #selector(launchpadWindowDidShow(_:)), name: .launchpadWindowShown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(launchpadWindowDidHide(_:)), name: .launchpadWindowHidden, object: nil)
        // Observe app-activation events (as a fallback)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)

        // print("✅ [CAGrid #\(instanceId)] Core Animation grid initialized")
    }

    func makeFirstResponderIfAvailable() {
        guard let win = window else { return }
        if win.firstResponder == nil || win.firstResponder === self {
            win.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            window.acceptsMouseMovedEvents = true
            setupDisplayLink()
            // Always install the scroll event monitor (more reliable)
            setupScrollEventMonitor()
            // Make sure the view becomes first responder
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponderIfAvailable()
            }
            // print("✅ [CAGrid #\(instanceId)] View moved to window, scroll monitor installed")

            // Observe window show/hide events
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)

            NotificationCenter.default.addObserver(self, selector: #selector(windowDidActivate(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidActivate(_:)), name: NSWindow.didBecomeMainNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowOcclusionChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            // launchpad window notifications are registered in setup(), no need to re-register here
        } else {
            finishFolderDissolve()
            finishDragLanding()
            removeFolderCreationHighlight()
            resetFolderGlass()
            // A torn-down view never gets AppKit's NSDraggingSession endedAt
            // callback if one was in flight; without this, a future instance's
            // mouse events would stay gated by a stuck flag on the app delegate.
            endExternalAppDragSessionIfActive()
            // The display link retains its target, so invalidate it before deinit.
            displayLink?.invalidate()
            displayLink = nil
            // Clean up window-related event observers when the view is removed from the window
            // Note: launchpad window notifications aren't removed here, since they're registered in setup()
            removeScrollEventMonitor()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        }
    }

    @objc func windowDidActivate(_ notification: Notification) {
        // print("🪟 [CAGrid] Window activated, making first responder")
        makeFirstResponderIfAvailable()
    }

    @objc func windowOcclusionChanged(_ notification: Notification) {
        guard let window = window else { return }
        if window.occlusionState.contains(.visible) {
            // print("🪟 [CAGrid] Window became visible, making first responder")
            makeFirstResponderIfAvailable()
        }
    }

    @objc func launchpadWindowDidShow(_ notification: Notification) {
        // Only instances that have a window respond
        guard let window = window else {
            // print("⚠️ [CAGrid #\(instanceId)] Launchpad window shown - but no window, ignoring")
            return
        }
        // print("🚀 [CAGrid #\(instanceId)] Launchpad window shown, hasMonitor=\(scrollEventMonitor != nil)")

        syncFolderGlass()

        // Immediately install the scroll event monitor (if not already installed)
        if scrollEventMonitor == nil {
            // print("🔄 [CAGrid #\(instanceId)] Reinstalling scroll monitor on window show")
            setupScrollEventMonitor()
        }

        // Make sure it becomes first responder
        makeFirstResponderIfAvailable()

        // Reconfirm after a delay (in case another component steals it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let win = self.window else { return }
            // print("🔄 [CAGrid #\(self.instanceId)] Delayed check, isFirstResponder=\(win.firstResponder === self), hasMonitor=\(self.scrollEventMonitor != nil)")
            self.makeFirstResponderIfAvailable()
            // Make sure the scroll event monitor exists
            if self.scrollEventMonitor == nil {
                self.setupScrollEventMonitor()
            }
        }
    }

    @objc func launchpadWindowDidHide(_ notification: Notification) {
        // Only instances that have a window respond
        guard window != nil else {
            // print("⚠️ [CAGrid #\(instanceId)] Window hidden - but no window, ignoring")
            return
        }
        // print("🚀 [CAGrid #\(instanceId)] Window hidden, hasMonitor=\(scrollEventMonitor != nil)")
        // No longer removing the monitor - keep it active, so it's ready immediately when the window is shown again
        // removeScrollEventMonitor()
        wasWindowVisible = false
        // The window can be hidden mid-drag (hot corner, trackpad gesture, or
        // losing key status all bypass isDraggingItem) with no further
        // mouseDragged/mouseUp ever delivered to this view. Left alone, the
        // floating preview and hidden source icon would stay stuck until the
        // app is relaunched, matching reports of drags "freezing".
        longPressTimer?.invalidate()
        longPressTimer = nil
        cancelEdgeDragTimer()
        isPageDragging = false
        setPressedIndex(nil, animated: false)
        // Same reasoning as above: if a system Dock-drag's endedAt callback was
        // ever skipped, this flag would otherwise stay stuck and permanently
        // block mouseDown/mouseDragged/mouseUp on this view.
        endExternalAppDragSessionIfActive()
        if isDraggingItem || isBatchDragging {
            cancelDragging()
        }
        finishFolderDissolve()
        finishDragLanding()
        removeFolderCreationHighlight()
        resetFolderGlass()
    }

    @objc func appDidBecomeActive(_ notification: Notification) {
        // Check whether the scroll monitor needs installing when the app activates
        // print("🔔 [CAGrid #\(instanceId)] App became active notification received, window=\(window != nil), isVisible=\(window?.isVisible ?? false)")
        guard let window = window else {
            // print("🔔 [CAGrid #\(instanceId)] App became active - no window")
            return
        }

        // Immediately try to reinstall the scroll monitor (regardless of window visibility)
        // because the window might still be animating in, so isVisible could still read false
        // print("🔔 [CAGrid #\(instanceId)] Reinstalling scroll monitor immediately on app activate")
        setupScrollEventMonitor()
        makeFirstResponderIfAvailable()

        // Recheck after a delay, to make sure the scroll monitor exists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let win = self.window else { return }
            // print("🔔 [CAGrid #\(self.instanceId)] Delayed check: isVisible=\(win.isVisible), scrollMonitor=\(self.scrollEventMonitor != nil)")
            if self.scrollEventMonitor == nil {
                // print("🔄 [CAGrid #\(self.instanceId)] App became active (delayed), reinstalling scroll monitor")
                self.setupScrollEventMonitor()
            }
            self.makeFirstResponderIfAvailable()
        }
    }

    func setupScrollEventMonitor() {
        // Remove the old monitor
        removeScrollEventMonitor()

        // Only set up the monitor once there's a window (visibility is checked dynamically when handling events)
        guard window != nil else {
            // print("⚠️ [CAGrid #\(instanceId)] setupScrollEventMonitor: no window, skipping")
            return
        }

        let myInstanceId = self.instanceId

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            guard !self.isContextMenuTracking else { return event }
            guard self.isScrollEnabled else { return event }
            guard let window = self.window else { return event }
            
            // Scroll wheel targeting follows the cursor, not key-window status
            // (unlike clicks) — AppKit still delivers it to whichever of our
            // windows is under the pointer even while a different window
            // (e.g. Settings) is key, or before this window has finished
            // becoming key after being shown. Requiring isKeyWindow here
            // made a scroll immediately after opening (before that
            // activation finished, which can be genuinely asynchronous)
            // silently do nothing; the bounds check below already scopes
            // this to events actually over the grid.
            guard window.isVisible else { return event }
            
            // Check whether the event is within the view's bounds
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }

            self.handleScrollWheel(with: event)
            // Consume the event, don't pass it along, to avoid double-handling
            return nil
        }
        // print("✅ [CAGrid #\(instanceId)] Scroll event monitor installed")
    }

    func removeScrollEventMonitor() {
        if let monitor = scrollEventMonitor {
            // print("🗑️ [CAGrid #\(instanceId)] Removing scroll event monitor")
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }
    }

    // MARK: - Display Link (120Hz)

    func setupDisplayLink() {
        displayLink?.invalidate()

        guard let window = window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupDisplayLink()
            }
            return
        }

        displayLink = window.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)

        // print("✅ [CAGrid] DisplayLink configured for 120Hz")
    }

    @objc func displayLinkFired(_ link: CADisplayLink) {
        updateFolderDissolve(at: CACurrentMediaTime())
        let creationUpdated = updateFolderCreationHighlight(at: CACurrentMediaTime())
        updateDragLanding(at: CACurrentMediaTime())
        let glassAnimating = usesLiquidGlassFolders && CACurrentMediaTime() < folderGlassAnimationDeadline
        let updatesScroll = isScrollAnimating
        defer {
            if glassAnimating && !updatesScroll && !creationUpdated {
                syncFolderGlass()
            }
        }
        // Only update while animating
        guard isScrollAnimating || isDraggingItem else {
            // Reset the frame count while idle
            if frameCount > 0 {
                frameCount = 0
                lastFrameTime = 0
            }
            return
        }

        // Compute the live frame rate (only while animating)
        let now = CFAbsoluteTimeGetCurrent()
        if lastFrameTime > 0 {
            let delta = now - lastFrameTime
            let instantFPS = 1.0 / delta
            // Use a sliding-window average, to reduce array operations
            if frameTimes.count >= 30 {
                frameTimes.removeFirst()
            }
            frameTimes.append(instantFPS)
            currentFPS = frameTimes.reduce(0, +) / Double(frameTimes.count)
        }
        lastFrameTime = now

        frameCount += 1
        // Report once every 60 frames (about every 0.5s)
        if frameCount % 60 == 0 {
            onFPSUpdate?(currentFPS)
            // print("🎮 [CAGrid] Avg FPS: \(String(format: "%.1f", currentFPS))")
        }

        // Update the scroll animation
        if isScrollAnimating {
            updateScrollAnimation()
        }
    }

    // MARK: - Scroll Animation

    func updateScrollAnimation() {
        if !animationsEnabled {
            scrollOffset = targetScrollOffset
            scrollVelocity = 0
            isScrollAnimating = false
            layoutRevealPageMotion = nil
        } else if let motion = layoutRevealPageMotion {
            let progress = min(1, max(0, (CACurrentMediaTime() - motion.startedAt) / motion.duration))
            let fraction = CGFloat(progress * progress * (3 - 2 * progress))
            scrollOffset = motion.from + (motion.to - motion.from) * fraction
            if progress >= 1 {
                scrollOffset = targetScrollOffset
                scrollVelocity = 0
                isScrollAnimating = false
                layoutRevealPageMotion = nil
            }
        } else {
            let diff = targetScrollOffset - scrollOffset
            let snapThreshold: CGFloat = 0.5
            if abs(diff) > snapThreshold {
                // Not time-controlled: exponential convergence, the farther the distance the faster it moves
                let t: CGFloat = 0.18
                scrollOffset += diff * t
            } else {
                scrollOffset = targetScrollOffset
                scrollVelocity = 0
                isScrollAnimating = false
            }
        }

        // Commit CA paging and the native glass subtree together. A separate
        // commit can present the two parts of a folder at different offsets.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        syncFolderGlass(geometryChanged: false)
        CATransaction.commit()
    }

    func easeOutSoft(_ t: CGFloat) -> CGFloat {
        // Damped spring: soft ease-out with a subtle bounce (about ~2% overshoot).
        return springEaseOut(t, damping: 0.78, frequency: 1.4)
    }

    func springEaseOut(_ t: CGFloat, damping: CGFloat, frequency: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        if clamped == 0 { return 0 }
        if clamped == 1 { return 1 }

        let dampingRatio = max(0, min(1, damping))
        let omega = 2 * CGFloat.pi * max(0.1, frequency)
        if dampingRatio >= 1 {
            return 1 - exp(-omega * clamped)
        }

        let omegaD = omega * sqrt(1 - dampingRatio * dampingRatio)
        let expTerm = exp(-dampingRatio * omega * clamped)
        let cosTerm = cos(omegaD * clamped)
        let sinTerm = sin(omegaD * clamped)
        let coeff = dampingRatio / sqrt(1 - dampingRatio * dampingRatio)
        return 1 - expTerm * (cosTerm + coeff * sinTerm)
    }

    func easeOutBack(_ t: CGFloat, overshoot: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        let s = max(0, overshoot)
        let t1 = clamped - 1
        return 1 + (s + 1) * t1 * t1 * t1 + s * t1 * t1
    }

    func cubicBezier(_ x: CGFloat, c1: CGPoint, c2: CGPoint) -> CGFloat {
        let clamped = max(0, min(1, x))
        let t = solveBezierT(forX: clamped, c1x: c1.x, c2x: c2.x)
        return cubicBezierValue(t, c1: c1.y, c2: c2.y)
    }

    func cubicBezierValue(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * t * c1
            + 3 * oneMinusT * t * t * c2
            + t * t * t
    }

    func cubicBezierDerivative(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * c1
            + 6 * oneMinusT * t * (c2 - c1)
            + 3 * t * t * (1 - c2)
    }

    func solveBezierT(forX x: CGFloat, c1x: CGFloat, c2x: CGFloat) -> CGFloat {
        var t = x
        for _ in 0..<5 {
            let xAtT = cubicBezierValue(t, c1: c1x, c2: c2x)
            let dx = xAtT - x
            if abs(dx) < 1e-4 { return t }
            let d = cubicBezierDerivative(t, c1: c1x, c2: c2x)
            if abs(d) < 1e-5 { break }
            t -= dx / d
            if t < 0 || t > 1 { break }
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<8 {
            let mid = (low + high) * 0.5
            let xAtMid = cubicBezierValue(mid, c1: c1x, c2: c2x)
            if xAtMid < x {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) * 0.5
    }
    
    // Set initial page before items are set to ensure correct positioning
    func setInitialPage(_ page: Int) {
        currentPage = max(0, page)
    }

    func navigateToPage(_ page: Int, animated: Bool = true, revealDuration: TimeInterval? = nil) {
        layoutRevealPageMotion = nil
        let newPage = max(0, min(navigablePageCount - 1, page))
        let pageChanged = newPage != currentPage
        if pageChanged, isDraggingItem, !isBatchDragging {
            // The previous page's highlight must not survive into a drop on
            // another page without a new, visible preview there.
            showDropPreview(.none)
        }
        currentPage = newPage

        // If bounds isn't ready yet, only update currentPage; the actual scroll is left to layout()
        guard bounds.width > 0 else {
            if pageChanged {
                onPageChanged?(currentPage)
            }
            return
        }

        let pageStride = bounds.width + pageSpacing
        targetScrollOffset = -CGFloat(currentPage) * pageStride

        // Check whether animation is needed (including snapping back to place)
        let needsAnimation = animated && abs(scrollOffset - targetScrollOffset) > 0.5
        
        if needsAnimation && animationsEnabled {
            isScrollAnimating = true
            if let duration = revealDuration, duration.isFinite, duration > 0 {
                layoutRevealPageMotion = LayoutRevealFeedback.PageMotion(
                    from: scrollOffset, to: targetScrollOffset, pageStride: pageStride, duration: duration)
            }
        } else {
            // Jump immediately
            isScrollAnimating = false
            scrollOffset = targetScrollOffset
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            syncFolderGlass(geometryChanged: false)
            CATransaction.commit()
        }

        if pageChanged {
            onPageChanged?(currentPage)
        }
        logIfMismatch("navigateToPage")
    }

    // MARK: - Public Methods

    var isBatchDragging: Bool { !batchDraggingAppPathsOrdered.isEmpty }

    func enableBatchSelectionMode() {
        guard allowsBatchSelectionMode else {
            NSSound.beep()
            return
        }
        isBatchSelectionMode = true
        syncBatchSelectionWithItems()
        refreshBatchSelectionUI()
    }

    func disableBatchSelectionMode() {
        if isDraggingItem && isBatchDragging {
            cancelDragging()
        }
        let hadState = isBatchSelectionMode ||
            !batchSelectedAppPathsOrdered.isEmpty ||
            !batchDraggingAppPathsOrdered.isEmpty
        isBatchSelectionMode = false
        batchSelectedAppPathsOrdered.removeAll()
        batchSelectedAppPathSet.removeAll()
        batchDraggingAppPathsOrdered.removeAll()
        restoreBatchHiddenCompanionLayers()
        if hadState {
            refreshBatchSelectionUI()
        }
    }

    func toggleBatchSelection(forAppPath path: String) {
        guard isBatchSelectionMode else { return }
        if batchSelectedAppPathSet.contains(path) {
            batchSelectedAppPathSet.remove(path)
            batchSelectedAppPathsOrdered.removeAll { $0 == path }
        } else {
            batchSelectedAppPathSet.insert(path)
            batchSelectedAppPathsOrdered.append(path)
        }
        refreshBatchSelectionUI()
    }

    func orderedBatchDragPaths(leadingAppPath path: String) -> [String] {
        guard batchSelectedAppPathSet.contains(path) else { return [] }
        var ordered: [String] = [path]
        ordered.append(contentsOf: batchSelectedAppPathsOrdered.filter { $0 != path })
        return ordered
    }

    func appPath(at index: Int) -> String? {
        guard items.indices.contains(index), case .app(let app) = items[index] else { return nil }
        return app.url.path
    }

    func syncBatchSelectionWithItems() {
        guard isBatchSelectionMode else { return }
        let currentPaths = Set(items.compactMap { item -> String? in
            guard case .app(let app) = item else { return nil }
            return app.url.path
        })
        let oldCount = batchSelectedAppPathSet.count
        batchSelectedAppPathSet = batchSelectedAppPathSet.intersection(currentPaths)
        batchSelectedAppPathsOrdered = batchSelectedAppPathsOrdered.filter { batchSelectedAppPathSet.contains($0) }
        if batchSelectedAppPathSet.count != oldCount {
            refreshBatchSelectionUI()
        }
    }

    func globalIndex(forAppPath path: String) -> Int? {
        for (index, item) in items.enumerated() {
            if case .app(let app) = item, app.url.path == path {
                return index
            }
        }
        return nil
    }

    func setOpacity(_ opacity: Float, forGlobalIndex index: Int) {
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count else { return }
        iconLayers[pageIndex][localIndex].opacity = opacity
    }

    func restoreBatchHiddenCompanionLayers() {
        guard !batchHiddenCompanionIndices.isEmpty else { return }
        for index in batchHiddenCompanionIndices {
            setOpacity(1.0, forGlobalIndex: index)
        }
        batchHiddenCompanionIndices.removeAll()
        batchDraggingAppPathsOrdered.removeAll()
    }

    func clearIconCache() {
        // An explicit content refresh must not reuse pre-refresh layers.
        finishFolderDissolve()
        finishDragLanding()
        iconCacheLock.lock()
        iconCache.removeAll()
        iconCacheLock.unlock()
    }

    func refreshLayout() {
        rebuildLayers()
    }

    func snapToCurrentPageIfNeeded() {
        // Don't force a snap while the user is dragging or an animation is in progress
        guard !isDragging && !isScrollAnimating && !isPageDragging else { return }
        guard bounds.width > 0 else { return }
        
        let expectedOffset = -CGFloat(currentPage) * (bounds.width + pageSpacing)
        let transformOffset = pageContainerLayer.transform.m41
        let needsOffsetSync = abs(scrollOffset - expectedOffset) > 0.5
        let needsTransformSync = abs(transformOffset - scrollOffset) > 0.5
        guard needsOffsetSync || needsTransformSync else { return }

        if needsOffsetSync {
            scrollOffset = expectedOffset
            targetScrollOffset = expectedOffset
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        syncFolderGlass(geometryChanged: false)
        CATransaction.commit()
    }

    func forceSyncPageTransformIfNeeded() {
        guard bounds.width > 0 else { return }
        let pageStride = bounds.width + pageSpacing
        let expectedOffset = -CGFloat(currentPage) * pageStride
        if abs(scrollOffset - expectedOffset) > 0.5 {
            scrollOffset = expectedOffset
            targetScrollOffset = expectedOffset
        }
        let transformOffset = pageContainerLayer.transform.m41
        guard abs(transformOffset - scrollOffset) > 0.5 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        syncFolderGlass(geometryChanged: false)
        CATransaction.commit()
    }

    /// Make sure the scroll event monitor is installed (for external callers)
    func ensureScrollMonitorInstalled() {
        guard let window = window else {
            // print("⚠️ [CAGrid #\(instanceId)] ensureScrollMonitorInstalled: no window")
            return
        }

        // Install it whenever there's a window and no monitor yet (visibility is checked when handling events)
        if scrollEventMonitor == nil {
            // print("🔄 [CAGrid #\(instanceId)] ensureScrollMonitorInstalled: monitor missing, installing")
            setupScrollEventMonitor()
            makeFirstResponderIfAvailable()
        }
    }

    /// Get the instance ID (for debugging)
    var debugInstanceId: Int { instanceId }
}
