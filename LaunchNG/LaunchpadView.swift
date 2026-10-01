import SwiftUI
import Combine
import AppKit

// MARK: - LaunchpadItem extension
extension LaunchpadItem {
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

// MARK: - Simplified page-flip manager
private class PageFlipManager: ObservableObject {
    @Published var isCooldown: Bool = false
    private var lastFlipTime: Date?
    var autoFlipInterval: TimeInterval = 0.8
    
    func canFlip() -> Bool {
        guard !isCooldown else { return false }
        guard let lastTime = lastFlipTime else { return true }
        return Date().timeIntervalSince(lastTime) >= autoFlipInterval
    }
    
    func recordFlip() {
        lastFlipTime = Date()
        isCooldown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + autoFlipInterval) {
            self.isCooldown = false
        }
    }
}

private extension View {
    @ViewBuilder
    func launchpadBackgroundStyle(_ style: AppStore.BackgroundStyle,
                                  cornerRadius: CGFloat,
                                  maskColor: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch style {
        case .glass:
            let base = self.liquidGlass(in: shape)
            if let maskColor {
                base.background(maskColor, in: shape)
            } else {
                base
            }
        case .blur:
            let base = self.background(.ultraThinMaterial, in: shape)
            if let maskColor {
                base.background(maskColor, in: shape)
            } else {
                base
            }
        case .unfiltered:
            if let maskColor {
                self.background(maskColor, in: shape)
            } else {
                self
            }
        }
    }
}

