import SwiftUI
import AppKit
import Combine

struct FolderView: View {
    @ObservedObject var appStore: AppStore
    @Binding var folder: FolderInfo
    // If provided, forces the same icon size as the outer view
    var preferredIconSize: CGFloat? = nil
    var presentationState: CAFolderPresentationState? = nil
    var labelColorOverride: NSColor? = nil
    var labelShadow: BackgroundLabelContrast.Shadow = .none
    var initialRevealAppPath: String? = nil
    @State private var folderName: String = ""
    @State private var isEditingName = false
    @State private var forceRefreshTrigger: UUID = UUID()
    @State private var folderCurrentPage: Int = 0
    @State private var folderPageCount: Int = 1
    @State private var folderVerticalScrollOffset: CGFloat = 0
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var reorderNamespaceFolder
    // Keyboard navigation
    @State private var selectedIndex: Int? = nil
    @State private var isKeyboardNavigationActive: Bool = false
    @State private var keyMonitor: Any?
    // Drag-related state
    @State private var draggingApp: AppInfo? = nil
    @State private var dragPreviewPosition: CGPoint = .zero
    @State private var dragPreviewScale: CGFloat = 1.2
    @State private var pendingDropIndex: Int? = nil
    @State private var scrollOffsetY: CGFloat = 0
    @State private var outOfBoundsBeganAt: Date? = nil
    @State private var hasHandedOffDrag: Bool = false
    private let outOfBoundsDwell: TimeInterval = 0.0
    
    let onClose: () -> Void
    let onLaunchApp: (AppInfo) -> Void

    private func canLaunch(_ app: AppInfo) -> Bool {
        FileManager.default.fileExists(atPath: app.url.path)
    }
    
    // Tuned spacing and layout parameters
    private let spacing: CGFloat = 30
    // Dynamic column count, adapted to window width and the cell's minimum width
    @State private var columnsCount: Int = 4
    private let gridPadding: CGFloat = 16
    private let titlePadding: CGFloat = 16
    private let folderTitleHeight: CGFloat = 72

    private var visualApps: [AppInfo] {
        guard let dragging = draggingApp, let pending = pendingDropIndex else { return folder.apps }
        var apps = folder.apps
        if let from = apps.firstIndex(of: dragging) {
            apps.remove(at: from)
            let insertIndex = pending
            let clamped = min(max(0, insertIndex), apps.count)
            apps.insert(dragging, at: clamped)
        }
        return apps
    }
    
