import Foundation
import AppKit
import SwiftData

struct FolderInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var apps: [AppInfo]
    var pinnedAppPaths: [String]
    let createdAt: Date
    
    init(id: String = UUID().uuidString,
         name: String = "Untitled",
         apps: [AppInfo] = [],
         pinnedAppPaths: [String] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.pinnedAppPaths = pinnedAppPaths
        self.createdAt = createdAt
    }
    
    var folderIcon: NSImage {
        // Use the cache to produce the folder icon, avoiding redundant rendering
        let icon = icon(of: 72)
        return icon
    }

    func icon(of side: CGFloat) -> NSImage {
        let useHighRes = UserDefaults.standard.object(forKey: AppStore.folderPreviewHighResKey) as? Bool ?? true
        let scale = useHighRes ? (NSScreen.main?.backingScaleFactor ?? 1) : 1
        return icon(of: side, scale: scale)
    }

    func icon(of side: CGFloat, scale: CGFloat) -> NSImage {
        let normalizedSide = max(16, side)
        let normalizedScale = max(1, scale)
        let cacheKey = folderPreviewCacheKey(for: normalizedSide, scale: normalizedScale)
        if let cached = FolderPreviewCache.shared.image(forKey: cacheKey) {
            return cached
        }
        let icon = renderFolderIcon(side: normalizedSide, scale: normalizedScale)
        FolderPreviewCache.shared.store(icon, forKey: cacheKey)
        return icon
    }

    /// A cache-only lookup lets rebuilt grid layers display an existing preview
    /// immediately without scheduling another background/main-queue round trip.
    func cachedIcon(of side: CGFloat, scale: CGFloat) -> NSImage? {
        let key = folderPreviewCacheKey(for: max(16, side), scale: max(1, scale))
        return FolderPreviewCache.shared.image(forKey: key)
    }

    private func renderFolderIcon(side: CGFloat, scale: CGFloat) -> NSImage {
        let pointSize = NSSize(width: side, height: side)
        let pixelSide = max(16, Int((side * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelSide,
                                         pixelsHigh: pixelSide,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return NSImage(size: pointSize)
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
            ctx.shouldAntialias = true
        }

        for (index, app) in apps.prefix(9).enumerated() {
            let iconRect = FolderPreviewLayout.iconRect(at: index, side: side)!

            // Icon fallback: if the app icon's size is 0, fall back to the system's file icon
            let iconToDraw: NSImage = {
                let baseIcon = IconStore.shared.icon(for: app)
                if baseIcon.size.width > 0 && baseIcon.size.height > 0 {
                    return baseIcon
                }
                return NSWorkspace.shared.icon(forFile: app.url.path)
            }()
            iconToDraw.draw(in: iconRect)
        }

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }

    private func folderPreviewCacheKey(for side: CGFloat, scale: CGFloat) -> String {
        var hasher = Hasher()
        hasher.combine(id)
        for app in apps {
            hasher.combine(app.url.path)
        }
        let contentHash = hasher.finalize()
        let sizeKey = Int((side * scale).rounded())
        let scaleKey = Int((scale * 100).rounded())
        return "folderPreview_\(id)_\(sizeKey)_\(scaleKey)_\(contentHash)"
    }
    
    static func == (lhs: FolderInfo, rhs: FolderInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum LaunchpadItem: Identifiable, Equatable {
    case app(AppInfo)
    case folder(FolderInfo)
    case empty(String)
    case missingApp(MissingAppPlaceholder)
    
    var id: String {
        switch self {
        case .app(let app):
            return "app_\(app.id)"
        case .folder(let folder):
            return "folder_\(folder.id)"
        case .empty(let token):
            return "empty_\(token)"
        case .missingApp(let placeholder):
            return "missing_\(placeholder.bundlePath)"
        }
    }
    
    var name: String {
        switch self {
        case .app(let app):
            return app.name
        case .folder(let folder):
            return folder.name
        case .empty:
            return ""
        case .missingApp(let placeholder):
            return placeholder.displayName
        }
    }

    var icon: NSImage {
        switch self {
        case .app(let app):
            return app.icon
        case .folder(let folder):
            let icon = folder.folderIcon
            return icon
        case .empty:
            // Transparent placeholder
            return NSImage(size: .zero)
        case .missingApp(let placeholder):
            return placeholder.icon
        }
    }

    // Convenience accessor: returns the AppInfo for a .app case, nil otherwise
    var appInfoIfApp: AppInfo? {
        if case let .app(app) = self { return app }
        return nil
    }
    
    static func == (lhs: LaunchpadItem, rhs: LaunchpadItem) -> Bool {
        lhs.id == rhs.id
    }

    /// True for the `.empty` placeholder case specifically -- distinct from
    /// `.missingApp`, which still occupies a real (if broken) slot.
    var isEmptyPlaceholder: Bool {
        if case .empty = self { return true }
        return false
    }
}

extension Sequence where Element == LaunchpadItem {
    /// True when every item in this slice is an `.empty` placeholder -- the
    /// "is this whole page blank" test shared by CAGridView.visiblePageCount
    /// and CAGridViewRepresentable's onRequestNewPage, kept in one place so
    /// the two don't independently redefine what counts as an empty
    /// trailing page and risk disagreeing about it.
    var isEntirelyEmptyPlaceholders: Bool {
        allSatisfy(\.isEmptyPlaceholder)
    }
}

// MARK: - Unified persistence model (top-level item: app or folder)
@Model
final class TopItemData {
    // Unified primary key: appPath for apps, folderId for folders
    @Attribute(.unique) var id: String
    var kind: String                 // "app" or "folder"
    var orderIndex: Int              // Top-level mixed order index
    // App fields
    var appPath: String?
    // Folder fields
    var folderName: String?
    var appPaths: [String]           // Order of apps within the folder
    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Folder initializer
    init(folderId: String,
         folderName: String,
         appPaths: [String],
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = folderId
        self.kind = "folder"
        self.orderIndex = orderIndex
        self.appPath = nil
        self.folderName = folderName
        self.appPaths = appPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // App initializer
    init(appPath: String,
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = appPath
        self.kind = "app"
        self.orderIndex = orderIndex
        self.appPath = appPath
        self.folderName = nil
        self.appPaths = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Empty-slot initializer
    init(emptyId: String,
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = emptyId
        self.kind = "empty"
        self.orderIndex = orderIndex
        self.appPath = nil
        self.folderName = nil
        self.appPaths = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Per-page order persistence model (stored as "page-slot")
@Model
final class PageEntryData {
    // Unique slot key, e.g. "page-0-pos-3"
    @Attribute(.unique) var slotId: String
    var pageIndex: Int
    var position: Int
    var kind: String          // "app" | "folder" | "empty" | "missing"
    // app entry
    var appPath: String?
    var appDisplayName: String?
    // folder entry
    var folderId: String?
    var folderName: String?
    var appPaths: [String]
    var pinnedAppPaths: [String] = []
    // removable source records which removable directory this missing app came from, to make cleanup easier
    var removableSource: String?
    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    init(slotId: String,
         pageIndex: Int,
         position: Int,
         kind: String,
         appPath: String? = nil,
         folderId: String? = nil,
         folderName: String? = nil,
         appPaths: [String] = [],
         pinnedAppPaths: [String] = [],
         appDisplayName: String? = nil,
         removableSource: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.slotId = slotId
        self.pageIndex = pageIndex
        self.position = position
        self.kind = kind
        self.appPath = appPath
        self.folderId = folderId
        self.folderName = folderName
        self.appPaths = appPaths
        self.pinnedAppPaths = pinnedAppPaths
        self.appDisplayName = appDisplayName
        self.removableSource = removableSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MissingAppPlaceholder: Equatable, Hashable, Identifiable {
    let bundlePath: String
    let displayName: String
    let removableSource: String?
    var id: String { bundlePath }
    var icon: NSImage { Self.defaultIcon }

    static let defaultIcon: NSImage = {
        let dimension: CGFloat = 256
        let size = NSSize(width: dimension, height: dimension)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let backgroundPath = NSBezierPath(roundedRect: rect,
                                          xRadius: dimension * 0.18,
                                          yRadius: dimension * 0.18)
        NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
        backgroundPath.fill()

        let inset = dimension * 0.12
        let strokeRect = rect.insetBy(dx: inset, dy: inset)
        let dashPath = NSBezierPath(roundedRect: strokeRect,
                                    xRadius: strokeRect.width * 0.18,
                                    yRadius: strokeRect.height * 0.18)
        let pattern: [CGFloat] = [dimension * 0.16, dimension * 0.10]
        pattern.withUnsafeBufferPointer { buffer in
            dashPath.setLineDash(buffer.baseAddress, count: pattern.count, phase: 0)
        }
        dashPath.lineWidth = max(1, dimension * 0.05)
        NSColor.quaternaryLabelColor.setStroke()
        dashPath.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }()
}