struct LaunchpadView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var searchEngine: LaunchpadSearchEngine
    @StateObject private var backgroundImageController = BackgroundImageController()
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyMonitor: Any?
    @State private var windowObserver: NSObjectProtocol?
    @State private var windowHiddenObserver: NSObjectProtocol?
    @State private var draggingItem: LaunchpadItem?
    @State private var dragPreviewPosition: CGPoint = .zero
    @State private var dragPreviewScale: CGFloat = 1.2
    @State private var pendingDropIndex: Int? = nil
    @StateObject private var pageFlipManager = PageFlipManager()
    @State private var folderHoverCandidateIndex: Int? = nil
    @State private var folderHoverBeganAt: Date? = nil
    @State private var folderAppToReveal: String? = nil
    @State private var selectedIndex: Int? = nil
    @State private var isKeyboardNavigationActive: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var reorderNamespace
    @State private var handoffEventMonitor: Any? = nil
    @State private var globalMouseUpMonitor: Any? = nil
    @State private var gridOriginInWindow: CGPoint = .zero
    @State private var currentContainerSize: CGSize = .zero
    @State private var currentColumnWidth: CGFloat = 0
    @State private var currentAppHeight: CGFloat = 0
    @State private var currentIconSize: CGFloat = 0
    @State private var headerTotalHeight: CGFloat = 0
    
    // Performance optimization: use a static cache to avoid state-mutation issues
    private static var geometryCache: [String: CGPoint] = [:]
    private static var lastGeometryUpdate: Date = Date.distantPast
    private let geometryCacheTimeout: TimeInterval = 0.1 // 100ms cache timeout

    // Performance monitoring
    @State private var performanceMetrics: [String: TimeInterval] = [:]
    private let enablePerformanceMonitoring = false // Set to true to enable performance monitoring
    @State private var isHandoffDragging: Bool = false
    @State private var dragPointerOffset: CGPoint = .zero
    @State private var isWindowVisible: Bool = false
    @State private var postOnboardingGridOpacity: Double = 1
    @State private var postOnboardingGridScale: CGFloat = 1
    @State private var pendingPostOnboardingReveal: Bool = false

    init(appStore: AppStore) {
        _appStore = ObservedObject(wrappedValue: appStore)
        _searchEngine = ObservedObject(wrappedValue: appStore.searchEngine)
    }

    @StateObject private var folderPresentation = CAFolderPresentationController()

    private var isFolderOpen: Bool { appStore.openFolder != nil }
    private var currentScreenID: String? {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        return screen.map { AppStore.screenIdentifier(for: $0) }
    }
    
    private var config: GridConfig {
        GridConfig(isFullscreen: appStore.isFullscreenMode,
                   columns: appStore.gridColumnsPerPage,
                   rows: appStore.gridRowsPerPage,
                   columnSpacing: CGFloat(appStore.iconColumnSpacing),
                   rowSpacing: CGFloat(appStore.iconRowSpacing))
    }

    private var backdropOpacity: Double {
        guard appStore.isFullscreenMode, effectiveBackgroundStyle != .unfiltered else { return 0.0 }
        if appStore.shouldShowOnboarding {
            return colorScheme == .dark ? 0.34 : 0.10
        }
        return colorScheme == .dark ? 0.30 : 0.35
    }

    private var onboardingLightFilterOpacity: Double {
        guard appStore.isFullscreenMode, effectiveBackgroundStyle != .unfiltered,
              appStore.shouldShowOnboarding, colorScheme == .light else { return 0.0 }
        return 0.20
    }

    var filteredItems: [LaunchpadItem] {
        searchEngine.filter(items: appStore.items,
                            query: appStore.searchQuery,
                            fuzzyEnabled: appStore.fuzzySearchEnabled)
    }
    
    var pages: [[LaunchpadItem]] {
        let items = draggingItem != nil ? visualItems : filteredItems
        return makePages(from: items)
    }

    /// Trailing pages made up entirely of `.empty` placeholders — e.g. one
    /// reserved by an edge-drag "create new page" that was never actually
    /// dropped into — don't get their own dot or swipeable slot. A page with
    /// at least one real app, folder or missing-app placeholder still counts,
    /// even if the rest of it is empty.
    private var visiblePageCount: Int {
        var count = pages.count
        while count > 1, pages[count - 1].isEntirelyEmptyPlaceholders {
            count -= 1
        }
        return count
    }
    
    private var currentItems: [LaunchpadItem] {
        draggingItem != nil ? visualItems : filteredItems
    }
    
    private var visualItems: [LaunchpadItem] {
        guard let dragging = draggingItem, let pending = pendingDropIndex else { return filteredItems }
        let itemsPerPage = config.itemsPerPage
        var pageSlices: [[LaunchpadItem]] = makePages(from: filteredItems)

        let sourcePage = pageSlices.firstIndex { $0.contains(dragging) }
        let sourceIndexInPage = sourcePage.flatMap { pageSlices[$0].firstIndex(of: dragging) }
        let targetPage = max(0, pending / itemsPerPage)
        let localIndexDesired = pending % itemsPerPage

        if let sPage = sourcePage, sPage == targetPage, let sIdx = sourceIndexInPage {
            pageSlices[sPage].remove(at: sIdx)
        }

        while pageSlices.count <= targetPage { pageSlices.append([]) }
        let localIndex = max(0, min(localIndexDesired, pageSlices[targetPage].count))
        pageSlices[targetPage].insert(dragging, at: localIndex)

        var p = targetPage
        while p < pageSlices.count {
            if pageSlices[p].count > itemsPerPage {
                let spilled = pageSlices[p].removeLast()
                if p + 1 >= pageSlices.count { pageSlices.append([]) }
                pageSlices[p + 1].insert(spilled, at: 0)
                p += 1
            } else {
                p += 1
            }
        }

        var transformed = pageSlices
        for pageIndex in transformed.indices {
            for itemIndex in transformed[pageIndex].indices {
                if transformed[pageIndex][itemIndex] == dragging {
                    let placeholderToken = "dragging-placeholder-\(dragging.id)-\(pageIndex)-\(itemIndex)"
                    transformed[pageIndex][itemIndex] = .empty(placeholderToken)
                }
            }
        }

        return transformed.flatMap { $0 }
    }

    private func makePages(from items: [LaunchpadItem]) -> [[LaunchpadItem]] {
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: config.itemsPerPage).map { start in
            let end = min(start + config.itemsPerPage, items.count)
            return Array(items[start..<end])
        }
    }
    
    var body: some View {
        launchpadEventBoundView
         .task(id: appStore.layoutRevealRequest?.id) {
             guard let request = appStore.layoutRevealRequest else { return }
             // Search observers must see the pending request before navigation
             // completes; otherwise they can reset the destination selection.
             await withCheckedContinuation { continuation in
                 DispatchQueue.main.async { continuation.resume() }
             }
             await revealAppInLayout(request)
         }
         .onChange(of: appStore.searchText) { _, text in
             if !text.isEmpty { appStore.layoutRevealRequest = nil }
         }
         .onChange(of: appStore.isSetting) { _, visible in
             if visible { appStore.layoutRevealRequest = nil }
         }
         .onChange(of: appStore.openFolder?.id) { _, id in
             if id == nil { folderAppToReveal = nil }
         }
    }

    private var launchpadEventBoundView: some View {
        launchpadBaseView
        .sheet(isPresented: $appStore.isSetting) {
            SettingsView(appStore: appStore)
        }
        .onChange(of: colorScheme) { _, _ in
            appStore.scheduleSystemAppearanceRefresh()
        }
         .onChange(of: appStore.items) {
             guard draggingItem == nil else { return }
             clampSelection()
             let maxPageIndex = max(pages.count - 1, 0)
             if appStore.currentPage > maxPageIndex {
                 appStore.currentPage = maxPageIndex
             }
          }
          .onChange(of: isSearchFieldFocused) { _, focused in
             if focused { isKeyboardNavigationActive = false }
         }
         .onReceive(ControllerInputManager.shared.commands) { command in
             appStore.layoutRevealRequest = nil
             handleControllerCommand(command)
         }
         .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
             WallpaperDiagnostics.record("context.spaceChanged")
             refreshBackgroundImage(reason: .contextChecked)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notification in
             guard let changedWindow = notification.object as? NSWindow,
                   changedWindow === AppDelegate.shared?.launchpadWindow else { return }
             // A window can report its screen again when it is shown. Validate
             // the display/context instead of discarding a settled frame.
             refreshBackgroundImage(reason: .contextChecked)
         }
         .onChange(of: appStore.backgroundImageEnabled) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onChange(of: appStore.launchpadBackgroundStyle) { old, new in
             guard (old == .unfiltered) != (new == .unfiltered) else { return }
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)
             .merge(with: NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification))
             .filter { notification in
                 guard let window = notification.object as? NSWindow else { return false }
                 return window === AppDelegate.shared?.launchpadWindow
             }
             .debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { notification in
             guard appStore.backgroundImageEnabled, appStore.launchpadBackgroundStyle == .unfiltered,
                   let window = notification.object as? NSWindow,
                   window === AppDelegate.shared?.launchpadWindow, !window.inLiveResize else { return }
             refreshBackgroundImage(reason: .viewportChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: .wallpaperCapturePermissionChanged)) { _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
             if appStore.backgroundImageEnabled,
                appStore.backgroundImageSource == .desktopWallpaper {
                 WallpaperCaptureAccess.shared.refresh()
             }
         }
         .onChange(of: appStore.backgroundImageSource) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onChange(of: appStore.customBackgroundImagePath) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }

           .onAppear {
              if !appStore.shouldShowOnboarding {
                  appStore.performInitialScanIfNeeded()
              }
              setupKeyHandlers()
              setupInitialSelection()
              setupWindowShownObserver()
              setupWindowHiddenObserver()
              let windowIsAlreadyVisible = AppDelegate.shared?.launchpadWindow?.isVisible == true
              isWindowVisible = windowIsAlreadyVisible
              if windowIsAlreadyVisible {
                  refreshBackgroundImage(reason: .windowShown)
              } else {
                  // Deliver the initial preference even for a login launch that
                  // starts hidden, so disabled snapshot caches are cleaned up.
                  refreshBackgroundImage(reason: .settingsChanged)
              }
              // Observe global mouse-up, to make sure drag state is cleaned up correctly (when released outside the window)
               if let existing = globalMouseUpMonitor { NSEvent.removeMonitor(existing) }
               globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
                   if handoffEventMonitor != nil || draggingItem != nil {
                       finalizeHandoffDrag()
                   }
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                      if draggingItem != nil {
                          draggingItem = nil
                          pendingDropIndex = nil
                          appStore.isDragCreatingFolder = false
                          appStore.folderCreationTarget = nil
                          pageFlipManager.isCooldown = false
                          isHandoffDragging = false
                          clampSelection()
                      }
                  }
              }
               isKeyboardNavigationActive = false
               clampSelection()
           }
         .onDisappear {
             [keyMonitor, handoffEventMonitor].forEach { monitor in
                 if let monitor = monitor { NSEvent.removeMonitor(monitor) }
             }
             if let monitor = globalMouseUpMonitor { NSEvent.removeMonitor(monitor) }
             [windowObserver, windowHiddenObserver].forEach { observer in
                 if let observer = observer { NotificationCenter.default.removeObserver(observer) }
             }
            keyMonitor = nil
            handoffEventMonitor = nil
            globalMouseUpMonitor = nil
            windowObserver = nil
            windowHiddenObserver = nil
            backgroundImageController.clear()
         }
        .onChange(of: appStore.shouldShowOnboarding) { wasVisible, visible in
            if wasVisible && !visible {
                if appStore.isInitialLoading {
                    postOnboardingGridOpacity = 0
                    pendingPostOnboardingReveal = true
                } else {
                    playPostOnboardingGridReveal()
                }
            }

            guard !visible, !appStore.isInitialLoading else { return }
            appStore.performInitialScanIfNeeded()
        }
        .onChange(of: appStore.isInitialLoading) { _, loading in
            guard !loading, pendingPostOnboardingReveal, !appStore.shouldShowOnboarding else { return }
            playPostOnboardingGridReveal()
        }
        .onChange(of: appStore.voiceFeedbackEnabled) { _, enabled in
            if enabled {
                if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                    let item = filteredItems[idx]
                    VoiceManager.shared.announceSelection(item: item)
                }
            } else {
                VoiceManager.shared.stop()
            }
        }
        .onChange(of: appStore.isLayoutLocked) { _, locked in
            guard locked else { return }
            if let monitor = handoffEventMonitor {
                NSEvent.removeMonitor(monitor)
                handoffEventMonitor = nil
            }
            draggingItem = nil
            pendingDropIndex = nil
            dragPreviewPosition = .zero
            dragPointerOffset = .zero
            dragPreviewScale = 1.2
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            appStore.handoffDraggingApp = nil
            appStore.handoffDragScreenLocation = nil
            folderHoverCandidateIndex = nil
            folderHoverBeganAt = nil
            pageFlipManager.isCooldown = false
            isHandoffDragging = false
            appStore.cleanupUnusedNewPage()
            appStore.removeEmptyPages()
            appStore.saveAllOrder()
            clampSelection()
        }
    }

    private var launchpadBaseView: some View {
        ZStack {
            LaunchpadBackgroundImageView(image: displayedBackgroundImage)

            launchpadBackdropLayer

            launchpadStyledContent
        }
        .ignoresSafeArea()
        .overlay(launchpadInteractionOverlay)
    }

    private var launchpadStyledContent: some View {
        GeometryReader { geo in
            launchpadMainContent(in: geo)
        }
        // Was a plain, unconditional .padding() (system default on all four
        // edges) around the whole window content — applies in Compact mode
        // too, unlike config.bottomPadding above, which is fullscreen-only.
        // Bottom split out and shrunk on its own; top/leading/trailing keep
        // the previous default so side/top margins don't shift too.
        .padding(.top)
        .padding(.horizontal)
        .padding(.bottom, 2)
        .launchpadBackgroundStyle(effectiveBackgroundStyle,
                                  cornerRadius: appStore.isFullscreenMode ? 0 : 30,
                                  maskColor: appStore.backgroundMaskColor(for: colorScheme))
    }

    private var launchpadBackdropLayer: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
            if onboardingLightFilterOpacity > 0 {
                Color.white.opacity(onboardingLightFilterOpacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: appStore.shouldShowOnboarding)
        .animation(.easeInOut(duration: 0.22), value: colorScheme)
        .allowsHitTesting(false)
    }

    private var displayedBackgroundImage: CGImage? {
        guard appStore.backgroundImageEnabled else {
            return nil
        }
        return backgroundImageController.content?.image
    }

    private var resolvedBackgroundLabelSample: BackgroundLabelContrast? {
        displayedBackgroundImage == nil ? nil : backgroundImageController.content?.labelSample
    }

    private var resolvedWallpaperControlStyle: BackgroundLabelContrast.Style? {
        resolvedBackgroundLabelSample?.resolvedStyle(darkAppearance: colorScheme == .dark,
                                                     tints: backgroundLabelTints)
    }

    private func toolbarSymbol(_ name: String) -> some View {
        let style = resolvedWallpaperControlStyle
        let foreground = style.map { AnyShapeStyle(($0.usesWhiteText ? Color.white : Color.black).opacity(0.75)) }
            ?? AnyShapeStyle(.placeholder.opacity(0.5))
        return Image(systemName: name)
            .font(.title)
            .foregroundStyle(foreground)
    }

    private var backgroundLabelTints: [BackgroundLabelContrast.Tint] {
        var tints = [BackgroundLabelContrast.Tint(red: 0, green: 0, blue: 0, alpha: backdropOpacity),
                     .init(red: 1, green: 1, blue: 1, alpha: onboardingLightFilterOpacity)]
        if appStore.backgroundMaskEnabled {
            let mask = colorScheme == .dark ? appStore.backgroundMaskDarkColor : appStore.backgroundMaskLightColor
            tints.append(.init(red: mask.red, green: mask.green, blue: mask.blue, alpha: mask.alpha))
        }
        return tints.filter { $0.alpha > 0 }
    }

    private var effectiveBackgroundStyle: AppStore.BackgroundStyle {
        // Preserve the saved choice, but keep a usable backdrop without an image.
        if appStore.launchpadBackgroundStyle == .unfiltered, displayedBackgroundImage == nil {
            return .glass
        }
        return appStore.launchpadBackgroundStyle
    }

    private func handleHeaderBackgroundTap() {
        guard appStore.openFolder == nil,
              !appStore.isSetting,
              !appStore.isFolderNameEditing,
              draggingItem == nil else { return }
        AppDelegate.shared?.hideWindow()
    }

    private func launchpadMainContent(in geo: GeometryProxy) -> some View {
        let actualTopPadding = config.isFullscreen ? geo.size.height * config.topPadding : 0
        let actualBottomPadding = config.isFullscreen ? geo.size.height * config.bottomPadding : 0
        let actualHorizontalPadding = config.isFullscreen ? geo.size.width * config.horizontalPadding : 0
        let indicatorTopPadding = appStore.effectivePageIndicatorTopPadding(for: currentScreenID)
        let indicatorOffset = appStore.effectivePageIndicatorOffset(for: currentScreenID)

        return VStack {
            // Add dynamic padding at the top (fullscreen mode)
            if config.isFullscreen {
                Spacer()
                    .frame(height: actualTopPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleHeaderBackgroundTap()
                    }
            }
            ZStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(appStore.localized(.searchPlaceholder), text: $appStore.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: 480)
                .disabled(isFolderOpen)
                .onChange(of: appStore.searchQuery) {
                    guard !isFolderOpen, appStore.layoutRevealRequest == nil else { return }
                    let query = appStore.searchQuery
                    // Avoid publishing a change directly within the view update cycle; defer it to the next run loop
                    let maxPageIndex = max(pages.count - 1, 0)
                    DispatchQueue.main.async {
                        guard appStore.searchQuery == query, appStore.layoutRevealRequest == nil else { return }
                        appStore.currentPage = 0
                        if appStore.currentPage > maxPageIndex {
                            appStore.currentPage = maxPageIndex
                        }
                    }
                    selectedIndex = filteredItems.isEmpty ? nil : 0
                    isKeyboardNavigationActive = false
                    clampSelection()
                }
                .focused($isSearchFieldFocused)
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Spacer()
                    if appStore.showQuickRefreshButton {
                        Button {
                            appStore.refresh()
                        } label: {
                            toolbarSymbol("arrow.clockwise.circle")
                        }
                        .buttonStyle(.plain)
                        .help(appStore.localized(.refresh))
                    }
                    Button {
                        appStore.isSetting = true
                    } label: {
                        toolbarSymbol("ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top)
            .padding(.horizontal)
            .background(
                ZStack {
                    // Search and toolbar controls remain above this catcher, so
                    // only otherwise-empty header space closes LaunchNG.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleHeaderBackgroundTap()
                        }

                    GeometryReader { proxy in
                        // Track the total header height, including dynamic top padding and extra spacing.
                        Color.clear.onAppear {
                            let extra: CGFloat = 24
                            let total = (config.isFullscreen ? geo.size.height * config.topPadding : 0) + proxy.size.height + extra
                            DispatchQueue.main.async { headerTotalHeight = total }
                        }
                        .onChange(of: proxy.size) { _, _ in
                            let extra: CGFloat = 24
                            let total = (config.isFullscreen ? geo.size.height * config.topPadding : 0) + proxy.size.height + extra
                            DispatchQueue.main.async { headerTotalHeight = total }
                        }
                        .allowsHitTesting(false)
                    }
                }
            )
            .opacity(isFolderOpen ? 0.1 : 1)
            .allowsHitTesting(!isFolderOpen)

            // Keep the original top/bottom margins, remove the visible divider
            Spacer()
                .frame(height: 30)

            GeometryReader { gridGeo in
                gridRegion(in: gridGeo,
                           actualTopPadding: actualTopPadding,
                           actualBottomPadding: actualBottomPadding)
            }
            .opacity(appStore.shouldShowOnboarding ? 1 : postOnboardingGridOpacity)
            .scaleEffect(appStore.shouldShowOnboarding ? 1 : postOnboardingGridScale)

            // Shared by both renderers; hover material stays local to this row.
            // Always present (rather than removed via `if`) once past onboarding,
            // even with a single visible page: its dots just go invisible then,
            // so this row's own height keeps reserving the same space instead of
            // the bottom spacing shifting depending on page count.
            if !appStore.shouldShowOnboarding {
                LaunchpadPageIndicator(pageCount: max(visiblePageCount, 1),
                                      currentPage: appStore.currentPage,
                                      isActive: !isFolderOpen && isWindowVisible && visiblePageCount > 1,
                                      backgroundStyle: resolvedWallpaperControlStyle) { index in
                    navigateToPage(index)
                }
                .padding(.top, CGFloat(indicatorTopPadding))
                .padding(.bottom, CGFloat(indicatorOffset))
                .opacity(visiblePageCount > 1 ? (isFolderOpen ? 0.1 : 1) : 0)
                .allowsHitTesting(visiblePageCount > 1 && !isFolderOpen)
            }

            // Add dynamic padding below the page indicator dots
            if config.isFullscreen {
                Spacer()
                    .frame(height: actualBottomPadding)
            }
        }
        .padding(.horizontal, actualHorizontalPadding)
    }

    private var launchpadInteractionOverlay: some View {
        ZStack {
            // Semi-transparent background: only inserted while a folder is open, with a fade transition
            if isFolderOpen {
                Color.black
                    .opacity(0.1)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    // Native folder presentation owns dismissal during CA transitions.
                    .allowsHitTesting(false)
                    .onTapGesture {
                        if !appStore.isFolderNameEditing {
                            let closingFolder = appStore.openFolder
                            withAnimation(LNAnimations.springFast) { appStore.openFolder = nil }
                            if let folder = closingFolder,
                               let idx = filteredItems.firstIndex(of: .folder(folder)) {
                                isKeyboardNavigationActive = true
                                selectedIndex = idx
                                let targetPage = idx / config.itemsPerPage
                                if targetPage != appStore.currentPage { appStore.currentPage = targetPage }
                            }
                            isSearchFieldFocused = true
                        }
                    }
            }

            CAFolderPresentation(appStore: appStore, controller: folderPresentation,
                iconSize: currentIconSize * CGFloat(min(max(appStore.iconScale, 0.6), 1.15)),
                onClose: { closePresentedFolder() }, onLaunchApp: { launchApp($0) },
                backgroundLabelSample: resolvedBackgroundLabelSample,
                backgroundLabelTints: backgroundLabelTints,
                initialRevealAppPath: folderAppToReveal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The header passes events through; clicking the outer window margins dismisses LaunchNG.
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let topSafe = max(0, headerTotalHeight)
                // Cover the page indicator row's real reserved height (top
                // padding + its own 28pt frame + bottom offset — always
                // present now even with its dots invisible, see
                // visiblePageCount) plus the outer bottom padding below it,
                // not just config.bottomPadding (fullscreen-only, 0 in
                // Compact) floored to a flat 24pt. That flat 24pt used to
                // leave a gap below the indicator row where a click hit
                // neither an icon nor this catcher — not "outside" enough to
                // close anything.
                let indicatorReservedHeight = CGFloat(appStore.effectivePageIndicatorTopPadding(for: currentScreenID))
                    + 28
                    + CGFloat(appStore.effectivePageIndicatorOffset(for: currentScreenID))
                    + (config.isFullscreen ? h * config.bottomPadding : 0)
                    + 2
                let bottomPad = max(indicatorReservedHeight, 24)
                let sidePad = max(config.isFullscreen ? w * config.horizontalPadding : 0, 24)

                // These margin catchers are removed from the view tree
                // entirely while a folder is open — structurally, the same
                // way the folder dimming overlay above is conditional on
                // isFolderOpen — rather than merely disabling their hit
                // testing. A present-but-hitTesting-disabled SwiftUI shape
                // still occupies its place in this ZStack; enlarging bottomPad
                // to close the gap above made that shape's (inert) claim
                // overlap the region CAFolderPresentation needs for its own
                // outside-click-closes-folder handling, silently swallowing
                // those clicks instead of letting them reach it. Removing the
                // catchers outright avoids that regardless of size.
                if appStore.openFolder == nil {
                    // Header area: pass through.
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.clear)
                            .frame(height: topSafe)
                            .allowsHitTesting(false)
                        Spacer()
                        // Bottom margin: tap to close
                        Rectangle().fill(Color.clear)
                            .frame(height: bottomPad)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !appStore.isFolderNameEditing {
                                    AppDelegate.shared?.hideWindow()
                                }
                            }
                    }
                    .ignoresSafeArea()

                    // Left/right margins: tap to close
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.clear)
                            .frame(width: sidePad)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !appStore.isFolderNameEditing {
                                    AppDelegate.shared?.hideWindow()
                                }
                            }
                        Spacer()
                        Rectangle().fill(Color.clear)
                            .frame(width: sidePad)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !appStore.isFolderNameEditing {
                                    AppDelegate.shared?.hideWindow()
                                }
                            }
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }
    
    private func playPostOnboardingGridReveal() {
        pendingPostOnboardingReveal = false
        postOnboardingGridOpacity = 0
        postOnboardingGridScale = 0.96
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
            postOnboardingGridOpacity = 1
            postOnboardingGridScale = 1
        }
    }
    
    private func gridRegion(in geo: GeometryProxy,
                            actualTopPadding: CGFloat,
                            actualBottomPadding: CGFloat) -> AnyView {
        let appCountPerRow = config.columns
        let maxRowsPerPage = Int(ceil(Double(config.itemsPerPage) / Double(appCountPerRow)))
        let availableWidth = geo.size.width
        let availableHeight = geo.size.height - (actualTopPadding + actualBottomPadding)

        let appHeight: CGFloat = {
            let totalRowSpacing = config.rowSpacing * CGFloat(maxRowsPerPage - 1)
            let height = (availableHeight - totalRowSpacing) / CGFloat(maxRowsPerPage)
            return max(56, height)
        }()

        let columnWidth: CGFloat = {
            let totalColumnSpacing = config.columnSpacing * CGFloat(appCountPerRow - 1)
            let width = (availableWidth - totalColumnSpacing) / CGFloat(appCountPerRow)
            return max(40, width)
        }()

        let iconSize: CGFloat = min(columnWidth, appHeight) * CGFloat(min(max(appStore.iconScale, 0.6), 1.15))

        if appStore.shouldShowOnboarding {
            let compactOnboardingLayout = geo.size.width < 960
            return AnyView(
                FirstLaunchOnboardingPanel(appStore: appStore, compactLayout: compactOnboardingLayout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, max(8, actualTopPadding))
                    .padding(.bottom, max(12, actualBottomPadding))
                    .padding(.horizontal, max(16, geo.size.width * 0.05))
            )
        }

        if appStore.isInitialLoading {
            return AnyView(
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .progressViewStyle(.circular)
                    Text(appStore.localized(.loadingApplications))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        if filteredItems.isEmpty && !appStore.searchQuery.isEmpty {
            return AnyView(
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.placeholder)
                    Text(appStore.localized(.noAppsFound))
                        .font(.title)
                        .foregroundStyle(.placeholder)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        let caInsets = NSEdgeInsets(top: actualTopPadding,
                                    left: 0,
                                    bottom: actualBottomPadding,
                                    right: 0)
        let caItems: [LaunchpadItem] = filteredItems
        let externalDragSourceIndex: Int? = draggingItem.flatMap { filteredItems.firstIndex(of: $0) }
        let externalDragHoverIndex: Int? = draggingItem != nil ? pendingDropIndex : nil

        return AnyView(
                ZStack(alignment: .topLeading) {
                    CAGridViewRepresentable(
                        appStore: appStore,
                        items: caItems,
                        iconSize: iconSize,
                        columnSpacing: config.columnSpacing,
                        rowSpacing: config.rowSpacing,
                        contentInsets: caInsets,
                        pageSpacing: config.pageSpacing,
                        onOpenApp: nil,
                        onOpenFolder: { folder in
                            withAnimation(LNAnimations.springFast) {
                                appStore.openFolder = folder
                            }
                        },
                        externalDragSourceIndex: externalDragSourceIndex,
                        externalDragHoverIndex: externalDragHoverIndex,
                        selectedIndex: isKeyboardNavigationActive ? selectedIndex : nil,
                        folderPresentation: folderPresentation,
                        backgroundLabelSample: resolvedBackgroundLabelSample,
                        backgroundLabelTints: backgroundLabelTints
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isFolderOpen ? 0.1 : 1)
                    .allowsHitTesting(!isFolderOpen)

                    if let draggingItem {
                        DragPreviewItem(item: draggingItem,
                                        iconSize: iconSize,
                                        labelWidth: columnWidth * 0.9,
                                        scale: dragPreviewScale)
                            .position(x: dragPreviewPosition.x, y: dragPreviewPosition.y)
                            .zIndex(100)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "grid")
                .onAppear {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
                .onChange(of: appStore.handoffDraggingApp) {
                    if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                        startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: appStore.openFolder) {
                    if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                        startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: geo.size) {
                    DispatchQueue.main.async {
                        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: appStore.gridRefreshTrigger) { _, _ in
                    DispatchQueue.main.async {
                        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
            )
    }

    @MainActor
    private func revealAppInLayout(_ request: AppStore.LayoutRevealRequest) async {
        guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return }
        defer {
            if appStore.layoutRevealRequest?.id == request.id {
                appStore.layoutRevealRequest = nil
            }
        }
        guard appStore.searchText.isEmpty, appStore.searchQuery.isEmpty,
              let location = appStore.layoutLocation(ofAppAtPath: request.appPath) else { return }
        isSearchFieldFocused = false
        isKeyboardNavigationActive = false
        selectedIndex = location.index
        let destinationPage = location.index / max(1, config.itemsPerPage)
        folderAppToReveal = nil

        let cancelReveal = {
            if appStore.layoutRevealRequest?.id == request.id {
                appStore.layoutRevealRequest = nil
            }
        }
        let inputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { event in
            cancelReveal()
            return event
        }
        let inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: NSApp, queue: .main
        ) { _ in cancelReveal() }
        defer {
            if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
            NotificationCenter.default.removeObserver(inactiveObserver)
        }

        // Show the restored layout before moving. Waiting is bounded so a
        // missing icon cannot leave navigation pending forever.
        do {
            let itemID = appStore.items[location.index].id
            var navigationGrid: CAGridView?
            _ = await waitForLayoutReveal(request, timeout: 1.5) {
                guard let grid = folderPresentation.grid, grid.window?.isVisible == true,
                      grid.items.count == appStore.items.count,
                      grid.items.indices.contains(location.index), grid.items[location.index].id == itemID,
                      grid.bounds.width > 0, grid.bounds.height > 0 else { return false }
                navigationGrid = grid
                return grid.revealIconsAreReady(from: grid.currentPage, through: destinationPage)
            }
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id,
                  let grid = navigationGrid else { return }
            let showsMotion = appStore.enableAnimations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let changesPage = grid.currentPage != destinationPage
            if showsMotion && changesPage {
                // Give the restored icons a few visible frames before the first movement.
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            guard appStore.layoutRevealRequest?.id == request.id else { return }
            let pageDuration = LayoutRevealFeedback.pageDuration(distance: abs(grid.currentPage - destinationPage))
            grid.navigateToPage(destinationPage, animated: showsMotion, revealDuration: pageDuration)
            let motionID = grid.layoutRevealPageMotion?.id
            defer {
                if let motionID, grid.layoutRevealPageMotion?.id == motionID {
                    // A cancelled reveal leaves ordinary paging in charge.
                    grid.layoutRevealPageMotion = nil
                }
            }
            appStore.currentPage = destinationPage
            let arrived = await waitForLayoutReveal(request, timeout: pageDuration + 0.6) {
                !grid.isScrollAnimating
            }
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return }
            if !arrived { grid.navigateToPage(destinationPage, animated: false) }
            if showsMotion {
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            }
            guard appStore.layoutRevealRequest?.id == request.id else { return }
            let feedbackLayer = grid.presentationContainer(at: location.index)
            if let feedbackLayer,
               LayoutRevealFeedback.animate(on: feedbackLayer,
                    pressScale: CGFloat(appStore.activePressScale), enabled: appStore.enableAnimations) {
                let hasGlass = location.folder != nil && grid.usesLiquidGlassFolders
                if hasGlass {
                    grid.folderGlassAnimationDeadline = max(grid.folderGlassAnimationDeadline,
                        CACurrentMediaTime() + LayoutRevealFeedback.duration)
                    grid.syncFolderGlass()
                }
                defer {
                    feedbackLayer.removeAnimation(forKey: LayoutRevealFeedback.animationKey)
                    if hasGlass { grid.syncFolderGlass() }
                }
                do { try await Task.sleep(for: .seconds(LayoutRevealFeedback.duration)) } catch { return }
            }
        }
        guard let folder = location.folder else { return }
        guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id,
              appStore.searchText.isEmpty, appStore.searchQuery.isEmpty,
              appStore.openFolder == nil, !appStore.isSetting,
              let currentLocation = appStore.layoutLocation(ofAppAtPath: request.appPath),
              currentLocation.index == location.index, currentLocation.folder?.id == folder.id,
              appStore.currentPage == location.index / max(1, config.itemsPerPage),
              selectedIndex == location.index else { return }
        folderAppToReveal = request.appPath
        appStore.openFolderActivatedByKeyboard = false
        appStore.openFolder = currentLocation.folder
    }

    @MainActor
    private func waitForLayoutReveal(_ request: AppStore.LayoutRevealRequest,
                                     timeout: TimeInterval, until ready: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        repeat {
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return false }
            if ready() { return true }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
        } while CACurrentMediaTime() < deadline
        return false
    }

    private func closePresentedFolder() {
        let closingFolder = appStore.openFolder
        withAnimation(LNAnimations.springFast) { appStore.openFolder = nil }
        if let folder = closingFolder,
           let index = filteredItems.firstIndex(where: { $0.id == "folder_\(folder.id)" }) {
            isKeyboardNavigationActive = true
            selectedIndex = index
            let page = index / max(1, config.itemsPerPage)
            if page != appStore.currentPage { appStore.currentPage = page }
        }
        isSearchFieldFocused = true
    }

    private func launchApp(_ app: AppInfo) {
        // Launch first, hide LaunchNG's own window only once that's confirmed --
        // not the other way around. Some apps (confirmed with Transmission, via
        // Console logs: an NSInternalInconsistencyException inside AppKit's own
        // NSToolbar/SF Symbol rendering while it builds its window) crash on
        // launch specifically when LaunchNG hides itself first with only a
        // blind short delay before the real launch call: that leaves a brief
        // window where neither LaunchNG nor the app being launched is properly
        // the active app, which is exactly the kind of gap Finder's own launch
        // (LaunchNG stays active and visible the whole time, right up until the
        // new app's window is ready to take over) never creates. Launching the
        // same app straight from Finder never reproduced the crash; launching
        // it the old way here did, reliably. Still, waiting for the full launch
        // leaves the window lingering for the entire startup time of slow apps
        // -- hide on whichever comes first, the confirmed launch or a short
        // fallback timeout, since the fallback only fires after openApplication
        // has already been called and so can't reopen the crash gap above.
        let configuration = NSWorkspace.OpenConfiguration()
        let fallbackHide = DispatchWorkItem { AppDelegate.shared?.hideWindow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + CAGridViewRepresentable.launchHideFallbackDelay, execute: fallbackHide)
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                fallbackHide.cancel()
                if error != nil {
                    NSSound.beep()
                    return
                }
                AppDelegate.shared?.hideWindow()
            }
        }
    }
    
    private func handleItemTap(_ item: LaunchpadItem) {
        guard draggingItem == nil else { return }
        switch item {
        case .app(let app):
            launchApp(app)
        case .folder(let folder):
            withAnimation(LNAnimations.springFast) {
                appStore.openFolder = folder
            }
        case .missingApp:
            NSSound.beep()
        case .empty:
            break
        }
    }
    
    

    // MARK: - Handoff drag from folder
    private func startHandoffDragIfNeeded(geo: GeometryProxy, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        guard draggingItem == nil, let app = appStore.handoffDraggingApp else { return }
        if appStore.isLayoutLocked {
            appStore.handoffDraggingApp = nil
            appStore.handoffDragScreenLocation = nil
            return
        }
        // Update the geometry context
        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)

        // Initial position: screen -> grid-local
        let screenPoint = appStore.handoffDragScreenLocation ?? NSEvent.mouseLocation
        let localPoint = convertScreenToGrid(screenPoint)

        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { draggingItem = .app(app) }
        isKeyboardNavigationActive = false
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        dragPreviewScale = 1.2
        dragPreviewPosition = localPoint
        // Make the handoff drag consistent with a normal drag: pre-create a new page to support edge paging
        isHandoffDragging = true

        // Smart page-jump: decide whether to jump to a suitable page based on the drag position
        if let targetIndex = indexAt(point: localPoint,
                                     in: currentContainerSize,
                                     pageIndex: appStore.currentPage,
                                     columnWidth: columnWidth,
                                     appHeight: appHeight),
           currentItems.indices.contains(targetIndex) {
            let targetPage = targetIndex / config.itemsPerPage
            if targetPage != appStore.currentPage && targetPage < pages.count {
                appStore.currentPage = targetPage
            }
        }

        if let existing = handoffEventMonitor { NSEvent.removeMonitor(existing) }
        handoffEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            switch event.type {
            case .leftMouseDragged:
                let lp = convertScreenToGrid(NSEvent.mouseLocation)
                // Reuse the same core update logic as a normal drag
                applyDragUpdate(at: lp,
                                containerSize: currentContainerSize,
                                columnWidth: currentColumnWidth,
                                appHeight: currentAppHeight,
                                iconSize: currentIconSize)
                return nil
            case .leftMouseUp:
                finalizeHandoffDrag()
                return nil
            default:
                return event
            }
        }

        appStore.handoffDraggingApp = nil
        appStore.handoffDragScreenLocation = nil
    }

    private func convertScreenToGrid(_ screenPoint: CGPoint) -> CGPoint {
        guard let window = NSApp.keyWindow else { return screenPoint }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        // SwiftUI's .global has its origin at the top, AppKit window coordinates have theirs at the bottom, so y needs flipping
        let windowHeight = window.contentView?.bounds.height ?? window.frame.size.height
        let x = windowPoint.x - gridOriginInWindow.x
        let yFromTop = windowHeight - windowPoint.y
        let y = yFromTop - gridOriginInWindow.y
        return CGPoint(x: x, y: y)
    }

    private func handleHandoffDragMove(to localPoint: CGPoint) {
        guard !appStore.isLayoutLocked else { return }
        // Reuse update logic that's exactly the same as a normal drag
        applyDragUpdate(at: localPoint,
                        containerSize: currentContainerSize,
                        columnWidth: currentColumnWidth,
                        appHeight: currentAppHeight,
                        iconSize: currentIconSize)
    }

    private func finalizeHandoffDrag() {
        guard draggingItem != nil else { return }
        defer {
            if let monitor = handoffEventMonitor { NSEvent.removeMonitor(monitor); handoffEventMonitor = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                draggingItem = nil
                pendingDropIndex = nil
                dragPointerOffset = .zero
                clampSelection()
                // Reset the paging state
                pageFlipManager.isCooldown = false
                isHandoffDragging = false
                // Reset the folder-creation-via-drag state, so future drags work correctly
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
                // Clean up consistently with how a normal drag ends
                appStore.cleanupUnusedNewPage()
                appStore.removeEmptyPages()
                appStore.saveAllOrder()
                // Trigger a grid refresh, to make sure drag gestures get re-attached correctly
                appStore.triggerGridRefresh()
            }
        }
        if appStore.isLayoutLocked {
            appStore.triggerGridRefresh()
            return
        }
        // In handoff-drag mode, compute the target index only at drop time; no snapping is shown mid-drag
        if isHandoffDragging && pendingDropIndex == nil {
            let pointerPoint = dragPreviewPosition
            if let idx = indexAt(point: pointerPoint,
                                  in: currentContainerSize,
                                  pageIndex: appStore.currentPage,
                                  columnWidth: currentColumnWidth,
                                  appHeight: currentAppHeight) {
                pendingDropIndex = idx
            } else {
                pendingDropIndex = predictedDropIndex(for: pointerPoint,
                                                      in: currentContainerSize,
                                                      columnWidth: currentColumnWidth,
                                                      appHeight: currentAppHeight)
            }
        }

        // Use the unified drag-end handling logic
        finalizeDragOperation(containerSize: currentContainerSize, columnWidth: currentColumnWidth, appHeight: currentAppHeight, iconSize: currentIconSize)

        // Trigger a grid refresh immediately, to make sure drag gestures get re-attached correctly
        appStore.triggerGridRefresh()
    }

    private func navigateToPage(_ targetPage: Int, animated: Bool = true) {
        guard targetPage >= 0 && targetPage < pages.count else { return }
        if animated {
            withAnimation(LNAnimations.springFast) {
                appStore.currentPage = targetPage
            }
        } else {
            appStore.currentPage = targetPage
        }
        
        if isKeyboardNavigationActive, selectedIndex != nil,
           let target = desiredIndexForPageKeepingPosition(targetPage: targetPage) {
            selectedIndex = target
        }
    }

    private func navigateToNextPage() {
        navigateToPage(appStore.currentPage + 1)
    }
    
    private func navigateToPreviousPage() {
        navigateToPage(appStore.currentPage - 1)
    }
    
}