    var body: some View {
        folderContent
        .padding()
        .modifier(FolderSurfaceModifier(isNativePresentation: presentationState != nil))
        .onTapGesture {
            // Exit edit mode if the name is being edited when a non-editing area of the folder view is tapped
            if isEditingName {
                finishEditing()
            }
        }
        .onAppear {
            resetFolderPagingState()
            folderName = folder.name
            setupKeyHandlers()
            setupInitialSelection()
            // If the folder was opened via the Return key, automatically enable navigation and select the first item
            if appStore.openFolderActivatedByKeyboard {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                appStore.openFolderActivatedByKeyboard = false
            } else {
                isKeyboardNavigationActive = false
            }
            if let path = initialRevealAppPath,
               let index = folder.apps.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                selectedIndex = index
                isKeyboardNavigationActive = false
            }
            consumeRenameRequestIfNeeded()
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if !focused && isEditingName {
                finishEditing()
            }
        }
        .onChange(of: folder.apps) {
            clampSelection()
            // Force a view refresh whenever the app list changes
            forceRefreshTrigger = UUID()
        }
        .onChange(of: folder.id) {
            resetFolderPagingState()
        }
        .onChange(of: appStore.folderLayoutMode) {
            resetFolderPagingState()
        }
        .onChange(of: appStore.voiceFeedbackEnabled) { _, enabled in
            if enabled {
                announceSelectedAppIfNeeded()
            } else {
                VoiceManager.shared.stop()
            }
        }
        .onChange(of: folder.name) {
            // Watch for folder name changes to keep the UI updated immediately
            if !isEditingName {
                folderName = folder.name
                // Force a view refresh
                forceRefreshTrigger = UUID()
            }
        }
        .onChange(of: appStore.folderUpdateTrigger) {
            // Force a folder view refresh so icons and names show the latest state
            forceRefreshTrigger = UUID()
            // Trigger a re-render
            folderName = folder.name
        }
        .onChange(of: appStore.gridRefreshTrigger) {
            // Force a grid view refresh so app icons and layout show the latest state
            forceRefreshTrigger = UUID()
            // Trigger a re-render
            folderName = folder.name
        }
        .onChange(of: appStore.folderRenameRequestID) {
            consumeRenameRequestIfNeeded()
        }
        .onReceive(ControllerInputManager.shared.commands.receive(on: RunLoop.main)) { command in
            handleControllerCommand(command)
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        if shouldScrollFolderTitleWithContent {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    appGridSection(geometry: geo)

                    folderTitleSection
                        .frame(height: folderTitleHeight)
                        .offset(y: -min(folderVerticalScrollOffset, folderTitleHeight))
                        .opacity(folderTitleOpacity)
                        .allowsHitTesting(folderVerticalScrollOffset < folderTitleHeight || isEditingName)
                }
            }
        } else {
            VStack(spacing: 0) {
                folderTitleSection
                    .frame(height: folderTitleHeight)

                GeometryReader { geo in
                    appGridSection(geometry: geo)
                }

                if shouldShowFolderPageIndicator {
                    folderPageIndicator
                }
            }
        }
    }
    
    @ViewBuilder
    private var folderTitleSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                if isEditingName {
                    TextField(appStore.localized(.folderNamePlaceholder), text: $folderName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.title)
                        .foregroundColor(labelColorOverride.map { Color(nsColor: $0) } ?? .primary)
                        .shadow(color: .black.opacity(Double(labelShadow.opacity)),
                            radius: labelShadow.radius, x: 0, y: labelShadow.offset)
                        .focused($isTextFieldFocused)
                        .padding()
                        .onSubmit {
                            finishEditing()
                        }
                        .onTapGesture(count: 2) {
                            finishEditing()
                        }
                        .onTapGesture {
                            finishEditing()
                        }
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    // Stop the tap on the edit field from bubbling up to the parent view
                                }
                        )
                } else {
                    Text(folder.name)
                        .font(.title)
                        .foregroundColor(labelColorOverride.map { Color(nsColor: $0) } ?? .primary)
                        .shadow(color: .black.opacity(Double(labelShadow.opacity)),
                            radius: labelShadow.radius, x: 0, y: labelShadow.offset)
                        .padding()
                        .contentShape(Rectangle()) // Make sure the whole area is tappable
                        .onTapGesture(count: 2) {
                            startEditing()
                        }
                        .onTapGesture {
                            // Do nothing on a single tap, to avoid triggering this by accident
                        }
                        .id(forceRefreshTrigger) // Force a refresh via forceRefreshTrigger
                }
            }
            Spacer()
        }
        .padding(.horizontal, titlePadding)
    }

    private var shouldShowFolderPageIndicator: Bool {
        appStore.useCAGridRenderer && appStore.folderLayoutMode == .paged && folderPageCount > 1
    }

    private var shouldScrollFolderTitleWithContent: Bool {
        appStore.useCAGridRenderer && appStore.folderLayoutMode == .vertical
    }

    private var folderTitleOpacity: Double {
        if isEditingName { return 1 }
        let fadeStart = folderTitleHeight * 0.45
        let fadeRange = max(folderTitleHeight * 0.55, 1)
        let progress = min(max((folderVerticalScrollOffset - fadeStart) / fadeRange, 0), 1)
        return Double(1 - progress)
    }

    private var safeFolderCurrentPage: Int {
        min(max(0, folderCurrentPage), max(folderPageCount - 1, 0))
    }

    private var folderPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<folderPageCount, id: \.self) { index in
                Circle()
                    .fill((labelColorOverride.map { Color(nsColor: $0) } ?? .gray)
                        .opacity(safeFolderCurrentPage == index ? 1 : (labelColorOverride == nil ? 0.3 : 0.55)))
                    .frame(width: 8, height: 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        folderCurrentPage = index
                    }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func resetFolderPagingState() {
        folderCurrentPage = 0
        folderPageCount = 1
        folderVerticalScrollOffset = 0
    }
    
    @ViewBuilder
    private func appGridSection(geometry geo: GeometryProxy) -> some View {
        // Initial estimate (using the current column count)
        let baseColumnWidth = computeColumnWidth(containerWidth: geo.size.width, columns: columnsCount)
        let baseAppHeight = computeAppHeight(containerHeight: geo.size.height, columns: columnsCount)
        let computedIcon = min(baseColumnWidth, baseAppHeight) * 0.75
        let iconSize: CGFloat = preferredIconSize ?? computedIcon
        // Fixed at 6 columns (restores the folder's original internal layout)
        let desiredColumns = 6
        // Recompute the size using the adaptive column count
        let recomputedColumnWidth = computeColumnWidth(containerWidth: geo.size.width, columns: desiredColumns)
        let recomputedAppHeight = computeAppHeight(containerHeight: geo.size.height, columns: desiredColumns)
        // Make sure each cell can hold at least the given icon size plus the label area
        let columnWidth = max(recomputedColumnWidth, iconSize)
        let appHeight = max(recomputedAppHeight, iconSize + 32)
        let labelWidth: CGFloat = columnWidth * 0.9

        if appStore.useCAGridRenderer {
            CAFolderGridViewRepresentable(
                appStore: appStore,
                folder: $folder,
                currentPage: $folderCurrentPage,
                pageCount: $folderPageCount,
                verticalScrollOffset: $folderVerticalScrollOffset,
                iconSize: iconSize,
                verticalHeaderHeight: shouldScrollFolderTitleWithContent ? folderTitleHeight : 0,
                onClose: onClose,
                onLaunchApp: onLaunchApp,
                presentationState: presentationState,
                labelColorOverride: labelColorOverride,
                labelShadow: labelShadow,
                initialRevealAppPath: initialRevealAppPath
            )
            .id("ca_folder_grid_\(folder.id)_\(appStore.folderLayoutMode.rawValue)")
            .onAppear { columnsCount = desiredColumns }
        } else {
            ZStack(alignment: .topLeading) {
            ScrollViewReader { reader in
            ScrollView {
                ScrollOffsetReader { offsetY in
                    scrollOffsetY = offsetY
                }
                .frame(height: 0)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: desiredColumns), spacing: spacing) {
                    ForEach(Array(visualApps.enumerated()), id: \.element.id) { (idx, app) in
                        appDraggable(
                            app: app,
                            appIndex: idx,
                            containerSize: geo.size,
                            columnWidth: columnWidth,
                            appHeight: appHeight,
                            iconSize: iconSize,
                            labelWidth: labelWidth,
                            isSelected: isKeyboardNavigationActive && selectedIndex == idx
                        )
                        .id(app.url.standardizedFileURL.path)
                    }
                }
                .animation(LNAnimations.gridUpdate, value: pendingDropIndex)
                .id(forceRefreshTrigger) // Force the app grid to refresh via forceRefreshTrigger
                .padding(EdgeInsets(top: gridPadding, leading: gridPadding, bottom: gridPadding, trailing: gridPadding))
            }
            .scrollIndicators(.hidden)
            .disabled(isEditingName) // Disable scrolling while editing
            .onAppear { columnsCount = desiredColumns }
            .onChange(of: geo.size) { _, _ in columnsCount = desiredColumns }
            .onAppear {
                if let path = initialRevealAppPath { reader.scrollTo(path, anchor: .center) }
            }
            }

            // Drag preview layer
            if let draggingApp {
                DragPreviewItem(item: .app(draggingApp),
                                iconSize: iconSize,
                                labelWidth: labelWidth,
                                scale: dragPreviewScale)
                    .position(x: dragPreviewPosition.x, y: dragPreviewPosition.y)
                    .zIndex(100)
                    .allowsHitTesting(false)
            }
        }
            .coordinateSpace(name: "folderGrid")
        }
    }
    
    // Visual drag reordering

    private func startEditing() {
        isEditingName = true
        folderName = folder.name
        isTextFieldFocused = true
        appStore.isFolderNameEditing = true
    }

    private func consumeRenameRequestIfNeeded() {
        guard appStore.folderRenameRequestID == folder.id else { return }
        appStore.folderRenameRequestID = nil
        DispatchQueue.main.async {
            startEditing()
        }
    }
    
    private func finishEditing() {
        isEditingName = false
        appStore.isFolderNameEditing = false
        // Allow the name to be made of pure spaces (a user-chosen visual placeholder); only block a fully empty string
        if !folderName.isEmpty {
            let newName = folderName
            if newName != folder.name {
                appStore.renameFolder(folder, newName: newName)
            }
        } else {
            folderName = folder.name
        }
    }
    
}

