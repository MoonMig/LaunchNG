import AppKit
import QuartzCore

extension CAGridView {
    // MARK: - Input Handling

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        // print("🎯 [CAGrid] becomeFirstResponder")
        return true
    }

    override func resignFirstResponder() -> Bool {
        // print("🎯 [CAGrid] resignFirstResponder")
        return true
    }

    // Make sure the view responds to the very first mouse click
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // Make sure the view can receive mouse events
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = frame.contains(point) ? self : nil
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard hoverMagnificationEnabled else {
            clearHover()
            return
        }
        guard !isDraggingItem && !isPageDragging && !isDragging else {
            clearHover()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if let (item, _) = itemAt(location), case .empty = item {
            updateHoverIndex(nil)
        } else if let (_, index) = itemAt(location) {
            updateHoverIndex(index)
        } else {
            updateHoverIndex(nil)
        }
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelColors()
        updateFolderGlassColors()
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isContextMenuTracking else {
            super.scrollWheel(with: event)
            return
        }
        // Avoid double-handling when the local monitor is present
        if scrollEventMonitor != nil {
            return
        }
        guard isScrollEnabled else { return }
        handleScrollWheel(with: event)
    }

    func handleScrollWheel(with event: NSEvent) {
        finishFolderDissolve()
        finishDragLanding()
        // Prefer horizontal movement; vertical precise input can be flipped separately.
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let isPrecise = event.hasPreciseScrollingDeltas
        let verticalDelta = preciseVerticalDelta(from: deltaY, isPrecise: isPrecise)
        let delta = abs(deltaX) > abs(deltaY) ? deltaX : verticalDelta
        let baseline = max(AppStore.defaultScrollSensitivity, 0.0001)
        let sensitivityScale = CGFloat(max(scrollSensitivity, 0.0001) / baseline)
        let scaledDelta = delta * sensitivityScale

        if !isPrecise {
            /*
            // Old follow-the-finger wheel + timer snap logic (kept commented out for later comparison)
            wheelSnapTimer?.invalidate()

            // Accumulate the scroll amount
            wheelAccumulatedDelta += scaledDelta * 8  // Amplification factor, to make the follow effect more noticeable

            // Compute the temporary offset (with a rubber-band effect)
            let pageStride = bounds.width + pageSpacing
            let baseOffset = -CGFloat(currentPage) * pageStride
            var newOffset = baseOffset + wheelAccumulatedDelta

            // Rubber-band effect: resistance at the boundary
            let minOffset = -CGFloat(pageCount - 1) * pageStride
            let maxOffset: CGFloat = 0
            if newOffset > maxOffset {
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.15)
            } else if newOffset < minOffset {
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.15)
            }

            // Update the display
            scrollOffset = newOffset
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            syncFolderGlass(geometryChanged: false)
            CATransaction.commit()

            // Set up a timer to decide whether to page or snap back once scrolling stops
            wheelSnapTimer = Timer.scheduledTimer(withTimeInterval: wheelSnapDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                let threshold = self.bounds.width * 0.15  // 15% triggers a page flip
                var targetPage = self.currentPage

                if self.wheelAccumulatedDelta < -threshold {
                    targetPage = self.currentPage + 1
                } else if self.wheelAccumulatedDelta > threshold {
                    targetPage = self.currentPage - 1
                }

                self.wheelAccumulatedDelta = 0
                self.navigateToPage(targetPage, animated: true)
            }
            */

            // Mouse wheel paging keeps its own reverse setting.
            handleWheelPaging(with: scaledDelta)
            return
        }

        // Trackpad swipe
        switch event.phase {
        case .began:
            isDragging = true
            isScrollAnimating = false
            dragStartOffset = scrollOffset
            accumulatedDelta = 0
            scrollVelocity = 0

        case .changed:
            accumulatedDelta += scaledDelta

            // Compute the new offset
            var newOffset = dragStartOffset + accumulatedDelta

            // Rubber-band effect: add resistance at the boundary
            let pageStride = bounds.width + pageSpacing
            let minOffset = -CGFloat(navigablePageCount - 1) * pageStride
            let maxOffset: CGFloat = 0

            if newOffset > maxOffset {
                // Past the left boundary
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.2)
            } else if newOffset < minOffset {
                // Past the right boundary
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.2)
            }

            scrollOffset = newOffset

            // Performance optimization: batch the update using CATransaction
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            syncFolderGlass(geometryChanged: false)
            CATransaction.commit()

        case .ended, .cancelled:
            isDragging = false

            // Determine the target page from the swipe distance and velocity
            let velocity = (abs(deltaX) > abs(deltaY) ? deltaX : verticalDelta) * sensitivityScale
            let threshold = (bounds.width + pageSpacing) * 0.15  // 15% is enough to trigger a page flip
            let velocityThreshold: CGFloat = 30
            var targetPage = currentPage

            // Decide the page flip direction from the accumulated swipe direction
            if accumulatedDelta < -threshold || velocity < -velocityThreshold {
                targetPage = currentPage + 1
            } else if accumulatedDelta > threshold || velocity > velocityThreshold {
                targetPage = currentPage - 1
            }

            navigateToPage(targetPage)

        default:
            break
        }
    }

    private func handleWheelPaging(with scaledDelta: CGFloat) {
        guard scaledDelta != 0 else { return }

        let direction = scaledDelta > 0 ? 1 : -1
        let effectiveDirection = reverseWheelPagingDirection ? -direction : direction
        if wheelLastDirection != direction {
            wheelAccumulatedDelta = 0
        }
        wheelLastDirection = direction
        wheelAccumulatedDelta += abs(scaledDelta)

        // Fixed threshold; sensitivity changes are already reflected in scaledDelta
        let threshold: CGFloat = 2.0
        guard wheelAccumulatedDelta >= threshold else { return }

        let now = Date()
        if let last = wheelLastFlipAt, now.timeIntervalSince(last) < wheelFlipCooldown {
            return
        }

        // Keep existing CA direction semantics by default; optional override flips wheel-only paging.
        let targetPage = effectiveDirection > 0 ? currentPage - 1 : currentPage + 1
        wheelLastFlipAt = now
        wheelAccumulatedDelta = 0
        navigateToPage(targetPage, animated: true)
    }

    private func preciseVerticalDelta(from deltaY: CGFloat, isPrecise: Bool) -> CGFloat {
        guard isPrecise else { return -deltaY }
        return trackpadVerticalDirection == .natural ? deltaY : -deltaY
    }

    func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let factor: CGFloat = 0.5
        let absOffset = abs(offset)
        let scaled = (factor * absOffset * limit) / (absOffset + limit)
        return offset >= 0 ? scaled : -scaled
    }

    override func mouseDown(with event: NSEvent) {
        guard !externalAppDragSessionActive else { return }
        finishFolderDissolve()
        finishDragLanding()
        // Make sure to become first responder, so later scroll wheel events can be received
        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        if let (item, index) = itemAt(location) {
            // print("🖱️ [CAGrid] Hit item: \(item.name) at index \(index)")
            // Reopening a folder immediately after dismissal may be classified
            // as a double click by AppKit; it is still a complete open gesture.
            let isFolder: Bool
            if case .folder = item { isFolder = true } else { isFolder = false }
            if event.clickCount == 1 || isFolder {
                // Add the press effect animation
                setPressedIndex(index)
                dragStartPoint = location

                // Start the long-press timer (used to begin a drag)
                // Note: must be added to the .common mode, otherwise it won't fire during mouse tracking
                longPressTimer?.invalidate()
                let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
                    self?.startDragging(item: item, index: index, at: location)
                }
                RunLoop.main.add(timer, forMode: .common)
                longPressTimer = timer
            }
        } else {
            // Clicked an empty area - start page-drag mode
            // print("🖱️ [CAGrid] Hit empty area, starting page drag")
            isPageDragging = true
            pageDragStartX = location.x
            pageDragStartOffset = scrollOffset
            dragStartPoint = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if externalAppDragSessionActive { return }
        let location = convert(event.locationInWindow, from: nil)

        // Page-drag mode
        if isPageDragging {
            let deltaX = location.x - pageDragStartX
            var newOffset = pageDragStartOffset + deltaX

            // Rubber-band effect - add resistance at the boundary
            let pageStride = bounds.width + pageSpacing
            let minOffset = -CGFloat(navigablePageCount - 1) * pageStride
            let maxOffset: CGFloat = 0

            if newOffset > maxOffset {
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.3)
            } else if newOffset < minOffset {
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.3)
            }

            scrollOffset = newOffset

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            syncFolderGlass(geometryChanged: false)
            CATransaction.commit()
            return
        }

        // Check if moved enough distance to start dragging
        if !isDraggingItem, let idx = pressedIndex {
            if isLayoutLocked { return }
            let distance = hypot(location.x - dragStartPoint.x, location.y - dragStartPoint.y)
            if distance > 10 {
                // Cancel the long-press timer, start dragging immediately
                longPressTimer?.invalidate()
                longPressTimer = nil
                if let item = items[safe: idx] {
                    startDragging(item: item, index: idx, at: location)
                }
            }
        }

        // Update the drag position
        if isDraggingItem {
            let dragDelta = CGPoint(x: location.x - dragCurrentPoint.x,
                                    y: location.y - dragCurrentPoint.y)
            if let app = externalDockDragCandidate(),
               shouldStartExternalDockDrag(localPoint: location,
                                           windowPoint: event.locationInWindow,
                                           dragDelta: dragDelta) {
                startExternalDockDrag(for: app, event: event, at: location)
                return
            }
            updateDragging(at: location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if externalAppDragSessionActive { return }
        let location = convert(event.locationInWindow, from: nil)

        // Cancel the long-press timer
        longPressTimer?.invalidate()
        longPressTimer = nil

        // End page-drag mode
        if isPageDragging {
            isPageDragging = false

            let totalDrag = location.x - pageDragStartX
            let threshold = (bounds.width + pageSpacing) * 0.15  // 15% is enough to trigger a page flip

            var targetPage = currentPage
            if totalDrag < -threshold {
                // Dragged left -> next page
                targetPage = min(currentPage + 1, navigablePageCount - 1)
            } else if totalDrag > threshold {
                // Dragged right -> previous page
                targetPage = max(currentPage - 1, 0)
            }

            // If there was no real drag (just a click), close the window
            if abs(totalDrag) < 5 {
                onEmptyAreaClicked?()
                return
            }

            navigateToPage(targetPage, animated: true)
            return
        }

        if isDraggingItem {
            // End the drag
            endDragging(at: location)
        } else if let idx = pressedIndex {
            // Restore the press effect
            setPressedIndex(nil)

            // Check whether it was released on the same item
            if let (item, index) = itemAt(location), index == idx {
                if isBatchSelectionMode {
                    if case .app(let app) = item {
                        toggleBatchSelection(forAppPath: app.url.path)
                    }
                } else {
                    if case .folder = item {
                        onItemClicked?(item, index)
                        return
                    }
                    // Trigger it with a small delay, to make the animation more noticeable
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.onItemClicked?(item, index)
                    }
                }
            }
        }
    }


    func setPressedIndex(_ newIndex: Int?, animated: Bool = true) {
        let oldIndex = pressedIndex
        guard oldIndex != newIndex else { return }

        pressedIndex = newIndex
        if let oldIndex {
            applyScaleForIndex(oldIndex, animated: animated)
        }
        if let newIndex {
            applyScaleForIndex(newIndex, animated: animated)
        }
    }

    // MARK: - Drag and Drop

    func startDragging(item: LaunchpadItem, index: Int, at point: CGPoint) {
        guard !isLayoutLocked else { return }
        if isBatchSelectionMode {
            guard case .app(let app) = item else { return }
            let dragPath = app.url.path
            let orderedBatch = orderedBatchDragPaths(leadingAppPath: dragPath)
            guard !orderedBatch.isEmpty else { return }
            batchDraggingAppPathsOrdered = orderedBatch
            batchHiddenCompanionIndices = orderedBatch
                .compactMap { globalIndex(forAppPath: $0) }
                .filter { $0 != index }
        } else {
            // Allow dragging apps and folders in normal mode.
            switch item {
            case .app, .folder:
                break
            case .empty, .missingApp:
                return
            }
            batchDraggingAppPathsOrdered.removeAll()
            batchHiddenCompanionIndices.removeAll()
        }

        dragDropPreview = .none
        pendingDropPreview = nil
        hoverUpdateTimer?.invalidate()
        hoverUpdateTimer = nil
        pendingHoverIndex = nil
        currentHoverIndex = nil
        clearDropTargetHighlight()
        clearHover()
        updateSelection(nil, animated: false)
        isDraggingItem = true
        draggingIndex = index
        draggingItem = item
        dragCurrentPoint = point

        // Restore the press effect
        if pressedIndex != nil {
            setPressedIndex(nil)
        }

        // Hand off the source to the drag preview atomically. A default opacity
        // animation would leave the old CA icon visible beneath the new glass.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Hide the original icon
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        if pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
            iconLayers[pageIndex][localIndex].removeAnimation(forKey: "opacity")
            iconLayers[pageIndex][localIndex].opacity = 0
        }
        if !batchHiddenCompanionIndices.isEmpty {
            for companionIndex in batchHiddenCompanionIndices {
                let companionPage = companionIndex / itemsPerPage
                let companionLocal = companionIndex % itemsPerPage
                if companionPage < iconLayers.count, companionLocal < iconLayers[companionPage].count {
                    iconLayers[companionPage][companionLocal].removeAnimation(forKey: "opacity")
                }
                setOpacity(0, forGlobalIndex: companionIndex)
            }
        }

        // Create the dragging layer
        createDraggingLayer(for: item, at: point)
        CATransaction.commit()

        if isBatchDragging {
            pendingHoverIndex = gridPositionAt(point)
            applyIconPositionUpdate()
        }

        // print("🎯 [CAGrid] Started dragging: \(item.name) at index \(index)")
    }

    func createDraggingLayer(for item: LaunchpadItem, at point: CGPoint) {
        let actualIconSize = iconSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Container for dragging (holds glass + icon for folders)
        let container = CALayer()
        container.frame = CGRect(x: point.x - actualIconSize / 2, y: point.y - actualIconSize / 2,
                            width: actualIconSize, height: actualIconSize)
        container.transform = CATransform3DMakeScale(1.1, 1.1, 1.0)
        container.zPosition = 1000

        // For folders, add glass background
        if case .folder = item {
            let glassSize = actualIconSize * 0.8
            let glassOffset = (actualIconSize - glassSize) / 2
            let glassLayer = CALayer()
            glassLayer.name = "glass"
            glassLayer.frame = CGRect(x: glassOffset, y: glassOffset, width: glassSize, height: glassSize)
            glassLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            glassLayer.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            glassLayer.borderWidth = 0.5
            glassLayer.cornerRadius = glassSize * 0.25
            glassLayer.shadowColor = NSColor.black.cgColor
            glassLayer.shadowOffset = CGSize(width: 0, height: -1)
            glassLayer.shadowRadius = 3
            glassLayer.shadowOpacity = 0.15
            container.addSublayer(glassLayer)
        }

        // Icon layer
        let iconLayer = CALayer()
        iconLayer.name = "icon"
        iconLayer.frame = CGRect(x: 0, y: 0, width: actualIconSize, height: actualIconSize)
        iconLayer.contentsScale = scale
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.shadowOpacity = 0

        // Set icon content with high resolution
        if case .app(let app) = item {
            let icon = IconStore.shared.icon(forPath: app.url.path)
            let renderSize = NSSize(width: actualIconSize * scale, height: actualIconSize * scale)
            let renderedImage = NSImage(size: renderSize)
            renderedImage.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: renderSize))
            renderedImage.unlockFocus()
            if let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                iconLayer.contents = cgImage
            }
        } else if case .folder(let folder) = item {
            let icon = folder.icon(of: actualIconSize, scale: folderPreviewScale)
            let renderSize = NSSize(width: actualIconSize * scale, height: actualIconSize * scale)
            let renderedImage = NSImage(size: renderSize)
            renderedImage.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: renderSize))
            renderedImage.unlockFocus()
            if let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                iconLayer.contents = cgImage
            }
        }

        container.addSublayer(iconLayer)

        if case .app = item, batchDraggingAppPathsOrdered.count > 1 {
            addBatchDragCountBadge(to: container, count: batchDraggingAppPathsOrdered.count)
        }

        // Keep dragged apps above the native folder backplates, too.
        (usesLiquidGlassFolders ? layer : containerLayer)?.addSublayer(container)
        draggingLayer = container
        syncFolderGlass()
    }

    func externalDockDragCandidate() -> AppInfo? {
        guard !isBatchDragging else { return nil }
        guard case .app(let app) = draggingItem else { return nil }
        let path = app.url.path
        guard !path.isEmpty else { return nil }
        guard app.url.pathExtension.lowercased() == "app" else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return app
    }

    func shouldStartExternalDockDrag(localPoint point: CGPoint, windowPoint: CGPoint, dragDelta: CGPoint) -> Bool {
        guard let contentView = window?.contentView else { return false }
        guard dockDragEnabled else { return false }

        switch dockDragSide {
        case .disabled:
            return false
        case .bottom:
            let movingTowardDock = dragDelta.y < -1.5
            let nearBottomEdge = windowPoint.y <= contentView.bounds.minY + externalAppDragTriggerDistance
            let isInsideHorizontalRange =
                windowPoint.x >= contentView.bounds.minX - externalAppDragOutset &&
                windowPoint.x <= contentView.bounds.maxX + externalAppDragOutset
            return movingTowardDock && nearBottomEdge && isInsideHorizontalRange

        case .left:
            let movingTowardDock = dragDelta.x < -1.5
            let nearLeftEdge = windowPoint.x <= contentView.bounds.minX + externalAppDragTriggerDistance
            let isInsideVerticalRange =
                windowPoint.y >= contentView.bounds.minY - externalAppDragOutset &&
                windowPoint.y <= contentView.bounds.maxY + externalAppDragOutset
            return movingTowardDock && nearLeftEdge && isInsideVerticalRange

        case .right:
            let movingTowardDock = dragDelta.x > 1.5
            let nearRightEdge = windowPoint.x >= contentView.bounds.maxX - externalAppDragTriggerDistance
            let isInsideVerticalRange =
                windowPoint.y >= contentView.bounds.minY - externalAppDragOutset &&
                windowPoint.y <= contentView.bounds.maxY + externalAppDragOutset
            return movingTowardDock && nearRightEdge && isInsideVerticalRange
        }
    }

    func startExternalDockDrag(for app: AppInfo, event: NSEvent, at point: CGPoint) {
        guard !externalAppDragSessionActive else { return }

        clearDropTargetHighlight()
        cancelEdgeDragTimer()

        let writer = app.url as NSURL
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)

        let dragImage = renderedExternalDockDragPreview(for: app)
        let frame = CGRect(x: point.x - iconSize / 2,
                           y: point.y - iconSize / 2,
                           width: iconSize,
                           height: iconSize)
        draggingItem.setDraggingFrame(frame, contents: dragImage)

        cancelDragging()

        externalAppDragSessionActive = true
        AppDelegate.shared?.beginExternalSystemDragSession()

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func renderedExternalDockDragPreview(for app: AppInfo) -> NSImage {
        let icon = IconStore.shared.icon(forPath: app.url.path)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let renderSize = NSSize(width: iconSize * scale, height: iconSize * scale)
        let renderedImage = NSImage(size: renderSize)
        renderedImage.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: renderSize),
                  from: .zero,
                  operation: .copy,
                  fraction: 1.0)
        renderedImage.unlockFocus()
        renderedImage.size = NSSize(width: iconSize, height: iconSize)
        return renderedImage
    }

    func addBatchDragCountBadge(to container: CALayer, count: Int) {
        let badgeSize: CGFloat = 22
        let badge = CALayer()
        badge.name = "batchDragCountBadge"
        badge.frame = CGRect(x: container.bounds.width - badgeSize * 0.9,
                             y: container.bounds.height - badgeSize * 0.95,
                             width: badgeSize,
                             height: badgeSize)
        badge.cornerRadius = badgeSize * 0.5
        badge.backgroundColor = NSColor.systemBlue.cgColor
        badge.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        badge.borderWidth = 1
        badge.zPosition = 40

        let text = CATextLayer()
        text.string = "\(count)"
        text.alignmentMode = .center
        text.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        text.fontSize = 11
        text.foregroundColor = NSColor.white.cgColor
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.frame = CGRect(x: 0, y: 4, width: badgeSize, height: badgeSize - 6)
        badge.addSublayer(text)
        container.addSublayer(badge)
    }

    func updateDragging(at point: CGPoint) {
        defer { syncFolderGlass(geometryChanged: false) }
        dragCurrentPoint = point

        // Update dragging layer position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Updating frame under the lift transform also changes bounds. Keep the
        // bitmap size stable so the drop can smoothly shrink from the lift scale.
        draggingLayer?.position = point
        CATransaction.commit()

        // Check edge drag for page flip
        checkEdgeDrag(at: point)

        if isBatchDragging {
            if let hoverIndex = gridPositionAt(point), hoverIndex != draggingIndex {
                clearDropTargetHighlight()
                updateIconPositionsForDrag(hoverIndex: hoverIndex)
            } else {
                clearDropTargetHighlight()
                updateIconPositionsForDrag(hoverIndex: nil)
            }
            return
        }

        guard let sourceIndex = draggingIndex else { return }
        let preview: GridDropPreview
        if let hoverIndex = gridPositionAt(point), hoverIndex != draggingIndex {
            if items.indices.contains(hoverIndex), case .app = draggingItem,
               isPointInFolderDropZone(point, targetIndex: hoverIndex) {
                switch items[hoverIndex] {
                case .app, .folder:
                    preview = .merge(targetID: items[hoverIndex].id)
                case .missingApp, .empty:
                    preview = .insertion(index: hoverIndex, sourceIndex: sourceIndex,
                                         itemCount: items.count, itemsPerPage: itemsPerPage)
                }
            } else {
                preview = .insertion(index: hoverIndex, sourceIndex: sourceIndex,
                                     itemCount: items.count, itemsPerPage: itemsPerPage)
            }
        } else {
            preview = .none
        }
        requestDropPreview(preview)
    }

    func updateIconPositionsForDrag(hoverIndex: Int?) {
        guard draggingIndex != nil else { return }
        
        // Skip if same as pending or current
        if hoverIndex == pendingHoverIndex { return }
        
        // Store pending hover index
        pendingHoverIndex = hoverIndex
        
        // Cancel previous timer
        hoverUpdateTimer?.invalidate()
        
        // Schedule delayed update to prevent jittering during fast movement
        hoverUpdateTimer = Timer.scheduledTimer(withTimeInterval: hoverUpdateDelay, repeats: false) { [weak self] _ in
            self?.applyIconPositionUpdate()
        }
    }
    
    func applyIconPositionUpdate() {
        guard let dragIndex = draggingIndex else { return }
        
        let hoverIndex = pendingHoverIndex
        
        // Batch mode always recomputes compaction so selected gaps are closed immediately.
        if !isBatchDragging, hoverIndex == currentHoverIndex { return }
        currentHoverIndex = hoverIndex
        
        // Get current page icons only
        let pageIndex = currentPage
        guard pageIndex < iconLayers.count else { return }
        // Only position updates need a new glass sampling interval. Preserve
        // an existing deadline when there is no drag, no change, or no page.
        defer { animateFolderGlass() }
        let pageLayers = iconLayers[pageIndex]
        let pageStart = pageIndex * itemsPerPage

        ensureOriginalPositionsForCurrentPage(pageLayers: pageLayers, pageStart: pageStart)
        
        if isBatchDragging {
            applyBatchCompactedPositions(pageLayers: pageLayers, pageStart: pageStart, dragIndex: dragIndex)
            return
        }
        
        // Calculate positions with item shifted - smooth spring-like animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for (localIndex, layer) in pageLayers.enumerated() {
            let globalIndex = pageStart + localIndex
            
            // Skip the dragging item's original layer - hide it completely
            if globalIndex == dragIndex {
                layer.opacity = 0
                continue
            }
            
            guard let originalPos = originalIconPositions[globalIndex] else { continue }
            
            var targetPos = originalPos
            
            if let hover = hoverIndex {
                let hoverLocalIndex = hover - pageStart
                let dragLocalIndex = dragIndex - pageStart
                let dragInThisPage = dragIndex >= pageStart && dragIndex < pageStart + itemsPerPage
                
                // Only affect items on current page
                if hover >= pageStart && hover < pageStart + itemsPerPage {
                    
                    // The hovered cell itself only gets a partial nudge (not the
                    // full cell-width slide cells strictly between drag and
                    // hover get) toward where it would end up: a full slide made
                    // a mergeable app/folder visually "flee" a full cell away
                    // from under the pointer while approaching it (the pointer
                    // would then be hovering wherever it fled to, not the
                    // target), but no nudge at all left nothing to see — with
                    // an immediately-adjacent target, "cells strictly between"
                    // is empty, so an insert preview was otherwise invisible
                    // until the pointer pushed a second cell into the shift.
                    // The nudge is small enough that the target stays under/near
                    // the pointer and its own merge zone remains reachable. Its
                    // actual post-drop position (if the drop lands as an insert,
                    // not a merge) is still picked up and animated by the normal
                    // landing/reuse path once the reorder actually commits.
                    let boundaryNudgeFraction: CGFloat = 0.35
                    func nudged(toward neighborPos: CGPoint) -> CGPoint {
                        CGPoint(x: originalPos.x + (neighborPos.x - originalPos.x) * boundaryNudgeFraction,
                                y: originalPos.y + (neighborPos.y - originalPos.y) * boundaryNudgeFraction)
                    }
                    if dragInThisPage {
                        if dragLocalIndex < hoverLocalIndex {
                            // Dragging forward: items strictly between drag and hover shift left
                            if localIndex > dragLocalIndex && localIndex < hoverLocalIndex {
                                if let prevPos = originalIconPositions[pageStart + localIndex - 1] {
                                    targetPos = prevPos
                                }
                            } else if localIndex == hoverLocalIndex,
                                      let prevPos = originalIconPositions[pageStart + localIndex - 1] {
                                targetPos = nudged(toward: prevPos)
                            }
                        } else if dragLocalIndex > hoverLocalIndex {
                            // Dragging backward: items strictly between hover and drag shift right
                            if localIndex > hoverLocalIndex && localIndex < dragLocalIndex {
                                if let nextPos = originalIconPositions[pageStart + localIndex + 1] {
                                    targetPos = nextPos
                                }
                            } else if localIndex == hoverLocalIndex,
                                      let nextPos = originalIconPositions[pageStart + localIndex + 1] {
                                targetPos = nudged(toward: nextPos)
                            }
                        }
                    } else {
                        // Dragging from another page: create a gap on the hover page by shifting later items to the right.
                        if localIndex > hoverLocalIndex {
                            let targetGlobalIndex = pageStart + localIndex + 1
                            targetPos = gridCenterForGlobalIndex(targetGlobalIndex)
                        } else if localIndex == hoverLocalIndex {
                            targetPos = nudged(toward: gridCenterForGlobalIndex(pageStart + localIndex + 1))
                        }
                    }
                }
            }
            
            GridLayerMotion.move(layer, to: targetPos, duringHover: true)
        }
        
        CATransaction.commit()
    }

    func applyBatchCompactedPositions(pageLayers: [CALayer], pageStart: Int, dragIndex: Int) {
        let pageEnd = pageStart + pageLayers.count
        let removedIndices = Set(batchHiddenCompanionIndices + [dragIndex]).filter { $0 >= pageStart && $0 < pageEnd }
        let removedLocals = Set(removedIndices.map { $0 - pageStart })

        var nonEmptyLocals: [Int] = []
        var emptyLocals: [Int] = []
        for localIndex in 0..<pageLayers.count {
            guard !removedLocals.contains(localIndex) else { continue }
            let globalIndex = pageStart + localIndex
            if globalIndex < items.count, case .empty = items[globalIndex] {
                emptyLocals.append(localIndex)
            } else {
                nonEmptyLocals.append(localIndex)
            }
        }
        let compactedLocals = nonEmptyLocals + emptyLocals

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.35, 1.0))

        for (targetLocalIndex, sourceLocalIndex) in compactedLocals.enumerated() {
            let layer = pageLayers[sourceLocalIndex]
            let targetGlobalIndex = pageStart + targetLocalIndex
            let targetPosition = originalIconPositions[targetGlobalIndex] ?? gridCenterForGlobalIndex(targetGlobalIndex)
            layer.position = targetPosition
            layer.opacity = 1
        }

        for removedLocalIndex in removedLocals {
            pageLayers[removedLocalIndex].opacity = 0
        }

        CATransaction.commit()
    }

    /// Per-cell geometry (size + page-relative origin) for a local index
    /// within one page. Shared by every function that needs to know where a
    /// grid cell sits -- content insets, spacing, stride, and the col/row
    /// split have independently been the site of real hit-testing bugs
    /// before (see gridPositionAt's own comment on the slab-boundary fix);
    /// three copies of this formula meant a fix like that one only landing
    /// in one of them, silently leaving the other two to disagree with it.
    struct CellGeometry {
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        /// Page-relative; does not include the page index's own offset.
        let cellOriginX: CGFloat
        let cellOriginY: CGFloat
    }

    func cellGeometry(forLocalIndex localIndex: Int) -> CellGeometry {
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing

        let col = localIndex % columns
        let row = localIndex / columns

        let cellOriginX = contentInsets.left + CGFloat(col) * strideX
        let cellOriginY = pageHeight - contentInsets.top - CGFloat(row + 1) * cellHeight - CGFloat(row) * rowSpacing
        return CellGeometry(cellWidth: cellWidth, cellHeight: cellHeight, cellOriginX: cellOriginX, cellOriginY: cellOriginY)
    }

    func gridCenterForGlobalIndex(_ globalIndex: Int) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let pageStride = bounds.width + pageSpacing
        let pageIndex = max(0, globalIndex / itemsPerPage)
        let localIndex = max(0, globalIndex % itemsPerPage)
        let geo = cellGeometry(forLocalIndex: localIndex)

        let actualIconSize = iconSize
        let labelHeight: CGFloat = showLabels ? labelFontSize + 8 : 0
        let labelTopSpacing: CGFloat = showLabels ? 4 : 0
        let totalHeight = actualIconSize + labelTopSpacing + labelHeight

        let containerX = CGFloat(pageIndex) * pageStride + geo.cellOriginX
        let containerY = geo.cellOriginY + (geo.cellHeight - totalHeight) / 2
        return CGPoint(x: containerX + geo.cellWidth / 2, y: containerY + totalHeight / 2)
    }
    
    func resetIconPositions() {
        defer {
            hideDragLandingDestination()
            animateFolderGlass()
        }
        // Cancel pending update timer
        hoverUpdateTimer?.invalidate()
        hoverUpdateTimer = nil
        pendingHoverIndex = nil
        
        guard !originalIconPositions.isEmpty else { 
            // Even if we never captured original positions, make sure the hidden drag source is restored
            if let dragIndex = draggingIndex {
                let pageIndex = dragIndex / itemsPerPage
                let localIndex = dragIndex % itemsPerPage
                if pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
                    iconLayers[pageIndex][localIndex].opacity = 1.0
                }
            }
            currentHoverIndex = nil
            return 
        }
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0))
        
        for (pageIndex, pageLayers) in iconLayers.enumerated() {
            let pageStart = pageIndex * itemsPerPage
            for (localIndex, layer) in pageLayers.enumerated() {
                let globalIndex = pageStart + localIndex
                if let originalPos = originalIconPositions[globalIndex] {
                    layer.position = originalPos
                }
                layer.opacity = 1.0
            }
        }
        
        CATransaction.commit()
        
        originalIconPositions.removeAll()
        currentHoverIndex = nil
    }

    func updateHoverIndex(_ newIndex: Int?) {
        guard hoveredIndex != newIndex else { return }
        let old = hoveredIndex
        hoveredIndex = newIndex
        if let old = old {
            applyScaleForIndex(old, animated: true)
        }
        if let newIndex = newIndex {
            applyScaleForIndex(newIndex, animated: true)
        }
    }

    func clearHover() {
        updateHoverIndex(nil)
    }

    func updateLabelFonts() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    textLayer.font = NSFont.systemFont(ofSize: labelFontSize, weight: labelFontWeight)
                    textLayer.fontSize = labelFontSize
                }
            }
        }
        CATransaction.commit()
    }

    func updateLabelVisibility() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    textLayer.isHidden = !showLabels
                }
            }
        }
        CATransaction.commit()
        updateLayout()
    }

    func setBackgroundLabelContrast(_ sample: BackgroundLabelContrast?, tints: [BackgroundLabelContrast.Tint]) {
        guard backgroundLabelSample !== sample || backgroundLabelTints != tints else { return }
        backgroundLabelSample = sample
        backgroundLabelTints = tints
        backgroundLabelDarkAppearance = nil
        updateLabelColors()
    }

    func updateLabelColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if backgroundLabelDarkAppearance != dark {
            backgroundLabelDarkAppearance = dark
            let style = backgroundLabelSample?.resolvedStyle(darkAppearance: dark, tints: backgroundLabelTints)
            backgroundLabelColor = style.map { $0.usesWhiteText ? .white : .black }
            backgroundLabelShadow = style?.shadow ?? .none
        }
        let color = currentLabelColor().cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for container in pageLayers {
                guard let text = container.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer else { continue }
                if text.foregroundColor != color { text.foregroundColor = color }
                BackgroundLabelContrast.applyLabelShadow(to: text, style: backgroundLabelShadow)
            }
        }
        CATransaction.commit()
    }

    func updateFolderGlassColors() {
        let colors = currentFolderGlassStyle()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let glassLayer = containerLayer.sublayers?.first(where: { $0.name == "glass" }) {
                    glassLayer.backgroundColor = colors.background.cgColor
                    glassLayer.borderColor = colors.border.cgColor
                    glassLayer.shadowOffset = colors.shadowOffset
                    glassLayer.shadowRadius = colors.shadowRadius
                    glassLayer.shadowOpacity = colors.shadowOpacity
                }
            }
        }
        CATransaction.commit()
    }

    func currentLabelColor() -> NSColor {
        if let backgroundLabelColor { return backgroundLabelColor }
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .white : .black
    }

    func isPointInFolderDropZone(_ point: CGPoint, targetIndex: Int) -> Bool {
        guard let center = iconCenter(for: targetIndex) else { return false }
        // Clamp against the cell stride (cell + spacing): gridPositionAt()
        // now hit-tests with slab boundaries at the midpoint of the gap
        // between two cells (see its comment), so a cell's icon center sits
        // symmetrically at strideX/2 from either neighbor's boundary. That
        // margin is exactly what must stay free of this zone on both sides
        // for "insert before/after this cell" (landing between this cell and
        // a neighbor, e.g. two folders) to be reachable from either
        // direction. An unclamped zone can reach or exceed that margin in
        // denser layouts (Compact window, more columns/rows) or at higher
        // folderDropZoneScale.
        let insertMargin: CGFloat = 16
        let size = min(iconSize * folderDropZoneScale, max(0, maxFolderDropZoneSide - insertMargin * 2))
        let rect = CGRect(x: center.x - size / 2,
                          y: center.y - size / 2,
                          width: size,
                          height: size)
        return rect.contains(point)
    }

    private var maxFolderDropZoneSide: CGFloat {
        let availableWidth = max(0, bounds.width - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, bounds.height - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let cellWidth = max(0, availableWidth - totalColumnSpacing) / CGFloat(max(columns, 1))
        let cellHeight = max(0, availableHeight - totalRowSpacing) / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing
        let strideY = cellHeight + rowSpacing
        return min(strideX, strideY)
    }

    func iconCenter(for index: Int) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex >= 0 && pageIndex < pageCount else { return nil }

        let pageStride = bounds.width + pageSpacing
        let geo = cellGeometry(forLocalIndex: localIndex)

        let labelHeight: CGFloat = showLabels ? (labelFontSize + 8) : 0
        let labelTopSpacing: CGFloat = showLabels ? 4 : 0
        let totalHeight = iconSize + labelTopSpacing + labelHeight

        let containerX = CGFloat(pageIndex) * pageStride + geo.cellOriginX
        let containerY = geo.cellOriginY + (geo.cellHeight - totalHeight) / 2

        let iconX = containerX + (geo.cellWidth - iconSize) / 2
        let iconY = containerY + labelHeight + labelTopSpacing

        let centerX = iconX + iconSize / 2 + scrollOffset
        let centerY = iconY + iconSize / 2
        return CGPoint(x: centerX, y: centerY)
    }

    func currentFolderGlassStyle() -> (background: NSColor, border: NSColor, shadowOpacity: Float, shadowRadius: CGFloat, shadowOffset: CGSize) {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return (NSColor.white.withAlphaComponent(0.08),
                    NSColor.white.withAlphaComponent(0.2),
                    0.15,
                    3,
                    CGSize(width: 0, height: -1))
        }
        return (NSColor.white.withAlphaComponent(0.7),
                NSColor.white.withAlphaComponent(0.75),
                0.2,
                4,
                CGSize(width: 0, height: -1))
    }

    func applyScaleForIndex(_ index: Int, animated: Bool) {
        guard index >= 0, itemsPerPage > 0 else { return }
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count else { return }

        let containerLayer = iconLayers[pageIndex][localIndex]

        let pressScale: CGFloat = (pressedIndex == index && activePressEffectEnabled) ? CGFloat(activePressScale) : 1.0

        let selectionScale: CGFloat = 1.2
        var iconScale: CGFloat = 1.0
        if dropTargetIndex == index {
            // Creating a folder expands only its temporary backplate.
            iconScale = containerLayer.sublayers?.contains(where: { $0.name == "creationGlass" }) == true ? 1 : 1.1
        } else if selectedIndex == index {
            iconScale = selectionScale
        } else if hoverMagnificationEnabled, hoveredIndex == index {
            iconScale = hoverMagnificationScale
        }

        let iconLayer = containerLayer.sublayers?.first(where: { $0.name == "icon" })
        let glassLayer = containerLayer.sublayers?.first(where: { $0.name == "glass" })
        let containerTransform = CATransform3DMakeScale(pressScale, pressScale, 1.0)
        let iconTransform = CATransform3DMakeScale(iconScale, iconScale, 1.0)
        let containerChanged = !CATransform3DEqualToTransform(containerLayer.transform, containerTransform)
        let iconChanged = iconLayer.map { !CATransform3DEqualToTransform($0.transform, iconTransform) } ?? false
        let glassChanged = glassLayer.map { !CATransform3DEqualToTransform($0.transform, iconTransform) } ?? false
        guard containerChanged || iconChanged || glassChanged else { return }
        // Ordinary app hover/press/selection cannot move native folder glass.
        // Only an actual folder geometry change needs to extend its sampling.
        defer {
            if glassLayer != nil, usesLiquidGlassFolders {
                if animated { animateFolderGlass() } else { syncFolderGlass() }
            }
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        containerLayer.transform = containerTransform

        if let iconLayer {
            iconLayer.transform = iconTransform
        }
        if let glassLayer {
            glassLayer.transform = iconTransform
        }
        CATransaction.commit()
    }

    func updateSelection(_ index: Int?, animated: Bool = true) {
        let clampedIndex: Int? = {
            guard let index else { return nil }
            guard index >= 0, index < items.count else { return nil }
            if case .empty = items[index] { return nil }
            return index
        }()

        guard selectedIndex != clampedIndex else { return }
        let old = selectedIndex
        selectedIndex = clampedIndex
        if let old = old { applyScaleForIndex(old, animated: animated) }
        if let newIndex = selectedIndex { applyScaleForIndex(newIndex, animated: animated) }
    }

    func updateExternalDragState(sourceIndex: Int?, hoverIndex: Int?) {
        // Avoid interfering with native CA drag.
        guard !isDraggingItem else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        if let sourceIndex = sourceIndex {
            if !externalDragActive || draggingIndex != sourceIndex {
                externalDragActive = true
                draggingIndex = sourceIndex
            }
            // A model refresh can replace the source layer without changing
            // its index. Reassert the handoff on every external-drag update.
            let pageIndex = sourceIndex / itemsPerPage
            let localIndex = sourceIndex % itemsPerPage
            if pageIndex >= 0, localIndex >= 0,
               pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                iconLayers[pageIndex][localIndex].removeAnimation(forKey: "opacity")
                iconLayers[pageIndex][localIndex].opacity = 0
                CATransaction.commit()
            }
            updateIconPositionsForDrag(hoverIndex: hoverIndex)
        } else if externalDragActive {
            // resetIconPositions()'s fallback path (no captured hover positions,
            // e.g. a handoff drag released before hoverUpdateTimer ever fired)
            // restores the hidden source cell by reading draggingIndex, so it
            // must still be set when this runs — nulling it first left that
            // cell stuck at opacity 0 forever in that case.
            resetIconPositions()
            externalDragActive = false
            draggingIndex = nil
        }
    }

    func ensureOriginalPositionsForCurrentPage(pageLayers: [CALayer], pageStart: Int) {
        // If we already captured positions for this page, keep them.
        var hasAny = false
        for localIndex in 0..<pageLayers.count {
            let globalIndex = pageStart + localIndex
            if originalIconPositions[globalIndex] != nil {
                hasAny = true
                break
            }
        }
        guard !hasAny else { return }

        for (localIndex, layer) in pageLayers.enumerated() {
            let globalIndex = pageStart + localIndex
            originalIconPositions[globalIndex] = layer.position
        }
    }

    // MARK: - Edge page-flip detection
    func checkEdgeDrag(at point: CGPoint) {
        let leftEdge = point.x < edgeDragThreshold
        let rightEdge = point.x > bounds.width - edgeDragThreshold

        if leftEdge && currentPage > 0 {
            // Left edge - flip to the previous page
            startEdgeDragTimer(direction: -1)
        } else if rightEdge {
            // Right edge - flip to the next page (may create a new page)
            startEdgeDragTimer(direction: 1)
        } else {
            // Left the edge zone - cancel the timer
            cancelEdgeDragTimer()
        }
    }

    func startEdgeDragTimer(direction: Int) {
        // Don't create a duplicate timer if one already exists for the same direction; but the
        // opposite direction must cancel the old timer and restart, otherwise a reversed drag at
        // the boundary gets stuck on the old direction and page flipping stops responding.
        if edgeDragTimer != nil {
            guard edgeDragTimerDirection != direction else { return }
            cancelEdgeDragTimer()
        }
        edgeDragTimerDirection = direction

        let timer = Timer(timeInterval: edgeDragDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let targetPage = self.currentPage + direction

            // Check whether a new page needs to be created
            if direction > 0 && targetPage >= self.pageCount {
                // Notify that a new page should be created
                self.onRequestNewPage?()
            }

            self.navigateToPage(targetPage, animated: true)
            self.edgeDragTimer = nil
            self.edgeDragTimerDirection = nil

            // Keep detecting after the page flip
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isDraggingItem else { return }
                self.checkEdgeDrag(at: self.dragCurrentPoint)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeDragTimer = timer
    }

    func cancelEdgeDragTimer() {
        edgeDragTimer?.invalidate()
        edgeDragTimer = nil
        edgeDragTimerDirection = nil
    }

    func hardSnapToCurrentPage() {
        guard bounds.width > 0 else { return }
        resetScrollInteractionState()
        isScrollAnimating = false
        scrollAnimationStartTime = 0
        let expectedOffset = -CGFloat(currentPage) * (bounds.width + pageSpacing)
        scrollOffset = expectedOffset
        targetScrollOffset = expectedOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        syncFolderGlass(geometryChanged: false)
        CATransaction.commit()
    }

    func resetScrollInteractionState() {
        isDragging = false
        accumulatedDelta = 0
        wheelAccumulatedDelta = 0
        wheelLastDirection = 0
        wheelLastFlipAt = nil
    }

    /// Compute the grid position corresponding to a click point (even in an empty area)
    func gridPositionAt(_ point: CGPoint) -> Int? {
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let adjustedX = point.x - scrollOffset

        // Compute the clicked page
        let pageStride = pageWidth + pageSpacing
        let pageIndex = Int(floor(adjustedX / pageStride))
        guard pageIndex >= 0 else { return nil }
        // Allow dragging past the last page (this will create a new page)
        let effectivePageIndex = min(pageIndex, max(0, pageCount - 1))

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing
        let strideY = cellHeight + rowSpacing

        // Compute the click position's coordinates relative to the current page
        let pageX = adjustedX - CGFloat(effectivePageIndex) * pageStride
        guard pageX >= 0, pageX <= pageWidth else { return nil }
        let localX = pageX - contentInsets.left
        let localY = pageHeight - point.y - contentInsets.top

        // Clamp to the valid range
        let clampedX = max(0, min(localX, availableWidth - 1))
        let clampedY = max(0, min(localY, availableHeight - 1))

        // Offset by half the spacing before dividing so the boundary between
        // two cells sits at the midpoint of the gap between their icons, not
        // at the next cell's own left/bottom edge. Without this, a column's
        // hit-test slab was [its own left edge, next column's left edge) —
        // all of column N's icon-to-icon spacing before column N+1 belonged
        // to column N, none of it to N+1. Dragging rightward toward a folder
        // then had to cross the entire visual gap AND part of the folder's
        // own cell before hoverIndex changed at all, so nothing (like the
        // "make space" gap) happened until the pointer was already deep
        // inside the folder's footprint. Matches GeometryUtils.indexAt(),
        // the Legacy engine's equivalent hit test, which already offsets by
        // spacing/2 for the same reason.
        let col = Int((clampedX + columnSpacing / 2) / strideX)
        let row = Int((clampedY + rowSpacing / 2) / strideY)

        let clampedCol = max(0, min(col, columns - 1))
        let clampedRow = max(0, min(row, rows - 1))

        let localIndex = clampedRow * columns + clampedCol
        let globalIndex = effectivePageIndex * itemsPerPage + localIndex

        return globalIndex
    }

    func highlightDropTarget(at index: Int) {
        // Clear the previous highlight
        if let oldTarget = dropTargetIndex, oldTarget != index {
            dropTargetIndex = nil
            applyScaleForIndex(oldTarget, animated: true)
        }

        dropTargetIndex = index
        if items.indices.contains(index), case .app = items[index] {
            showFolderCreationHighlight(at: index)
        } else {
            hideFolderCreationHighlight()
        }
        applyScaleForIndex(index, animated: true)
    }

    func clearDropTargetHighlight(preservingCreation: Bool = false) {
        hideFolderCreationHighlight(preservingForDrop: preservingCreation)
        if let target = dropTargetIndex {
            dropTargetIndex = nil
            applyScaleForIndex(target, animated: true)
        }
    }

    func setHighlight(at index: Int, highlighted _: Bool) {
        applyScaleForIndex(index, animated: true)
    }

    func endDragging(at point: CGPoint) {
        guard let dragIndex = draggingIndex, let dragItem = draggingItem else {
            cancelDragging()
            return
        }
        let revisionBeforeDrop = itemsRevision
        let displayedDrop = dragDropPreview
        dragDropPreview = .none
        pendingDropPreview = nil
        hoverUpdateTimer?.invalidate()
        hoverUpdateTimer = nil

        // Save current hover position before clearing
        let savedHoverIndex = currentHoverIndex

        // Keep a creation backplate until the model replaces it with the folder.
        let isMerge: Bool = { if case .merge = displayedDrop { return true }; return false }()
        clearDropTargetHighlight(preservingCreation: isMerge)
        cancelEdgeDragTimer()

        // Calculate target position
        let targetPosition = gridPositionAt(point)

        // Track if we're doing a reorder (so we don't reset positions unnecessarily)
        var didReorder = false
        var didMerge = false
        var landingIndex: Int?
        var landingPageOffset: CGFloat?

        if isBatchDragging {
            if let insertIndex = savedHoverIndex ?? targetPosition {
                let clampedIndex = max(0, min(insertIndex, items.count))
                let singleDragNoop = batchDraggingAppPathsOrdered.count == 1 && clampedIndex == dragIndex
                if !singleDragNoop {
                    onReorderAppBatch?(batchDraggingAppPathsOrdered, clampedIndex)
                    didReorder = true
                }
            }
        } else {
            if case .insert(let target) = displayedDrop {
                let occupied = items.map { item in
                    if case .empty = item { return false }
                    return true
                }
                if let plan = GridReorderPlan.make(occupied: occupied, from: dragIndex, to: target,
                                                  itemsPerPage: itemsPerPage,
                                                  cascading: dragIndex / itemsPerPage != target / itemsPerPage) {
                    landingIndex = plan.destinationIndex
                    let finalPage = min(currentPage, max(0, (plan.slots.count - 1) / itemsPerPage))
                    landingPageOffset = -CGFloat(finalPage) * (bounds.width + pageSpacing)
                }
            }
            if case .merge(let targetID) = displayedDrop {
                didMerge = beginMergeLanding(itemID: dragItem.id, targetID: targetID)
            }
            switch commitDropPreview(displayedDrop, draggedItem: dragItem) {
            case .merge:
                if !didMerge { cancelDragging(); return }
            case .insert(let insertIndex):
                landingIndex = landingIndex ?? insertIndex
                didReorder = true
            case .none:
                if didMerge { finishDragLanding(); didMerge = false }
                break
            }
        }

        // A single icon retains its lifted representation until it reaches the
        // actual post-reorder cell, or shrinks into a merge target. Batch drops
        // keep their existing semantics.
        if !isBatchDragging {
            if !didMerge {
                beginDragLanding(itemID: dragItem.id,
                                 waitingForRevision: didReorder ? revisionBeforeDrop : nil,
                                 predictedIndex: landingIndex,
                                 predictedPageOffset: landingPageOffset)
            }
            if !didReorder && !didMerge { resetIconPositions() }
            isDraggingItem = false
            draggingIndex = nil
            draggingItem = nil
            dropTargetIndex = nil
            hoverUpdateTimer?.invalidate()
            hoverUpdateTimer = nil
            pendingHoverIndex = nil
            currentHoverIndex = nil
            originalIconPositions.removeAll()
            hardSnapToCurrentPage()
            updateDragLanding(at: CACurrentMediaTime())
            return
        }

        // If we did a reorder, data will update and rebuild layers
        // Delay clearing dragging state to avoid visual glitches during rebuild
        if didReorder {
            // Save drag index before clearing
            let savedDragIndex = draggingIndex
            
            // Remove dragging layer immediately
            removeDraggingVisuals()
            
            // Clear dragging flags immediately
            isDraggingItem = false
            dropTargetIndex = nil
            
            // Cancel pending updates
            hoverUpdateTimer?.invalidate()
            hoverUpdateTimer = nil
            pendingHoverIndex = nil
            currentHoverIndex = nil
            
            // Delay clearing other state to let data update complete
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.draggingIndex = nil
                self.draggingItem = nil
                self.originalIconPositions.removeAll()
                
                // Restore opacity of dragged item (if layers still exist)
                if let dragIndex = savedDragIndex {
                    let pageIndex = dragIndex / self.itemsPerPage
                    let localIndex = dragIndex % self.itemsPerPage
                    if pageIndex < self.iconLayers.count, localIndex < self.iconLayers[pageIndex].count {
                        self.iconLayers[pageIndex][localIndex].opacity = 1.0
                    }
                }
                self.restoreBatchHiddenCompanionLayers()
                if self.isBatchSelectionMode {
                    self.disableBatchSelectionMode()
                }
                self.forceSyncPageTransformIfNeeded()
                self.animateFolderGlass()
            }
        } else {
            // No reorder happened, reset positions to original
            cancelDragging()
        }
        hardSnapToCurrentPage()
        logIfMismatch("endDragging")
    }

    /// True while a live (pre-drop) drag is holding `item`'s original grid cell
    /// hidden behind the floating preview. Unlike `dragLanding`/`isFolderMergeDestination`,
    /// this covers the interval before mouse-up, so a mid-drag `rebuildLayers()`
    /// (an unrelated items refresh, e.g. icon cache invalidation or an app-folder
    /// rescan) knows to keep this cell hidden instead of redrawing it at full
    /// opacity next to the still-floating preview.
    ///
    /// Also covers `externalDragActive` (`updateExternalDragState`): a handoff
    /// drag pulling an item out of an open folder drives its own floating
    /// preview from SwiftUI (LaunchpadView's DragPreviewItem) and only asks
    /// this view to hide the source cell by index — it never sets
    /// isDraggingItem. Without this, a rebuild mid-handoff-drag would redraw
    /// that cell at full opacity right next to the SwiftUI preview until the
    /// next updateExternalDragState call happened to reassert it, which is
    /// exactly the intermittent "duplicate icon" users saw when dragging out
    /// of a folder.
    func isLiveDragSource(_ item: LaunchpadItem) -> Bool {
        if externalDragActive, let draggingIndex, items.indices.contains(draggingIndex),
           items[draggingIndex].id == item.id {
            return true
        }
        guard isDraggingItem else { return false }
        if isBatchDragging {
            if case .app(let app) = item { return batchDraggingAppPathsOrdered.contains(app.url.path) }
            return false
        }
        return item.id == draggingItem?.id
    }

    func removeDraggingVisuals() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let draggingLayer {
            folderGlassOverlay?.removeDraggingGlass(for: draggingLayer)
            draggingLayer.removeFromSuperlayer()
        }
        draggingLayer = nil
        CATransaction.commit()
    }

    func cancelDragging() {
        dragDropPreview = .none
        pendingDropPreview = nil
        clearDropTargetHighlight()
        finishDragLanding()
        defer { syncFolderGlass() }
        // Remove both drag representations before restoring the source icon.
        removeDraggingVisuals()
        // Reset icon positions to original
        resetIconPositions()

        isDraggingItem = false
        draggingIndex = nil
        draggingItem = nil
        dropTargetIndex = nil
        restoreBatchHiddenCompanionLayers()
        hardSnapToCurrentPage()
        logIfMismatch("cancelDragging")
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endExternalAppDragSessionIfActive()
    }

    /// `externalAppDragSessionActive` has exactly one normal reset path: this
    /// delegate callback from AppKit's `NSDraggingSession`. mouseDown/mouseDragged/
    /// mouseUp all early-return while it is true, so if the callback is ever not
    /// delivered to this exact view instance (window torn down or hidden mid
    /// system drag), the grid stops responding to clicks and drags permanently.
    /// Call this from window-hide/teardown paths as a safety net.
    func endExternalAppDragSessionIfActive() {
        guard externalAppDragSessionActive else { return }
        externalAppDragSessionActive = false
        AppDelegate.shared?.endExternalSystemDragSession()
    }

    func itemAt(_ point: CGPoint) -> (LaunchpadItem, Int)? {
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let adjustedX = point.x - scrollOffset

        // Compute the clicked page
        let pageStride = pageWidth + pageSpacing
        let pageIndex = Int(floor(adjustedX / pageStride))
        guard pageIndex >= 0 && pageIndex < pageCount else { return nil }

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing
        let strideY = cellHeight + rowSpacing

        // Compute the click position's coordinates relative to the current page
        let pageX = adjustedX - CGFloat(pageIndex) * pageStride
        guard pageX >= 0, pageX <= pageWidth else { return nil }
        let localX = pageX - contentInsets.left
        let localY = pageHeight - point.y - contentInsets.top

        guard localX >= 0, localY >= 0 else { return nil }
        guard localX < availableWidth, localY < availableHeight else { return nil }

        let col = Int(localX / strideX)
        let row = Int(localY / strideY)

        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }

        let cellOriginX = CGFloat(col) * strideX
        let cellOriginY = CGFloat(row) * strideY
        let cellLocalX = localX - cellOriginX
        let cellLocalY = localY - cellOriginY

        guard cellLocalX >= 0, cellLocalX <= cellWidth else { return nil }
        guard cellLocalY >= 0, cellLocalY <= cellHeight else { return nil }

        let localIndex = row * columns + col
        let globalIndex = pageIndex * itemsPerPage + localIndex

        guard globalIndex < items.count else { return nil }
        // An empty placeholder slot renders no icon, so it must behave like
        // blank space for hit-testing purposes too — otherwise this still
        // returns a non-nil (item, index) for its icon-sized hitbox exactly
        // as it would for a real app/folder, so mouseDown treats a click
        // there as "pressed an item" instead of starting the blank-area
        // tap-to-close/page-drag gesture. Only the second symptom (dead
        // click, not a wrong press effect) was reported, but both trace back
        // to this same missing check.
        if case .empty = items[globalIndex] { return nil }

        // Check whether the click is within the icon+label area (not the cell's blank margin)
        let actualIconSize = iconSize
        let labelHeight: CGFloat = showLabels ? (labelFontSize + 8) : 0
        let labelTopSpacing: CGFloat = showLabels ? 4 : 0
        let totalItemHeight = actualIconSize + labelTopSpacing + labelHeight

        // The icon+label area is centered within the cell
        let itemStartX = (cellWidth - actualIconSize) / 2
        let itemEndX = itemStartX + actualIconSize
        let itemStartY = (cellHeight - totalItemHeight) / 2
        let itemEndY = itemStartY + totalItemHeight

        // Check whether it's within the icon+label area
        guard cellLocalX >= itemStartX && cellLocalX <= itemEndX else { return nil }
        guard cellLocalY >= itemStartY && cellLocalY <= itemEndY else { return nil }

        return (items[globalIndex], globalIndex)
    }

}