private struct FirstLaunchOnboardingPanel: View {
    @ObservedObject var appStore: AppStore
    let compactLayout: Bool
    @State private var currentStep: Int = 0
    @State private var movingForward: Bool = true
    @State private var isImportingSystem = false
    @State private var isApplyingPreset = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var nativeImportAvailable: Bool = true
    @State private var hasCheckedNativeImport: Bool = false
    @State private var hasTriggeredBackgroundPreparation = false

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 14 : 18) {
            headerView

            HStack(alignment: .top, spacing: compactLayout ? 16 : 22) {
                if shouldShowStepSidebar {
                    stepSidebar
                }

                ZStack {
                    stepView(for: currentStep)
                        .id(currentStep)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity)
                .frame(height: stepContentHeight)
            }

            statusInlineRow
            footerView
        }
        .padding(compactLayout ? 16 : 20)
        .frame(maxWidth: compactLayout ? 680 : 760, alignment: .leading)
        .task {
            evaluateNativeImportAvailabilityIfNeeded()
        }
        .onChange(of: currentStep) { _, step in
            if step == 1 {
                triggerBackgroundPreparationIfNeeded()
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: heroSymbolName)
                .font(.system(size: compactLayout ? 34 : 40, weight: .light))
                .foregroundStyle(accentBlue)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(appStore.localized(.onboardingFlowWelcomeTitle))
                    .font(.system(size: compactLayout ? 24 : 28, weight: .bold))
                Text(appStore.localized(.onboardingFlowWelcomeSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(String(format: appStore.localized(.onboardingFlowProgressFormat), visibleStepPosition, visibleStepTotal))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .bottomLeading) {
            progressRail
                .offset(y: compactLayout ? 16 : 18)
        }
        .padding(.bottom, compactLayout ? 12 : 14)
    }

    @ViewBuilder
    private var statusInlineRow: some View {
        HStack(spacing: 8) {
            if let statusMessage, !statusMessage.isEmpty {
                Image(systemName: statusIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusIsError ? Color.red : accentBlue)
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .lineLimit(1)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: compactLayout ? 20 : 22, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: statusMessage)
    }

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(visibleStepSequence.enumerated()), id: \.element) { order, step in
                Button {
                    goToStep(step)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(step == currentStep ? accentBlue : Color.secondary.opacity(0.2))
                            .frame(width: 18, height: 18)
                            .overlay {
                                Text("\(order + 1)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(step == currentStep ? Color.white : Color.secondary)
                            }

                        Text(sidebarTitle(for: step))
                            .font(.subheadline.weight(step == currentStep ? .semibold : .regular))
                            .foregroundStyle(step == currentStep ? Color.primary : Color.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: compactLayout ? 128 : 150, alignment: .topLeading)
    }

    private var footerView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.onboardingFlowPoweredBy))
                    .font(.system(size: compactLayout ? 10 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(appStore.localized(.onboardingFlowSkip)) {
                    appStore.completeOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(accentBlue)
            }

            Spacer(minLength: 0)

            if !isAtFirstVisibleStep {
                Button(appStore.localized(.onboardingFlowBack)) {
                    goToStep(previousStepIndex(from: currentStep))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(accentBlue)
            }

            Button(primaryActionTitle) {
                if isAtLastVisibleStep {
                    appStore.completeOnboarding()
                } else {
                    goToStep(nextStepIndex(from: currentStep))
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accentBlue)
        }
    }

    private var welcomeStep: some View {
        stepCard(title: appStore.localized(.onboardingFlowIntroTitle),
                 subtitle: appStore.localized(.onboardingFlowIntroSubtitle),
                 icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                introItem(icon: "square.and.arrow.down", text: appStore.localized(.onboardingFlowIntroImportItem))
                introItem(icon: "square.grid.3x3", text: appStore.localized(.onboardingFlowIntroPresetItem))
                introItem(icon: "command", text: appStore.localized(.onboardingFlowIntroShortcutItem))
            }
        }
    }

    private var setupChoiceStep: some View {
        stepCard(title: appStore.localized(.onboardingFlowLayoutStepTitle),
                 subtitle: appStore.localized(.onboardingFlowLayoutStepSubtitle),
                 icon: "square.grid.3x3.topleft.filled") {
            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.onboardingFlowLayoutChooseMethod))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: setupChoiceColumns, spacing: 12) {
                    setupChoiceCard(
                        title: appStore.localized(.onboardingFlowLayoutOptionATitle),
                        subtitle: appStore.localized(.onboardingFlowLayoutOptionASubtitle),
                        detail: nativeImportAvailable ? appStore.localized(.onboardingFlowLayoutOptionADetail) : appStore.localized(.onboardingFlowLayoutOptionAUnavailableDetail),
                        icon: "square.and.arrow.down.on.square.fill",
                        buttonTitle: nativeImportAvailable ? appStore.localized(.onboardingFlowLayoutOptionAButton) : appStore.localized(.onboardingFlowLayoutOptionAUnavailableButton),
                        loading: isImportingSystem,
                        enabled: nativeImportAvailable,
                        action: importFromSystemLaunchpad
                    )

                    setupChoiceCard(
                        title: appStore.localized(.onboardingFlowLayoutOptionBTitle),
                        subtitle: appStore.localized(.onboardingFlowLayoutOptionBSubtitle),
                        detail: appStore.localized(.onboardingFlowLayoutOptionBDetail),
                        icon: "square.grid.3x3.topleft.filled",
                        buttonTitle: appStore.localized(.onboardingFlowLayoutOptionBButton),
                        loading: isApplyingPreset,
                        enabled: true,
                        action: applyClassicLayoutPreset
                    )
                }

                HStack {
                    Spacer()
                    Button(appStore.localized(.onboardingFlowLayoutSkipButton)) {
                        goToStep(2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(accentBlue)
                    .disabled(isBusy)
                }
            }
        }
    }

    private var shortcutStep: some View {
        stepCard(title: appStore.localized(.onboardingFlowShortcutStepTitle),
                 subtitle: appStore.localized(.onboardingFlowShortcutStepSubtitle),
                 icon: "command.circle.fill") {
            Button(appStore.localized(.onboardingFlowShortcutStepButton)) {
                DispatchQueue.main.async {
                    appStore.isSetting = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accentBlue)
        }
    }

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 16 : 20) {
            Spacer(minLength: 0)

            HStack(spacing: compactLayout ? 14 : 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: compactLayout ? 34 : 40, weight: .semibold))
                    .foregroundStyle(accentBlue)

                Text(appStore.localized(.onboardingFlowWelcomeTitle))
                    .font(.system(size: compactLayout ? 34 : 42, weight: .bold))
            }

            Text(appStore.localized(.onboardingFlowCompletionHeadline))
                .font(.system(size: compactLayout ? 20 : 24, weight: .semibold))
                .foregroundStyle(.primary)

            Text(appStore.localized(.onboardingFlowCompletionDescription))
                .font(.system(size: compactLayout ? 15 : 17))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, compactLayout ? 10 : 14)
    }

    private func stepCard<Content: View>(title: String,
                                         subtitle: String,
                                         icon: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: compactLayout ? 18 : 24) {
            stepSymbol(icon: icon)
                .frame(width: compactLayout ? 52 : 68, alignment: .top)

            VStack(alignment: .leading, spacing: compactLayout ? 10 : 12) {
                Text(title)
                    .font(.system(size: compactLayout ? 22 : 25, weight: .bold))

                Text(subtitle)
                    .font(.system(size: compactLayout ? 14 : 15))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(accentBlue.opacity(0.22))

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compactLayout ? 14 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var setupChoiceColumns: [GridItem] {
        if compactLayout {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func setupChoiceCard(title: String,
                                 subtitle: String,
                                 detail: String,
                                 icon: String,
                                 buttonTitle: String,
                                 loading: Bool,
                                 enabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: compactLayout ? 18 : 20, weight: .semibold))
                    .foregroundStyle(enabled ? accentBlue : Color.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.system(size: compactLayout ? 16 : 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(action: action) {
                HStack(spacing: 8) {
                    if loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(buttonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accentBlue)
            .disabled(isBusy || !enabled)
        }
        .padding(compactLayout ? 12 : 14)
        .frame(maxWidth: .infinity, minHeight: compactLayout ? 168 : 182, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(enabled ? accentBlue.opacity(0.20) : Color.secondary.opacity(0.20), lineWidth: 1)
        )
    }

    private func stepView(for step: Int) -> some View {
        Group {
            switch step {
            case 0:
                welcomeStep
            case 1:
                setupChoiceStep
            case 2:
                shortcutStep
            case 3:
                completionStep
            default:
                completionStep
            }
        }
    }

    private var stepTransition: AnyTransition {
        let insertionX: CGFloat = movingForward ? 46 : -46
        let removalX: CGFloat = movingForward ? -34 : 34
        return .asymmetric(
            insertion: .modifier(
                active: StepMotionModifier(offsetX: insertionX, opacity: 0),
                identity: StepMotionModifier(offsetX: 0, opacity: 1)
            ),
            removal: .modifier(
                active: StepMotionModifier(offsetX: removalX, opacity: 0),
                identity: StepMotionModifier(offsetX: 0, opacity: 1)
            )
        )
    }

    private func introItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentBlue)

            Text(text)
                .font(.subheadline)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    private func stepSymbol(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: compactLayout ? 42 : 54, weight: .light))
            .foregroundStyle(accentBlue)
            .symbolRenderingMode(.monochrome)
            .contentTransition(.symbolEffect(.replace))
    }

    private var heroSymbolName: String {
        switch currentStep {
        case 0: return "sparkles"
        case 1: return "square.grid.3x3"
        case 2: return "command"
        default: return "sparkles"
        }
    }

    private var accentBlue: Color {
        Color(red: 0.18, green: 0.48, blue: 1.0)
    }

    private var progressRail: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 4)

                Capsule()
                    .fill(accentBlue)
                    .frame(width: progressWidth(totalWidth: proxy.size.width), height: 4)
            }
        }
        .frame(width: compactLayout ? 180 : 210, height: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleStepPosition)
    }

    private var primaryActionTitle: String {
        if isAtLastVisibleStep { return appStore.localized(.onboardingFlowDone) }
        if currentStep == 0 { return appStore.localized(.onboardingFlowStart) }
        return appStore.localized(.onboardingFlowNext)
    }

    private func sidebarTitle(for step: Int) -> String {
        switch step {
        case 0: return appStore.localized(.onboardingFlowSidebarStart)
        case 1: return appStore.localized(.onboardingFlowSidebarLayout)
        case 2: return appStore.localized(.onboardingFlowSidebarShortcut)
        default: return appStore.localized(.onboardingFlowSidebarDone)
        }
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(visibleStepPosition) / CGFloat(max(visibleStepTotal, 1))
        return max(18, totalWidth * ratio)
    }

    private var visibleStepSequence: [Int] {
        [0, 1, 2, 3]
    }

    private var visibleStepPosition: Int {
        (visibleStepSequence.firstIndex(of: currentStep) ?? 0) + 1
    }

    private var visibleStepTotal: Int {
        visibleStepSequence.count
    }

    private var isAtFirstVisibleStep: Bool {
        currentStep == (visibleStepSequence.first ?? 0)
    }

    private var isAtLastVisibleStep: Bool {
        currentStep == (visibleStepSequence.last ?? lastStep)
    }

    private func nextStepIndex(from step: Int) -> Int {
        guard let idx = visibleStepSequence.firstIndex(of: step) else { return min(step + 1, lastStep) }
        let nextIdx = min(idx + 1, visibleStepSequence.count - 1)
        return visibleStepSequence[nextIdx]
    }

    private func previousStepIndex(from step: Int) -> Int {
        guard let idx = visibleStepSequence.firstIndex(of: step) else { return max(step - 1, 0) }
        let previousIdx = max(idx - 1, 0)
        return visibleStepSequence[previousIdx]
    }

    private func goToStep(_ target: Int) {
        let normalized = min(max(0, target), lastStep)

        guard normalized != currentStep else { return }

        let currentIndex = visibleStepSequence.firstIndex(of: currentStep) ?? 0
        let targetIndex = visibleStepSequence.firstIndex(of: normalized) ?? currentIndex
        movingForward = targetIndex > currentIndex

        withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18)) {
            currentStep = normalized
        }
    }

    private func evaluateNativeImportAvailabilityIfNeeded() {
        guard !hasCheckedNativeImport else { return }
        hasCheckedNativeImport = true

        let available = NativeLaunchpadImporter.hasImportableNativeLaunchpadDatabase()
        nativeImportAvailable = available
    }

    private func triggerBackgroundPreparationIfNeeded() {
        guard !hasTriggeredBackgroundPreparation else { return }
        hasTriggeredBackgroundPreparation = true
        appStore.performInitialScanIfNeeded()
    }

    private var shouldShowStepSidebar: Bool { currentStep != lastStep }
    private var stepContentHeight: CGFloat {
        if currentStep == 1 {
            return compactLayout ? 360 : 390
        }
        return compactLayout ? 250 : 290
    }
    private var lastStep: Int { 3 }
    private var isBusy: Bool { isImportingSystem || isApplyingPreset }

    private struct StepMotionModifier: ViewModifier {
        let offsetX: CGFloat
        let opacity: Double

        func body(content: Content) -> some View {
            content
                .opacity(opacity)
                .offset(x: offsetX)
        }
    }

    private func importFromSystemLaunchpad() {
        guard !isBusy else { return }
        isImportingSystem = true
        Task {
            let result = await appStore.importFromNativeLaunchpad()
            await MainActor.run {
                statusMessage = result.message
                statusIsError = !result.success
                isImportingSystem = false
                if result.success {
                    goToStep(2)
                }
            }
        }
    }

    private func applyClassicLayoutPreset() {
        guard !isBusy else { return }
        isApplyingPreset = true
        let success = appStore.applyMacOS26PresetLayout()
        statusMessage = success ? appStore.localized(.layoutPresetAppliedMessage) : appStore.localized(.layoutPresetApplyFailedMessage)
        statusIsError = !success
        isApplyingPreset = false
        if success {
            goToStep(2)
        }
    }
}