// MARK: - Drag helpers & builders (mirror outer logic, without folder creation)
extension FolderView {
    private func computeAppHeight(containerHeight: CGFloat, columns: Int) -> CGFloat {
        // Estimate row height under the adaptive column count
        let maxRowsPerPage = Int(ceil(Double(folder.apps.count) / Double(max(columns, 1))))
        let totalRowSpacing = spacing * CGFloat(max(0, maxRowsPerPage - 1))
        let height = (containerHeight - totalRowSpacing) / CGFloat(maxRowsPerPage == 0 ? 1 : maxRowsPerPage)
        return max(60, min(120, height)) // Clamp to a reasonable height range
    }

    private func computeColumnWidth(containerWidth: CGFloat, columns: Int) -> CGFloat {
        let cols = max(columns, 1)
        let totalColumnSpacing = spacing * CGFloat(max(0, cols - 1))
        let width = (containerWidth - totalColumnSpacing) / CGFloat(cols)
        return max(50, width) // Clamp to a reasonable minimum width
    }

    // Drag hit-testing and cell geometry (implemented in the extension below)

    @ViewBuilder
    private func appDraggable(app: AppInfo,
                              appIndex: Int,
                              containerSize: CGSize,
                              columnWidth: CGFloat,
                              appHeight: CGFloat,
                              iconSize: CGFloat,
                              labelWidth: CGFloat,
                              isSelected: Bool) -> some View {
        let base = LaunchpadItemButton(
            item: .app(app),
            iconSize: iconSize,
            labelWidth: labelWidth,
            isSelected: isSelected,
            showLabel: appStore.showLabels,
            labelFontSize: CGFloat(appStore.iconLabelFontSize),
            labelFontWeight: appStore.iconLabelFontWeightValue,
            shouldAllowHover: draggingApp == nil,
            hoverMagnificationEnabled: appStore.enableHoverMagnification,
            hoverMagnificationScale: CGFloat(appStore.hoverMagnificationScale),
            activePressEffectEnabled: appStore.enableActivePressEffect,
            activePressScale: CGFloat(appStore.activePressScale),
            onTap: {
                // Don't launch the app while editing
                if draggingApp == nil && !isEditingName {
                    if canLaunch(app) {
                        onLaunchApp(app)
                    } else {
                        NSSound.beep()
                    }
                }
            }
        )
        .frame(height: appHeight)
        // matchedGeometryEffect removed to reduce scrolling overhead

        let isDraggingThisTile = (draggingApp == app)

        if appStore.isLayoutLocked {
            base
                .launchNGHideAppContextMenu(app: app, appStore: appStore)
        } else {
            base
                .opacity(isDraggingThisTile ? 0 : 1)
                .allowsHitTesting(!isDraggingThisTile)
                .animation(LNAnimations.springFast, value: isSelected)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("folderGrid"))
                        .onChanged { value in
                            guard !appStore.isLayoutLocked else { return }
                            // Disable dragging while editing
                            if isEditingName { return }

                        if draggingApp == nil {
                            var tx = Transaction(); tx.disablesAnimations = true
                            withTransaction(tx) { draggingApp = app }
                            isKeyboardNavigationActive = false // Disable keyboard navigation

                            // Keep the drag preview's center matching the pointer position, avoiding any offset
                            dragPreviewPosition = value.location
                        }

                        // The preview follows the pointer position (no starting offset), keeping the cursor aligned with the icon's center
                        dragPreviewPosition = value.location

                        // Detect whether the drag has left the folder's bounds and is dwelling there
                        let isOutside: Bool = (value.location.x < 0 || value.location.y < 0 ||
                                               value.location.x > containerSize.width ||
                                               value.location.y > containerSize.height)
                        let now = Date()
                        if isOutside {
                            if outOfBoundsBeganAt == nil { outOfBoundsBeganAt = now }
                            if !hasHandedOffDrag, let start = outOfBoundsBeganAt, now.timeIntervalSince(start) >= outOfBoundsDwell, let dragging = draggingApp {
                                // Hand off to the outer grid: move the app out of the folder and close the folder
                                hasHandedOffDrag = true
                                pendingDropIndex = nil
                                appStore.handoffDraggingApp = dragging
                                appStore.handoffDragScreenLocation = NSEvent.mouseLocation
                                appStore.removeAppFromFolder(dragging, folder: folder)
                                // Clean up the internal drag state and close the folder
                                draggingApp = nil
                                outOfBoundsBeganAt = nil
                                withAnimation(LNAnimations.springFast) {
                                    onClose()
                                }
                                return
                            }
                        } else {
                            outOfBoundsBeganAt = nil
                        }

                        if let hoveringIndex = indexAt(point: dragPreviewPosition,
                                                       containerSize: containerSize,
                                                       columnWidth: columnWidth,
                                                       appHeight: appHeight) {
                            // Treat "hovering over the last cell" as inserting at the end, pushing the last item forward to make room
                            let count = visualApps.count
                            if count > 0,
                               hoveringIndex == count - 1,
                               let dragging = draggingApp,
                               dragging != visualApps[hoveringIndex] {
                                pendingDropIndex = count // Trailing slot
                            } else {
                                // If the hit is the "trailing slot" (== count), keep it as count; otherwise it's a cell index
                                pendingDropIndex = hoveringIndex
                            }
                        } else {
                            pendingDropIndex = nil
                        }
                    }
                    .onEnded { _ in
                        if appStore.isLayoutLocked { return }
                        // Don't process the end of a drag while editing
                        if isEditingName { return }
                        
                        guard let dragging = draggingApp else { return }
                        defer {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                draggingApp = nil
                                pendingDropIndex = nil
                                // Don't automatically restore keyboard navigation after a drag ends, to keep the experience consistent
                            }
                        }

                        // If the drag was already handed off to the outer grid, don't process the drop here
                        if hasHandedOffDrag {
                            hasHandedOffDrag = false
                            outOfBoundsBeganAt = nil
                            return
                        }

                        if let finalIndex = pendingDropIndex {
                            // Visual snap position: use finalIndex directly, to snap accurately to the target position
                            let dropDisplayIndex = finalIndex
                            let targetCenter = cellCenter(for: dropDisplayIndex,
                                                          containerSize: containerSize,
                                                          columnWidth: columnWidth,
                                                          appHeight: appHeight)
                            withAnimation(LNAnimations.dragPreview) {
                                dragPreviewPosition = targetCenter
                                dragPreviewScale = 1.0
                            }
                            if let from = folder.apps.firstIndex(of: dragging) {
                                var apps = folder.apps
                                apps.remove(at: from)
                                // Exactly matches the visual preview: use the hover index directly
                                let insertIndex = finalIndex
                                let clamped = min(max(0, insertIndex), apps.count)
                                apps.insert(dragging, at: clamped)
                                folder.apps = apps
                                appStore.notifyFolderContentChanged(folder)

                                // Also trigger compaction after a drag inside the folder ends, so empty items on the main screen move to the end of the page
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    appStore.compactItemsWithinPages()
                                }
                            }
                        }
                    }
                )
                .launchNGHideAppContextMenu(app: app, appStore: appStore)
        }
    }
}

