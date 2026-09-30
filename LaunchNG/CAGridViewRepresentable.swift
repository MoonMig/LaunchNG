import AppKit
import SwiftUI
import LaunchNGContextMenuCore

// MARK: - SwiftUI Wrapper

struct CAGridViewRepresentable: NSViewRepresentable {
    @ObservedObject var appStore: AppStore
    var items: [LaunchpadItem]  // Supports passing in already-filtered items
    var iconSize: CGFloat
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var contentInsets: NSEdgeInsets
    var pageSpacing: CGFloat
    var onOpenApp: ((AppInfo) -> Void)?
    var onOpenFolder: ((FolderInfo) -> Void)?
    var externalDragSourceIndex: Int?
    var externalDragHoverIndex: Int?
    var selectedIndex: Int?
    var folderPresentation: CAFolderPresentationController? = nil
    var backgroundLabelSample: BackgroundLabelContrast? = nil
    var backgroundLabelTints: [BackgroundLabelContrast.Tint] = []

    // Observe these triggers to force a refresh
    var gridRefreshTrigger: UUID { appStore.gridRefreshTrigger }
    var folderUpdateTrigger: UUID { appStore.folderUpdateTrigger }
    var iconCacheRefreshTrigger: UUID { appStore.iconCacheRefreshTrigger }