// MARK: - Keyboard Navigation
extension LaunchpadView {
    private func refreshBackgroundImage(reason: BackgroundImageController.RefreshReason) {
        let window = AppDelegate.shared?.launchpadWindow
        backgroundImageController.refresh(
            for: window?.screen ?? NSScreen.main,
            enabled: appStore.backgroundImageEnabled,
            source: appStore.backgroundImageSource,
            customImagePath: appStore.customBackgroundImagePath,
            unfiltered: appStore.launchpadBackgroundStyle == .unfiltered,
            targetSize: appStore.isFullscreenMode ? nil : window?.contentView?.bounds.size,
            reason: reason
        )
    }

    private func setupWindowShownObserver() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        windowObserver = NotificationCenter.default.addObserver(forName: .launchpadWindowShown, object: nil, queue: .main) { _ in
            isWindowVisible = true
            refreshBackgroundImage(reason: .windowShown)
            isKeyboardNavigationActive = false
            selectedIndex = 0
            isSearchFieldFocused = true
            if !appStore.apps.isEmpty {
                appStore.applyOrderAndFolders()
            }
        }
    }
    
    private func setupWindowHiddenObserver() {
        if let observer = windowHiddenObserver {
            NotificationCenter.default.removeObserver(observer)
            windowHiddenObserver = nil
        }
        windowHiddenObserver = NotificationCenter.default.addObserver(forName: .launchpadWindowHidden, object: nil, queue: .main) { _ in
            isWindowVisible = false
            appStore.layoutRevealRequest = nil
            MainActor.assumeIsolated {
                folderPresentation.dismissImmediately()
                backgroundImageController.windowDidHide()
            }
            selectedIndex = 0
        }
    }
    
    private func setupInitialSelection() {
        if selectedIndex == nil, let firstIndex = filteredItems.indices.first {
            selectedIndex = firstIndex
        }
    }

    private func setupKeyHandlers() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if isFolderOpen {
            if event.keyCode == 53 { // esc
                let closingFolder = appStore.openFolder
                withAnimation(LNAnimations.springFast) {
                    appStore.openFolder = nil
                }
                if let folder = closingFolder,
                   let idx = filteredItems.firstIndex(of: .folder(folder)) {
                    isKeyboardNavigationActive = true
                    selectedIndex = idx
                    let targetPage = idx / config.itemsPerPage
                    if targetPage != appStore.currentPage {
                        appStore.currentPage = targetPage
                    }
                }
                // Restore focus to the search field after closing the folder
                isSearchFieldFocused = true
                return nil
            }
            return event
        }
        
        guard !filteredItems.isEmpty else { return event }
        let code = event.keyCode

        if draggingItem != nil {
            switch code {
            case 123, 124, 125, 126, 48, 36: return nil
            default: return event
            }
        }

        if code == 53 { // esc
            AppDelegate.shared?.hideWindow()
            return nil
        }

        if code == 36 { // return
            if isSearchFieldFocused, isIMEComposing() { return event }

            let trimmedQuery = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                if selectedIndex == nil || !(selectedIndex.map { filteredItems.indices.contains($0) } ?? false) {
                    selectedIndex = filteredItems.indices.first
                }
                if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                    isKeyboardNavigationActive = true
                    let sel = filteredItems[idx]
                    if case .folder = sel {
                        appStore.openFolderActivatedByKeyboard = true
                    }
                    handleItemTap(sel)
                    return nil
                }
                return event
            }

            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }

            if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                let sel = filteredItems[idx]
                if case .folder = sel {
                    appStore.openFolderActivatedByKeyboard = true
                }
                handleItemTap(sel)
                return nil
            }
            return event
        }

        if code == 48 { // tab
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }
            // Keep the original paging behavior once already active (Shift reverses direction)
            let backward = event.modifierFlags.contains(.shift)
            if backward {
                navigateToPreviousPage()
            } else {
                navigateToNextPage()
            }
            setSelectionToPageStart(appStore.currentPage)
            return nil
        }

        // Shift + arrow key pages
        if event.modifierFlags.contains(.shift) {
            switch code {
            case 123: // left arrow - page backward
                guard isKeyboardNavigationActive else { return event }
                navigateToPreviousPage()
                setSelectionToPageStart(appStore.currentPage)
                return nil
            case 124: // right arrow - page forward
                guard isKeyboardNavigationActive else { return event }
                navigateToNextPage()
                setSelectionToPageStart(appStore.currentPage)
                return nil
            default:
                break
            }
        }

        if code == 125 { // down arrow activates navigation first
            if isSearchFieldFocused, isIMEComposing() { return event }
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }
            moveSelection(dx: 0, dy: 1)
            return nil
        }

        if code == 126 { // up arrow
            guard isKeyboardNavigationActive else { return event }
            if let idx = selectedIndex {
                let columns = config.columns
                let itemsPerPage = config.itemsPerPage
                let rowInPage = (idx % itemsPerPage) / columns
                if rowInPage == 0 {
                    isKeyboardNavigationActive = false
                    selectedIndex = nil
                    return nil
                }
            }
            moveSelection(dx: 0, dy: -1)
            return nil
        }

        // Regular arrow-key navigation (only when Shift isn't held)
        if !event.modifierFlags.contains(.shift), let (dx, dy) = arrowDelta(for: code) {
            guard isKeyboardNavigationActive else { return event }
            moveSelection(dx: dx, dy: dy)
            return nil
        }

        return event
    }

    private func handleControllerCommand(_ command: ControllerCommand) {
        guard appStore.gameControllerEnabled else { return }
        guard ControllerInputManager.shared.isActive else { return }

        guard isWindowVisible else { return }
        if appStore.isSetting { return }

        switch command {
        case .move(let direction), .moveRepeat(let direction):
            activateKeyboardNavigationIfNeeded()
            synthesizeKeyDown(keyCode: keyCode(for: direction))
        case .stop(_):
            break
        case .select:
            synthesizeKeyDown(keyCode: 36)
        case .cancel:
            synthesizeKeyDown(keyCode: 53)
        case .menu:
            break
        }
    }

    private func activateKeyboardNavigationIfNeeded() {
        guard !isKeyboardNavigationActive else { return }
        isKeyboardNavigationActive = true
        setSelectionToPageStart(appStore.currentPage)
        clampSelection()
    }

    private func keyCode(for direction: ControllerCommand.Direction) -> UInt16 {
        switch direction {
        case .left: return 123
        case .right: return 124
        case .up: return 126
        case .down: return 125
        }
    }

    private func synthesizeKeyDown(keyCode: UInt16) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }
        _ = handleKeyEvent(event)
    }

    private func moveSelection(dx: Int, dy: Int) {
        guard let current = selectedIndex else { return }
        let columns = config.columns
        let newIndex: Int = dy == 0 ? current + dx : current + dy * columns
        guard filteredItems.indices.contains(newIndex) else { return }
        guard newIndex != current else { return }
        selectedIndex = newIndex
        let item = filteredItems[newIndex]
        SoundManager.shared.play(.navigation)
        VoiceManager.shared.announceSelection(item: item)
        
        let page = newIndex / config.itemsPerPage
        if page != appStore.currentPage {
            navigateToPage(page, animated: true)
        }
    }

    private func setSelectionToPageStart(_ page: Int) {
        let startIndex = page * config.itemsPerPage
        if filteredItems.indices.contains(startIndex) {
            selectedIndex = startIndex
        } else if let last = filteredItems.indices.last {
            selectedIndex = last
        } else {
            selectedIndex = nil
        }
    }

    private func desiredIndexForPageKeepingPosition(targetPage: Int) -> Int? {
        guard let current = selectedIndex else { return nil }
        let columns = config.columns
        let itemsPerPage = config.itemsPerPage
        let currentOffsetInPage = current % itemsPerPage
        let currentRow = currentOffsetInPage / columns
        let currentCol = currentOffsetInPage % columns
        let targetOffset = currentRow * columns + currentCol
        let candidate = targetPage * itemsPerPage + targetOffset

        if filteredItems.indices.contains(candidate) {
            return candidate
        }

        let startOfPage = targetPage * itemsPerPage
        let endExclusive = min((targetPage + 1) * itemsPerPage, filteredItems.count)
        let lastIndexInPage = endExclusive - 1
        return lastIndexInPage >= startOfPage ? lastIndexInPage : nil
    }
}

