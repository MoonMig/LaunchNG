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
    // Keyboard navigation
    @State private var selectedIndex: Int? = nil
    @State private var isKeyboardNavigationActive: Bool = false
    @State private var keyMonitor: Any?

    let onClose: () -> Void
    let onLaunchApp: (AppInfo) -> Void

    private func canLaunch(_ app: AppInfo) -> Bool {
        FileManager.default.fileExists(atPath: app.url.path)
    }
    
    // Tuned spacing and layout parameters.
    // This view uses one symmetric spacing value throughout rather than
    // separate horizontal/vertical figures like the main folder grid
    // (CAFolderGridView), so a single blended value is what's achievable
    // here without a larger geometry rewrite -- averaging keeps it
    // responsive to both sliders instead of ignoring one of them.
    private var spacing: CGFloat {
        CGFloat((appStore.folderIconColumnSpacing + appStore.folderIconRowSpacing) / 2)
    }
    // Dynamic column count, adapted to window width and the cell's minimum width
    @State private var columnsCount: Int = 4
    private let gridPadding: CGFloat = 16
    private let titlePadding: CGFloat = 16
    private let folderTitleHeight: CGFloat = 72

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
        appStore.folderLayoutMode == .paged && folderPageCount > 1
    }

    private var shouldScrollFolderTitleWithContent: Bool {
        appStore.folderLayoutMode == .vertical
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
        // The Next Engine's own CAFolderGridView/CAFolderPresentation handles
        // keyboard navigation for an open folder; this SwiftUI-level monitor
        // is a no-op passthrough now that folders are always CA-hosted.
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