    func makeNSView(context: Context) -> CAFolderBackdropView {
        let backdrop = CAFolderBackdropView()
        let view = backdrop.grid
        folderPresentation?.backdrop = backdrop
        folderPresentation?.grid = view

        view.setBackgroundLabelContrast(backgroundLabelSample, tints: backgroundLabelTints)

        // Initialize configuration
        view.columns = appStore.gridColumnsPerPage
        view.rows = appStore.gridRowsPerPage
        view.iconSize = iconSize
        view.columnSpacing = columnSpacing
        view.rowSpacing = rowSpacing
        view.contentInsets = contentInsets
        view.pageSpacing = pageSpacing
        view.labelFontSize = CGFloat(appStore.iconLabelFontSize)
        view.labelFontWeight = nsFontWeight(for: appStore.iconLabelFontWeight)
        view.showLabels = appStore.showLabels
        view.isLayoutLocked = appStore.isLayoutLocked
        view.folderDropZoneScale = CGFloat(appStore.folderDropZoneScale)
        let preferredScale = nsViewScale(for: view)
        view.folderPreviewScale = appStore.enableHighResFolderPreviews ? preferredScale : 1
        view.usesLiquidGlassFolders = appStore.folderLiquidGlassEnabled
        view.enableIconPreload = false
        view.scrollSensitivity = appStore.scrollSensitivity
        view.reverseWheelPagingDirection = appStore.reverseWheelPagingDirection
        view.trackpadVerticalDirection = appStore.trackpadVerticalDirection
        view.hoverMagnificationEnabled = appStore.enableHoverMagnification
        view.hoverMagnificationScale = CGFloat(appStore.hoverMagnificationScale)
        view.activePressEffectEnabled = appStore.enableActivePressEffect
        view.activePressScale = CGFloat(appStore.activePressScale)
        view.animationsEnabled = appStore.enableAnimations
        view.animationDuration = appStore.animationDuration
        view.dockDragEnabled = appStore.dockDragEnabled
        view.dockDragSide = appStore.dockDragSide
        view.externalAppDragTriggerDistance = CGFloat(appStore.dockDragTriggerDistance)
        let allowsBatchSelection = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        view.contextMenuConfiguration = makeContextMenuConfiguration(allowsBatchSelection: allowsBatchSelection)
        view.allowsBatchSelectionMode = allowsBatchSelection
        
        // Set current page BEFORE items to ensure correct initial position
        view.setInitialPage(appStore.currentPage)
        view.items = items

        let launchApp: (AppInfo) -> Void = { app in
            onOpenApp?(app)
            // See the matching comment in LaunchpadView.launchApp: launch first
            // and only hide LaunchNG's own window once that's confirmed, not the
            // other way around -- hiding first with just a blind short delay
            // left a gap where no app was cleanly "active", which crashed some
            // apps' own window setup (confirmed with Transmission) in a way
            // launching the same app from Finder never did.
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if error != nil {
                        NSSound.beep()
                        return
                    }
                    AppDelegate.shared?.hideWindow()
                }
            }
        }

        view.onItemClicked = { item, index in
            // A single click opens the app or folder
            switch item {
            case .app(let app):
                launchApp(app)
            case .folder(let folder):
                onOpenFolder?(folder)
            case .missingApp:
                // Missing app, do nothing
                break
            case .empty:
                // Empty slot, do nothing (matches real Launchpad behavior)
                // Only clicking the blank area outside the grid closes the window
                break
            }
        }
        view.onItemDoubleClicked = { item, index in
            // Also handle double-click (for compatibility)
        }

        view.onPageChanged = { page in
            DispatchQueue.main.async {
                if appStore.currentPage != page {
                    appStore.currentPage = page
                }
            }
        }

        view.onFPSUpdate = { fps in
            // FPS display could be updated here
        }

        view.onEmptyAreaClicked = {
            // Clicking the empty area closes the window
            AppDelegate.shared?.hideWindow()
        }

        view.onContextMenuAction = { route in
            DispatchQueue.main.async {
                performAppContextMenuRoute(
                    route,
                    appStore: appStore,
                    launchApp: launchApp
                )
            }
        }

        // Drag to create a folder
        view.onCreateFolder = { dragApp, targetApp, insertAt in
            DispatchQueue.main.async {
                _ = appStore.createFolder(with: [dragApp, targetApp], insertAt: insertAt)
            }
        }

        // Drag into a folder
        view.onMoveToFolder = { app, folder in
            DispatchQueue.main.async {
                appStore.addAppToFolder(app, folder: folder)
            }
        }

        // Drag reorder
        view.onReorderItems = { fromIndex, toIndex in
            DispatchQueue.main.async {
                appStore.reorderGridItem(from: fromIndex, to: toIndex)
            }
        }

        view.onReorderAppBatch = { appPathsOrdered, toIndex in
            DispatchQueue.main.async {
                appStore.moveSelectedAppsAcrossPagesWithCascade(appPathsOrdered: appPathsOrdered, to: toIndex)
            }
        }

        // Request a new page (when dragged to the right edge)
        view.onRequestNewPage = {
            DispatchQueue.main.async {
                let itemsPerPage = appStore.gridColumnsPerPage * appStore.gridRowsPerPage
                guard itemsPerPage > 0, !appStore.items.isEmpty else { return }
                // A drag that lingers at the right edge re-fires this on every
                // edge-drag timer tick (checkEdgeDrag -> startEdgeDragTimer),
                // including right after navigating onto a page this same call
                // just created. Without checking whether the trailing page is
                // already entirely empty, each tick appended another whole
                // empty page for as long as the pointer stayed at the edge,
                // leaving dangling empty pages (with their own indicator dot)
                // behind once the drag ended without ever using them.
                let lastPageStart = ((appStore.items.count - 1) / itemsPerPage) * itemsPerPage
                guard !appStore.items[lastPageStart...].isEntirelyEmptyPlaceholders else { return }
                let currentPageCount = (appStore.items.count + itemsPerPage - 1) / itemsPerPage
                let neededItems = (currentPageCount + 1) * itemsPerPage - appStore.items.count
                for _ in 0..<neededItems {
                    appStore.items.append(.empty(UUID().uuidString))
                }
            }
        }

        return backdrop
    }

    func updateNSView(_ backdrop: CAFolderBackdropView, context: Context) {
        let nsView = backdrop.grid
        nsView.setBackgroundLabelContrast(backgroundLabelSample, tints: backgroundLabelTints)
        folderPresentation?.backdrop = backdrop
        folderPresentation?.grid = nsView
        // print("🔄 [CAGrid #\(nsView.debugInstanceId)] updateNSView, window=\(nsView.window != nil), isVisible=\(nsView.window?.isVisible ?? false)")
        // Make sure the scroll event monitor is installed (needed after the window is shown again)
        nsView.ensureScrollMonitorInstalled()

        // Update configuration
        let configChanged = nsView.columns != appStore.gridColumnsPerPage ||
                            nsView.rows != appStore.gridRowsPerPage ||
                            nsView.iconSize != iconSize ||
                            nsView.columnSpacing != columnSpacing ||
                            nsView.rowSpacing != rowSpacing ||
                            nsView.contentInsets.top != contentInsets.top ||
                            nsView.contentInsets.left != contentInsets.left ||
                            nsView.contentInsets.bottom != contentInsets.bottom ||
                            nsView.contentInsets.right != contentInsets.right ||
                            nsView.pageSpacing != pageSpacing ||
                            nsView.labelFontSize != CGFloat(appStore.iconLabelFontSize) ||
                            nsView.labelFontWeight != nsFontWeight(for: appStore.iconLabelFontWeight) ||
                            nsView.showLabels != appStore.showLabels ||
                            nsView.isLayoutLocked != appStore.isLayoutLocked ||
                            nsView.folderDropZoneScale != CGFloat(appStore.folderDropZoneScale) ||
                            nsView.folderPreviewScale != (appStore.enableHighResFolderPreviews ? nsViewScale(for: nsView) : 1)

        if configChanged {
            nsView.columns = appStore.gridColumnsPerPage
            nsView.rows = appStore.gridRowsPerPage
            nsView.iconSize = iconSize
            nsView.columnSpacing = columnSpacing
            nsView.rowSpacing = rowSpacing
            nsView.contentInsets = contentInsets
            nsView.pageSpacing = pageSpacing
            nsView.labelFontSize = CGFloat(appStore.iconLabelFontSize)
            nsView.labelFontWeight = nsFontWeight(for: appStore.iconLabelFontWeight)
            nsView.showLabels = appStore.showLabels
            nsView.isLayoutLocked = appStore.isLayoutLocked
            nsView.folderDropZoneScale = CGFloat(appStore.folderDropZoneScale)
            let preferredScale = nsViewScale(for: nsView)
            nsView.folderPreviewScale = appStore.enableHighResFolderPreviews ? preferredScale : 1
        }
        nsView.usesLiquidGlassFolders = appStore.folderLiquidGlassEnabled
        nsView.enableIconPreload = false
        nsView.scrollSensitivity = appStore.scrollSensitivity
        nsView.reverseWheelPagingDirection = appStore.reverseWheelPagingDirection
        nsView.trackpadVerticalDirection = appStore.trackpadVerticalDirection
        nsView.hoverMagnificationEnabled = appStore.enableHoverMagnification
        nsView.hoverMagnificationScale = CGFloat(appStore.hoverMagnificationScale)
        nsView.activePressEffectEnabled = appStore.enableActivePressEffect
        nsView.activePressScale = CGFloat(appStore.activePressScale)
        nsView.animationsEnabled = appStore.enableAnimations
        nsView.animationDuration = appStore.animationDuration
        nsView.isScrollEnabled = appStore.openFolder == nil && !appStore.isSetting
        let allowsBatchSelection = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        nsView.contextMenuConfiguration = makeContextMenuConfiguration(allowsBatchSelection: allowsBatchSelection)
        nsView.allowsBatchSelectionMode = allowsBatchSelection

        // Check whether the refresh triggers changed (folder creation/edits fire this)
        let triggerChanged = context.coordinator.lastGridRefreshTrigger != gridRefreshTrigger ||
                             context.coordinator.lastFolderUpdateTrigger != folderUpdateTrigger

        if context.coordinator.lastIconCacheRefreshTrigger != iconCacheRefreshTrigger {
            context.coordinator.lastIconCacheRefreshTrigger = iconCacheRefreshTrigger
            nsView.clearIconCache()
            nsView.items = items
        }

        var didUpdateItems = false
        if triggerChanged {
            context.coordinator.lastGridRefreshTrigger = gridRefreshTrigger
            context.coordinator.lastFolderUpdateTrigger = folderUpdateTrigger
            // print("🔄 [CAGrid] Trigger changed, forcing refresh")
            nsView.items = items
            didUpdateItems = true
        } else if itemsChanged(nsView.items, items) {
            // Update items - always check for a full change (including folder names etc.)
            // print("🔄 [CAGrid] Updating items: \(nsView.items.count) -> \(items.count)")
            nsView.items = items
            didUpdateItems = true
        }

        let maxPageIndex = max(nsView.pageCount - 1, 0)
        if appStore.currentPage > maxPageIndex {
            nsView.navigateToPage(maxPageIndex, animated: false)
            DispatchQueue.main.async {
                if appStore.currentPage > maxPageIndex {
                    appStore.currentPage = maxPageIndex
                }
            }
        }

        // Sync the page
        if nsView.currentPage != appStore.currentPage {
            // print("📄 [CAGrid] Page sync: \(nsView.currentPage) -> \(appStore.currentPage)")
            nsView.navigateToPage(appStore.currentPage, animated: appStore.enableAnimations)
        }

        if didUpdateItems {
            nsView.forceSyncPageTransformIfNeeded()
        } else {
            nsView.snapToCurrentPageIfNeeded()
        }

        let safeSelectedIndex: Int? = {
            guard let selectedIndex else { return nil }
            return items.indices.contains(selectedIndex) ? selectedIndex : nil
        }()
        nsView.dockDragEnabled = appStore.dockDragEnabled
        nsView.dockDragSide = appStore.dockDragSide
        nsView.externalAppDragTriggerDistance = CGFloat(appStore.dockDragTriggerDistance)
        nsView.updateSelection(safeSelectedIndex, animated: true)
        nsView.updateExternalDragState(sourceIndex: externalDragSourceIndex,
                                       hoverIndex: externalDragHoverIndex)
        nsView.logIfMismatch("updateNSView", appPage: appStore.currentPage)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func makeContextMenuConfiguration(allowsBatchSelection: Bool) -> AppContextMenuConfiguration {
        let store = appStore
        return AppContextMenuConfiguration(
            localize: { [weak store] key in store?.localized(key.localizationKey) ?? key.localizationKey.rawValue },
            canShowInLayout: !allowsBatchSelection,
            showQuarantineRemovalAction: appStore.showQuarantineRemovalAction,
            canUseConfiguredUninstallTool: appStore.uninstallToolAppURL != nil,
            allowsBatchSelection: allowsBatchSelection,
            folderQuickLaunchEnabled: appStore.folderQuickLaunchEnabled,
            orderedFolderQuickLaunchApps: { [weak store] folder in
                store?.orderedFolderQuickLaunchApps(in: folder) ?? folder.apps
            },
            isFolderQuickLaunchAppPinned: { [weak store] folder, app in
                store?.isFolderQuickLaunchAppPinned(app, inFolderID: folder.id) ?? false
            }
        )
    }

    private func nsFontWeight(for option: AppStore.IconLabelFontWeightOption) -> NSFont.Weight {
        switch option {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private func nsViewScale(for view: NSView) -> CGFloat {
        if let scale = view.window?.backingScaleFactor {
            return scale
        }
        return NSScreen.main?.backingScaleFactor ?? 1
    }

    class Coordinator {
        var lastGridRefreshTrigger: UUID = UUID()
        var lastFolderUpdateTrigger: UUID = UUID()
        var lastIconCacheRefreshTrigger: UUID = UUID()
    }

    // Check whether items changed (a full comparison of every item's id and name)
    private func itemsChanged(_ old: [LaunchpadItem], _ new: [LaunchpadItem]) -> Bool {
        guard old.count == new.count else { return true }
        guard !old.isEmpty else { return !new.isEmpty }

        // Fully compare each item
        for i in 0..<old.count {
            let oldItem = old[i]
            let newItem = new[i]

            // Compare id
            if oldItem.id != newItem.id { return true }

            // Compare name (needs a refresh after a folder is renamed)
            if oldItem.name != newItem.name { return true }

            // For folders, also compare the number of apps inside
            if case .folder(let oldFolder) = oldItem, case .folder(let newFolder) = newItem {
                if oldFolder.apps.count != newFolder.apps.count { return true }
            }
        }

        return false
    }
}

// MARK: - Preview

#if DEBUG
struct CAGridViewRepresentable_Previews: PreviewProvider {
    static var previews: some View {
        CAGridViewRepresentable(appStore: AppStore(),
                                items: [],
                                iconSize: 72,
                                columnSpacing: 20,
                                rowSpacing: 14,
                                contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                                pageSpacing: 80,
                                externalDragSourceIndex: nil,
                                externalDragHoverIndex: nil)
            .frame(width: 1200, height: 800)
    }
}
#endif