// MARK: - Key mapping helpers
extension LaunchpadView {
    private func isIMEComposing() -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }
}

// MARK: - Drag math helpers
extension LaunchpadView {
    private func pageOf(index: Int) -> Int { index / config.itemsPerPage }

    private func cellOrigin(for globalIndex: Int,
                            in containerSize: CGSize,
                            pageIndex: Int,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        let columns = config.columns
        let displayedOffsetInPage: Int = {
            guard pages.indices.contains(pageIndex), currentItems.indices.contains(globalIndex) else {
                return globalIndex % config.itemsPerPage
            }
            let pageItems = pages[pageIndex]
            let item = currentItems[globalIndex]
            return pageItems.firstIndex(of: item) ?? (globalIndex % config.itemsPerPage)
        }()
        
        return GeometryUtils.cellOrigin(for: displayedOffsetInPage,
                                      containerSize: containerSize,
                                      pageIndex: pageIndex,
                                      columnWidth: columnWidth,
                                      appHeight: appHeight,
                                      columns: columns,
                                      columnSpacing: config.columnSpacing,
                                      rowSpacing: config.rowSpacing,
                                      pageSpacing: config.pageSpacing,
                                      currentPage: appStore.currentPage)
    }

    private func cellCenter(for globalIndex: Int,
                            in containerSize: CGSize,
                            pageIndex: Int,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        // Cache geometry to avoid repeating layout math.
        let cacheKey = "center_\(globalIndex)_\(pageIndex)_\(containerSize.width)_\(containerSize.height)_\(columnWidth)_\(appHeight)"
        
        // Check whether the cache is still valid
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) < geometryCacheTimeout,
           let cached = Self.geometryCache[cacheKey] {
            return cached
        }
        