// MARK: - Drag geometry & hit-testing (folder internal)
extension FolderView {
    private func cellOrigin(for index: Int,
                            containerSize: CGSize,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        return GeometryUtils.cellOrigin(for: index,
                                      containerSize: containerSize,
                                      pageIndex: 0,
                                      columnWidth: columnWidth,
                                      appHeight: appHeight,
                                      columns: max(columnsCount, 1),
                                      columnSpacing: spacing,
                                      rowSpacing: spacing,
                                      pageSpacing: 0,
                                      currentPage: 0,
                                      gridPadding: gridPadding,
                                      scrollOffsetY: scrollOffsetY)
    }

    private func cellCenter(for index: Int,
                            containerSize: CGSize,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        let origin = cellOrigin(for: index, containerSize: containerSize, columnWidth: columnWidth, appHeight: appHeight)
        return CGPoint(x: origin.x + columnWidth / 2, y: origin.y + appHeight / 2)
    }

    private func indexAt(point: CGPoint,
                         containerSize: CGSize,
                         columnWidth: CGFloat,
                         appHeight: CGFloat) -> Int? {
        guard let offsetInPage = GeometryUtils.indexAt(point: point,
                                                      containerSize: containerSize,
                                                      pageIndex: 0,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight,
                                                      columns: max(columnsCount, 1),
                                                      columnSpacing: spacing,
                                                      rowSpacing: spacing,
                                                      pageSpacing: 0,
                                                      currentPage: 0,
                                                      itemsPerPage: visualApps.count,
                                                      gridPadding: gridPadding,
                                                      scrollOffsetY: scrollOffsetY) else { return nil }
        
        let count = visualApps.count
        // Allow returning count as the "trailing slot", so dragging past the last item makes room
        if count == 0 { return 0 }
        return min(max(offsetInPage, 0), count)
    }
}