        let origin = cellOrigin(for: globalIndex, in: containerSize, pageIndex: pageIndex, columnWidth: columnWidth, appHeight: appHeight)
        let center = CGPoint(x: origin.x + columnWidth / 2, y: origin.y + appHeight / 2)
        
        // Update cache on the next run loop to avoid state writes during layout.
        DispatchQueue.main.async {
            Self.geometryCache[cacheKey] = center
            Self.lastGeometryUpdate = now
        }
        
        return center
    }

    private func indexAt(point: CGPoint,
                         in containerSize: CGSize,
                         pageIndex: Int,
                         columnWidth: CGFloat,
                         appHeight: CGFloat) -> Int? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let pageItems = pages[pageIndex]

        guard let offsetInPage = GeometryUtils.indexAt(point: point,
                                                      containerSize: containerSize,
                                                      pageIndex: pageIndex,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight,
                                                      columns: config.columns,
                                                      columnSpacing: config.columnSpacing,
                                                      rowSpacing: config.rowSpacing,
                                                      pageSpacing: config.pageSpacing,
                                                      currentPage: appStore.currentPage,
                                                      itemsPerPage: config.itemsPerPage,
                                                      pageItems: pageItems) else { return nil }

        let startIndexInCurrentItems = pages.prefix(pageIndex).reduce(0) { $0 + $1.count }
        let globalIndex = startIndexInCurrentItems + offsetInPage
        return currentItems.indices.contains(globalIndex) ? globalIndex : nil
    }

    private func clampPointWithinBounds(_ point: CGPoint, containerSize: CGSize) -> CGPoint {
        let maxX = max(containerSize.width - 0.1, 0)
        let maxY = max(containerSize.height - 0.1, 0)
        let clampedX = min(max(point.x, 0), maxX)
        let clampedY = min(max(point.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func isPointInCenterArea(point: CGPoint,
                                      targetIndex: Int,
                                      containerSize: CGSize,
                                      pageIndex: Int,
                                      columnWidth: CGFloat,
                                      appHeight: CGFloat,
                                      iconSize: CGFloat) -> Bool {
        // Performance optimization: use a cache to avoid redundant computation
        let cacheKey = "centerArea_\(targetIndex)_\(pageIndex)_\(containerSize.width)_\(containerSize.height)_\(columnWidth)_\(appHeight)_\(iconSize)"
        
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) < geometryCacheTimeout,
           let cached = Self.geometryCache[cacheKey] {
            let centerAreaSize = clampedFolderDropZoneSize(iconSize: iconSize, columnWidth: columnWidth, appHeight: appHeight)
            let centerAreaRect = CGRect(
                x: cached.x - centerAreaSize / 2,
                y: cached.y - centerAreaSize / 2,
                width: centerAreaSize,
                height: centerAreaSize
            )
            return centerAreaRect.contains(point)
        }

        let targetCenter = cellCenter(for: targetIndex, in: containerSize, pageIndex: pageIndex, columnWidth: columnWidth, appHeight: appHeight)
        let centerAreaSize = clampedFolderDropZoneSize(iconSize: iconSize, columnWidth: columnWidth, appHeight: appHeight)
        let centerAreaRect = CGRect(
            x: targetCenter.x - centerAreaSize / 2,
            y: targetCenter.y - centerAreaSize / 2,
            width: centerAreaSize,
            height: centerAreaSize
        )

        // Update the cache asynchronously, to avoid mutating state during a view update
        DispatchQueue.main.async {
            Self.geometryCache[cacheKey] = targetCenter
            Self.lastGeometryUpdate = now
        }

        return centerAreaRect.contains(point)
    }

    /// GeometryUtils.indexAt() hit-tests in slabs centered on each cell (it
    /// offsets by spacing/2 before dividing), so the margin from a cell's
    /// center to the boundary with either neighbor is columnWidth/2 +
    /// columnSpacing/2 (and the equivalent on the row axis). An unclamped
    /// merge/create-folder zone (iconSize * folderDropZoneScale) can reach or
    /// exceed that margin — especially at higher scale settings, or in denser
    /// layouts — leaving no point that resolves to a neighboring cell while
    /// sitting outside this cell's own zone. That makes an .insert landing
    /// between two occupied cells (e.g. two folders) unreachable. This is the
    /// same fix as CAGridView+Input.swift's isPointInFolderDropZone, applied
    /// to the handoff drag used to pull an item out of an open folder, which
    /// still runs through this SwiftUI-side drag math regardless of which
    /// grid is rendering.
    private func clampedFolderDropZoneSize(iconSize: CGFloat, columnWidth: CGFloat, appHeight: CGFloat) -> CGFloat {
        let insertMargin: CGFloat = 16
        let maxWidth = columnWidth + config.columnSpacing
        let maxHeight = appHeight + config.rowSpacing
        let maxSide = max(0, min(maxWidth, maxHeight) - insertMargin * 2)
        let scale = CGFloat(appStore.folderDropZoneScale)
        return min(iconSize * scale, maxSide)
    }
}

// MARK: - Drag preview view


// MARK: - Selection Helpers
extension LaunchpadView {
    private func clampSelection() {
        guard isKeyboardNavigationActive else { return }
        let count = filteredItems.count
        if count == 0 {
            selectedIndex = nil
            return
        }
        if let idx = selectedIndex {
            if idx >= count { selectedIndex = count - 1 }
            if idx < 0 { selectedIndex = 0 }
        } else {
            selectedIndex = 0
        }
        
        if let idx = selectedIndex, filteredItems.indices.contains(idx) {
            let page = idx / config.itemsPerPage
            if page != appStore.currentPage {
                navigateToPage(page, animated: true)
            }
        } else {
            selectedIndex = filteredItems.isEmpty ? nil : 0
        }
    }
}

// MARK: - Geometry & Drag helpers
extension LaunchpadView {
    fileprivate func captureGridGeometry(_ geo: GeometryProxy, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        gridOriginInWindow = geo.frame(in: .global).origin
        currentContainerSize = geo.size
        currentColumnWidth = columnWidth
        currentAppHeight = appHeight
        currentIconSize = iconSize
        
        // Performance optimization: clear the stale geometry cache
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) > geometryCacheTimeout * 2 {
            // Clear the cache asynchronously, to avoid mutating state during a view update
            DispatchQueue.main.async {
                Self.geometryCache.removeAll()
                Self.lastGeometryUpdate = now
            }
        }
    }

    fileprivate func flipPageIfNeeded(iconCenter: CGPoint,
                                      pointer: CGPoint,
                                      iconSize: CGFloat,
                                      in containerSize: CGSize) -> Bool {
        let edgeMargin: CGFloat = config.pageNavigation.edgeFlipMargin
        
        // Check the page-flip cooldown state
        pageFlipManager.autoFlipInterval = config.pageNavigation.autoFlipInterval
        guard pageFlipManager.canFlip() else { return false }

        let verticalTolerance = max(iconSize * 0.8, 60)
        if pointer.y < -verticalTolerance || pointer.y > containerSize.height + verticalTolerance {
            return false
        }
                
        if iconCenter.x <= edgeMargin && appStore.currentPage > 0 {
            navigateToPreviousPage()
            pageFlipManager.recordFlip()
            return true
        } else if iconCenter.x >= containerSize.width - edgeMargin {
            // Check whether a new page needs to be created
            let nextPage = appStore.currentPage + 1
            let itemsPerPage = config.itemsPerPage
            let nextPageStart = nextPage * itemsPerPage

            // If dragging onto a new page, make sure there's enough room
            if nextPageStart >= currentItems.count {
                let neededItems = nextPageStart + itemsPerPage - currentItems.count
                for _ in 0..<neededItems {
                    appStore.items.append(.empty(UUID().uuidString))
                }
            }
            
            navigateToNextPage()
            pageFlipManager.recordFlip()
            return true
        }
        
        return false
    }

    fileprivate func predictedDropIndex(for pointer: CGPoint, in containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat) -> Int? {
        let queryPoint = appStore.enableDropPrediction
            ? clampPointWithinBounds(pointer, containerSize: containerSize)
            : pointer

        if let predicted = indexAt(point: queryPoint,
                                   in: containerSize,
                                   pageIndex: appStore.currentPage,
                                   columnWidth: columnWidth,
                                   appHeight: appHeight) {
            return predicted
        }
        
        let edgeMargin: CGFloat = config.pageNavigation.edgeFlipMargin
        let itemsPerPage = config.itemsPerPage
        
        if queryPoint.x <= edgeMargin && appStore.currentPage > 0 {
            let prevPage = appStore.currentPage - 1
            let prevPageStart = prevPage * itemsPerPage
            let prevPageEnd = min(prevPageStart + itemsPerPage, currentItems.count)
            return max(prevPageStart, prevPageEnd - 1)
        } else if queryPoint.x >= containerSize.width - edgeMargin {
            let nextPage = appStore.currentPage + 1
            let nextPageStart = nextPage * itemsPerPage

            // If dragging onto a new page, make sure it correctly predicts the new page's first position
            if nextPageStart >= currentItems.count {
                // Dragging onto a brand-new page, return that page's first position
                return nextPageStart
            } else {
                return min(nextPageStart, currentItems.count - 1)
            }
        } else {
            if queryPoint.x <= edgeMargin {
                return appStore.currentPage * itemsPerPage
            } else {
                let currentPageEnd = min((appStore.currentPage + 1) * itemsPerPage, currentItems.count)
                return max(appStore.currentPage * itemsPerPage, currentPageEnd - 1)
            }
        }
    }
}

struct GridConfig {
    let isFullscreen: Bool
    private let columnCount: Int
    private let rowCount: Int
    private let columnSpacingValue: CGFloat
    private let rowSpacingValue: CGFloat

    init(isFullscreen: Bool = false,
         columns: Int = 7,
         rows: Int = 5,
         columnSpacing: CGFloat = 20,
         rowSpacing: CGFloat = 14) {
        self.isFullscreen = isFullscreen
        self.columnCount = max(1, columns)
        self.rowCount = max(1, rows)
        self.columnSpacingValue = max(0, columnSpacing)
        self.rowSpacingValue = max(0, rowSpacing)
    }

    var itemsPerPage: Int { columnCount * rowCount }
    var columns: Int { columnCount }
    var rows: Int { rowCount }
    var columnSpacing: CGFloat { columnSpacingValue }
    var rowSpacing: CGFloat { rowSpacingValue }

    let maxBounce: CGFloat = 80
    let pageSpacing: CGFloat = 80

    struct PageNavigation {
        let edgeFlipMargin: CGFloat = 15
        let autoFlipInterval: TimeInterval = 0.8 // 0.8s between two consecutive edge-drag page flips
        let scrollPageThreshold: CGFloat = 0.75
        let scrollFinishThreshold: CGFloat = 0.5
    }
    
    let pageNavigation = PageNavigation()
    let folderCreateDwell: TimeInterval = 0
    
    var horizontalPadding: CGFloat { isFullscreen ? 0.04 : 0 }
    var topPadding: CGFloat { isFullscreen ? 0.035 : 0 }
    var bottomPadding: CGFloat { isFullscreen ? 0.024 : 0 }
    
    var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: columns)
    }
}

// MARK: - Drag preview view
struct DragPreviewItem: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let labelWidth: CGFloat
    var scale: CGFloat = 1.2

    // Performance optimization: use a computed property to avoid state mutation
    private var displayIcon: NSImage {
        switch item {
        case .app(let app):
            let pathExists = FileManager.default.fileExists(atPath: app.url.path)
            let icon = IconStore.shared.icon(for: app)
            if pathExists && icon.size.width > 0 && icon.size.height > 0 {
                return icon
            }
            return MissingAppPlaceholder.defaultIcon
        case .missingApp(let placeholder):
            let pathExists = FileManager.default.fileExists(atPath: placeholder.bundlePath)
            let icon = placeholder.icon
            if pathExists && icon.size.width > 0 && icon.size.height > 0 {
                return icon
            }
            return MissingAppPlaceholder.defaultIcon
        case .folder(let folder):
            return folder.icon(of: iconSize)
        case .empty:
            return item.icon
        }
    }

    private var isMissing: Bool {
        switch item {
        case .missingApp:
            return true
        case .app(let app):
            return !FileManager.default.fileExists(atPath: app.url.path)
        default:
            return false
        }
    }

    var body: some View {
        switch item {
        case .app(let app):
            VStack(spacing: 6) {
                Image(nsImage: displayIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(isMissing ? 0.65 : 1.0)
                    .overlay(alignment: .topTrailing) {
                        if isMissing {
                            Circle()
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: iconSize * 0.22, height: iconSize * 0.22)
                                .overlay(
                                    Image(systemName: "exclamationmark")
                                        .font(.system(size: iconSize * 0.14, weight: .bold))
                                        .foregroundStyle(Color.white)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(iconSize * 0.1)
                        }
                    }
                Text(app.name)
                    .font(.default)
                    .foregroundColor(isMissing ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)

        case .missingApp(let placeholder):
            VStack(spacing: 6) {
                Image(nsImage: displayIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(0.65)
                    .overlay(
                        Circle()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: iconSize * 0.22, height: iconSize * 0.22)
                            .overlay(
                                Image(systemName: "exclamationmark")
                                    .font(.system(size: iconSize * 0.14, weight: .bold))
                                    .foregroundStyle(Color.white)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(iconSize * 0.1)
                    )
                Text(placeholder.displayName)
                    .font(.default)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)

        case .folder(let folder):
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .foregroundStyle(Color.clear)
                        .frame(width: iconSize * 0.8, height: iconSize * 0.8)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: iconSize * 0.2))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: iconSize * 0.2)
                                .stroke(Color.launchpadBorder.opacity(0.5), lineWidth: 1)
                        )
                    Image(nsImage: folder.icon(of: iconSize))
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: iconSize, height: iconSize)
                }
                
                Text(folder.name)
                    .font(.default)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)
            
        case .empty:
            EmptyView()
        }
    }
}