// MARK: - Scroll offset reader for NSScrollView
private struct ScrollOffsetReader: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = OffsetProxyView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let proxy = nsView as? OffsetProxyView else { return }
        proxy.onChange = onChange
        proxy.attachIfNeeded()
    }

    private final class OffsetProxyView: NSView {
        var onChange: (CGFloat) -> Void = { _ in }
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        override func removeFromSuperview() {
            detach()
            super.removeFromSuperview()
        }

        func attachIfNeeded() {
            guard observer == nil, let scrollView = enclosingScrollView else { return }
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                              object: scrollView.contentView,
                                                              queue: .main) { [weak self] _ in
                self?.notify()
            }
            notify()
        }

        private func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }

        private func notify() {
            guard let scrollView = enclosingScrollView else { return }
            let offsetY = scrollView.contentView.bounds.origin.y
            onChange(offsetY)
        }

        deinit { detach() }
    }
}
// MARK: - Keyboard navigation (mirror outer behavior)
extension FolderView {
    private func setupKeyHandlers() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func setupInitialSelection() {
        if selectedIndex == nil, folder.apps.indices.first != nil {
            selectedIndex = 0
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Let input through while editing the folder name
        if isTextFieldFocused { return event }
        if appStore.useCAGridRenderer { return event }

        // Esc closes the folder
        if event.keyCode == 53 {
            onClose()
            return nil
        }

        // Return: activate or trigger the selection
        if event.keyCode == 36 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            if let idx = selectedIndex, folder.apps.indices.contains(idx) {
                let targetApp = folder.apps[idx]
                if canLaunch(targetApp) {
                    onLaunchApp(targetApp)
                } else {
                    NSSound.beep()
                }
                return nil
            }
            return event
        }

        // Tab: same as Return, activates keyboard navigation first
        if event.keyCode == 48 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            return event
        }

        // Down arrow: activate navigation first
        if event.keyCode == 125 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            moveSelection(dx: 0, dy: 1)
            return nil
        }

        // Left/right or other arrow keys
        if let (dx, dy) = arrowDelta(for: event.keyCode) {
            guard isKeyboardNavigationActive else { return event }
            moveSelection(dx: dx, dy: dy)
            return nil
        }

        return event
    }

    private func moveSelection(dx: Int, dy: Int) {
        guard let current = selectedIndex else { return }
        let columnsCount = max(columnsCount, 1)
        let newIndex: Int = dy == 0 ? current + dx : current + dy * columnsCount
        guard folder.apps.indices.contains(newIndex) else { return }
        selectedIndex = newIndex
        announceSelectedAppIfNeeded()
    }

    private func handleControllerCommand(_ command: ControllerCommand) {
        guard presentationState?.allowsInteraction != false else { return }
        guard appStore.gameControllerEnabled else { return }
        guard ControllerInputManager.shared.isActive else { return }
        guard !isEditingName else { return }

        switch command {
        case .move(let direction), .moveRepeat(let direction):
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return
            }

            switch direction {
            case .left:
                moveSelection(dx: -1, dy: 0)
            case .right:
                moveSelection(dx: 1, dy: 0)
            case .up:
                moveSelection(dx: 0, dy: -1)
            case .down:
                moveSelection(dx: 0, dy: 1)
            }
        case .stop(_):
            break
        case .select:
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return
            }

            if let idx = selectedIndex, folder.apps.indices.contains(idx) {
                let targetApp = folder.apps[idx]
                if canLaunch(targetApp) {
                    onLaunchApp(targetApp)
                } else {
                    NSSound.beep()
                }
            }
        case .cancel:
            onClose()
        case .menu:
            break
        }
    }

    private func setSelectionToStart() {
        if let first = folder.apps.indices.first {
            selectedIndex = first
        } else {
            selectedIndex = nil
        }
    }

    private func clampSelection() {
        let count = folder.apps.count
        if count == 0 { selectedIndex = nil; return }
        if let idx = selectedIndex {
            if idx >= count { selectedIndex = count - 1 }
            if idx < 0 { selectedIndex = 0 }
        } else {
            selectedIndex = 0
        }
    }

    private func announceSelectedAppIfNeeded() {
        guard appStore.voiceFeedbackEnabled,
              let index = selectedIndex,
              folder.apps.indices.contains(index) else { return }
        VoiceManager.shared.announceSelection(item: .app(folder.apps[index]))
    }
}

private struct FolderSurfaceModifier: ViewModifier {
    let isNativePresentation: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isNativePresentation {
            content
        } else {
            content.liquidGlass(in: RoundedRectangle(cornerRadius: 30))
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .transition(LNAnimations.folderOpenTransition)
        }
    }
}