func arrowDelta(for keyCode: UInt16) -> (dx: Int, dy: Int)? {
    switch keyCode {
    case 123: return (-1, 0) // left
    case 124: return (1, 0)  // right
    case 126: return (0, -1) // up
    case 125: return (0, 1)  // down
    default: return nil
    }
}

// MARK: - Cache management extension

extension LaunchpadView {
    // Unified drag-end handling logic (shared by normal and handoff drags)
    private func finalizeDragOperation(containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        guard let dragging = draggingItem else { return }
        defer { dragPointerOffset = .zero }

        if appStore.isLayoutLocked {
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            pendingDropIndex = nil
            return
        }

        // Handle folder-creation logic
        if appStore.isDragCreatingFolder, case .app(let app) = dragging {
            if let targetApp = appStore.folderCreationTarget {
                if let insertAt = filteredItems.firstIndex(of: .app(targetApp)) {
                    let newFolder = appStore.createFolder(with: [app, targetApp], insertAt: insertAt)
                    if let folderIndex = filteredItems.firstIndex(of: .folder(newFolder)) {
                        let targetCenter = cellCenter(for: folderIndex,
                                                      in: containerSize,
                                                      pageIndex: appStore.currentPage,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight)
                        withAnimation(LNAnimations.springFast) {
                            dragPreviewPosition = targetCenter
                            dragPreviewScale = 1.0
                        }
                    }
                } else {
                    let newFolder = appStore.createFolder(with: [app, targetApp])
                    if let folderIndex = filteredItems.firstIndex(of: .folder(newFolder)) {
                        let targetCenter = cellCenter(for: folderIndex,
                                                      in: containerSize,
                                                      pageIndex: appStore.currentPage,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight)
                        withAnimation(LNAnimations.springFast) {
                            dragPreviewPosition = targetCenter
                            dragPreviewScale = 1.0
                        }
                    }
                }
            } else {
                let pointerPoint = dragPreviewPosition
                if let hoveringIndex = indexAt(point: pointerPoint,
                                               in: containerSize,
                                               pageIndex: appStore.currentPage,
                                               columnWidth: columnWidth,
                                               appHeight: appHeight),
                   filteredItems.indices.contains(hoveringIndex),
                   case .folder(let folder) = filteredItems[hoveringIndex] {
                    appStore.addAppToFolder(app, folder: folder)
                    let targetCenter = cellCenter(for: hoveringIndex,
                                                  in: containerSize,
                                                  pageIndex: appStore.currentPage,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight)
                    withAnimation(LNAnimations.springFast) {
                        dragPreviewPosition = targetCenter
                        dragPreviewScale = 1.0
                    }
                }
            }
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            return
        }
        
        // Handle normal drag logic
        if let finalIndex = pendingDropIndex,
           let _ = filteredItems.firstIndex(of: dragging) {
            // Check whether this is a cross-page drag
            let sourceIndexInItems = appStore.items.firstIndex(of: dragging) ?? 0
            let targetPage = finalIndex / config.itemsPerPage
            let sourcePage = sourceIndexInItems / config.itemsPerPage

            // Visually snap to the target cell's center
            let dropDisplayIndex = finalIndex
            let finalPage = pageOf(index: dropDisplayIndex)
            let targetCenter = cellCenter(for: dropDisplayIndex,
                                          in: containerSize,
                                          pageIndex: finalPage,
                                          columnWidth: columnWidth,
                                          appHeight: appHeight)
            withAnimation(LNAnimations.springFast) {
                dragPreviewPosition = targetCenter
                dragPreviewScale = 1.0
            }
            
            if targetPage == sourcePage {
                // Moving within the same page: use the existing in-page reordering logic
                let pageStart = (finalIndex / config.itemsPerPage) * config.itemsPerPage
                let pageEnd = min(pageStart + config.itemsPerPage, appStore.items.count)
                var newItems = appStore.items
                var pageSlice = Array(newItems[pageStart..<pageEnd])
                let localFrom = sourceIndexInItems - pageStart
                let moving = pageSlice.remove(at: localFrom)
                let desiredLocal = max(0, finalIndex - pageStart)
                let clampedLocal = min(desiredLocal, pageSlice.count)
                pageSlice.insert(moving, at: clampedLocal)
                newItems.replaceSubrange(pageStart..<pageEnd, with: pageSlice)
                withAnimation(LNAnimations.springFast) {
                    appStore.items = newItems
                }
                appStore.triggerGridRefresh()
                appStore.saveAllOrder()
                
                // Also compact after a within-page drag ends, so empty items move to the end of the page
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appStore.compactItemsWithinPages()
                }
            } else {
                // Cross-page drag: use the cascading-insert logic
                appStore.moveItemAcrossPagesWithCascade(item: dragging, to: finalIndex)
            }
        } else {
            // Fallback logic: if there's no valid target index, place the app at the end of the current page
            if filteredItems.contains(dragging) {
                let currentPageStart = appStore.currentPage * config.itemsPerPage
                let currentPageEnd = min(currentPageStart + config.itemsPerPage, appStore.items.count)
                let targetIndex = currentPageEnd

                // Use the cascading insert to place the app correctly
                appStore.moveItemAcrossPagesWithCascade(item: dragging, to: targetIndex)
            }
        }
    }

    // Unified drag-update logic (shared by normal and handoff drags)
    private func applyDragUpdate(at point: CGPoint,
                                 containerSize: CGSize,
                                 columnWidth: CGFloat,
                                 appHeight: CGFloat,
                                 iconSize: CGFloat) {
        guard !appStore.isLayoutLocked else { return }
        let rawIconCenter = CGPoint(x: point.x - dragPointerOffset.x,
                                     y: point.y - dragPointerOffset.y)
        var iconCenter = rawIconCenter
        var hoverPoint = rawIconCenter
        if appStore.enableDropPrediction {
            let clamped = clampPointWithinBounds(rawIconCenter, containerSize: containerSize)
            iconCenter = clamped
            hoverPoint = clamped
        }
        // Performance optimization: reduce overly frequent position updates
        let distance = sqrt(pow(dragPreviewPosition.x - iconCenter.x, 2) + pow(dragPreviewPosition.y - iconCenter.y, 2))
        if distance < 2.0 { return } // Skip the update if the movement is under 2 pixels

        dragPreviewPosition = iconCenter

        // Performance optimization: throttle to reduce computation frequency
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) < 0.016 { // About 60fps
            return
        }
        
        Self.lastGeometryUpdate = now
        
        if let hoveringIndex = indexAt(point: hoverPoint,
                                       in: containerSize,
                                       pageIndex: appStore.currentPage,
                                       columnWidth: columnWidth,
                                       appHeight: appHeight),
           currentItems.indices.contains(hoveringIndex) {
            handleHoveringLogic(hoveringIndex: hoveringIndex, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
        } else {
            clearHoveringState()
        }

        if flipPageIfNeeded(iconCenter: iconCenter,
                            pointer: point,
                            iconSize: iconSize,
                            in: containerSize) {
            let dropPoint = appStore.enableDropPrediction ? iconCenter : point
            pendingDropIndex = predictedDropIndex(for: dropPoint,
                                                  in: containerSize,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight)
        }
    }
    
    private func handleHoveringLogic(hoveringIndex: Int, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        let hoveringItem = currentItems[hoveringIndex]
        guard pageOf(index: hoveringIndex) == appStore.currentPage else {
            clearHoveringState()
            return
        }

        let pointerPoint = dragPreviewPosition
        let isInCenterArea = isPointInCenterArea(
            point: pointerPoint,
            targetIndex: hoveringIndex,
            containerSize: currentContainerSize,
            pageIndex: appStore.currentPage,
            columnWidth: columnWidth,
            appHeight: appHeight,
            iconSize: iconSize
        )

        guard let dragging = draggingItem else { return }

        switch hoveringItem {
        case .app(let targetApp):
            handleAppHover(dragging: dragging, targetApp: targetApp, hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea)
        case .missingApp(let placeholder):
            handleMissingHover(dragging: dragging,
                                placeholder: placeholder,
                                hoveringIndex: hoveringIndex,
                                isInCenterArea: isInCenterArea)
        case .folder(_):
            handleFolderHover(dragging: dragging, hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea)
        case .empty:
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            pendingDropIndex = hoveringIndex
        }
    }

    private func handleAppHover(dragging: LaunchpadItem, targetApp: AppInfo, hoveringIndex: Int, isInCenterArea: Bool) {
        if dragging == .app(targetApp) {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        } else if case .app = dragging {
            handleAppToAppHover(hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea, targetApp: targetApp)
        } else {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        }
    }

    private func handleMissingHover(dragging: LaunchpadItem,
                                     placeholder: MissingAppPlaceholder,
                                     hoveringIndex: Int,
                                     isInCenterArea: Bool) {
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        if case .missingApp(let draggingPlaceholder) = dragging,
           draggingPlaceholder.id == placeholder.id {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        } else {
            pendingDropIndex = hoveringIndex
        }
    }
    
    private func handleAppToAppHover(hoveringIndex: Int, isInCenterArea: Bool, targetApp: AppInfo) {
        let now = Date()
        let candidateChanged = folderHoverCandidateIndex != hoveringIndex || !isInCenterArea
        
        if candidateChanged {
            folderHoverCandidateIndex = isInCenterArea ? hoveringIndex : nil
            folderHoverBeganAt = isInCenterArea ? now : nil
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
        }
        
        if isInCenterArea {
            appStore.isDragCreatingFolder = true
            appStore.folderCreationTarget = targetApp
            pendingDropIndex = nil
        } else {
            if !isInCenterArea || folderHoverCandidateIndex == nil {
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
                pendingDropIndex = hoveringIndex
            } else {
                pendingDropIndex = nil
            }
        }
    }
    
    private func handleFolderHover(dragging: LaunchpadItem, hoveringIndex: Int, isInCenterArea: Bool) {
        if case .app = dragging {
            let now = Date()
            let candidateChanged = folderHoverCandidateIndex != hoveringIndex || !isInCenterArea
            
            if candidateChanged {
                folderHoverCandidateIndex = isInCenterArea ? hoveringIndex : nil
                folderHoverBeganAt = isInCenterArea ? now : nil
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
            }
            
            if isInCenterArea {
                appStore.isDragCreatingFolder = true
                appStore.folderCreationTarget = nil
                pendingDropIndex = nil
            } else {
                if !isInCenterArea || folderHoverCandidateIndex == nil {
                    appStore.isDragCreatingFolder = false
                    appStore.folderCreationTarget = nil
                    pendingDropIndex = hoveringIndex
                } else {
                    pendingDropIndex = nil
                }
            }
        } else {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        }
    }
    
    private func clearHoveringState() {
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        pendingDropIndex = nil
        folderHoverCandidateIndex = nil
        folderHoverBeganAt = nil
    }
    
    // Performance-monitoring helper function
    private func measurePerformance<T>(_ operation: String, _ block: () -> T) -> T {
        guard enablePerformanceMonitoring else { return block() }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        performanceMetrics[operation] = timeElapsed
        if timeElapsed > 0.016 { // Over 16ms (the 60fps threshold)
            print("⚠️ Performance warning: \(operation) took \(String(format: "%.3f", timeElapsed * 1000))ms")
        }
        
        return result
    }
}
