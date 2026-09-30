import Foundation
import AppKit
import Combine
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Carbon
import Carbon.HIToolbox
import ServiceManagement
@preconcurrency import UserNotifications

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .system: return .appearanceModeFollowSystem
        case .light: return .appearanceModeLight
        case .dark: return .appearanceModeDark
        }
    }
}


final class AppStore: ObservableObject {

    struct PageIndicatorOverride: Codable, Equatable {
        var offset: Double
        var topPadding: Double
    }

    enum AppearanceLayoutMode: String, CaseIterable, Codable, Identifiable {
        case fullscreen
        case compact

        var id: String { rawValue }
    }

    enum FolderLayoutMode: String, CaseIterable, Identifiable {
        case paged
        case vertical

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .paged: return .folderLayoutPaged
            case .vertical: return .folderLayoutVertical
            }
        }
    }

    enum TrackpadVerticalDirection: String, CaseIterable, Identifiable {
        case natural
        case reversed

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .natural: return .trackpadVerticalDirectionNatural
            case .reversed: return .trackpadVerticalDirectionReversed
            }
        }
    }

    struct ModeScopedAppearanceSettings: Codable, Equatable {
        var iconScale: Double
        var iconLabelFontSize: Double
        var folderDropZoneScale: Double
        var pageIndicatorOffset: Double
        var pageIndicatorTopPadding: Double
        var pageIndicatorPerDisplayEnabled: Bool
        var pageIndicatorOverrides: [String: PageIndicatorOverride]
    }

    struct DualModeAppearanceSettings: Codable, Equatable {
        var fullscreen: ModeScopedAppearanceSettings
        var compact: ModeScopedAppearanceSettings

        subscript(mode: AppearanceLayoutMode) -> ModeScopedAppearanceSettings {
            get {
                switch mode {
                case .fullscreen: return fullscreen
                case .compact: return compact
                }
            }
            set {
                switch mode {
                case .fullscreen: fullscreen = newValue
                case .compact: compact = newValue
                }
            }
        }
    }

    struct RGBAColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(_ color: Color) {
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            self.red = Double(min(max(r, 0), 1))
            self.green = Double(min(max(g, 0), 1))
            self.blue = Double(min(max(b, 0), 1))
            self.alpha = Double(min(max(a, 0), 1))
        }

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    enum BackgroundStyle: String, CaseIterable, Identifiable {
        case blur
        case glass
        case unfiltered

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .blur: return .backgroundStyleOptionBlur
            case .glass: return .backgroundStyleOptionGlass
            case .unfiltered: return .backgroundStyleOptionUnfiltered
            }
        }
    }

    enum BackgroundImageSource: String, CaseIterable, Identifiable {
        case desktopPreview
        case desktopWallpaper
        case customImage

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .desktopPreview: return .backgroundImageSourceDesktopPreview
            case .desktopWallpaper: return .backgroundImageSourceDesktopWallpaper
            case .customImage: return .backgroundImageSourceCustomImage
            }
        }
    }

    enum DockDragSide: String, CaseIterable, Codable, Identifiable {
        case disabled
        case bottom
        case left
        case right

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .disabled: return .dockDragDisabled
            case .bottom: return .dockDragSideBottom
            case .left: return .dockDragSideLeft
            case .right: return .dockDragSideRight
            }
        }
    }

    enum HotCornerPosition: String, CaseIterable, Codable, Identifiable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .topLeft: return .hotCornerPositionTopLeft
            case .topRight: return .hotCornerPositionTopRight
            case .bottomLeft: return .hotCornerPositionBottomLeft
            case .bottomRight: return .hotCornerPositionBottomRight
            }
        }
    }

    // Experimental tap behavior used by the low-level gesture monitor.
    // If gesture support is removed later, this enum can be deleted together
    // with the gesture keys and @Published fields below.
    enum GestureTapAction: String, CaseIterable, Codable, Identifiable {
        case off
        case open
        case toggle

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .off: return .gestureTapActionOff
            case .open: return .gestureTapActionOpen
            case .toggle: return .gestureTapActionToggle
            }
        }
    }

    enum GestureFingerCount: Int, CaseIterable, Codable, Identifiable {
        case four = 4
        case five = 5

        var id: Int { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .four: return .gestureFingerCountFour
            case .five: return .gestureFingerCountFive
            }
        }

        var minimumOpenParticipatingFingerCount: Int {
            switch self {
            case .four: return 3
            case .five: return 4
            }
        }
    }

    enum DevelopmentBackgroundOverride: String, CaseIterable, Identifiable {
        case none
        case solidWhite
        case solidBlack

        var id: String { rawValue }

        var color: Color? {
            switch self {
            case .none:
                return nil
            case .solidWhite:
                return .white
            case .solidBlack:
                return .black
            }
        }
    }

    enum SidebarIconPreset: String, CaseIterable, Identifiable {
        case large
        case medium

        var id: String { rawValue }
        
        var localizationKeyTitle: LocalizationKey {
            switch self {
            case .large: return .sidebarIconSizeLarge
            case .medium: return .sidebarIconSizeMedium
            }
        }
    }

    enum IconLabelFontWeightOption: String, CaseIterable, Identifiable {
        case light
        case regular
        case medium
        case semibold
        case bold

        var id: String { rawValue }

        var fontWeight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var displayName: String {
            switch self {
            case .light: return "Light"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .semibold: return "Semibold"
            case .bold: return "Bold"
            }
        }
    }

    static let customTitlesKey = "customAppTitles"
    static let hiddenAppsKey = "hiddenAppBundlePaths"
    // Deliberately still "LaunchNext", not the current product name: this is
    // the persistent-domain name a pre-bundle-ID-era install used, kept
    // exactly as-is so migrating from that specific historical artifact
    // still works regardless of what this app is called today.
    static let legacyPreferencesDomain = "LaunchNext"
    private static let legacyPreferencesMigrationKey = "didMigratePreferencesFromLaunchNGBundleID"
    static let gridColumnsKey = "gridColumnsPerPage"
    static let gridRowsKey = "gridRowsPerPage"
    static let columnSpacingKey = "gridColumnSpacing"
    static let rowSpacingKey = "gridRowSpacing"
    static let folderColumnSpacingKey = "folderGridColumnSpacing"
    static let folderRowSpacingKey = "folderGridRowSpacing"
    static let iconLabelFontWeightKey = "iconLabelFontWeight"
    static let showQuickRefreshButtonKey = "showQuickRefreshButton"
    static let lockLayoutKey = "lockLayoutEnabled"
    static let rememberPageKey = "rememberLastPage"
    static let rememberedPageIndexKey = "rememberedPageIndex"
    static let globalHotKeyKey = "globalHotKeyConfiguration"
    static let hoverMagnificationKey = "enableHoverMagnification"
    static let hoverMagnificationScaleKey = "hoverMagnificationScale"
    static let activePressEffectKey = "enableActivePressEffect"
    static let activePressScaleKey = "activePressScale"
    static let reverseWheelPagingKey = "reverseWheelPagingDirection"
    static let reverseWheelVerticalKey = "reverseWheelVerticalDirection"
    static let trackpadVerticalDirectionKey = "trackpadVerticalDirection"
    static let hideMenuBarKey = "hideMenuBar"
    static let folderLayoutModeKey = "folderLayoutMode"
    static let windowOpenAnimationKey = "windowOpenAnimationEnabled"
    static let windowShadowEnabledKey = "windowShadowEnabled"
    static let compactWindowMaxWidthKey = "compactWindowMaxWidth"
    static let compactWindowMaxHeightKey = "compactWindowMaxHeight"
    static let windowAnimationDurationKey = "windowAnimationDuration"
    static let developmentEnableCLICodeKey = "developmentEnableCLICode"
    static let showQuarantineRemovalActionKey = "showQuarantineRemovalAction"
    static let fuzzySearchEnabledKey = "fuzzySearchEnabled"
    static let searchDebounceMillisecondsKey = "searchDebounceMilliseconds"
    static let dockDragEnabledKey = "dockDragEnabled"
    static let dockDragSideKey = "dockDragSide"
    static let dockDragTriggerDistanceKey = "dockDragTriggerDistance"
    static let hotCornerEnabledKey = "hotCornerEnabled"
    static let hotCornerPositionKey = "hotCornerPosition"
    static let hotCornerTriggerDelayKey = "hotCornerTriggerDelay"
    static let hotCornerHitboxSizeKey = "hotCornerHitboxSize"
    static let hotCornerToggleWhenOpenKey = "hotCornerToggleWhenOpen"
    // Experimental gesture persistence keys.
    // Safe to remove together with LaunchNG/Gesture/ and gesture UI wiring
    // if the private multitouch feature is dropped later.
    static let gestureEnabledKey = "gestureEnabled"
    static let gestureCloseOnPinchOutKey = "gestureCloseOnPinchOut"
    static let gestureTapActionKey = "gestureTapAction"
    static let gestureFingerCountKey = "gestureFingerCount"
    static let gestureDeviceSelectionModeKey = "gestureDeviceSelectionMode"
    static let gestureSelectedDeviceIDsKey = "gestureSelectedDeviceIDs"
    static let gestureShowAllInputDevicesKey = "gestureShowAllInputDevices"
    static let searchDebounceMillisecondsRange: ClosedRange<Double> = 100...600
    private static let cliShimMarker = "# LaunchNG CLI shim"
    private static let cliPathSnippetHeader = "# >>> LaunchNG CLI >>>"
    private static let cliPathSnippetFooter = "# <<< LaunchNG CLI <<<"
    static let backgroundStyleKey = "launchpadBackgroundStyle"
    static let backgroundImageEnabledKey = "launchpadBackgroundImageEnabled"
    static let backgroundImageSourceKey = "launchpadBackgroundImageSource"
    static let customBackgroundImagePathKey = "launchpadCustomBackgroundImagePath"
    static let backgroundMaskEnabledKey = "launchpadBackgroundMaskEnabled"
    static let backgroundMaskLightKey = "launchpadBackgroundMaskLight"
    static let backgroundMaskDarkKey = "launchpadBackgroundMaskDark"
    static let folderLiquidGlassKey = "folderLiquidGlassEnabled"
    private static let folderLiquidGlassDefaultMigrationKey = "folderLiquidGlassDefaultEnabledV1"
    static let folderPreviewHighResKey = "folderPreviewHighRes"
    static let folderQuickLaunchEnabledKey = "folderQuickLaunchEnabled"
    static let sidebarIconPresetKey = "sidebarIconPreset"
    static let uninstallToolAppPathKey = "uninstallToolAppPath"
    static let pageIndicatorPerDisplayEnabledKey = "pageIndicatorPerDisplayEnabled"
    static let pageIndicatorPerDisplayOverridesKey = "pageIndicatorPerDisplayOverrides"
    static let dualModeAppearanceSettingsKey = "dualModeAppearanceSettings"
    private static let gameControllerEnabledKey = "gameControllerEnabled"
    static let gameControllerMenuToggleKey = "gameControllerMenuToggleLaunchpad"
    private static let soundEffectsEnabledKey = "soundEffectsEnabled"

    static func loadFolderLiquidGlassEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: folderLiquidGlassKey) as? Bool ?? true
    }

    static func migrateFolderLiquidGlassDefaultIfNeeded(from defaults: UserDefaults) {
        // Enable once for both new and existing installations. Keep the marker
        // across appearance resets so later manual opt-outs remain respected.
        if !defaults.bool(forKey: folderLiquidGlassDefaultMigrationKey) {
            defaults.set(true, forKey: folderLiquidGlassKey)
            defaults.set(true, forKey: folderLiquidGlassDefaultMigrationKey)
        }
    }

    static func migrateLegacyPreferencesIfNeeded(
        defaults: UserDefaults = .standard,
        currentDomain: String? = Bundle.main.bundleIdentifier
    ) {
        guard let currentDomain,
              !currentDomain.isEmpty,
              currentDomain != legacyPreferencesDomain else { return }

        var currentPreferences = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard currentPreferences[legacyPreferencesMigrationKey] as? Bool != true else { return }

        if let legacyPreferences = defaults.persistentDomain(forName: legacyPreferencesDomain) {
            for (key, value) in legacyPreferences where currentPreferences[key] == nil {
                currentPreferences[key] = value
            }
        }

        currentPreferences[legacyPreferencesMigrationKey] = true
        defaults.setPersistentDomain(currentPreferences, forName: currentDomain)
    }

    private static let soundLaunchpadOpenKey = "soundLaunchpadOpenSound"
    private static let soundLaunchpadCloseKey = "soundLaunchpadCloseSound"
    private static let soundNavigationKey = "soundNavigationSound"
    private static let voiceFeedbackEnabledKey = "voiceFeedbackEnabled"
    static let folderDropZoneScaleKey = "folderDropZoneScale"
    static let pageIndicatorTopPaddingKey = "pageIndicatorTopPadding"
    private static let pageIndicatorOffsetReducedV1Key = "pageIndicatorOffsetReducedV1"
    static let onboardingVersionKey = "onboardingVersionShown"
    static let currentOnboardingVersion = 1
    static let dockDragTriggerDistanceRange: ClosedRange<Double> = 8...72
    static let defaultDockDragTriggerDistance: Double = 50
    static let hotCornerTriggerDelayRange: ClosedRange<Double> = 0...1.2
    static let hotCornerHitboxSizeRange: ClosedRange<Double> = 20...120
    static let defaultHotCornerTriggerDelay: Double = 0.25
    static let defaultHotCornerHitboxSize: Double = 50
    // private static let aiFeatureEnabledKey = "aiFeatureEnabled"
    // private static let aiOverlayHotKeyKey = "aiOverlayHotKeyConfiguration"

    private static func loadHiddenApps() -> Set<String> {
        if let array = UserDefaults.standard.array(forKey: hiddenAppsKey) as? [String] {
            return Set(array)
        }
        return []
    }

    private static func loadBackgroundStyle() -> BackgroundStyle {
        if let raw = UserDefaults.standard.string(forKey: backgroundStyleKey),
           let style = BackgroundStyle(rawValue: raw) {
            return style
        }
        return .glass
    }

    private static func loadFolderLayoutMode(from defaults: UserDefaults = .standard,
                                             isExistingInstall: Bool? = nil) -> FolderLayoutMode {
        if let raw = defaults.string(forKey: folderLayoutModeKey),
           let mode = FolderLayoutMode(rawValue: raw) {
            return mode
        }
        let existingInstall = isExistingInstall ?? (
            defaults.object(forKey: onboardingVersionKey) != nil ||
            defaults.object(forKey: "isFullscreenMode") != nil ||
            defaults.object(forKey: gridColumnsKey) != nil
        )
        return existingInstall ? .vertical : .paged
    }

    private static let defaultBackgroundMaskOpacity: Double = 0.1
    private static let defaultBackgroundMaskColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: defaultBackgroundMaskOpacity)

    private static func loadBackgroundMaskEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: backgroundMaskEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: backgroundMaskEnabledKey)
    }

    private static func loadBackgroundMaskColor(forKey key: String) -> RGBAColor {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return defaultBackgroundMaskColor
        }
        if let decoded = try? JSONDecoder().decode(RGBAColor.self, from: data) {
            return decoded
        }
        UserDefaults.standard.removeObject(forKey: key)
        return defaultBackgroundMaskColor
    }

    private static func persistBackgroundMaskColor(_ color: RGBAColor, forKey key: String) {
        if let data = try? JSONEncoder().encode(color) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static let minColumnsPerPage = 4
    private static let maxColumnsPerPage = 10
    private static let minRowsPerPage = 3
    private static let maxRowsPerPage = 8
    private static let minColumnSpacing: Double = 8
    private static let maxColumnSpacing: Double = 50
    private static let minRowSpacing: Double = 6
    private static let maxRowSpacing: Double = 40
    private static let defaultGridColumnsPerPage = 7
    private static let defaultGridRowsPerPage = 5
    private static let defaultColumnSpacing: Double = 20
    private static let defaultRowSpacing: Double = 14
    private static let defaultFolderColumnSpacing: Double = 22
    private static let defaultFolderRowSpacing: Double = 18
    private static let defaultIconScale: Double = 0.95
    private static let defaultIconLabelFontSize: Double = 11.0
    static let defaultScrollSensitivity: Double = 0.2
    static var gridColumnRange: ClosedRange<Int> { minColumnsPerPage...maxColumnsPerPage }
    static var gridRowRange: ClosedRange<Int> { minRowsPerPage...maxRowsPerPage }
    static var columnSpacingRange: ClosedRange<Double> { minColumnSpacing...maxColumnSpacing }
    static var rowSpacingRange: ClosedRange<Double> { minRowSpacing...maxRowSpacing }
    // Folders reuse the main grid's min/max: same physical icon sizing, just
    // a separate stored value and default so the two aren't forced in sync
    // (a folder panel is much smaller than the main grid, so the same shared
    // spacing number can look right in one and cramped/sparse in the other).
    static var folderColumnSpacingRange: ClosedRange<Double> { minColumnSpacing...maxColumnSpacing }
    static var folderRowSpacingRange: ClosedRange<Double> { minRowSpacing...maxRowSpacing }
    static let hoverMagnificationRange: ClosedRange<Double> = 1.0...1.4
    private static let defaultHoverMagnificationScale: Double = 1.1
    static let activePressScaleRange: ClosedRange<Double> = 0.85...1.0
    private static let defaultActivePressScale: Double = 0.92
    static let folderPopoverWidthRange: ClosedRange<Double> = 0.6...0.95
    static let folderPopoverHeightRange: ClosedRange<Double> = 0.6...0.95
    private static let defaultFolderPopoverWidth: Double = 0.9
    private static let defaultFolderPopoverHeight: Double = 0.85
    static let folderDropZoneScaleRange: ClosedRange<Double> = 0.6...2.0
    static let defaultFolderDropZoneScale: Double = 1.6
    private static let defaultPageIndicatorOffset: Double = 27.0
    static let pageIndicatorTopPaddingRange: ClosedRange<Double> = 0...60
    static let defaultPageIndicatorTopPadding: Double = 12
    private static let defaultAnimationDuration: Double = 0.3
    static let windowAnimationDurationRange: ClosedRange<Double> = 0.1...0.5
    private static let defaultWindowAnimationDuration: Double = 0.25
    private static let defaultLaunchpadOpenSound = "Submarine"
    private static let defaultLaunchpadCloseSound = "Glass"
    private static let defaultNavigationSound = "Tink"

    private static func normalizedSoundName(_ raw: String?, defaultValue: String) -> String {
        guard let raw else { return defaultValue }
        if raw.isEmpty { return "" }
        return SoundManager.isValidSystemSoundName(raw) ? raw : defaultValue
    }

    struct HotKeyConfiguration: Equatable {
        let keyCode: UInt16
        let modifiersRawValue: NSEvent.ModifierFlags.RawValue

        init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
            self.keyCode = keyCode
            self.modifiersRawValue = modifierFlags.normalizedShortcutFlags.rawValue
        }

        init?(dictionary: [String: Any]) {
            guard let rawKeyCode = dictionary["keyCode"] as? Int,
                  let rawModifiers = dictionary["modifiers"] as? Int else {
                return nil
            }
            self.keyCode = UInt16(rawKeyCode)
            self.modifiersRawValue = NSEvent.ModifierFlags.RawValue(rawModifiers)
        }

        var modifierFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifiersRawValue).normalizedShortcutFlags
        }

        var dictionaryRepresentation: [String: Any] {
            ["keyCode": Int(keyCode), "modifiers": Int(modifiersRawValue)]
        }

        var carbonModifierFlags: UInt32 { modifierFlags.carbonFlags }
        var keyCodeUInt32: UInt32 { UInt32(keyCode) }

        var displayString: String {
            let modifierSymbols = modifierFlags.displaySymbols.joined()
            let keyName = HotKeyConfiguration.keyDisplayName(for: keyCode)
            return modifierSymbols + keyName
        }

        private static func keyDisplayName(for keyCode: UInt16) -> String {
            if let special = Self.specialKeyNames[keyCode] {
                return special
            }

            guard let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let rawPtr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
                return String(format: "Key %d", keyCode)
            }

            let data = unsafeBitCast(rawPtr, to: CFData.self) as Data
            return data.withUnsafeBytes { ptr -> String in
                guard let layoutPtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return String(format: "Key %d", keyCode)
                }
                var keysDown: UInt32 = 0
                var chars: [UniChar] = Array(repeating: 0, count: 4)
                var length: Int = 0
                let error = UCKeyTranslate(layoutPtr,
                                           keyCode,
                                           UInt16(kUCKeyActionDisplay),
                                           0,
                                           UInt32(LMGetKbdType()),
                                           UInt32(kUCKeyTranslateNoDeadKeysBit),
                                           &keysDown,
                                           chars.count,
                                           &length,
                                           &chars)
                if error == noErr, length > 0 {
                    return String(utf16CodeUnits: chars, count: length).uppercased()
                }
                return fallbackName(for: keyCode)
            }
        }

        private static func fallbackName(for keyCode: UInt16) -> String {
            Self.specialKeyNames[keyCode] ?? String(format: "Key %d", keyCode)
        }

        private static let specialKeyNames: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑"
        ]
    }
    @Published var apps: [AppInfo] = []
    @Published var folders: [FolderInfo] = []
    let searchEngine = LaunchpadSearchEngine()
    @Published var items: [LaunchpadItem] = [] {
        didSet {
            searchEngine.updateIndex(for: items)
        }
    }
    @Published private(set) var missingPlaceholders: [String: MissingAppPlaceholder] = [:]
    @Published private(set) var hiddenAppPaths: Set<String> = AppStore.loadHiddenApps()

    private func persistHiddenApps(_ set: Set<String>) {
        let array = Array(set).sorted()
        UserDefaults.standard.set(array, forKey: Self.hiddenAppsKey)
    }

    private func updateHiddenAppPaths(_ changes: (inout Set<String>) -> Void) {
        var updated = hiddenAppPaths
        let original = updated
        changes(&updated)
        guard updated != original else { return }
        hiddenAppPaths = updated
        persistHiddenApps(updated)
    }

    @Published var launchpadBackgroundStyle: BackgroundStyle = AppStore.loadBackgroundStyle() {
        didSet {
            guard launchpadBackgroundStyle != oldValue else { return }
            UserDefaults.standard.set(launchpadBackgroundStyle.rawValue, forKey: Self.backgroundStyleKey)
        }
    }

    @Published var backgroundImageEnabled: Bool = {
        UserDefaults.standard.object(forKey: AppStore.backgroundImageEnabledKey) as? Bool ?? false
    }() {
        didSet {
            guard backgroundImageEnabled != oldValue else { return }
            UserDefaults.standard.set(backgroundImageEnabled, forKey: Self.backgroundImageEnabledKey)
        }
    }

    @Published var backgroundImageSource: BackgroundImageSource = {
        guard let raw = UserDefaults.standard.string(forKey: AppStore.backgroundImageSourceKey),
              let source = BackgroundImageSource(rawValue: raw) else {
            return .desktopPreview
        }
        return source
    }() {
        didSet {
            guard backgroundImageSource != oldValue else { return }
            UserDefaults.standard.set(backgroundImageSource.rawValue, forKey: Self.backgroundImageSourceKey)
        }
    }

    @Published var customBackgroundImagePath: String = {
        UserDefaults.standard.string(forKey: AppStore.customBackgroundImagePathKey) ?? ""
    }() {
        didSet {
            guard customBackgroundImagePath != oldValue else { return }
            UserDefaults.standard.set(customBackgroundImagePath, forKey: Self.customBackgroundImagePathKey)
        }
    }

    // Development-only override to capture flat screenshots quickly.
    @Published var developmentBackgroundOverride: DevelopmentBackgroundOverride = .none

    @Published var developmentEnableCLICode: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.developmentEnableCLICodeKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.developmentEnableCLICodeKey)
    }() {
        didSet {
            UserDefaults.standard.set(developmentEnableCLICode, forKey: Self.developmentEnableCLICodeKey)
            if developmentEnableCLICode && !oldValue {
                installCLICommandIfNeeded()
            } else if !developmentEnableCLICode && oldValue {
                uninstallCLICommandIfNeeded()
            }
        }
    }

    @Published var showQuarantineRemovalAction: Bool = {
        UserDefaults.standard.object(forKey: AppStore.showQuarantineRemovalActionKey) as? Bool ?? false
    }() {
        didSet {
            guard showQuarantineRemovalAction != oldValue else { return }
            UserDefaults.standard.set(showQuarantineRemovalAction, forKey: Self.showQuarantineRemovalActionKey)
        }
    }

    @Published var wallpaperDiagnosticsEnabled = WallpaperDiagnostics.isEnabled {
        didSet { WallpaperDiagnostics.isEnabled = wallpaperDiagnosticsEnabled }
    }

    @Published var backgroundMaskEnabled: Bool = AppStore.loadBackgroundMaskEnabled() {
        didSet {
            UserDefaults.standard.set(backgroundMaskEnabled, forKey: Self.backgroundMaskEnabledKey)
        }
    }

    @Published var backgroundMaskLightColor: RGBAColor = AppStore.loadBackgroundMaskColor(forKey: AppStore.backgroundMaskLightKey) {
        didSet {
            AppStore.persistBackgroundMaskColor(backgroundMaskLightColor, forKey: Self.backgroundMaskLightKey)
        }
    }

    @Published var backgroundMaskDarkColor: RGBAColor = AppStore.loadBackgroundMaskColor(forKey: AppStore.backgroundMaskDarkKey) {
        didSet {
            AppStore.persistBackgroundMaskColor(backgroundMaskDarkColor, forKey: Self.backgroundMaskDarkKey)
        }
    }

    @Published var sidebarIconPreset: SidebarIconPreset = {
        if let raw = UserDefaults.standard.string(forKey: AppStore.sidebarIconPresetKey),
           let preset = SidebarIconPreset(rawValue: raw) {
            return preset
        }
        return .large
    }() {
        didSet {
            guard sidebarIconPreset != oldValue else { return }
            UserDefaults.standard.set(sidebarIconPreset.rawValue, forKey: Self.sidebarIconPresetKey)
        }
    }

    // One catalogue supplies both effective export values and the appearance
    // import allowlist. Reading it must not register or persist defaults.
    private var appearanceBackupValues: [String: Any] {
        [
            Self.sidebarIconPresetKey: sidebarIconPreset.rawValue,
            Self.backgroundStyleKey: launchpadBackgroundStyle.rawValue,
            Self.backgroundImageEnabledKey: backgroundImageEnabled,
            Self.backgroundImageSourceKey: backgroundImageSource.rawValue,
            Self.customBackgroundImagePathKey: customBackgroundImagePath,
            Self.backgroundMaskEnabledKey: backgroundMaskEnabled,
            "scrollSensitivity": scrollSensitivity,
            "isFullscreenMode": isFullscreenMode,
            "showLabels": showLabels,
            "hideDock": hideDock,
            Self.hideMenuBarKey: hideMenuBar,
            "enableAnimations": enableAnimations,
            Self.windowOpenAnimationKey: enableWindowOpenAnimation,
            Self.windowShadowEnabledKey: windowShadowEnabled,
            Self.compactWindowMaxWidthKey: compactWindowMaxWidth,
            Self.compactWindowMaxHeightKey: compactWindowMaxHeight,
            Self.windowAnimationDurationKey: windowAnimationDuration,
            "useLocalizedThirdPartyTitles": useLocalizedThirdPartyTitles,
            "enableDropPrediction": enableDropPrediction,
            Self.reverseWheelPagingKey: reverseWheelPagingDirection,
            Self.reverseWheelVerticalKey: reverseWheelVerticalDirection,
            Self.trackpadVerticalDirectionKey: trackpadVerticalDirection.rawValue,
            Self.rememberPageKey: rememberLastPage,
            Self.rememberedPageIndexKey: UserDefaults.standard.integer(forKey: Self.rememberedPageIndexKey),
            "iconScale": iconScale,
            "iconLabelFontSize": iconLabelFontSize,
            Self.iconLabelFontWeightKey: iconLabelFontWeight.rawValue,
            Self.gridColumnsKey: gridColumnsPerPage,
            Self.gridRowsKey: gridRowsPerPage,
            Self.columnSpacingKey: iconColumnSpacing,
            Self.rowSpacingKey: iconRowSpacing,
            Self.folderColumnSpacingKey: folderIconColumnSpacing,
            Self.folderRowSpacingKey: folderIconRowSpacing,
            Self.folderDropZoneScaleKey: folderDropZoneScale,
            Self.folderLiquidGlassKey: folderLiquidGlassEnabled,
            Self.folderPreviewHighResKey: enableHighResFolderPreviews,
            Self.folderQuickLaunchEnabledKey: folderQuickLaunchEnabled,
            Self.folderLayoutModeKey: folderLayoutMode.rawValue,
            "pageIndicatorOffset": pageIndicatorOffset,
            Self.pageIndicatorTopPaddingKey: pageIndicatorTopPadding,
            Self.pageIndicatorPerDisplayEnabledKey: pageIndicatorPerDisplayEnabled,
            Self.dockDragEnabledKey: dockDragEnabled,
            "folderPopoverWidthFactor": folderPopoverWidthFactor,
            "folderPopoverHeightFactor": folderPopoverHeightFactor,
            Self.hoverMagnificationKey: enableHoverMagnification,
            Self.hoverMagnificationScaleKey: hoverMagnificationScale,
            Self.activePressEffectKey: enableActivePressEffect,
            Self.activePressScaleKey: activePressScale,
            "animationDuration": animationDuration,
            Self.globalHotKeyKey: globalHotKey?.dictionaryRepresentation ?? [:],
            "showFPSOverlay": showFPSOverlay,
            Self.gameControllerEnabledKey: gameControllerEnabled,
            Self.gameControllerMenuToggleKey: gameControllerMenuTogglesLaunchpad
        ]
    }

    private var encodedAppearanceBackupValues: [String: any Encodable] {
        [
            Self.backgroundMaskLightKey: backgroundMaskLightColor,
            Self.backgroundMaskDarkKey: backgroundMaskDarkColor,
            Self.pageIndicatorPerDisplayOverridesKey: pageIndicatorOverrides,
            Self.dualModeAppearanceSettingsKey: dualModeAppearanceSettings
        ]
    }

    var appearanceBackupPreferenceKeys: Set<String> {
        Set(appearanceBackupValues.keys).union(encodedAppearanceBackupValues.keys)
    }

    func preferencesForBackup(persisted: [String: Any]) throws -> [String: Any] {
        var result = persisted
        result.merge(appearanceBackupValues) { _, effectiveValue in effectiveValue }
        let encoder = JSONEncoder()
        for (key, value) in encodedAppearanceBackupValues {
            result[key] = try encoder.encode(value)
        }
        // Developer tooling and diagnostic logging remain local to this Mac.
        result.removeValue(forKey: Self.showQuarantineRemovalActionKey)
        result.removeValue(forKey: WallpaperDiagnostics.enabledKey)
        return result
    }

    private static func writeDefaultAppearancePreferences(to defaults: UserDefaults) {
        defaults.set(SidebarIconPreset.large.rawValue, forKey: Self.sidebarIconPresetKey)
        defaults.set(AppearancePreference.system.rawValue, forKey: "appearancePreference")
        defaults.set(BackgroundStyle.glass.rawValue, forKey: Self.backgroundStyleKey)
        defaults.set(false, forKey: Self.backgroundImageEnabledKey)
        defaults.set(BackgroundImageSource.desktopPreview.rawValue, forKey: Self.backgroundImageSourceKey)
        defaults.set("", forKey: Self.customBackgroundImagePathKey)
        defaults.set(false, forKey: Self.backgroundMaskEnabledKey)
        Self.persistBackgroundMaskColor(Self.defaultBackgroundMaskColor, forKey: Self.backgroundMaskLightKey)
        Self.persistBackgroundMaskColor(Self.defaultBackgroundMaskColor, forKey: Self.backgroundMaskDarkKey)
        defaults.set(true, forKey: "isFullscreenMode")
        defaults.set(true, forKey: "showLabels")
        defaults.set(true, forKey: Self.folderPreviewHighResKey)
        defaults.set(false, forKey: Self.folderQuickLaunchEnabledKey)
        defaults.set(FolderLayoutMode.paged.rawValue, forKey: Self.folderLayoutModeKey)
        defaults.set(false, forKey: "hideDock")
        defaults.set(false, forKey: Self.hideMenuBarKey)
        defaults.set(0.8, forKey: "scrollSensitivity")
        defaults.set(Self.defaultGridColumnsPerPage, forKey: Self.gridColumnsKey)
        defaults.set(Self.defaultGridRowsPerPage, forKey: Self.gridRowsKey)
        defaults.set(Self.defaultColumnSpacing, forKey: Self.columnSpacingKey)
        defaults.set(Self.defaultRowSpacing, forKey: Self.rowSpacingKey)
        defaults.set(Self.defaultFolderColumnSpacing, forKey: Self.folderColumnSpacingKey)
        defaults.set(Self.defaultFolderRowSpacing, forKey: Self.folderRowSpacingKey)
        defaults.set(true, forKey: "enableDropPrediction")
        defaults.set(true, forKey: "enableAnimations")
        defaults.set(false, forKey: Self.hoverMagnificationKey)
        defaults.set(Self.defaultHoverMagnificationScale, forKey: Self.hoverMagnificationScaleKey)
        defaults.set(false, forKey: Self.activePressEffectKey)
        defaults.set(false, forKey: Self.reverseWheelPagingKey)
        defaults.set(false, forKey: Self.reverseWheelVerticalKey)
        defaults.set(TrackpadVerticalDirection.natural.rawValue, forKey: Self.trackpadVerticalDirectionKey)
        defaults.set(Self.defaultActivePressScale, forKey: Self.activePressScaleKey)
        defaults.set(Self.defaultIconScale, forKey: "iconScale")
        defaults.set(Self.defaultIconLabelFontSize, forKey: "iconLabelFontSize")
        defaults.set(IconLabelFontWeightOption.medium.rawValue, forKey: Self.iconLabelFontWeightKey)
        defaults.set(Self.defaultAnimationDuration, forKey: "animationDuration")
        defaults.set(true, forKey: Self.windowOpenAnimationKey)
        defaults.set(false, forKey: Self.windowShadowEnabledKey)
        defaults.set(0, forKey: Self.compactWindowMaxWidthKey)
        defaults.set(0, forKey: Self.compactWindowMaxHeightKey)
        defaults.set(Self.defaultWindowAnimationDuration, forKey: Self.windowAnimationDurationKey)
        defaults.set(true, forKey: "useLocalizedThirdPartyTitles")
        defaults.set(Self.defaultPageIndicatorOffset, forKey: "pageIndicatorOffset")
        defaults.set(Self.defaultPageIndicatorTopPadding, forKey: Self.pageIndicatorTopPaddingKey)
        defaults.set(false, forKey: Self.pageIndicatorPerDisplayEnabledKey)
        defaults.removeObject(forKey: Self.pageIndicatorPerDisplayOverridesKey)
        defaults.set(true, forKey: Self.rememberPageKey)
        defaults.removeObject(forKey: Self.rememberedPageIndexKey)
        defaults.set(Self.defaultFolderPopoverWidth, forKey: "folderPopoverWidthFactor")
        defaults.set(Self.defaultFolderPopoverHeight, forKey: "folderPopoverHeightFactor")
        defaults.set(false, forKey: "showFPSOverlay")
        if let data = try? JSONEncoder().encode(Self.defaultDualModeAppearanceSettings) {
            defaults.set(data, forKey: Self.dualModeAppearanceSettingsKey)
        }
    }

    private func reloadAppearancePreferencesFromDefaults() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Self.sidebarIconPresetKey),
           let preset = SidebarIconPreset(rawValue: raw) {
            sidebarIconPreset = preset
        } else {
            sidebarIconPreset = .large
        }

        if let raw = defaults.string(forKey: "appearancePreference"),
           let preference = AppearancePreference(rawValue: raw) {
            appearancePreference = preference
        } else {
            appearancePreference = .system
        }

        launchpadBackgroundStyle = Self.loadBackgroundStyle()
        backgroundImageEnabled = defaults.object(forKey: Self.backgroundImageEnabledKey) as? Bool ?? false
        if let raw = defaults.string(forKey: Self.backgroundImageSourceKey),
           let source = BackgroundImageSource(rawValue: raw) {
            backgroundImageSource = source
        } else {
            backgroundImageSource = .desktopPreview
        }
        customBackgroundImagePath = defaults.string(forKey: Self.customBackgroundImagePathKey) ?? ""
        backgroundMaskEnabled = Self.loadBackgroundMaskEnabled()
        backgroundMaskLightColor = Self.loadBackgroundMaskColor(forKey: Self.backgroundMaskLightKey)
        backgroundMaskDarkColor = Self.loadBackgroundMaskColor(forKey: Self.backgroundMaskDarkKey)

        isFullscreenMode = defaults.object(forKey: "isFullscreenMode") as? Bool ?? true
        showLabels = defaults.object(forKey: "showLabels") as? Bool ?? true
        folderLiquidGlassEnabled = Self.loadFolderLiquidGlassEnabled(from: defaults)
        enableHighResFolderPreviews = defaults.object(forKey: Self.folderPreviewHighResKey) as? Bool ?? true
        folderQuickLaunchEnabled = defaults.object(forKey: Self.folderQuickLaunchEnabledKey) as? Bool ?? false
        folderLayoutMode = Self.loadFolderLayoutMode(from: defaults, isExistingInstall: nil)
        hideDock = defaults.object(forKey: "hideDock") as? Bool ?? false
        hideMenuBar = defaults.object(forKey: Self.hideMenuBarKey) as? Bool ?? false
        scrollSensitivity = defaults.object(forKey: "scrollSensitivity") as? Double ?? 0.8
        gridColumnsPerPage = Self.clampColumns(defaults.object(forKey: Self.gridColumnsKey) as? Int ?? Self.defaultGridColumnsPerPage)
        gridRowsPerPage = Self.clampRows(defaults.object(forKey: Self.gridRowsKey) as? Int ?? Self.defaultGridRowsPerPage)
        iconColumnSpacing = Self.clampColumnSpacing(defaults.object(forKey: Self.columnSpacingKey) as? Double ?? Self.defaultColumnSpacing)
        iconRowSpacing = Self.clampRowSpacing(defaults.object(forKey: Self.rowSpacingKey) as? Double ?? Self.defaultRowSpacing)
        folderIconColumnSpacing = Self.clampColumnSpacing(defaults.object(forKey: Self.folderColumnSpacingKey) as? Double ?? Self.defaultFolderColumnSpacing)
        folderIconRowSpacing = Self.clampRowSpacing(defaults.object(forKey: Self.folderRowSpacingKey) as? Double ?? Self.defaultFolderRowSpacing)
        enableDropPrediction = defaults.object(forKey: "enableDropPrediction") as? Bool ?? true
        enableAnimations = defaults.object(forKey: "enableAnimations") as? Bool ?? true
        enableHoverMagnification = defaults.object(forKey: Self.hoverMagnificationKey) as? Bool ?? false
        hoverMagnificationScale = defaults.object(forKey: Self.hoverMagnificationScaleKey) as? Double ?? Self.defaultHoverMagnificationScale
        enableActivePressEffect = defaults.object(forKey: Self.activePressEffectKey) as? Bool ?? false
        reverseWheelPagingDirection = defaults.object(forKey: Self.reverseWheelPagingKey) as? Bool ?? false
        reverseWheelVerticalDirection = defaults.object(forKey: Self.reverseWheelVerticalKey) as? Bool ?? false
        trackpadVerticalDirection = defaults.string(forKey: Self.trackpadVerticalDirectionKey)
            .flatMap(TrackpadVerticalDirection.init(rawValue:)) ?? .natural
        activePressScale = defaults.object(forKey: Self.activePressScaleKey) as? Double ?? Self.defaultActivePressScale
        useLocalizedThirdPartyTitles = defaults.object(forKey: "useLocalizedThirdPartyTitles") as? Bool ?? true
        iconLabelFontWeight = defaults.string(forKey: Self.iconLabelFontWeightKey).flatMap(IconLabelFontWeightOption.init(rawValue:)) ?? .medium
        showFPSOverlay = defaults.object(forKey: "showFPSOverlay") as? Bool ?? false
        enableWindowOpenAnimation = defaults.object(forKey: Self.windowOpenAnimationKey) as? Bool ?? true
        windowShadowEnabled = defaults.object(forKey: Self.windowShadowEnabledKey) as? Bool ?? false
        compactWindowMaxWidth = CompactWindowLayout.normalizedMaximumWidth(defaults.integer(forKey: Self.compactWindowMaxWidthKey))
        compactWindowMaxHeight = CompactWindowLayout.normalizedMaximumHeight(defaults.integer(forKey: Self.compactWindowMaxHeightKey))
        windowAnimationDuration = Self.clampWindowAnimationDuration(
            defaults.object(forKey: Self.windowAnimationDurationKey) as? Double ?? Self.defaultWindowAnimationDuration
        )
        rememberLastPage = defaults.object(forKey: Self.rememberPageKey) as? Bool ?? true
        folderPopoverWidthFactor = Self.clampFolderWidth(defaults.object(forKey: "folderPopoverWidthFactor") as? Double ?? Self.defaultFolderPopoverWidth)
        folderPopoverHeightFactor = Self.clampFolderHeight(defaults.object(forKey: "folderPopoverHeightFactor") as? Double ?? Self.defaultFolderPopoverHeight)

        if let storedDualModeAppearance = Self.loadDualModeAppearanceSettings(from: defaults) {
            dualModeAppearanceSettings = storedDualModeAppearance
        } else {
            let legacy = Self.legacyAppearanceSettings(from: defaults)
            dualModeAppearanceSettings = DualModeAppearanceSettings(fullscreen: legacy, compact: legacy)
            persistDualModeAppearanceSettings()
        }
        syncActiveAppearanceProxies(from: currentAppearanceLayoutMode)
        persistLegacyAppearanceProxyValues()

        iconScale = dualModeAppearanceSettings[currentAppearanceLayoutMode].iconScale
        iconLabelFontSize = dualModeAppearanceSettings[currentAppearanceLayoutMode].iconLabelFontSize
        pageIndicatorOffset = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorOffset
        pageIndicatorTopPadding = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorTopPadding
        pageIndicatorPerDisplayEnabled = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorPerDisplayEnabled
        pageIndicatorOverrides = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorOverrides
        folderDropZoneScale = dualModeAppearanceSettings[currentAppearanceLayoutMode].folderDropZoneScale
        animationDuration = defaults.object(forKey: "animationDuration") as? Double ?? Self.defaultAnimationDuration
    }

    // Reload selected preferences from UserDefaults after an import
    func reloadPreferencesFromDefaults() {
        hiddenAppPaths = AppStore.loadHiddenApps()

        if let savedSources = UserDefaults.standard.array(forKey: AppStore.customAppSourcesKey) as? [String] {
            customAppSourcePaths = savedSources
        }

        uninstallToolAppPath = UserDefaults.standard.string(forKey: AppStore.uninstallToolAppPathKey) ?? ""
        reloadAppearancePreferencesFromDefaults()

        developmentEnableCLICode = UserDefaults.standard.object(forKey: Self.developmentEnableCLICodeKey) as? Bool ?? false
        showQuarantineRemovalAction = UserDefaults.standard.object(forKey: Self.showQuarantineRemovalActionKey) as? Bool ?? false
        wallpaperDiagnosticsEnabled = UserDefaults.standard.bool(forKey: WallpaperDiagnostics.enabledKey)
        fuzzySearchEnabled = UserDefaults.standard.object(forKey: Self.fuzzySearchEnabledKey) as? Bool ?? true
        searchDebounceMilliseconds = Self.clampedSearchDebounceMilliseconds(
            UserDefaults.standard.object(forKey: Self.searchDebounceMillisecondsKey) as? Double ?? 300
        )

        globalHotKey = Self.loadHotKeyConfiguration()
        gestureEnabled = UserDefaults.standard.object(forKey: Self.gestureEnabledKey) as? Bool ?? false
        gestureCloseOnPinchOut = UserDefaults.standard.object(forKey: Self.gestureCloseOnPinchOutKey) as? Bool ?? false
        gestureTapAction = GestureTapAction(rawValue: UserDefaults.standard.string(forKey: Self.gestureTapActionKey) ?? "") ?? .off
        gestureFingerCount = GestureFingerCount(rawValue: UserDefaults.standard.integer(forKey: Self.gestureFingerCountKey)) ?? .four
        gestureDeviceSelectionMode = GestureDeviceSelectionMode(rawValue: UserDefaults.standard.string(forKey: Self.gestureDeviceSelectionModeKey) ?? "") ?? .automatic
        gestureSelectedDeviceIDs = Array(Set(UserDefaults.standard.stringArray(forKey: Self.gestureSelectedDeviceIDsKey) ?? [])).sorted()
        gestureShowAllInputDevices = UserDefaults.standard.object(forKey: Self.gestureShowAllInputDevicesKey) as? Bool ?? false

        // Apply hidden filtering immediately
        pruneHiddenAppsFromAppList()
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        removeEmptyPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        refreshGestureDeviceInventory()
    }

    func refreshGestureDeviceInventory() {
        let provider = GestureTouchProvider()
        provider.refreshDevices()
        provider.configureDevices(mode: gestureDeviceSelectionMode, selectedDeviceIDs: gestureSelectedDeviceIDs)
        availableGestureDevices = provider.availableDevices.sorted {
            if $0.isBuiltIn != $1.isBuiltIn {
                return $0.isBuiltIn && !$1.isBuiltIn
            }
            if $0.isRecommended != $1.isRecommended {
                return $0.isRecommended && !$1.isRecommended
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var visibleGestureDevices: [GestureInputDevice] {
        gestureShowAllInputDevices ? availableGestureDevices : availableGestureDevices.filter(\.isRecommended)
    }

    var gestureUnavailableSelectionCount: Int {
        let availableIDs = Set(availableGestureDevices.map(\.id))
        return gestureSelectedDeviceIDs.filter { !availableIDs.contains($0) }.count
    }

    @Published var isSetting = false
    @Published var isInitialLoading = true
    @Published var shouldShowOnboarding: Bool = false
    @Published var currentPage = 0 {
        didSet {
            if currentPage < 0 { currentPage = 0; return }
            if rememberLastPage {
                UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
            }
        }
    }
    struct LayoutRevealRequest: Equatable {
        let id = UUID()
        let appPath: String
    }
    @Published var layoutRevealRequest: LayoutRevealRequest?

    @Published var searchText: String = ""
    @Published private(set) var searchQuery: String = ""
    @Published var fuzzySearchEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.fuzzySearchEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: AppStore.fuzzySearchEnabledKey)
    }() {
        didSet {
            guard fuzzySearchEnabled != oldValue else { return }
            UserDefaults.standard.set(fuzzySearchEnabled, forKey: Self.fuzzySearchEnabledKey)
        }
    }
    @Published var searchDebounceMilliseconds: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.searchDebounceMillisecondsKey) == nil { return 300 }
        return AppStore.clampedSearchDebounceMilliseconds(
            defaults.object(forKey: AppStore.searchDebounceMillisecondsKey) as? Double ?? 300
        )
    }() {
        didSet {
            let clamped = Self.clampedSearchDebounceMilliseconds(searchDebounceMilliseconds)
            if searchDebounceMilliseconds != clamped {
                searchDebounceMilliseconds = clamped
                return
            }
            guard searchDebounceMilliseconds != oldValue else { return }
            UserDefaults.standard.set(searchDebounceMilliseconds, forKey: Self.searchDebounceMillisecondsKey)
            scheduleSearchQueryUpdate(with: searchText)
        }
    }
    @Published var isStartOnLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }() {
        didSet {
            guard !loginItemUpdateInProgress else { return }
            guard isStartOnLogin != oldValue else { return }
            guard #available(macOS 13.0, *) else {
                loginItemUpdateInProgress = true
                isStartOnLogin = false
                loginItemUpdateInProgress = false
                return
            }

            loginItemUpdateInProgress = true
            defer { loginItemUpdateInProgress = false }

            do {
                if isStartOnLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LaunchNG: Failed to update login item setting - %@", error.localizedDescription)
                isStartOnLogin = oldValue
            }
        }
    }
    var canConfigureStartOnLogin: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }
    @Published var isFullscreenMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isFullscreenMode, forKey: "isFullscreenMode")
            syncActiveAppearanceProxies(from: currentAppearanceLayoutMode)
            persistLegacyAppearanceProxyValues()
            DispatchQueue.main.async { [weak self] in
                if let appDelegate = AppDelegate.shared {
                    appDelegate.updateWindowMode(isFullscreen: self?.isFullscreenMode ?? false)
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.clearIconCachesForLayoutChange()
                self?.triggerGridRefresh()
            }
        }
    }
    private static func clampColumns(_ value: Int) -> Int {
        min(max(value, minColumnsPerPage), maxColumnsPerPage)
    }

    private static func clampRows(_ value: Int) -> Int {
        min(max(value, minRowsPerPage), maxRowsPerPage)
    }

    private static func clampColumnSpacing(_ value: Double) -> Double {
        min(max(value, minColumnSpacing), maxColumnSpacing)
    }

    private static func clampRowSpacing(_ value: Double) -> Double {
        min(max(value, minRowSpacing), maxRowSpacing)
    }

    private static func clampFolderWidth(_ value: Double) -> Double {
        min(max(value, folderPopoverWidthRange.lowerBound), folderPopoverWidthRange.upperBound)
    }

    private static func clampFolderHeight(_ value: Double) -> Double {
        min(max(value, folderPopoverHeightRange.lowerBound), folderPopoverHeightRange.upperBound)
    }

    private static func clampFolderDropZoneScale(_ value: Double) -> Double {
        min(max(value, folderDropZoneScaleRange.lowerBound), folderDropZoneScaleRange.upperBound)
    }

    private static func clampPageIndicatorTopPadding(_ value: Double) -> Double {
        min(max(value, pageIndicatorTopPaddingRange.lowerBound), pageIndicatorTopPaddingRange.upperBound)
    }

    private static func clampWindowAnimationDuration(_ value: Double) -> Double {
        min(max(value, windowAnimationDurationRange.lowerBound), windowAnimationDurationRange.upperBound)
    }

    private static func clampDockDragTriggerDistance(_ value: Double) -> Double {
        min(max(value, dockDragTriggerDistanceRange.lowerBound), dockDragTriggerDistanceRange.upperBound)
    }

    private static func clampHotCornerTriggerDelay(_ value: Double) -> Double {
        min(max(value, hotCornerTriggerDelayRange.lowerBound), hotCornerTriggerDelayRange.upperBound)
    }

    private static func clampHotCornerHitboxSize(_ value: Double) -> Double {
        min(max(value, hotCornerHitboxSizeRange.lowerBound), hotCornerHitboxSizeRange.upperBound)
    }

    private var appearanceRefreshWorkItem: DispatchWorkItem?
    private var lastAppearanceEventAt: TimeInterval = 0
    private var isApplyingScopedAppearanceState = false
    @Published private var dualModeAppearanceSettings: DualModeAppearanceSettings = AppStore.defaultDualModeAppearanceSettings

    static func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private static func loadPageIndicatorOverrides() -> [String: PageIndicatorOverride] {
        guard let data = UserDefaults.standard.data(forKey: pageIndicatorPerDisplayOverridesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PageIndicatorOverride].self, from: data)) ?? [:]
    }

    private func persistPageIndicatorOverrides(_ overrides: [String: PageIndicatorOverride]) {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pageIndicatorPerDisplayOverridesKey)
            return
        }
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.pageIndicatorPerDisplayOverridesKey)
        }
    }

    private static func legacyAppearanceSettings(from defaults: UserDefaults) -> ModeScopedAppearanceSettings {
        let iconScale = defaults.object(forKey: "iconScale") as? Double ?? Self.defaultIconScale
        let iconLabelFontSize = defaults.object(forKey: "iconLabelFontSize") as? Double ?? Self.defaultIconLabelFontSize
        let dropZoneScale = clampFolderDropZoneScale(defaults.object(forKey: Self.folderDropZoneScaleKey) as? Double ?? Self.defaultFolderDropZoneScale)
        let indicatorOffset = defaults.object(forKey: "pageIndicatorOffset") as? Double ?? Self.defaultPageIndicatorOffset
        let indicatorTopPadding = clampPageIndicatorTopPadding(defaults.object(forKey: Self.pageIndicatorTopPaddingKey) as? Double ?? Self.defaultPageIndicatorTopPadding)
        let perDisplayEnabled = defaults.object(forKey: Self.pageIndicatorPerDisplayEnabledKey) as? Bool ?? false
        let overrides = (try? JSONDecoder().decode([String: PageIndicatorOverride].self,
                                                   from: defaults.data(forKey: Self.pageIndicatorPerDisplayOverridesKey) ?? Data())) ?? [:]
        return ModeScopedAppearanceSettings(iconScale: iconScale,
                                            iconLabelFontSize: iconLabelFontSize,
                                            folderDropZoneScale: dropZoneScale,
                                            pageIndicatorOffset: indicatorOffset,
                                            pageIndicatorTopPadding: indicatorTopPadding,
                                            pageIndicatorPerDisplayEnabled: perDisplayEnabled,
                                            pageIndicatorOverrides: overrides)
    }

    private static func normalizedAppearanceSettings(_ settings: ModeScopedAppearanceSettings) -> ModeScopedAppearanceSettings {
        ModeScopedAppearanceSettings(iconScale: settings.iconScale,
                                     iconLabelFontSize: settings.iconLabelFontSize,
                                     folderDropZoneScale: clampFolderDropZoneScale(settings.folderDropZoneScale),
                                     pageIndicatorOffset: settings.pageIndicatorOffset,
                                     pageIndicatorTopPadding: clampPageIndicatorTopPadding(settings.pageIndicatorTopPadding),
                                     pageIndicatorPerDisplayEnabled: settings.pageIndicatorPerDisplayEnabled,
                                     pageIndicatorOverrides: settings.pageIndicatorOverrides)
    }

    private static func normalizedDualModeAppearanceSettings(_ settings: DualModeAppearanceSettings) -> DualModeAppearanceSettings {
        DualModeAppearanceSettings(fullscreen: normalizedAppearanceSettings(settings.fullscreen),
                                   compact: normalizedAppearanceSettings(settings.compact))
    }

    private static func loadDualModeAppearanceSettings(from defaults: UserDefaults) -> DualModeAppearanceSettings? {
        guard let data = defaults.data(forKey: dualModeAppearanceSettingsKey),
              let decoded = try? JSONDecoder().decode(DualModeAppearanceSettings.self, from: data) else {
            return nil
        }
        return normalizedDualModeAppearanceSettings(decoded)
    }

    private func persistDualModeAppearanceSettings() {
        let normalized = Self.normalizedDualModeAppearanceSettings(dualModeAppearanceSettings)
        dualModeAppearanceSettings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: Self.dualModeAppearanceSettingsKey)
        }
    }

    private static var defaultScopedAppearanceSettings: ModeScopedAppearanceSettings {
        ModeScopedAppearanceSettings(
            iconScale: defaultIconScale,
            iconLabelFontSize: defaultIconLabelFontSize,
            folderDropZoneScale: defaultFolderDropZoneScale,
            pageIndicatorOffset: defaultPageIndicatorOffset,
            pageIndicatorTopPadding: defaultPageIndicatorTopPadding,
            pageIndicatorPerDisplayEnabled: false,
            pageIndicatorOverrides: [:]
        )
    }

    private static var defaultDualModeAppearanceSettings: DualModeAppearanceSettings {
        let scoped = defaultScopedAppearanceSettings
        return DualModeAppearanceSettings(fullscreen: scoped, compact: scoped)
    }

    private var currentAppearanceLayoutMode: AppearanceLayoutMode {
        isFullscreenMode ? .fullscreen : .compact
    }

    private func updateScopedAppearanceSettings(for mode: AppearanceLayoutMode,
                                                _ update: (inout ModeScopedAppearanceSettings) -> Void) {
        var settings = dualModeAppearanceSettings
        var scoped = settings[mode]
        update(&scoped)
        settings[mode] = Self.normalizedAppearanceSettings(scoped)
        dualModeAppearanceSettings = settings
        persistDualModeAppearanceSettings()
    }

    /// One-time reduction of the page indicator's bottom offset to 40% of
    /// its previous value, on direct user request. This is a persisted,
    /// per-mode/per-display slider (`pageIndicatorOffset`, plus any
    /// `pageIndicatorOverrides`) rather than a fixed layout constant, so an
    /// already-launched install's stored value doesn't move just from
    /// lowering a default — this rewrites the value already on disk, through
    /// the normal scoped-settings path so every persistence layer (flat key,
    /// dual-mode blob, per-display overrides) stays consistent. Runs once;
    /// the marker also protects a value the user deliberately readjusts
    /// afterward from being silently scaled down again on a later launch.
    func reducePageIndicatorOffsetIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.pageIndicatorOffsetReducedV1Key) else { return }
        defaults.set(true, forKey: Self.pageIndicatorOffsetReducedV1Key)
        for mode in AppearanceLayoutMode.allCases {
            updateScopedAppearanceSettings(for: mode) { scoped in
                scoped.pageIndicatorOffset *= 0.4
                for (screenID, override) in scoped.pageIndicatorOverrides {
                    scoped.pageIndicatorOverrides[screenID] = PageIndicatorOverride(offset: override.offset * 0.4,
                                                                                    topPadding: override.topPadding)
                }
            }
        }
        pageIndicatorOffset = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorOffset
        pageIndicatorOverrides = dualModeAppearanceSettings[currentAppearanceLayoutMode].pageIndicatorOverrides
    }

    private func syncActiveAppearanceProxies(from mode: AppearanceLayoutMode) {
        let settings = dualModeAppearanceSettings[mode]
        isApplyingScopedAppearanceState = true
        defer { isApplyingScopedAppearanceState = false }
        iconScale = settings.iconScale
        iconLabelFontSize = settings.iconLabelFontSize
        folderDropZoneScale = settings.folderDropZoneScale
        pageIndicatorOffset = settings.pageIndicatorOffset
        pageIndicatorTopPadding = settings.pageIndicatorTopPadding
        pageIndicatorPerDisplayEnabled = settings.pageIndicatorPerDisplayEnabled
        pageIndicatorOverrides = settings.pageIndicatorOverrides
    }

    private func persistLegacyAppearanceProxyValues() {
        let defaults = UserDefaults.standard
        defaults.set(iconScale, forKey: "iconScale")
        defaults.set(iconLabelFontSize, forKey: "iconLabelFontSize")
        defaults.set(folderDropZoneScale, forKey: Self.folderDropZoneScaleKey)
        defaults.set(pageIndicatorOffset, forKey: "pageIndicatorOffset")
        defaults.set(pageIndicatorTopPadding, forKey: Self.pageIndicatorTopPaddingKey)
        defaults.set(pageIndicatorPerDisplayEnabled, forKey: Self.pageIndicatorPerDisplayEnabledKey)
        persistPageIndicatorOverrides(pageIndicatorOverrides)
    }

    func scopedIconScale(for mode: AppearanceLayoutMode) -> Double {
        dualModeAppearanceSettings[mode].iconScale
    }

    func setScopedIconScale(_ value: Double, for mode: AppearanceLayoutMode) {
        if mode == currentAppearanceLayoutMode {
            iconScale = value
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.iconScale = value }
        }
    }

    func scopedIconLabelFontSize(for mode: AppearanceLayoutMode) -> Double {
        dualModeAppearanceSettings[mode].iconLabelFontSize
    }

    func setScopedIconLabelFontSize(_ value: Double, for mode: AppearanceLayoutMode) {
        if mode == currentAppearanceLayoutMode {
            iconLabelFontSize = value
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.iconLabelFontSize = value }
        }
    }

    func scopedFolderDropZoneScale(for mode: AppearanceLayoutMode) -> Double {
        dualModeAppearanceSettings[mode].folderDropZoneScale
    }

    func setScopedFolderDropZoneScale(_ value: Double, for mode: AppearanceLayoutMode) {
        let clamped = Self.clampFolderDropZoneScale(value)
        if mode == currentAppearanceLayoutMode {
            folderDropZoneScale = clamped
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.folderDropZoneScale = clamped }
        }
    }

    func scopedPageIndicatorOffset(for mode: AppearanceLayoutMode) -> Double {
        dualModeAppearanceSettings[mode].pageIndicatorOffset
    }

    func setScopedPageIndicatorOffset(_ value: Double, for mode: AppearanceLayoutMode) {
        if mode == currentAppearanceLayoutMode {
            pageIndicatorOffset = value
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.pageIndicatorOffset = value }
        }
    }

    func scopedPageIndicatorTopPadding(for mode: AppearanceLayoutMode) -> Double {
        dualModeAppearanceSettings[mode].pageIndicatorTopPadding
    }

    func setScopedPageIndicatorTopPadding(_ value: Double, for mode: AppearanceLayoutMode) {
        let clamped = Self.clampPageIndicatorTopPadding(value)
        if mode == currentAppearanceLayoutMode {
            pageIndicatorTopPadding = clamped
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.pageIndicatorTopPadding = clamped }
        }
    }

    func scopedPageIndicatorPerDisplayEnabled(for mode: AppearanceLayoutMode) -> Bool {
        dualModeAppearanceSettings[mode].pageIndicatorPerDisplayEnabled
    }

    func setScopedPageIndicatorPerDisplayEnabled(_ enabled: Bool, for mode: AppearanceLayoutMode) {
        if mode == currentAppearanceLayoutMode {
            pageIndicatorPerDisplayEnabled = enabled
        } else {
            updateScopedAppearanceSettings(for: mode) { $0.pageIndicatorPerDisplayEnabled = enabled }
        }
    }

    func scopedPageIndicatorOverrides(for mode: AppearanceLayoutMode) -> [String: PageIndicatorOverride] {
        dualModeAppearanceSettings[mode].pageIndicatorOverrides
    }

    func scopedPageIndicatorOverride(for screenID: String, mode: AppearanceLayoutMode) -> PageIndicatorOverride? {
        dualModeAppearanceSettings[mode].pageIndicatorOverrides[screenID]
    }

    func setScopedPageIndicatorOverride(_ override: PageIndicatorOverride?, for screenID: String, mode: AppearanceLayoutMode) {
        if mode == currentAppearanceLayoutMode {
            setPageIndicatorOverride(override, for: screenID)
            return
        }
        updateScopedAppearanceSettings(for: mode) { settings in
            if let override {
                settings.pageIndicatorOverrides[screenID] = override
            } else {
                settings.pageIndicatorOverrides.removeValue(forKey: screenID)
            }
        }
    }

    func applyIndicatorDefaults(to screenID: String, mode: AppearanceLayoutMode) {
        let settings = dualModeAppearanceSettings[mode]
        let override = PageIndicatorOverride(offset: settings.pageIndicatorOffset,
                                             topPadding: settings.pageIndicatorTopPadding)
        setScopedPageIndicatorOverride(override, for: screenID, mode: mode)
    }

    // Icon title display
    @Published var showLabels: Bool = {
        if UserDefaults.standard.object(forKey: "showLabels") == nil { return true }
        return UserDefaults.standard.bool(forKey: "showLabels")
    }() {
        didSet { UserDefaults.standard.set(showLabels, forKey: "showLabels") }
    }

    @Published var folderLiquidGlassEnabled = true {
        didSet {
            guard folderLiquidGlassEnabled != oldValue else { return }
            UserDefaults.standard.set(folderLiquidGlassEnabled, forKey: Self.folderLiquidGlassKey)
        }
    }

    @Published var enableHighResFolderPreviews: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.folderPreviewHighResKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: AppStore.folderPreviewHighResKey)
    }() {
        didSet {
            guard enableHighResFolderPreviews != oldValue else { return }
            UserDefaults.standard.set(enableHighResFolderPreviews, forKey: AppStore.folderPreviewHighResKey)
            clearIconCachesForLayoutChange()
            triggerFolderUpdate()
            triggerGridRefresh()
        }
    }

    @Published var folderQuickLaunchEnabled: Bool = {
        UserDefaults.standard.object(forKey: AppStore.folderQuickLaunchEnabledKey) as? Bool ?? false
    }() {
        didSet {
            guard folderQuickLaunchEnabled != oldValue else { return }
            UserDefaults.standard.set(folderQuickLaunchEnabled, forKey: AppStore.folderQuickLaunchEnabledKey)
        }
    }

    @Published var folderLayoutMode: FolderLayoutMode = AppStore.loadFolderLayoutMode() {
        didSet {
            guard folderLayoutMode != oldValue else { return }
            UserDefaults.standard.set(folderLayoutMode.rawValue, forKey: Self.folderLayoutModeKey)
            DispatchQueue.main.async { [weak self] in
                self?.triggerFolderUpdate()
            }
        }
    }

    @Published var hideDock: Bool = {
        if UserDefaults.standard.object(forKey: "hideDock") == nil { return false }
        return UserDefaults.standard.bool(forKey: "hideDock")
    }() {
        didSet {
            guard hideDock != oldValue else { return }
            UserDefaults.standard.set(hideDock, forKey: "hideDock")
        }
    }

    @Published var hideMenuBar: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.hideMenuBarKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.hideMenuBarKey)
    }() {
        didSet {
            guard hideMenuBar != oldValue else { return }
            UserDefaults.standard.set(hideMenuBar, forKey: Self.hideMenuBarKey)
        }
    }
    
    @Published var scrollSensitivity: Double {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "scrollSensitivity")
        }
    }

    @Published var gridColumnsPerPage: Int {
        didSet {
            let clamped = Self.clampColumns(gridColumnsPerPage)
            if gridColumnsPerPage != clamped {
                gridColumnsPerPage = clamped
                return
            }
            guard gridColumnsPerPage != oldValue else { return }
            UserDefaults.standard.set(gridColumnsPerPage, forKey: Self.gridColumnsKey)
            handleGridConfigurationChange()
        }
    }

    @Published var gridRowsPerPage: Int {
        didSet {
            let clamped = Self.clampRows(gridRowsPerPage)
            if gridRowsPerPage != clamped {
                gridRowsPerPage = clamped
                return
            }
            guard gridRowsPerPage != oldValue else { return }
            UserDefaults.standard.set(gridRowsPerPage, forKey: Self.gridRowsKey)
            handleGridConfigurationChange()
        }
    }

    @Published var iconColumnSpacing: Double {
        didSet {
            let clamped = Self.clampColumnSpacing(iconColumnSpacing)
            if iconColumnSpacing != clamped {
                iconColumnSpacing = clamped
                return
            }
            guard iconColumnSpacing != oldValue else { return }
            UserDefaults.standard.set(iconColumnSpacing, forKey: Self.columnSpacingKey)
            triggerGridRefresh()
        }
    }

    @Published var iconRowSpacing: Double {
        didSet {
            let clamped = Self.clampRowSpacing(iconRowSpacing)
            if iconRowSpacing != clamped {
                iconRowSpacing = clamped
                return
            }
            guard iconRowSpacing != oldValue else { return }
            UserDefaults.standard.set(iconRowSpacing, forKey: Self.rowSpacingKey)
            triggerGridRefresh()
        }
    }

    @Published var folderIconColumnSpacing: Double {
        didSet {
            let clamped = Self.clampColumnSpacing(folderIconColumnSpacing)
            if folderIconColumnSpacing != clamped {
                folderIconColumnSpacing = clamped
                return
            }
            guard folderIconColumnSpacing != oldValue else { return }
            UserDefaults.standard.set(folderIconColumnSpacing, forKey: Self.folderColumnSpacingKey)
        }
    }

    @Published var folderIconRowSpacing: Double {
        didSet {
            let clamped = Self.clampRowSpacing(folderIconRowSpacing)
            if folderIconRowSpacing != clamped {
                folderIconRowSpacing = clamped
                return
            }
            guard folderIconRowSpacing != oldValue else { return }
            UserDefaults.standard.set(folderIconRowSpacing, forKey: Self.folderRowSpacingKey)
        }
    }

    @Published var enableDropPrediction: Bool = {
        if UserDefaults.standard.object(forKey: "enableDropPrediction") == nil { return true }
        return UserDefaults.standard.bool(forKey: "enableDropPrediction")
    }() {
        didSet { UserDefaults.standard.set(enableDropPrediction, forKey: "enableDropPrediction") }
    }

    @Published var folderDropZoneScale: Double = AppStore.defaultFolderDropZoneScale {
        didSet {
            let clamped = Self.clampFolderDropZoneScale(folderDropZoneScale)
            if folderDropZoneScale != clamped {
                folderDropZoneScale = clamped
                return
            }
            UserDefaults.standard.set(folderDropZoneScale, forKey: Self.folderDropZoneScaleKey)
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.folderDropZoneScale = folderDropZoneScale }
        }
    }

    @Published var pageIndicatorTopPadding: Double = AppStore.defaultPageIndicatorTopPadding {
        didSet {
            let clamped = Self.clampPageIndicatorTopPadding(pageIndicatorTopPadding)
            if pageIndicatorTopPadding != clamped {
                pageIndicatorTopPadding = clamped
                return
            }
            UserDefaults.standard.set(pageIndicatorTopPadding, forKey: Self.pageIndicatorTopPaddingKey)
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.pageIndicatorTopPadding = pageIndicatorTopPadding }
        }
    }

    @Published var enableAnimations: Bool = {
        if UserDefaults.standard.object(forKey: "enableAnimations") == nil { return true }
        return UserDefaults.standard.bool(forKey: "enableAnimations")
    }() {
        didSet { UserDefaults.standard.set(enableAnimations, forKey: "enableAnimations") }
    }

    @Published var enableHoverMagnification: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.hoverMagnificationKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.hoverMagnificationKey)
    }() {
        didSet { UserDefaults.standard.set(enableHoverMagnification, forKey: Self.hoverMagnificationKey) }
    }

    @Published var hoverMagnificationScale: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.hoverMagnificationScaleKey) as? Double
        let initial = stored ?? AppStore.defaultHoverMagnificationScale
        let clamped = min(max(initial, AppStore.hoverMagnificationRange.lowerBound), AppStore.hoverMagnificationRange.upperBound)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.hoverMagnificationScaleKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = min(max(hoverMagnificationScale, Self.hoverMagnificationRange.lowerBound), Self.hoverMagnificationRange.upperBound)
            if hoverMagnificationScale != clamped {
                hoverMagnificationScale = clamped
                return
            }
            UserDefaults.standard.set(hoverMagnificationScale, forKey: Self.hoverMagnificationScaleKey)
        }
    }

    @Published var enableActivePressEffect: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.activePressEffectKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.activePressEffectKey)
    }() {
        didSet { UserDefaults.standard.set(enableActivePressEffect, forKey: Self.activePressEffectKey) }
    }

    @Published var reverseWheelPagingDirection: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.reverseWheelPagingKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.reverseWheelPagingKey)
    }() {
        didSet { UserDefaults.standard.set(reverseWheelPagingDirection, forKey: Self.reverseWheelPagingKey) }
    }

    @Published var reverseWheelVerticalDirection: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.reverseWheelVerticalKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.reverseWheelVerticalKey)
    }() {
        didSet { UserDefaults.standard.set(reverseWheelVerticalDirection, forKey: Self.reverseWheelVerticalKey) }
    }

    @Published var trackpadVerticalDirection: TrackpadVerticalDirection = {
        let raw = UserDefaults.standard.string(forKey: AppStore.trackpadVerticalDirectionKey)
        return raw.flatMap(TrackpadVerticalDirection.init(rawValue:)) ?? .natural
    }() {
        didSet { UserDefaults.standard.set(trackpadVerticalDirection.rawValue, forKey: Self.trackpadVerticalDirectionKey) }
    }

    @Published var activePressScale: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.activePressScaleKey) as? Double
        let initial = stored ?? AppStore.defaultActivePressScale
        let clamped = min(max(initial, AppStore.activePressScaleRange.lowerBound), AppStore.activePressScaleRange.upperBound)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.activePressScaleKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = min(max(activePressScale, Self.activePressScaleRange.lowerBound), Self.activePressScaleRange.upperBound)
            if activePressScale != clamped {
                activePressScale = clamped
                return
            }
            UserDefaults.standard.set(activePressScale, forKey: Self.activePressScaleKey)
        }
    }

    @Published var iconLabelFontSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "iconLabelFontSize")
        return stored == 0 ? 11.0 : stored
    }() {
        didSet {
            UserDefaults.standard.set(iconLabelFontSize, forKey: "iconLabelFontSize")
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.iconLabelFontSize = iconLabelFontSize }
            triggerGridRefresh()
        }
    }

    @Published var iconLabelFontWeight: IconLabelFontWeightOption = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: AppStore.iconLabelFontWeightKey),
           let value = IconLabelFontWeightOption(rawValue: raw) {
            return value
        }
        return .medium
    }() {
        didSet {
            guard iconLabelFontWeight != oldValue else { return }
            UserDefaults.standard.set(iconLabelFontWeight.rawValue, forKey: AppStore.iconLabelFontWeightKey)
            triggerGridRefresh()
        }
    }

    var iconLabelFontWeightValue: Font.Weight {
        iconLabelFontWeight.fontWeight
    }

    @Published var showQuickRefreshButton: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.showQuickRefreshButtonKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.showQuickRefreshButtonKey)
    }() {
        didSet {
            guard showQuickRefreshButton != oldValue else { return }
            UserDefaults.standard.set(showQuickRefreshButton, forKey: AppStore.showQuickRefreshButtonKey)
        }
    }

    @Published var uninstallToolAppPath: String = {
        UserDefaults.standard.string(forKey: AppStore.uninstallToolAppPathKey) ?? ""
    }() {
        didSet {
            guard uninstallToolAppPath != oldValue else { return }
            let trimmed = uninstallToolAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: AppStore.uninstallToolAppPathKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: AppStore.uninstallToolAppPathKey)
            }
        }
    }

    @Published var isLayoutLocked: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.lockLayoutKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.lockLayoutKey)
    }() {
        didSet {
            guard isLayoutLocked != oldValue else { return }
            UserDefaults.standard.set(isLayoutLocked, forKey: AppStore.lockLayoutKey)
            triggerGridRefresh()
        }
    }

    @Published var animationDuration: Double = {
        let stored = UserDefaults.standard.double(forKey: "animationDuration")
        return stored == 0 ? 0.3 : stored
    }() {
        didSet { UserDefaults.standard.set(animationDuration, forKey: "animationDuration") }
    }

    @Published var enableWindowOpenAnimation: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.windowOpenAnimationKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: AppStore.windowOpenAnimationKey)
    }() {
        didSet { UserDefaults.standard.set(enableWindowOpenAnimation, forKey: Self.windowOpenAnimationKey) }
    }

    @Published var compactWindowMaxWidth = 0 {
        didSet {
            compactWindowMaxWidth = CompactWindowLayout.normalizedMaximumWidth(compactWindowMaxWidth)
            guard compactWindowMaxWidth != oldValue else { return }
            UserDefaults.standard.set(compactWindowMaxWidth, forKey: Self.compactWindowMaxWidthKey)
            refreshCompactWindowSize()
        }
    }

    @Published var compactWindowMaxHeight = 0 {
        didSet {
            compactWindowMaxHeight = CompactWindowLayout.normalizedMaximumHeight(compactWindowMaxHeight)
            guard compactWindowMaxHeight != oldValue else { return }
            UserDefaults.standard.set(compactWindowMaxHeight, forKey: Self.compactWindowMaxHeightKey)
            refreshCompactWindowSize()
        }
    }

    private func refreshCompactWindowSize() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFullscreenMode else { return }
            AppDelegate.shared?.updateWindowMode(isFullscreen: false)
        }
    }

    @Published var windowShadowEnabled = false {
        didSet {
            guard windowShadowEnabled != oldValue else { return }
            UserDefaults.standard.set(windowShadowEnabled, forKey: Self.windowShadowEnabledKey)
            AppDelegate.shared?.updateWindowShadow()
        }
    }

    @Published var windowAnimationDuration: Double = {
        let stored = UserDefaults.standard.object(forKey: AppStore.windowAnimationDurationKey) as? Double
            ?? AppStore.defaultWindowAnimationDuration
        return AppStore.clampWindowAnimationDuration(stored)
    }() {
        didSet {
            let clamped = Self.clampWindowAnimationDuration(windowAnimationDuration)
            if windowAnimationDuration != clamped {
                windowAnimationDuration = clamped
                return
            }
            UserDefaults.standard.set(windowAnimationDuration, forKey: Self.windowAnimationDurationKey)
        }
    }

    @Published var useLocalizedThirdPartyTitles: Bool = {
        if UserDefaults.standard.object(forKey: "useLocalizedThirdPartyTitles") == nil { return true }
        return UserDefaults.standard.bool(forKey: "useLocalizedThirdPartyTitles")
    }() {
        didSet {
            guard oldValue != useLocalizedThirdPartyTitles else { return }
            UserDefaults.standard.set(useLocalizedThirdPartyTitles, forKey: "useLocalizedThirdPartyTitles")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }
    }

    @Published var showFPSOverlay: Bool = {
        if UserDefaults.standard.object(forKey: "showFPSOverlay") == nil { return false }
        return UserDefaults.standard.bool(forKey: "showFPSOverlay")
    }() {
        didSet { UserDefaults.standard.set(showFPSOverlay, forKey: "showFPSOverlay") }
    }

    @Published var gameControllerEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.gameControllerEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.gameControllerEnabledKey)
    }() {
        didSet {
            guard oldValue != gameControllerEnabled else { return }
            UserDefaults.standard.set(gameControllerEnabled, forKey: AppStore.gameControllerEnabledKey)
        }
    }

    @Published var gameControllerMenuTogglesLaunchpad: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.gameControllerMenuToggleKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: AppStore.gameControllerMenuToggleKey)
    }() {
        didSet {
            guard oldValue != gameControllerMenuTogglesLaunchpad else { return }
            UserDefaults.standard.set(gameControllerMenuTogglesLaunchpad, forKey: AppStore.gameControllerMenuToggleKey)
        }
    }

    @Published var soundEffectsEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.soundEffectsEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.soundEffectsEnabledKey)
    }() {
        didSet {
            guard oldValue != soundEffectsEnabled else { return }
            UserDefaults.standard.set(soundEffectsEnabled, forKey: AppStore.soundEffectsEnabledKey)
        }
    }

    @Published var soundLaunchpadOpenSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundLaunchpadOpenKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultLaunchpadOpenSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundLaunchpadOpenSound, forKey: AppStore.soundLaunchpadOpenKey)
        }
    }

    @Published var soundLaunchpadCloseSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundLaunchpadCloseKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultLaunchpadCloseSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundLaunchpadCloseSound, forKey: AppStore.soundLaunchpadCloseKey)
        }
    }

    @Published var soundNavigationSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundNavigationKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultNavigationSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundNavigationSound, forKey: AppStore.soundNavigationKey)
        }
    }

    @Published var voiceFeedbackEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.voiceFeedbackEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.voiceFeedbackEnabledKey)
    }() {
        didSet {
            guard oldValue != voiceFeedbackEnabled else { return }
            UserDefaults.standard.set(voiceFeedbackEnabled, forKey: AppStore.voiceFeedbackEnabledKey)
            if !voiceFeedbackEnabled {
                VoiceManager.shared.stop()
            }
        }
    }

    @Published var pageIndicatorOffset: Double = {
        if UserDefaults.standard.object(forKey: "pageIndicatorOffset") == nil { return 27.0 }
        return UserDefaults.standard.double(forKey: "pageIndicatorOffset")
    }() {
        didSet {
            UserDefaults.standard.set(pageIndicatorOffset, forKey: "pageIndicatorOffset")
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.pageIndicatorOffset = pageIndicatorOffset }
        }
    }

    @Published var pageIndicatorPerDisplayEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.pageIndicatorPerDisplayEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.pageIndicatorPerDisplayEnabledKey)
    }() {
        didSet {
            UserDefaults.standard.set(pageIndicatorPerDisplayEnabled, forKey: AppStore.pageIndicatorPerDisplayEnabledKey)
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.pageIndicatorPerDisplayEnabled = pageIndicatorPerDisplayEnabled }
        }
    }

    @Published private(set) var pageIndicatorOverrides: [String: PageIndicatorOverride] = AppStore.loadPageIndicatorOverrides() {
        didSet {
            persistPageIndicatorOverrides(pageIndicatorOverrides)
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.pageIndicatorOverrides = pageIndicatorOverrides }
        }
    }

    @Published var rememberLastPage: Bool = AppStore.defaultRememberSetting() {
        didSet {
            UserDefaults.standard.set(rememberLastPage, forKey: Self.rememberPageKey)
            if rememberLastPage {
                UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.rememberedPageIndexKey)
            }
        }
    }

    @Published var folderPopoverWidthFactor: Double = {
        let stored = UserDefaults.standard.double(forKey: "folderPopoverWidthFactor")
        if stored == 0 { return defaultFolderPopoverWidth }
        return clampFolderWidth(stored)
    }() {
        didSet {
            let clamped = AppStore.clampFolderWidth(folderPopoverWidthFactor)
            if folderPopoverWidthFactor != clamped {
                folderPopoverWidthFactor = clamped
                return
            }
            UserDefaults.standard.set(folderPopoverWidthFactor, forKey: "folderPopoverWidthFactor")
        }
    }

    @Published var folderPopoverHeightFactor: Double = {
        let stored = UserDefaults.standard.double(forKey: "folderPopoverHeightFactor")
        if stored == 0 { return defaultFolderPopoverHeight }
        return clampFolderHeight(stored)
    }() {
        didSet {
            let clamped = AppStore.clampFolderHeight(folderPopoverHeightFactor)
            if folderPopoverHeightFactor != clamped {
                folderPopoverHeightFactor = clamped
                return
            }
            UserDefaults.standard.set(folderPopoverHeightFactor, forKey: "folderPopoverHeightFactor")
        }
    }

    @Published var appearancePreference: AppearancePreference = {
        if let raw = UserDefaults.standard.string(forKey: "appearancePreference"),
           let pref = AppearancePreference(rawValue: raw) {
            return pref
        }
        return .system
    }() {
        didSet {
            guard oldValue != appearancePreference else { return }
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: "appearancePreference")
        }
    }

    private static func defaultRememberSetting() -> Bool {
        if UserDefaults.standard.object(forKey: rememberPageKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: rememberPageKey)
    }

    @Published var globalHotKey: HotKeyConfiguration? = AppStore.loadHotKeyConfiguration() {
        didSet {
            persistHotKeyConfiguration()
            AppDelegate.shared?.updateGlobalHotKey(configuration: globalHotKey)
        }
    }

    @Published var dockDragEnabled: Bool = {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: AppStore.dockDragEnabledKey) as? Bool {
            return stored
        }
        let legacySideRaw = defaults.string(forKey: AppStore.dockDragSideKey)
        let enabled = legacySideRaw != DockDragSide.disabled.rawValue
        defaults.set(enabled, forKey: AppStore.dockDragEnabledKey)
        return enabled
    }() {
        didSet {
            guard dockDragEnabled != oldValue else { return }
            UserDefaults.standard.set(dockDragEnabled, forKey: Self.dockDragEnabledKey)
        }
    }

    @Published var dockDragSide: DockDragSide = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: AppStore.dockDragSideKey),
           let side = DockDragSide(rawValue: raw),
           side != .disabled {
            return side
        }
        return .bottom
    }() {
        didSet {
            guard dockDragSide != oldValue else { return }
            UserDefaults.standard.set(dockDragSide.rawValue, forKey: Self.dockDragSideKey)
        }
    }

    @Published var dockDragTriggerDistance: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.dockDragTriggerDistanceKey) as? Double
        let initial = stored ?? AppStore.defaultDockDragTriggerDistance
        let clamped = AppStore.clampDockDragTriggerDistance(initial)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.dockDragTriggerDistanceKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = Self.clampDockDragTriggerDistance(dockDragTriggerDistance)
            if dockDragTriggerDistance != clamped {
                dockDragTriggerDistance = clamped
                return
            }
            UserDefaults.standard.set(dockDragTriggerDistance, forKey: Self.dockDragTriggerDistanceKey)
        }
    }

    @Published var hotCornerEnabled: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.hotCornerEnabledKey) == nil {
            defaults.set(false, forKey: AppStore.hotCornerEnabledKey)
        }
        return defaults.bool(forKey: AppStore.hotCornerEnabledKey)
    }() {
        didSet {
            guard hotCornerEnabled != oldValue else { return }
            UserDefaults.standard.set(hotCornerEnabled, forKey: Self.hotCornerEnabledKey)
        }
    }

    @Published var hotCornerPosition: HotCornerPosition = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: AppStore.hotCornerPositionKey),
           let position = HotCornerPosition(rawValue: raw) {
            return position
        }
        return .topLeft
    }() {
        didSet {
            guard hotCornerPosition != oldValue else { return }
            UserDefaults.standard.set(hotCornerPosition.rawValue, forKey: Self.hotCornerPositionKey)
        }
    }

    @Published var hotCornerTriggerDelay: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.hotCornerTriggerDelayKey) as? Double
        let initial = stored ?? AppStore.defaultHotCornerTriggerDelay
        let clamped = AppStore.clampHotCornerTriggerDelay(initial)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.hotCornerTriggerDelayKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = Self.clampHotCornerTriggerDelay(hotCornerTriggerDelay)
            if hotCornerTriggerDelay != clamped {
                hotCornerTriggerDelay = clamped
                return
            }
            UserDefaults.standard.set(hotCornerTriggerDelay, forKey: Self.hotCornerTriggerDelayKey)
        }
    }

    @Published var hotCornerHitboxSize: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.hotCornerHitboxSizeKey) as? Double
        let initial = stored ?? AppStore.defaultHotCornerHitboxSize
        let clamped = AppStore.clampHotCornerHitboxSize(initial)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.hotCornerHitboxSizeKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = Self.clampHotCornerHitboxSize(hotCornerHitboxSize)
            if hotCornerHitboxSize != clamped {
                hotCornerHitboxSize = clamped
                return
            }
            UserDefaults.standard.set(hotCornerHitboxSize, forKey: Self.hotCornerHitboxSizeKey)
        }
    }

    @Published var hotCornerToggleWhenOpen: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.hotCornerToggleWhenOpenKey) == nil {
            defaults.set(false, forKey: AppStore.hotCornerToggleWhenOpenKey)
        }
        return defaults.bool(forKey: AppStore.hotCornerToggleWhenOpenKey)
    }() {
        didSet {
            guard hotCornerToggleWhenOpen != oldValue else { return }
            UserDefaults.standard.set(hotCornerToggleWhenOpen, forKey: Self.hotCornerToggleWhenOpenKey)
        }
    }

    // Experimental gesture settings consumed by LaunchpadApp gesture wiring.
    // Remove these fields together with the gesture monitor/configuration flow
    // if low-level multitouch support is no longer needed.
    @Published var gestureEnabled: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.gestureEnabledKey) == nil {
            defaults.set(false, forKey: AppStore.gestureEnabledKey)
        }
        return defaults.bool(forKey: AppStore.gestureEnabledKey)
    }() {
        didSet {
            guard gestureEnabled != oldValue else { return }
            UserDefaults.standard.set(gestureEnabled, forKey: Self.gestureEnabledKey)
        }
    }

    @Published var gestureCloseOnPinchOut: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.gestureCloseOnPinchOutKey) == nil {
            defaults.set(false, forKey: AppStore.gestureCloseOnPinchOutKey)
        }
        return defaults.bool(forKey: AppStore.gestureCloseOnPinchOutKey)
    }() {
        didSet {
            guard gestureCloseOnPinchOut != oldValue else { return }
            UserDefaults.standard.set(gestureCloseOnPinchOut, forKey: Self.gestureCloseOnPinchOutKey)
        }
    }

    @Published var gestureTapAction: GestureTapAction = {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: AppStore.gestureTapActionKey),
           let action = GestureTapAction(rawValue: rawValue) {
            return action
        }
        let legacyEnabled = defaults.object(forKey: "gestureTapEnabled") as? Bool ?? false
        let legacyToggle = defaults.object(forKey: "gestureTapToggleWhenOpen") as? Bool ?? false
        let migratedAction: GestureTapAction = legacyEnabled ? (legacyToggle ? .toggle : .open) : .off
        defaults.set(migratedAction.rawValue, forKey: AppStore.gestureTapActionKey)
        return migratedAction
    }() {
        didSet {
            guard gestureTapAction != oldValue else { return }
            UserDefaults.standard.set(gestureTapAction.rawValue, forKey: Self.gestureTapActionKey)
        }
    }

    @Published var gestureFingerCount: GestureFingerCount = {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.object(forKey: AppStore.gestureFingerCountKey) as? Int,
              let count = GestureFingerCount(rawValue: rawValue) else {
            defaults.set(GestureFingerCount.four.rawValue, forKey: AppStore.gestureFingerCountKey)
            return .four
        }
        return count
    }() {
        didSet {
            guard gestureFingerCount != oldValue else { return }
            UserDefaults.standard.set(gestureFingerCount.rawValue, forKey: Self.gestureFingerCountKey)
        }
    }

    @Published var gestureDeviceSelectionMode: GestureDeviceSelectionMode = {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.string(forKey: AppStore.gestureDeviceSelectionModeKey),
              let mode = GestureDeviceSelectionMode(rawValue: rawValue) else {
            defaults.set(GestureDeviceSelectionMode.automatic.rawValue, forKey: AppStore.gestureDeviceSelectionModeKey)
            return .automatic
        }
        return mode
    }() {
        didSet {
            guard gestureDeviceSelectionMode != oldValue else { return }
            UserDefaults.standard.set(gestureDeviceSelectionMode.rawValue, forKey: Self.gestureDeviceSelectionModeKey)
        }
    }

    @Published var gestureSelectedDeviceIDs: [String] = {
        let defaults = UserDefaults.standard
        let rawIDs = defaults.stringArray(forKey: AppStore.gestureSelectedDeviceIDsKey) ?? []
        let normalized = Array(Set(rawIDs)).sorted()
        if rawIDs != normalized {
            defaults.set(normalized, forKey: AppStore.gestureSelectedDeviceIDsKey)
        }
        return normalized
    }() {
        didSet {
            let normalized = Array(Set(gestureSelectedDeviceIDs)).sorted()
            if gestureSelectedDeviceIDs != normalized {
                gestureSelectedDeviceIDs = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.gestureSelectedDeviceIDsKey)
        }
    }

    @Published var gestureShowAllInputDevices: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppStore.gestureShowAllInputDevicesKey) == nil {
            defaults.set(false, forKey: AppStore.gestureShowAllInputDevicesKey)
        }
        return defaults.bool(forKey: AppStore.gestureShowAllInputDevicesKey)
    }() {
        didSet {
            guard gestureShowAllInputDevices != oldValue else { return }
            UserDefaults.standard.set(gestureShowAllInputDevices, forKey: Self.gestureShowAllInputDevicesKey)
        }
    }

    @Published private(set) var availableGestureDevices: [GestureInputDevice] = []

    // @Published var isAIEnabled: Bool = {
    //     if UserDefaults.standard.object(forKey: AppStore.aiFeatureEnabledKey) == nil { return false }
    //     return UserDefaults.standard.bool(forKey: AppStore.aiFeatureEnabledKey)
    // }() {
    //     didSet {
    //         guard isAIEnabled != oldValue else { return }
    //         UserDefaults.standard.set(isAIEnabled, forKey: AppStore.aiFeatureEnabledKey)
    //         // if !isAIEnabled {
    //         //     AIOverlayController.shared.hide()
    //         // }
    //         // AppDelegate.shared?.updateAIOverlayHotKey(configuration: isAIEnabled ? aiOverlayHotKey : nil)
    //     }
    // }
    //
    // @Published var aiOverlayHotKey: HotKeyConfiguration? = AppStore.loadAIOverlayHotKeyConfiguration() {
    //     didSet {
    //         persistAIOverlayHotKeyConfiguration()
    //         // if isAIEnabled {
    //         //     AppDelegate.shared?.updateAIOverlayHotKey(configuration: aiOverlayHotKey)
    //         // }
    //     }
    // }

    @Published private(set) var currentAppIcon: NSImage {
        didSet { applyCurrentAppIcon() }
    }

    @Published private(set) var hasCustomAppIcon: Bool

    @Published var preferredLanguage: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "preferredLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return .system
    }() {
        didSet { UserDefaults.standard.set(preferredLanguage.rawValue, forKey: "preferredLanguage") }
    }

    @Published private(set) var customTitles: [String: String] = AppStore.loadCustomTitles() {
        didSet { persistCustomTitles() }
    }

    // Cache manager
    private let cacheManager = AppCacheManager.shared

    // Folder-related state
    @Published var openFolder: FolderInfo? = nil
    @Published var isDragCreatingFolder = false
    @Published var folderCreationTarget: AppInfo? = nil
    @Published var openFolderActivatedByKeyboard: Bool = false
    @Published var isFolderNameEditing: Bool = false
    @Published var folderRenameRequestID: String? = nil
    @Published var handoffDraggingApp: AppInfo? = nil
    @Published var handoffDragScreenLocation: CGPoint? = nil
    
    // Triggers
    @Published var folderUpdateTrigger: UUID = UUID()
    @Published var gridRefreshTrigger: UUID = UUID()
    @Published var iconCacheRefreshTrigger: UUID = UUID()
    private var folderUpdateScheduled = false
    private var gridRefreshScheduled = false
    
    var modelContext: ModelContext?

    // MARK: - Auto rescan (FSEvents)
    private enum ApplicationReconciliationReason: Hashable {
        case initial
        case fileSystemEvent
        case externalUninstallerReturn
        case staleWindowFallback
        case manual
        case sourceChange
        case explicit
    }

    private static let applicationReconciliationFallbackInterval: TimeInterval = 15 * 60
    private static let applicationReconciliationEventDebounce: TimeInterval = 1.0

    private var fsEventStream: FSEventStreamRef?
    private var applicationReconciliationReasons: Set<ApplicationReconciliationReason> = []
    private var applicationReconciliationInProgress = false
    private var applicationReconciliationWorkItem: DispatchWorkItem?
    private var lastSuccessfulApplicationReconciliationAt: Date?
    private var needsReconciliationAfterExternalUninstall = false

    // State markers
    private var hasPerformedInitialScan: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    private var hasAppliedOrderFromStore: Bool = false

    // Background refresh queues and throttling
    private var gridRefreshWorkItem: DispatchWorkItem?
    private var iconScaleWorkItem: DispatchWorkItem?
    private var customTitleRefreshWorkItem: DispatchWorkItem?
    private var searchQueryWorkItem: DispatchWorkItem?
    private let fsEventsQueue = DispatchQueue(label: "app.store.fsevents")
    private let customIconFileURL: URL
    private let defaultAppIcon: NSImage
    private var loginItemUpdateInProgress = false
    private var volumeObservers: [NSObjectProtocol] = []
    
    // Computed properties
    private var itemsPerPage: Int { gridColumnsPerPage * gridRowsPerPage }

    var builtinAppSourcePaths: [String] { systemApplicationSearchPaths }

    private var applicationSearchPaths: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let candidates = systemApplicationSearchPaths + customAppSourcePaths
        let fileManager = FileManager.default

        for raw in candidates {
            guard let standardized = normalizeApplicationPath(raw) else { continue }
            guard !standardized.isEmpty, !seen.contains(standardized) else { continue }

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
               isDirectory.boolValue,
               fileManager.isReadableFile(atPath: standardized) {
                seen.insert(standardized)
                result.append(standardized)
            }
        }

        return result
    }

    private func normalizeApplicationPath(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        return URL(fileURLWithPath: expanded).standardized.path
    }

    private func standardizedFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    private func removableSourcePath(forAppPath path: String) -> String? {
        let standardizedApp = standardizedFilePath(path)
        for source in customAppSourcePaths {
            guard let normalizedSource = normalizeApplicationPath(source) else { continue }
            if standardizedApp == normalizedSource { return normalizedSource }
            if standardizedApp.hasPrefix(normalizedSource.hasSuffix("/") ? normalizedSource : normalizedSource + "/") {
                return normalizedSource
            }
        }
        return nil
    }

    private func placeholderDisplayName(for path: String, preferred: String?) -> String {
        let normalizedPath = standardizedFilePath(path)
        let legacyMatch = missingPlaceholders.first { standardizedFilePath($0.key) == normalizedPath }?.value.displayName
        let candidates: [String?] = [preferred,
                                     missingPlaceholders[normalizedPath]?.displayName,
                                     legacyMatch,
                                     URL(fileURLWithPath: normalizedPath).deletingPathExtension().lastPathComponent]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return normalizedPath
    }

    private func updateMissingPlaceholder(path: String,
                                          displayName: String? = nil,
                                          removableSource: String? = nil) -> MissingAppPlaceholder? {
        let normalizedPath = standardizedFilePath(path)
        let resolvedDisplayName = placeholderDisplayName(for: normalizedPath, preferred: displayName)
        let resolvedSource = removableSource ?? removableSourcePath(forAppPath: normalizedPath) ?? missingPlaceholders[normalizedPath]?.removableSource
        guard shouldTrackMissingPlaceholder(at: normalizedPath, removableSource: resolvedSource) else {
            missingPlaceholders.removeValue(forKey: normalizedPath)
            return nil
        }

        let placeholder = MissingAppPlaceholder(bundlePath: normalizedPath,
                                               displayName: resolvedDisplayName,
                                               removableSource: resolvedSource)
        missingPlaceholders[normalizedPath] = placeholder
        if missingPlaceholders.count > 1 {
            missingPlaceholders = missingPlaceholders.filter { key, _ in
                let normalizedKey = standardizedFilePath(key)
                return normalizedKey != normalizedPath || key == normalizedPath
            }
            missingPlaceholders[normalizedPath] = placeholder
        }
        return placeholder
    }

    private func shouldTrackMissingPlaceholder(at normalizedPath: String,
                                               removableSource: String?) -> Bool {
        guard let removableSource else { return false }

        let normalizedSource = normalizeApplicationPath(removableSource) ?? standardizedFilePath(removableSource)
        let customSources = customAppSourcePaths.map { normalizeApplicationPath($0) ?? standardizedFilePath($0) }
        guard customSources.contains(normalizedSource) else { return false }

        // A missing app is retained only while its configured source itself is
        // unavailable (for example, an unmounted external volume). If the source
        // is reachable, the missing bundle represents a real removal.
        var isDirectory: ObjCBool = false
        return !FileManager.default.fileExists(atPath: normalizedSource, isDirectory: &isDirectory)
            || !isDirectory.boolValue
            || !FileManager.default.isReadableFile(atPath: normalizedSource)
    }

    private func clearMissingPlaceholder(for path: String) {
        missingPlaceholders.removeValue(forKey: standardizedFilePath(path))
    }

    private func currentMissingAppItem(for placeholder: MissingAppPlaceholder) -> LaunchpadItem? {
        let normalizedPath = standardizedFilePath(placeholder.bundlePath)
        guard let currentPlaceholder = missingPlaceholders[normalizedPath] else { return nil }
        return .missingApp(currentPlaceholder)
    }

    private func placeholderAppInfo(forMissingPath path: String, preferredName: String? = nil) -> AppInfo? {
        guard let placeholder = updateMissingPlaceholder(path: path, displayName: preferredName) else {
            return nil
        }
        let placeholderURL = URL(fileURLWithPath: placeholder.bundlePath)
        let info = AppInfo(name: placeholder.displayName,
                           icon: placeholder.icon,
                           url: placeholderURL)
        return info
    }

    private func refreshMissingPlaceholders() {
        guard !items.isEmpty else {
            if !missingPlaceholders.isEmpty {
                missingPlaceholders.removeAll()
            }
            return
        }

        var updatedItems = items
        var mutated = false
        let fileManager = FileManager.default

        for index in updatedItems.indices {
            switch updatedItems[index] {
            case .app(let app):
                let path = standardizedFilePath(app.url.path)
                if fileManager.fileExists(atPath: path) {
                    clearMissingPlaceholder(for: path)
                } else {
                    if let placeholder = updateMissingPlaceholder(path: path, displayName: app.name) {
                        updatedItems[index] = .missingApp(placeholder)
                    } else {
                        updatedItems[index] = .empty(UUID().uuidString)
                    }
                    mutated = true
                }
            case .missingApp(let placeholder):
                let path = standardizedFilePath(placeholder.bundlePath)
                if fileManager.fileExists(atPath: path) {
                    if let existing = apps.first(where: { standardizedFilePath($0.url.path) == path }) {
                        clearMissingPlaceholder(for: path)
                        updatedItems[index] = .app(existing)
                        mutated = true
                    } else {
                        let url = URL(fileURLWithPath: path)
                        let info = appInfo(from: url, preferredName: placeholder.displayName)
                        clearMissingPlaceholder(for: path)
                        if !apps.contains(where: { standardizedFilePath($0.url.path) == path }) {
                            apps.append(info)
                            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                            pruneHiddenAppsFromAppList()
                        }
                        updatedItems[index] = .app(info)
                        mutated = true
                    }
                } else {
                    if updateMissingPlaceholder(path: path,
                                                displayName: placeholder.displayName,
                                                removableSource: placeholder.removableSource) == nil {
                        updatedItems[index] = .empty(UUID().uuidString)
                        mutated = true
                    }
                }
            default:
                break
            }
        }

        if mutated {
            updatedItems = filteredItemsRemovingHidden(from: updatedItems)
            items = updatedItems
        }

        let placeholderPathsInUse = Set(updatedItems.compactMap { item -> String? in
            if case let .missingApp(placeholder) = item { return standardizedFilePath(placeholder.bundlePath) }
            return nil
        })
        if placeholderPathsInUse.count != missingPlaceholders.count {
            missingPlaceholders = missingPlaceholders.filter { key, _ in
                placeholderPathsInUse.contains(standardizedFilePath(key))
            }
        }
    }

    private func purgeMissingPlaceholders(forRemovedSources rawSources: [String]) {
        guard !rawSources.isEmpty else { return }
        let normalizedSources = rawSources.compactMap { path in
            normalizeApplicationPath(path) ?? standardizedFilePath(path)
        }
        guard !normalizedSources.isEmpty else { return }
        let sourceSet = Set(normalizedSources)

        var removalSet = Set<String>()
        var removalRawPaths = Set<String>()
        for (key, placeholder) in missingPlaceholders {
            let normalizedKey = standardizedFilePath(key)

            var matchesRemovedSource = false
            if let source = placeholder.removableSource {
                let normalizedSource = normalizeApplicationPath(source) ?? standardizedFilePath(source)
                if sourceSet.contains(normalizedSource) {
                    matchesRemovedSource = true
                }
            }

            if !matchesRemovedSource {
                matchesRemovedSource = sourceSet.contains { source in
                    if normalizedKey == source { return true }
                    let prefix = source.hasSuffix("/") ? source : source + "/"
                    return normalizedKey.hasPrefix(prefix)
                }
            }

            if matchesRemovedSource {
                removalSet.insert(normalizedKey)
                removalRawPaths.insert(key)
            }
        }

        // Proactively add every existing app path from a removed source (whether or not it's missing)
        if !sourceSet.isEmpty {
            let prefixes: [String] = sourceSet.map { $0.hasSuffix("/") ? $0 : $0 + "/" }

            func considerRemoval(path raw: String) {
                let normalized = standardizedFilePath(raw)
                if sourceSet.contains(normalized) || prefixes.contains(where: { normalized.hasPrefix($0) }) {
                    removalSet.insert(normalized)
                    removalRawPaths.insert(raw)
                }
            }

            for app in apps {
                considerRemoval(path: app.url.path)
            }

            for folder in folders {
                for app in folder.apps {
                    considerRemoval(path: app.url.path)
                }
            }

            for item in items {
                switch item {
                case .app(let app):
                    considerRemoval(path: app.url.path)
                case .missingApp(let placeholder):
                    considerRemoval(path: placeholder.bundlePath)
                case .folder(let folder):
                    for app in folder.apps {
                        considerRemoval(path: app.url.path)
                    }
                case .empty:
                    break
                }
            }
        }

        guard !removalSet.isEmpty else { return }

        var updatedItems = items
        var mutatedItems = false
        for index in updatedItems.indices {
            switch updatedItems[index] {
            case .missingApp(let placeholder):
                if removalSet.contains(standardizedFilePath(placeholder.bundlePath)) {
                    updatedItems[index] = .empty(UUID().uuidString)
                    mutatedItems = true
                }
            case .app(let app):
                if removalSet.contains(standardizedFilePath(app.url.path)) {
                    updatedItems[index] = .empty(UUID().uuidString)
                    mutatedItems = true
                }
            case .folder(var folder):
                let originalCount = folder.apps.count
                folder.apps.removeAll { removalSet.contains(standardizedFilePath($0.url.path)) }
                if folder.apps.count != originalCount {
                    mutatedItems = true
                    if folder.apps.isEmpty {
                        updatedItems[index] = .empty(UUID().uuidString)
                    } else {
                        updatedItems[index] = .folder(folder)
                    }
                }
            case .empty:
                break
            }
        }
        if mutatedItems {
            updatedItems = filteredItemsRemovingHidden(from: updatedItems)
            items = updatedItems
        }

        if !removalSet.isEmpty {
            apps.removeAll { removalSet.contains(standardizedFilePath($0.url.path)) }
            for idx in folders.indices {
                folders[idx].apps.removeAll { removalSet.contains(standardizedFilePath($0.url.path)) }
            }
            pruneHiddenAppsFromAppList()
            if !customTitles.isEmpty {
                customTitles = customTitles.filter { key, _ in
                    !removalSet.contains(standardizedFilePath(key))
                }
            }
            if !hiddenAppPaths.isEmpty {
                updateHiddenAppPaths { hidden in
                    for path in removalSet { hidden.remove(path) }
                    for raw in removalRawPaths { hidden.remove(raw) }
                }
            }
        }

        missingPlaceholders = missingPlaceholders.filter { key, _ in
            !removalSet.contains(standardizedFilePath(key))
        }

        triggerFolderUpdate()
        triggerGridRefresh()
        compactItemsWithinPages()
        refreshMissingPlaceholders()
        saveAllOrder()
    }

    private func sanitizedCustomPaths(from rawPaths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in rawPaths {
            guard let normalized = normalizeApplicationPath(raw) else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }
    


    private let systemApplicationSearchPaths: [String] = [
        "/Applications",
        "\(NSHomeDirectory())/Applications",
        "/System/Applications",
        "/System/Cryptexes/App/System/Applications"
    ]

    static let customAppSourcesKey = "customApplicationSourcePaths"

    @Published var customAppSourcePaths: [String] = {
        guard let saved = UserDefaults.standard.array(forKey: AppStore.customAppSourcesKey) as? [String] else { return [] }
        return saved
    }() {
        didSet {
            guard customAppSourcePaths != oldValue else { return }
            UserDefaults.standard.set(customAppSourcePaths, forKey: AppStore.customAppSourcesKey)
            restartAutoRescan()
            requestApplicationReconciliation(reason: .sourceChange)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.removeEmptyPages()
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        compactWindowMaxWidth = CompactWindowLayout.normalizedMaximumWidth(defaults.integer(forKey: Self.compactWindowMaxWidthKey))
        compactWindowMaxHeight = CompactWindowLayout.normalizedMaximumHeight(defaults.integer(forKey: Self.compactWindowMaxHeightKey))
        windowShadowEnabled = defaults.object(forKey: Self.windowShadowEnabledKey) as? Bool ?? false
        Self.migrateFolderLiquidGlassDefaultIfNeeded(from: defaults)
        folderLiquidGlassEnabled = Self.loadFolderLiquidGlassEnabled(from: defaults)
        let existingInstallBeforeDefaults = defaults.object(forKey: Self.onboardingVersionKey) != nil ||
            defaults.object(forKey: "isFullscreenMode") != nil ||
            defaults.object(forKey: Self.gridColumnsKey) != nil

        if defaults.object(forKey: Self.folderLayoutModeKey) == nil {
            let initialFolderLayout = Self.loadFolderLayoutMode(from: defaults, isExistingInstall: existingInstallBeforeDefaults)
            defaults.set(initialFolderLayout.rawValue, forKey: Self.folderLayoutModeKey)
            self.folderLayoutMode = initialFolderLayout
        } else {
            self.folderLayoutMode = Self.loadFolderLayoutMode(from: defaults, isExistingInstall: existingInstallBeforeDefaults)
        }

        if UserDefaults.standard.object(forKey: "isFullscreenMode") == nil {
            self.isFullscreenMode = true // New users default to Classic (Fullscreen)
            UserDefaults.standard.set(true, forKey: "isFullscreenMode")
        } else {
            self.isFullscreenMode = UserDefaults.standard.bool(forKey: "isFullscreenMode")
        }
        let shouldRememberPage = defaults.object(forKey: Self.rememberPageKey) == nil ? true : defaults.bool(forKey: Self.rememberPageKey)
        let savedPageIndex = defaults.object(forKey: Self.rememberedPageIndexKey) as? Int

        let initialScrollSensitivity: Double
        if defaults.object(forKey: "scrollSensitivity") == nil {
            initialScrollSensitivity = 0.8
            defaults.set(initialScrollSensitivity, forKey: "scrollSensitivity")
        } else {
            let storedSensitivity = defaults.double(forKey: "scrollSensitivity")
            initialScrollSensitivity = storedSensitivity == 0 ? Self.defaultScrollSensitivity : storedSensitivity
        }
        scrollSensitivity = initialScrollSensitivity

        let storedColumns = defaults.object(forKey: Self.gridColumnsKey) as? Int ?? 7
        let clampedColumns = Self.clampColumns(storedColumns)
        self.gridColumnsPerPage = clampedColumns

        defaults.set(clampedColumns, forKey: Self.gridColumnsKey)

        let storedRows = defaults.object(forKey: Self.gridRowsKey) as? Int ?? 5
        let clampedRows = Self.clampRows(storedRows)
        self.gridRowsPerPage = clampedRows
        defaults.set(clampedRows, forKey: Self.gridRowsKey)

        let storedColumnSpacing = defaults.object(forKey: Self.columnSpacingKey) as? Double ?? 20.0
        let clampedColumnSpacing = Self.clampColumnSpacing(storedColumnSpacing)
        self.iconColumnSpacing = clampedColumnSpacing
        defaults.set(clampedColumnSpacing, forKey: Self.columnSpacingKey)

        let storedRowSpacing = defaults.object(forKey: Self.rowSpacingKey) as? Double ?? 14.0
        let clampedRowSpacing = Self.clampRowSpacing(storedRowSpacing)
        self.iconRowSpacing = clampedRowSpacing
        defaults.set(clampedRowSpacing, forKey: Self.rowSpacingKey)

        let storedFolderColumnSpacing = defaults.object(forKey: Self.folderColumnSpacingKey) as? Double ?? Self.defaultFolderColumnSpacing
        let clampedFolderColumnSpacing = Self.clampColumnSpacing(storedFolderColumnSpacing)
        self.folderIconColumnSpacing = clampedFolderColumnSpacing
        defaults.set(clampedFolderColumnSpacing, forKey: Self.folderColumnSpacingKey)

        let storedFolderRowSpacing = defaults.object(forKey: Self.folderRowSpacingKey) as? Double ?? Self.defaultFolderRowSpacing
        let clampedFolderRowSpacing = Self.clampRowSpacing(storedFolderRowSpacing)
        self.folderIconRowSpacing = clampedFolderRowSpacing
        defaults.set(clampedFolderRowSpacing, forKey: Self.folderRowSpacingKey)

        let storedDropZoneScale = defaults.object(forKey: Self.folderDropZoneScaleKey) as? Double ?? Self.defaultFolderDropZoneScale
        let clampedDropZoneScale = Self.clampFolderDropZoneScale(storedDropZoneScale)
        self.folderDropZoneScale = clampedDropZoneScale
        defaults.set(clampedDropZoneScale, forKey: Self.folderDropZoneScaleKey)
        if defaults.object(forKey: Self.pageIndicatorTopPaddingKey) == nil {
            defaults.set(Self.defaultPageIndicatorTopPadding, forKey: Self.pageIndicatorTopPaddingKey)
        }
        if defaults.object(forKey: Self.pageIndicatorPerDisplayEnabledKey) == nil {
            defaults.set(false, forKey: Self.pageIndicatorPerDisplayEnabledKey)
        }
        let storedTopPadding = defaults.object(forKey: Self.pageIndicatorTopPaddingKey) as? Double ?? Self.defaultPageIndicatorTopPadding
        let clampedTopPadding = Self.clampPageIndicatorTopPadding(storedTopPadding)
        self.pageIndicatorTopPadding = clampedTopPadding
        defaults.set(clampedTopPadding, forKey: Self.pageIndicatorTopPaddingKey)
        // Read the icon scale default value
        if let v = UserDefaults.standard.object(forKey: "iconScale") as? Double {
            self.iconScale = v
        }
        if UserDefaults.standard.object(forKey: "enableDropPrediction") == nil {
            UserDefaults.standard.set(true, forKey: "enableDropPrediction")
        }
        if UserDefaults.standard.object(forKey: "useLocalizedThirdPartyTitles") == nil {
            UserDefaults.standard.set(true, forKey: "useLocalizedThirdPartyTitles")
        }
        if UserDefaults.standard.object(forKey: "enableAnimations") == nil {
            UserDefaults.standard.set(true, forKey: "enableAnimations")
        }
        if UserDefaults.standard.object(forKey: AppStore.reverseWheelPagingKey) == nil {
            UserDefaults.standard.set(false, forKey: AppStore.reverseWheelPagingKey)
        }
        if UserDefaults.standard.object(forKey: AppStore.reverseWheelVerticalKey) == nil {
            UserDefaults.standard.set(false, forKey: AppStore.reverseWheelVerticalKey)
        }
        if UserDefaults.standard.object(forKey: AppStore.trackpadVerticalDirectionKey) == nil {
            UserDefaults.standard.set(TrackpadVerticalDirection.natural.rawValue, forKey: AppStore.trackpadVerticalDirectionKey)
        }
        if defaults.object(forKey: Self.dockDragEnabledKey) == nil {
            let legacySideRaw = defaults.string(forKey: Self.dockDragSideKey)
            defaults.set(legacySideRaw != DockDragSide.disabled.rawValue, forKey: Self.dockDragEnabledKey)
        }
        if defaults.object(forKey: Self.dockDragSideKey) == nil {
            defaults.set(DockDragSide.bottom.rawValue, forKey: Self.dockDragSideKey)
        }
        let storedDockDragDistance = defaults.object(forKey: Self.dockDragTriggerDistanceKey) as? Double ?? Self.defaultDockDragTriggerDistance
        let clampedDockDragDistance = Self.clampDockDragTriggerDistance(storedDockDragDistance)
        defaults.set(clampedDockDragDistance, forKey: Self.dockDragTriggerDistanceKey)
        if defaults.object(forKey: Self.hotCornerEnabledKey) == nil {
            defaults.set(false, forKey: Self.hotCornerEnabledKey)
        }
        if defaults.object(forKey: Self.hotCornerPositionKey) == nil {
            defaults.set(HotCornerPosition.topLeft.rawValue, forKey: Self.hotCornerPositionKey)
        }
        let storedHotCornerDelay = defaults.object(forKey: Self.hotCornerTriggerDelayKey) as? Double ?? Self.defaultHotCornerTriggerDelay
        let clampedHotCornerDelay = Self.clampHotCornerTriggerDelay(storedHotCornerDelay)
        defaults.set(clampedHotCornerDelay, forKey: Self.hotCornerTriggerDelayKey)
        let storedHotCornerHitboxSize = defaults.object(forKey: Self.hotCornerHitboxSizeKey) as? Double ?? Self.defaultHotCornerHitboxSize
        let clampedHotCornerHitboxSize = Self.clampHotCornerHitboxSize(storedHotCornerHitboxSize)
        defaults.set(clampedHotCornerHitboxSize, forKey: Self.hotCornerHitboxSizeKey)
        if defaults.object(forKey: Self.hotCornerToggleWhenOpenKey) == nil {
            defaults.set(false, forKey: Self.hotCornerToggleWhenOpenKey)
        }
        if defaults.object(forKey: Self.hideMenuBarKey) == nil {
            defaults.set(false, forKey: Self.hideMenuBarKey)
        }
        if defaults.object(forKey: Self.gestureEnabledKey) == nil {
            defaults.set(false, forKey: Self.gestureEnabledKey)
        }
        if defaults.object(forKey: Self.gestureCloseOnPinchOutKey) == nil {
            defaults.set(false, forKey: Self.gestureCloseOnPinchOutKey)
        }
        // Keep a one-time migration path from the older tap booleans so users
        // do not lose settings if gesture support remains enabled.
        if defaults.object(forKey: Self.gestureTapActionKey) == nil {
            let legacyEnabled = defaults.object(forKey: "gestureTapEnabled") as? Bool ?? false
            let legacyToggle = defaults.object(forKey: "gestureTapToggleWhenOpen") as? Bool ?? false
            let migratedAction: GestureTapAction = legacyEnabled ? (legacyToggle ? .toggle : .open) : .off
            defaults.set(migratedAction.rawValue, forKey: Self.gestureTapActionKey)
        }
        if defaults.object(forKey: Self.gestureFingerCountKey) == nil {
            defaults.set(GestureFingerCount.four.rawValue, forKey: Self.gestureFingerCountKey)
        }
        if defaults.object(forKey: Self.gestureDeviceSelectionModeKey) == nil {
            defaults.set(GestureDeviceSelectionMode.automatic.rawValue, forKey: Self.gestureDeviceSelectionModeKey)
        }
        if defaults.object(forKey: Self.gestureSelectedDeviceIDsKey) == nil {
            defaults.set([], forKey: Self.gestureSelectedDeviceIDsKey)
        }
        if defaults.object(forKey: Self.gestureShowAllInputDevicesKey) == nil {
            defaults.set(false, forKey: Self.gestureShowAllInputDevicesKey)
        }
        if defaults.object(forKey: Self.gameControllerMenuToggleKey) == nil {
            defaults.set(true, forKey: Self.gameControllerMenuToggleKey)
        }
        if defaults.object(forKey: Self.developmentEnableCLICodeKey) == nil {
            defaults.set(false, forKey: Self.developmentEnableCLICodeKey)
        }
        if defaults.object(forKey: Self.showQuarantineRemovalActionKey) == nil {
            defaults.set(false, forKey: Self.showQuarantineRemovalActionKey)
        }
        if defaults.object(forKey: Self.fuzzySearchEnabledKey) == nil {
            defaults.set(true, forKey: Self.fuzzySearchEnabledKey)
        }
        if defaults.object(forKey: Self.searchDebounceMillisecondsKey) == nil {
            defaults.set(300, forKey: Self.searchDebounceMillisecondsKey)
        }
        if defaults.object(forKey: Self.backgroundMaskEnabledKey) == nil {
            defaults.set(false, forKey: Self.backgroundMaskEnabledKey)
        }
        if defaults.object(forKey: Self.backgroundMaskLightKey) == nil {
            Self.persistBackgroundMaskColor(Self.defaultBackgroundMaskColor, forKey: Self.backgroundMaskLightKey)
        }
        if defaults.object(forKey: Self.backgroundMaskDarkKey) == nil {
            Self.persistBackgroundMaskColor(Self.defaultBackgroundMaskColor, forKey: Self.backgroundMaskDarkKey)
        }
        if UserDefaults.standard.object(forKey: "iconLabelFontSize") == nil {
            UserDefaults.standard.set(11.0, forKey: "iconLabelFontSize")
        }
        if UserDefaults.standard.object(forKey: AppStore.iconLabelFontWeightKey) == nil {
            UserDefaults.standard.set(IconLabelFontWeightOption.medium.rawValue, forKey: AppStore.iconLabelFontWeightKey)
        }
        if UserDefaults.standard.object(forKey: "animationDuration") == nil {
            UserDefaults.standard.set(0.3, forKey: "animationDuration")
        }
        if defaults.object(forKey: Self.windowOpenAnimationKey) == nil {
            defaults.set(true, forKey: Self.windowOpenAnimationKey)
        }
        if defaults.object(forKey: Self.windowAnimationDurationKey) == nil {
            defaults.set(Self.defaultWindowAnimationDuration, forKey: Self.windowAnimationDurationKey)
        }
        if UserDefaults.standard.object(forKey: "showFPSOverlay") == nil {
            UserDefaults.standard.set(false, forKey: "showFPSOverlay")
        }
        if defaults.object(forKey: "pageIndicatorOffset") == nil {
            defaults.set(27.0, forKey: "pageIndicatorOffset")
        }

        if let storedDualModeAppearance = Self.loadDualModeAppearanceSettings(from: defaults) {
            self.dualModeAppearanceSettings = storedDualModeAppearance
        } else {
            let legacy = Self.legacyAppearanceSettings(from: defaults)
            let migrated = DualModeAppearanceSettings(fullscreen: legacy, compact: legacy)
            self.dualModeAppearanceSettings = migrated
            if let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: Self.dualModeAppearanceSettingsKey)
            }
        }

        let storedDuration = UserDefaults.standard.double(forKey: "animationDuration")
        self.animationDuration = storedDuration == 0 ? 0.3 : storedDuration
        self.enableWindowOpenAnimation = defaults.object(forKey: Self.windowOpenAnimationKey) as? Bool ?? true
        self.windowAnimationDuration = Self.clampWindowAnimationDuration(
            defaults.object(forKey: Self.windowAnimationDurationKey) as? Double ?? Self.defaultWindowAnimationDuration
        )
        self.dockDragEnabled = defaults.object(forKey: Self.dockDragEnabledKey) as? Bool ?? true
        let storedDockDragSide = DockDragSide(rawValue: defaults.string(forKey: Self.dockDragSideKey) ?? "")
        self.dockDragSide = storedDockDragSide == .disabled ? .bottom : (storedDockDragSide ?? .bottom)
        self.dockDragTriggerDistance = clampedDockDragDistance
        self.hotCornerEnabled = defaults.object(forKey: Self.hotCornerEnabledKey) as? Bool ?? false
        self.hotCornerPosition = HotCornerPosition(rawValue: defaults.string(forKey: Self.hotCornerPositionKey) ?? "") ?? .topLeft
        self.hotCornerTriggerDelay = clampedHotCornerDelay
        self.hotCornerHitboxSize = clampedHotCornerHitboxSize
        self.hotCornerToggleWhenOpen = defaults.object(forKey: Self.hotCornerToggleWhenOpenKey) as? Bool ?? false
        self.hideMenuBar = defaults.object(forKey: Self.hideMenuBarKey) as? Bool ?? false
        self.gestureEnabled = defaults.object(forKey: Self.gestureEnabledKey) as? Bool ?? false
        self.gestureCloseOnPinchOut = defaults.object(forKey: Self.gestureCloseOnPinchOutKey) as? Bool ?? false
        self.gestureTapAction = GestureTapAction(rawValue: defaults.string(forKey: Self.gestureTapActionKey) ?? "") ?? .off
        self.gestureFingerCount = GestureFingerCount(rawValue: defaults.integer(forKey: Self.gestureFingerCountKey)) ?? .four
        self.gestureDeviceSelectionMode = GestureDeviceSelectionMode(rawValue: defaults.string(forKey: Self.gestureDeviceSelectionModeKey) ?? "") ?? .automatic
        self.gestureSelectedDeviceIDs = Array(Set(defaults.stringArray(forKey: Self.gestureSelectedDeviceIDsKey) ?? [])).sorted()
        self.gestureShowAllInputDevices = defaults.object(forKey: Self.gestureShowAllInputDevicesKey) as? Bool ?? false
        self.enableAnimations = UserDefaults.standard.object(forKey: "enableAnimations") as? Bool ?? true
        self.customIconFileURL = AppStore.customIconFileURL

        let fallbackIcon = (NSApplication.shared.applicationIconImage?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 512, height: 512))
        self.defaultAppIcon = fallbackIcon
        if let storedIcon = AppStore.loadStoredAppIcon(from: customIconFileURL) {
            self.hasCustomAppIcon = true
            self.currentAppIcon = storedIcon
        } else {
            self.hasCustomAppIcon = false
            self.currentAppIcon = fallbackIcon
        }
        applyCurrentAppIcon()
        syncActiveAppearanceProxies(from: currentAppearanceLayoutMode)
        persistLegacyAppearanceProxyValues()

        let sanitizedSources = sanitizedCustomPaths(from: customAppSourcePaths)
        if sanitizedSources != customAppSourcePaths {
            customAppSourcePaths = sanitizedSources
        }
        refreshGestureDeviceInventory()

        setupVolumeObservers()

        $searchText
            .removeDuplicates()
            .sink { [weak self] value in
                self?.scheduleSearchQueryUpdate(with: value)
            }
            .store(in: &cancellables)

        searchQuery = searchText

        if developmentEnableCLICode {
            installCLICommandIfNeeded()
        } else {
            uninstallCLICommandIfNeeded()
        }

        self.rememberLastPage = shouldRememberPage
        if shouldRememberPage, let savedPageIndex {
            self.currentPage = max(0, savedPageIndex)
        }

        syncLoginItemStatusFromSystem()
    }

    private static func clampedSearchDebounceMilliseconds(_ value: Double) -> Double {
        min(max(value, searchDebounceMillisecondsRange.lowerBound), searchDebounceMillisecondsRange.upperBound)
    }

    /// Resolve against the saved layout, not the flattened search results.
    func layoutLocation(ofAppAtPath path: String) -> (index: Int, folder: FolderInfo?)? {
        for (index, item) in items.enumerated() {
            switch item {
            case .app(let app) where app.url.standardizedFileURL.path == path:
                return (index, nil)
            case .folder(let folder) where folder.apps.contains(where: { $0.url.standardizedFileURL.path == path }):
                return (index, folder)
            default:
                continue
            }
        }
        return nil
    }

    @discardableResult
    func requestShowInLayout(_ app: AppInfo) -> Bool {
        let path = app.url.standardizedFileURL.path
        guard layoutLocation(ofAppAtPath: path) != nil else { return false }
        layoutRevealRequest = LayoutRevealRequest(appPath: path)
        searchText = ""
        // Do not wait for search debounce or allow an older query to arrive later.
        searchQueryWorkItem?.cancel()
        searchQueryWorkItem = nil
        searchQuery = ""
        return true
    }

    private func scheduleSearchQueryUpdate(with value: String) {
        searchQueryWorkItem?.cancel()

        let delayMilliseconds = Self.clampedSearchDebounceMilliseconds(searchDebounceMilliseconds)
        guard delayMilliseconds > 0 else {
            searchQuery = value
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.searchQuery = value
        }
        searchQueryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delayMilliseconds / 1000, execute: work)
    }

    func syncLoginItemStatusFromSystem() {
        guard #available(macOS 13.0, *) else { return }
        loginItemUpdateInProgress = true
        isStartOnLogin = SMAppService.mainApp.status == .enabled
        loginItemUpdateInProgress = false
    }

    private func installCLICommandIfNeeded() {
        guard let executablePath = Bundle.main.executableURL?.path else { return }
        for path in cliCommandTargets() {
            if installCLIShim(at: path, executablePath: executablePath) {
                let directory = (path as NSString).deletingLastPathComponent
                ensureZProfilePathIncludes(directory: directory)
                return
            }
        }
    }

    @discardableResult
    func removeInstalledCLICommand() -> Bool {
        uninstallCLICommandIfNeeded()
    }

    private func cliCommandTargets() -> [String] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/launchng",
            "/usr/local/bin/launchng",
            "\(homePath)/.local/bin/launchng",
            "\(homePath)/bin/launchng"
        ]
    }

    private func installCLIShim(at shimPath: String, executablePath: String) -> Bool {
        let fileManager = FileManager.default
        let directoryPath = (shimPath as NSString).deletingLastPathComponent

        if !fileManager.fileExists(atPath: directoryPath) {
            do {
                try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        guard fileManager.isWritableFile(atPath: directoryPath) else {
            return false
        }

        if fileManager.fileExists(atPath: shimPath) {
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: shimPath),
               destination == executablePath {
                return true
            }
            if let existing = try? String(contentsOfFile: shimPath, encoding: .utf8),
               existing.contains(Self.cliShimMarker) {
                // Managed shim, safe to replace.
            } else {
                return false
            }
        }

        let escapedExecutable = executablePath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        #!/bin/zsh
        \(Self.cliShimMarker)
        
        if [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
          cat <<'EOF'
        LaunchNG CLI
        
        Usage:
          launchng --help
          launchng --gui
          launchng --tui
          launchng --cli help
          launchng --cli list
          launchng --cli snapshot
          launchng --cli search --query "safari"
          launchng --cli move --source normal-app --path "/Applications/Thaw.app" --to folder-append --target-folder-id <folder-id>
        
        Notes:
          - Keep `--cli --help` and `--cli help` for full in-app CLI help.
          - LaunchNG GUI must be running for list/snapshot/search/move.
          - "Command line interface" must be ON in General settings.
        EOF
          exit 0
        fi
        
        exec "\(escapedExecutable)" "$@"
        """

        do {
            try script.write(toFile: shimPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int(0o755))], ofItemAtPath: shimPath)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func uninstallCLICommandIfNeeded() -> Bool {
        var removedAny = false
        for path in cliCommandTargets() {
            let directory = (path as NSString).deletingLastPathComponent
            if uninstallCLIShim(at: path) { removedAny = true }
            if removeCLIPathSnippetFromZProfile(directory: directory) { removedAny = true }
        }
        return removedAny
    }

    private func uninstallCLIShim(at shimPath: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: shimPath) else { return false }

        let isManagedShim: Bool = {
            if let existing = try? String(contentsOfFile: shimPath, encoding: .utf8),
               existing.contains(Self.cliShimMarker) {
                return true
            }
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: shimPath),
               destination.contains("/LaunchNG.app/Contents/MacOS/LaunchNG") {
                return true
            }
            return false
        }()

        guard isManagedShim else { return false }
        do {
            try fileManager.removeItem(atPath: shimPath)
            return true
        } catch {
            return false
        }
    }

    private func ensureZProfilePathIncludes(directory: String) {
        guard directory.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) else { return }

        let zprofileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zprofile")
        let snippet = cliPathSnippet(directory: directory)

        if let existing = try? String(contentsOf: zprofileURL, encoding: .utf8) {
            if existing.contains(":\(directory):") || existing.contains("export PATH=\"\(directory):$PATH\"") {
                return
            }
            try? (existing + snippet).write(to: zprofileURL, atomically: true, encoding: .utf8)
        } else {
            try? snippet.write(to: zprofileURL, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    private func removeCLIPathSnippetFromZProfile(directory: String) -> Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard directory.hasPrefix(homePath) else { return false }

        let zprofileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zprofile")
        guard let existing = try? String(contentsOf: zprofileURL, encoding: .utf8) else { return false }

        var updated = existing
        updated = updated.replacingOccurrences(of: cliPathSnippet(directory: directory), with: "")
        updated = updated.replacingOccurrences(of: legacyCLIPathSnippet(directory: directory), with: "")

        guard updated != existing else { return false }
        do {
            try updated.write(to: zprofileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func cliPathSnippet(directory: String) -> String {
        """
        
        \(Self.cliPathSnippetHeader)
        if [[ ":$PATH:" != *":\(directory):"* ]]; then
          export PATH="\(directory):$PATH"
        fi
        \(Self.cliPathSnippetFooter)
        """
    }

    private func legacyCLIPathSnippet(directory: String) -> String {
        """
        
        # LaunchNG CLI
        if [[ ":$PATH:" != *":\(directory):"* ]]; then
          export PATH="\(directory):$PATH"
        fi
        """
    }

    private static func loadCustomTitles() -> [String: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: AppStore.customTitlesKey) else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in raw {
            guard let stringValue = value as? String else { continue }
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[key] = trimmed
            }
        }
        return result
    }

    private static func loadHotKeyConfiguration() -> HotKeyConfiguration? {
        guard let dict = UserDefaults.standard.dictionary(forKey: globalHotKeyKey) else { return nil }
        return HotKeyConfiguration(dictionary: dict)
    }

    // private static func loadAIOverlayHotKeyConfiguration() -> HotKeyConfiguration? {
    //     guard let dict = UserDefaults.standard.dictionary(forKey: aiOverlayHotKeyKey) else { return nil }
    //     return HotKeyConfiguration(dictionary: dict)
    // }

    private func persistCustomTitles() {
        let sanitized = customTitles.reduce(into: [String: String]()) { partialResult, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                partialResult[entry.key] = trimmed
            }
        }

        if sanitized.isEmpty {
            UserDefaults.standard.removeObject(forKey: AppStore.customTitlesKey)
        } else {
            UserDefaults.standard.set(sanitized, forKey: AppStore.customTitlesKey)
        }
    }

    // private func persistAIOverlayHotKeyConfiguration() {
    //     let defaults = UserDefaults.standard
    //     if let config = aiOverlayHotKey {
    //         defaults.set(config.dictionaryRepresentation, forKey: Self.aiOverlayHotKeyKey)
    //     } else {
    //         defaults.removeObject(forKey: Self.aiOverlayHotKeyKey)
    //     }
    // }

    private func persistHotKeyConfiguration() {
        let defaults = UserDefaults.standard
        if let config = globalHotKey {
            defaults.set(config.dictionaryRepresentation, forKey: Self.globalHotKeyKey)
        } else {
            defaults.removeObject(forKey: Self.globalHotKeyKey)
        }
    }


    // Icon scale (relative to the grid cell): defaults to 0.95, recommended range 0.8~1.1
    @Published var iconScale: Double = 0.95 {
        didSet {
            UserDefaults.standard.set(iconScale, forKey: "iconScale")
            guard !isApplyingScopedAppearanceState else { return }
            updateScopedAppearanceSettings(for: currentAppearanceLayoutMode) { $0.iconScale = iconScale }
            iconScaleWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.triggerGridRefresh() }
            iconScaleWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        evaluateOnboardingGate()
        
        // Try loading persisted data right away (if any already exists) -- don't set the flag too early, set it once loading actually completes
        if !hasAppliedOrderFromStore {
            loadAllOrder()
        }
        
        $apps
            .map { !$0.isEmpty }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.hasAppliedOrderFromStore {
                    self.loadAllOrder()
                }
            }
            .store(in: &cancellables)
        
        // Observe changes to items and auto-save the order
        $items
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.items.isEmpty else { return }
                // Delay saving to avoid saving too often
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.saveAllOrder()
                }
            }
            .store(in: &cancellables)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(Self.currentOnboardingVersion, forKey: Self.onboardingVersionKey)
        shouldShowOnboarding = false
    }

    func forceShowOnboarding() {
        guard isFullscreenMode else { return }

        if isSetting {
            isSetting = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.shouldShowOnboarding = false
                self.shouldShowOnboarding = true
            }
            return
        }

        shouldShowOnboarding = false
        DispatchQueue.main.async { [weak self] in
            self?.shouldShowOnboarding = true
        }
    }

    private func evaluateOnboardingGate() {
        let shownVersion = UserDefaults.standard.object(forKey: Self.onboardingVersionKey) as? Int ?? 0
        guard shownVersion < Self.currentOnboardingVersion else {
            shouldShowOnboarding = false
            return
        }

        if isExistingUserForOnboarding() {
            UserDefaults.standard.set(Self.currentOnboardingVersion, forKey: Self.onboardingVersionKey)
            shouldShowOnboarding = false
            return
        }

        shouldShowOnboarding = true
    }

    private func isExistingUserForOnboarding() -> Bool {
        if !hiddenAppPaths.isEmpty { return true }
        if !customTitles.isEmpty { return true }
        if hasPersistedOrderData() { return true }
        return false
    }

    // MARK: - Order Persistence
    func applyOrderAndFolders() {
        self.loadAllOrder()
    }

    // MARK: - Initial scan (once)
    func performInitialScanIfNeeded() {
        guard !hasPerformedInitialScan else { return }

        // Try loading persisted data first, so a scan can't overwrite it (don't set the flag too early)
        if !hasAppliedOrderFromStore {
            loadAllOrder()
        }

        // Then scan, but keep the existing order
        hasPerformedInitialScan = true
        requestApplicationReconciliation(reason: .initial)
    }

    /// Called only when the LaunchNG window is about to become visible.
    /// There is no background timer: the 15-minute fallback is evaluated here.
    func reconcileApplicationsOnWindowShow() {
        guard hasPerformedInitialScan else { return }

        if needsReconciliationAfterExternalUninstall {
            requestApplicationReconciliation(reason: .externalUninstallerReturn)
            return
        }

        guard !applicationReconciliationInProgress else { return }
        guard let lastSuccessfulApplicationReconciliationAt else {
            requestApplicationReconciliation(reason: .staleWindowFallback)
            return
        }
        guard Date().timeIntervalSince(lastSuccessfulApplicationReconciliationAt)
                >= Self.applicationReconciliationFallbackInterval else { return }
        requestApplicationReconciliation(reason: .staleWindowFallback)
    }

    private func requestApplicationReconciliation(reason: ApplicationReconciliationReason,
                                                  debounce: TimeInterval = 0) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestApplicationReconciliation(reason: reason, debounce: debounce)
            }
            return
        }

        applicationReconciliationReasons.insert(reason)
        guard !applicationReconciliationInProgress else { return }

        applicationReconciliationWorkItem?.cancel()
        applicationReconciliationWorkItem = nil

        guard debounce > 0 else {
            startPendingApplicationReconciliation()
            return
        }

        schedulePendingApplicationReconciliation(after: debounce)
    }

    private func schedulePendingApplicationReconciliation(after delay: TimeInterval) {
        applicationReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applicationReconciliationWorkItem = nil
            self.startPendingApplicationReconciliation()
        }
        applicationReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startPendingApplicationReconciliation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startPendingApplicationReconciliation()
            }
            return
        }
        guard !applicationReconciliationInProgress,
              !applicationReconciliationReasons.isEmpty else { return }

        applicationReconciliationWorkItem?.cancel()
        applicationReconciliationWorkItem = nil

        let reasons = applicationReconciliationReasons
        FolderIconBitmapCache.shared.clear()
        applicationReconciliationReasons.removeAll()
        applicationReconciliationInProgress = true

        if reasons.contains(.manual) {
            cacheManager.clearAllCaches()
        }

        performApplicationReconciliation(reasons: reasons)
    }

    private func finishApplicationReconciliation(reasons: Set<ApplicationReconciliationReason>,
                                                 succeeded: Bool) {
        precondition(Thread.isMainThread)

        if succeeded {
            lastSuccessfulApplicationReconciliationAt = Date()
            if reasons.contains(.externalUninstallerReturn) {
                needsReconciliationAfterExternalUninstall = false
            }
        }
        applicationReconciliationInProgress = false

        if !applicationReconciliationReasons.isEmpty {
            if applicationReconciliationReasons == [.fileSystemEvent] {
                schedulePendingApplicationReconciliation(
                    after: Self.applicationReconciliationEventDebounce
                )
            } else {
                startPendingApplicationReconciliation()
            }
        }
    }

    func scanApplications(loadPersistedOrder: Bool = true) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [AppInfo] = []
            var seenPaths = Set<String>()

            for path in self.applicationSearchPaths {
                let url = URL(fileURLWithPath: path)
                
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let item as URL in enumerator {
                        let resolved = item.resolvingSymlinksInPath()
                        guard resolved.pathExtension == "app",
                              self.isValidApp(at: resolved),
                              !self.isInsideAnotherApp(resolved) else { continue }
                        if !seenPaths.contains(resolved.path) {
                            seenPaths.insert(resolved.path)
                            found.append(self.appInfo(from: resolved))
                        }
                    }
                }
            }

            let sorted = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.apps = sorted
                self.pruneHiddenAppsFromAppList()
                if loadPersistedOrder {
                    self.rebuildItems()
                    self.loadAllOrder()
                } else {
                    self.items = self.filteredItemsRemovingHidden(from: sorted.map { .app($0) })
                    self.saveAllOrder()
                }
                self.refreshMissingPlaceholders()
                
                // Generate the cache once the scan finishes
                self.generateCacheAfterScan()
            }
        }
    }
    
    /// Requests an order-preserving scan through the single-flight coordinator.
    func scanApplicationsWithOrderPreservation() {
        requestApplicationReconciliation(reason: .explicit)
    }

    /// Smart app scan: keeps the existing order, appends new apps at the end,
    /// removes missing apps, and auto-fills gaps within each page.
    private func performApplicationReconciliation(reasons: Set<ApplicationReconciliationReason>) {
        let searchPaths = applicationSearchPaths
        let previousApps = apps
        let normalizedCustomSources = customAppSourcePaths.compactMap(normalizeApplicationPath)
        let normalizedCustomSourceSet = Set(normalizedCustomSources)
        let fileManager = FileManager.default
        let unavailableCustomSources = normalizedCustomSources.filter { source in
            var isDirectory: ObjCBool = false
            return !fileManager.fileExists(atPath: source, isDirectory: &isDirectory)
                || !isDirectory.boolValue
                || !fileManager.isReadableFile(atPath: source)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var found: [AppInfo] = []
            var seenPaths = Set<String>()
            var scanFailed = false
            var sourceBecameUnavailable = false

            // Use a concurrent queue to speed up the scan
            let scanQueue = DispatchQueue(label: "app.scan", attributes: .concurrent)
            let group = DispatchGroup()
            let lock = NSLock()
            
            // Scan every application
            for path in searchPaths {
                group.enter()
                scanQueue.async {
                    defer { group.leave() }
                    let url = URL(fileURLWithPath: path)
                    var localScanFailed = false
                    var localFound: [AppInfo] = []
                    var localSeenPaths = Set<String>()

                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                        errorHandler: { _, _ in
                            localScanFailed = true
                            return false
                        }
                    ) else {
                        lock.withLock {
                            scanFailed = true
                        }
                        return
                    }

                    for case let item as URL in enumerator {
                        let resolved = item.resolvingSymlinksInPath()
                        guard resolved.pathExtension == "app",
                              self.isValidApp(at: resolved),
                              !self.isInsideAnotherApp(resolved) else { continue }
                        if !localSeenPaths.contains(resolved.path) {
                            localSeenPaths.insert(resolved.path)
                            localFound.append(self.appInfo(from: resolved))
                        }
                    }

                    var isDirectory: ObjCBool = false
                    let sourceStillAvailable = FileManager.default.fileExists(
                        atPath: path,
                        isDirectory: &isDirectory
                    ) && isDirectory.boolValue && FileManager.default.isReadableFile(atPath: path)

                    lock.withLock {
                        if localScanFailed || !sourceStillAvailable {
                            scanFailed = true
                            if !sourceStillAvailable && normalizedCustomSourceSet.contains(path) {
                                sourceBecameUnavailable = true
                            }
                        } else {
                            // Only complete source results are allowed into the
                            // aggregate. Partial enumeration must never authorize
                            // removals from the persisted layout.
                            found.append(contentsOf: localFound)
                            seenPaths.formUnion(localSeenPaths)
                        }
                    }
                }
            }
            
            group.wait()

            guard !scanFailed else {
                DispatchQueue.main.async {
                    self.finishApplicationReconciliation(reasons: reasons, succeeded: false)
                    if sourceBecameUnavailable {
                        self.requestApplicationReconciliation(reason: .sourceChange)
                    }
                }
                return
            }
            
            // De-dupe and sort - use a safer approach
            var uniqueApps: [AppInfo] = []
            var uniqueSeenPaths = Set<String>()
            
            for app in found {
                if !uniqueSeenPaths.contains(app.url.path) {
                    uniqueSeenPaths.insert(app.url.path)
                    uniqueApps.append(app)
                }
            }
            
            // Keep the existing apps' order, only sort newly added apps by name
            var newApps: [AppInfo] = []
            var existingAppPaths = Set<String>()
            let refreshedMap = Dictionary(uniqueKeysWithValues: uniqueApps.map { ($0.url.path, $0) })

            for app in previousApps {
                guard let refreshed = refreshedMap[app.url.path] else { continue }
                newApps.append(refreshed)
                existingAppPaths.insert(app.url.path)
            }

            let newAppPaths = uniqueApps.filter { !existingAppPaths.contains($0.url.path) }
            let sortedNewApps = newAppPaths.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            newApps.append(contentsOf: sortedNewApps)
            
            DispatchQueue.main.async {
                let didApplyChanges = self.processScannedApplications(
                    newApps,
                    unavailableCustomSources: unavailableCustomSources,
                    reasons: reasons
                )
                if didApplyChanges {
                    self.generateCacheAfterScan()
                }
                self.finishApplicationReconciliation(reasons: reasons, succeeded: true)
            }
        }
    }
    
    /// Manually triggers a full rescan (used by the manual refresh in Settings)
    func forceFullRescan() {
        hasPerformedInitialScan = true
        requestApplicationReconciliation(reason: .manual)
    }
    
    /// Processes scanned apps, smartly matching them against the existing order
    @discardableResult
    private func processScannedApplications(
        _ newApps: [AppInfo],
        unavailableCustomSources: [String],
        reasons: Set<ApplicationReconciliationReason>
    ) -> Bool {
        // Save the current items' order and structure
        let currentItems = self.items

        func isUnderUnavailableCustomSource(_ rawPath: String) -> Bool {
            let path = standardizedFilePath(rawPath)
            return unavailableCustomSources.contains { source in
                path == source || path.hasPrefix(source.hasSuffix("/") ? source : source + "/")
            }
        }

        func inventoryPaths(apps: [AppInfo], folders: [FolderInfo]) -> Set<String> {
            var paths = Set(apps.map { standardizedFilePath($0.url.path) })
            for folder in folders {
                paths.formUnion(folder.apps.map { standardizedFilePath($0.url.path) })
            }
            return paths
        }

        let previousInventoryPaths = inventoryPaths(apps: apps, folders: folders)
        
        // Build the new apps list, but keep the existing order
        var updatedApps: [AppInfo] = []
        var newAppsToAdd: [AppInfo] = []
        var freshMap: [String: AppInfo] = [:]
        for app in newApps {
            freshMap[app.url.path] = app
        }

        // Step 1: keep the existing order while refreshing app info from the latest scan results
        for app in self.apps {
            if let refreshed = freshMap[app.url.path] {
                updatedApps.append(refreshed)
            } else if isUnderUnavailableCustomSource(app.url.path) {
                updatedApps.append(app)
            }
        }

        // Sync-update the app objects inside folders too, so names/icons refresh promptly
        let reconciledFolders = folders.map { folder -> FolderInfo in
            var updatedFolder = folder
            updatedFolder.apps = folder.apps.compactMap { app in
                if let refreshed = freshMap[app.url.path] {
                    return refreshed
                }
                return isUnderUnavailableCustomSource(app.url.path) ? app : nil
            }
            return folderWithValidQuickLaunchPins(updatedFolder)
        }
        
        // Step 2: find the newly added apps (keeping the scan result's order)
        let existingPaths = Set(updatedApps.map { $0.url.path })
        for newApp in newApps where !existingPaths.contains(newApp.url.path) {
            newAppsToAdd.append(newApp)
        }

        // Step 3: append the newly added apps at the end, leaving the existing apps' order untouched
        updatedApps.append(contentsOf: newAppsToAdd)

        let nextInventoryPaths = inventoryPaths(apps: updatedApps, folders: reconciledFolders)
        let inventoryChanged = previousInventoryPaths != nextInventoryPaths
        let requiresMetadataRefresh = !reasons.isDisjoint(with: [
            .initial,
            .fileSystemEvent,
            .manual,
            .sourceChange,
            .explicit
        ])
        guard inventoryChanged || requiresMetadataRefresh else {
            return false
        }

        // Update the apps list
        self.apps = updatedApps
        pruneHiddenAppsFromAppList()
        self.folders = sanitizedFolders(reconciledFolders)

        // Step 4: smartly rebuild the items list, preserving the user's order
        self.smartRebuildItemsWithOrderPreservation(currentItems: currentItems, newApps: newAppsToAdd)

        // Step 5: auto-fill gaps within each page
        self.compactItemsWithinPages()

        // Step 5.5: sync missing placeholders against the latest on-disk state
        self.refreshMissingPlaceholders()

        // Step 6: save the new order
        self.saveAllOrder()

        // Trigger a UI refresh
        self.triggerFolderUpdate()
        self.triggerGridRefresh()
        return true
    }
    
    /// A rebuild method that strictly preserves the existing order
    private func rebuildItemsWithStrictOrderPreservation(currentItems: [LaunchpadItem]) {
        
        var newItems: [LaunchpadItem] = []
        let appsInFolders = Set(self.folders.flatMap { $0.apps })
        
        // Strictly preserve the existing items' order and position
        for (_, item) in currentItems.enumerated() {
            switch item {
            case .folder(let folder):
                // Check whether the folder still exists
                if self.folders.contains(where: { $0.id == folder.id }) {
                    // Update the folder reference, keeping its original position
                    if let updatedFolder = self.folders.first(where: { $0.id == folder.id }) {
                        newItems.append(.folder(updatedFolder))
                    } else {
                        // Folder was deleted, keep the slot empty
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // Folder was deleted, keep the slot empty
                    newItems.append(.empty(UUID().uuidString))
                }

            case .app(let app):
                let standardizedPath = standardizedFilePath(app.url.path)
                // Check whether the app still exists
                if self.apps.contains(where: { standardizedFilePath($0.url.path) == standardizedPath }) {
                    if !appsInFolders.contains(app) {
                        // App still exists and isn't in a folder, keep its original position
                        newItems.append(.app(app))
                    } else {
                        // App is now inside a folder, keep the slot empty
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // App is missing: turn it into a placeholder
                    if let placeholder = updateMissingPlaceholder(path: standardizedPath, displayName: app.name) {
                        newItems.append(.missingApp(placeholder))
                    } else {
                        newItems.append(.empty(UUID().uuidString))
                    }
                }
            case .missingApp(let placeholder):
                if let item = currentMissingAppItem(for: placeholder) {
                    newItems.append(item)
                } else {
                    newItems.append(.empty(UUID().uuidString))
                }
            case .empty(let token):
                // Keep the slot empty, preserving the page layout
                newItems.append(.empty(token))
            }
        }

        // Append newly added free apps (not in any folder) to the end of the last page
        let existingAppPaths = Set(newItems.compactMap { item -> String? in
            switch item {
            case .app(let app):
                return standardizedFilePath(app.url.path)
            case .missingApp(let placeholder):
                return standardizedFilePath(placeholder.bundlePath)
            default:
                return nil
            }
        })
        
        let newFreeApps = self.apps.filter { app in
            !appsInFolders.contains(app) && !existingAppPaths.contains(standardizedFilePath(app.url.path))
        }
        
        if !newFreeApps.isEmpty {
            var pendingApps = newFreeApps
            let itemsPerPage = self.itemsPerPage

            if newItems.count > 0 {
                let lastPageStart = ((newItems.count - 1) / itemsPerPage) * itemsPerPage
                let lastPageIndices = Array(lastPageStart..<newItems.count)
                let emptyIndices = lastPageIndices.filter { index in
                    if case .empty = newItems[index] { return true }
                    return false
                }
                let fillCount = min(pendingApps.count, emptyIndices.count)
                for i in 0..<fillCount {
                    newItems[emptyIndices[i]] = .app(pendingApps.removeFirst())
                }
            }

            if !pendingApps.isEmpty {
                let remainder = newItems.count % itemsPerPage
                if remainder != 0 {
                    let fillCount = min(itemsPerPage - remainder, pendingApps.count)
                    for _ in 0..<fillCount {
                        newItems.append(.app(pendingApps.removeFirst()))
                    }
                }

                while !pendingApps.isEmpty {
                    for _ in 0..<itemsPerPage {
                        if pendingApps.isEmpty {
                            newItems.append(.empty(UUID().uuidString))
                        } else {
                            newItems.append(.app(pendingApps.removeFirst()))
                        }
                    }
                }
            }
        }

        self.items = filteredItemsRemovingHidden(from: newItems)
    }
    
    /// Smartly rebuilds the items list, preserving the user's order
    private func smartRebuildItemsWithOrderPreservation(currentItems: [LaunchpadItem], newApps: [AppInfo]) {

        // Check for persisted data, but don't load it yet (that would overwrite the existing order)
        let hasPersistedData = self.hasPersistedOrderData()

        if hasPersistedData {

            // Smartly merge the existing order with the persisted data
            self.mergeCurrentOrderWithPersistedData(currentItems: currentItems, newApps: newApps, loadPersistedFolders: true)
        } else {

            // No persisted data: merge directly based on the current order
            self.mergeCurrentOrderWithPersistedData(currentItems: currentItems, newApps: newApps, loadPersistedFolders: false)
        }

    }

    /// Checks whether persisted data exists
    private func hasPersistedOrderData() -> Bool {
        guard let modelContext = self.modelContext else { return false }
        
        do {
            let pageEntries = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            let topItems = try modelContext.fetch(FetchDescriptor<TopItemData>())
            return !pageEntries.isEmpty || !topItems.isEmpty
        } catch {
            return false
        }
    }
    
    /// Smartly merges the existing order with the persisted data
    private func mergeCurrentOrderWithPersistedData(currentItems: [LaunchpadItem], newApps: [AppInfo], loadPersistedFolders: Bool = true) {

        // Save the current items' order
        let currentOrder = currentItems

        // Load the persisted data, but only update folder info
        if loadPersistedFolders {
            self.loadFoldersFromPersistedData()
        }

        // Rebuild the items list, strictly preserving the existing order
        var newItems: [LaunchpadItem] = []
        let appsInFolders = Set(self.folders.flatMap { $0.apps })
        let refreshedAppsByPath = Dictionary(uniqueKeysWithValues: self.apps.map { ($0.url.path, $0) })

        // Step 1: process the existing items, preserving order
        for (_, item) in currentOrder.enumerated() {
            switch item {
            case .folder(let folder):
                // Check whether the folder still exists
                if self.folders.contains(where: { $0.id == folder.id }) {
                    // Update the folder reference, keeping its original position
                    if let updatedFolder = self.folders.first(where: { $0.id == folder.id }) {
                        newItems.append(.folder(updatedFolder))
                    } else {
                        // Folder was deleted, keep the slot empty
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // Folder was deleted, keep the slot empty
                    newItems.append(.empty(UUID().uuidString))
                }

            case .app(let app):
                let standardizedPath = standardizedFilePath(app.url.path)
                // Check whether the app still exists
                if self.apps.contains(where: { standardizedFilePath($0.url.path) == standardizedPath }) {
                    if !appsInFolders.contains(app) {
                        // App still exists and isn't in a folder, refresh it with the latest info
                        let updatedApp = refreshedAppsByPath[app.url.path] ?? app
                        newItems.append(.app(updatedApp))
                    } else {
                        // App is now inside a folder, keep the slot empty
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // App is missing: turn it into a placeholder
                    if let placeholder = updateMissingPlaceholder(path: standardizedPath, displayName: app.name) {
                        newItems.append(.missingApp(placeholder))
                    } else {
                        newItems.append(.empty(UUID().uuidString))
                    }
                }
            case .missingApp(let placeholder):
                if let item = currentMissingAppItem(for: placeholder) {
                    newItems.append(item)
                } else {
                    newItems.append(.empty(UUID().uuidString))
                }
            case .empty(let token):
                // Keep the slot empty, preserving the page layout
                newItems.append(.empty(token))
            }
        }

        // Step 2: append newly added free apps (not in any folder) to the end of the last page
        let existingAppPaths = Set(newItems.compactMap { item -> String? in
            switch item {
            case .app(let app):
                return standardizedFilePath(app.url.path)
            case .missingApp(let placeholder):
                return standardizedFilePath(placeholder.bundlePath)
            default:
                return nil
            }
        })

        let newFreeApps = self.apps.filter { app in
            !appsInFolders.contains(app) && !existingAppPaths.contains(standardizedFilePath(app.url.path))
        }
        
        if !newFreeApps.isEmpty {
            var pendingApps = newFreeApps
            let itemsPerPage = self.itemsPerPage

            if newItems.count > 0 {
                let lastPageStart = ((newItems.count - 1) / itemsPerPage) * itemsPerPage
                let lastPageIndices = Array(lastPageStart..<newItems.count)
                let emptyIndices = lastPageIndices.filter { index in
                    if case .empty = newItems[index] { return true }
                    return false
                }
                let fillCount = min(pendingApps.count, emptyIndices.count)
                for i in 0..<fillCount {
                    newItems[emptyIndices[i]] = .app(pendingApps.removeFirst())
                }
            }

            if !pendingApps.isEmpty {
                let remainder = newItems.count % itemsPerPage
                if remainder != 0 {
                    let fillCount = min(itemsPerPage - remainder, pendingApps.count)
                    for _ in 0..<fillCount {
                        newItems.append(.app(pendingApps.removeFirst()))
                    }
                }

                while !pendingApps.isEmpty {
                    for _ in 0..<itemsPerPage {
                        if pendingApps.isEmpty {
                            newItems.append(.empty(UUID().uuidString))
                        } else {
                            newItems.append(.app(pendingApps.removeFirst()))
                        }
                    }
                }
            }
        }
        
        self.items = filteredItemsRemovingHidden(from: newItems)

    }
    
    /// Loads only folder info, without rebuilding the items order
    private func loadFoldersFromPersistedData() {
        guard let modelContext = self.modelContext else { return }

        do {
            // Try reading folder info from the newer "page-slot" model
            let saved = try modelContext.fetch(FetchDescriptor<PageEntryData>(
                sortBy: [SortDescriptor(\.pageIndex, order: .forward), SortDescriptor(\.position, order: .forward)]
            ))
            
            if !saved.isEmpty {
                // Build the folders
                var folderMap: [String: FolderInfo] = [:]
                var foldersInOrder: [FolderInfo] = []

                for row in saved where row.kind == "folder" {
                    guard let fid = row.folderId else { continue }
                    if folderMap[fid] != nil { continue }
                    
                    let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                        if let existing = apps.first(where: { $0.url.path == path }) {
                            return existing
                        }
                        let url = URL(fileURLWithPath: path)
                        if FileManager.default.fileExists(atPath: url.path) {
                            return self.appInfo(from: url)
                        }
                        return self.placeholderAppInfo(forMissingPath: path)
                    }
                    
                    let folder = folderWithValidQuickLaunchPins(FolderInfo(
                        id: fid,
                        name: row.folderName ?? "Untitled",
                        apps: folderApps,
                        pinnedAppPaths: row.pinnedAppPaths,
                        createdAt: row.createdAt
                    ))
                    folderMap[fid] = folder
                    foldersInOrder.append(folder)
                }
                
                self.folders = self.sanitizedFolders(foldersInOrder)
            }
        } catch {
        }
    }

    // MARK: - AI Overlay Preview
    //
    // func presentAIOverlayPreview() {
    //     // guard isAIEnabled else { return }
    //     // DispatchQueue.main.async { [weak self] in
    //     //     guard let self else { return }
    //     //     AIOverlayController.shared.show(with: self)
    //     // }
    // }
    //
    // func dismissAIOverlayPreview() {
    //     // DispatchQueue.main.async {
    //     //     AIOverlayController.shared.hide()
    //     // }
    // }
    //
    // func toggleAIOverlayPreview() {
    //     // guard isAIEnabled else {
    //     //     AIOverlayController.shared.hide()
    //     //     return
    //     // }
    //     // DispatchQueue.main.async { [weak self] in
    //     //     guard let self else { return }
    //     //     AIOverlayController.shared.toggle(with: self)
    //     // }
    // }

    func orderedFolderQuickLaunchApps(in folder: FolderInfo) -> [AppInfo] {
        let resolvedFolder = folders.first(where: { $0.id == folder.id }) ?? folder
        let normalizedFolder = folderWithValidQuickLaunchPins(resolvedFolder)
        let pinnedPaths = Set(normalizedFolder.pinnedAppPaths)
        let pinnedApps = normalizedFolder.apps.filter {
            pinnedPaths.contains(standardizedFilePath($0.url.path))
        }
        let unpinnedApps = normalizedFolder.apps.filter {
            !pinnedPaths.contains(standardizedFilePath($0.url.path))
        }
        return pinnedApps + unpinnedApps
    }

    func isFolderQuickLaunchAppPinned(_ app: AppInfo, inFolderID folderID: String) -> Bool {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return false }
        let path = standardizedFilePath(app.url.path)
        return folder.pinnedAppPaths.contains(path)
    }

    @discardableResult
    func setFolderQuickLaunchAppPinned(_ pinned: Bool, app: AppInfo, inFolderID folderID: String) -> Bool {
        guard folderQuickLaunchEnabled,
              let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return false }

        var updatedFolder = folderWithValidQuickLaunchPins(folders[folderIndex])
        let appPath = standardizedFilePath(app.url.path)
        guard updatedFolder.apps.contains(where: { standardizedFilePath($0.url.path) == appPath }) else {
            return false
        }

        var pinnedPaths = Set(updatedFolder.pinnedAppPaths)
        let changed: Bool
        if pinned {
            changed = pinnedPaths.insert(appPath).inserted
        } else {
            changed = pinnedPaths.remove(appPath) != nil
        }
        guard changed else { return false }

        updatedFolder.pinnedAppPaths = Array(pinnedPaths)
        updatedFolder = folderWithValidQuickLaunchPins(updatedFolder)
        folders[folderIndex] = updatedFolder

        for index in items.indices {
            if case .folder(let folder) = items[index], folder.id == folderID {
                items[index] = .folder(updatedFolder)
            }
        }
        if openFolder?.id == folderID {
            openFolder = updatedFolder
        }

        triggerFolderUpdate()
        triggerGridRefresh()
        saveAllOrder()
        return true
    }

    private func folderWithValidQuickLaunchPins(_ folder: FolderInfo) -> FolderInfo {
        let requestedPaths = Set(folder.pinnedAppPaths.map(standardizedFilePath))
        let validPaths = folder.apps.compactMap { app -> String? in
            let path = standardizedFilePath(app.url.path)
            return requestedPaths.contains(path) ? path : nil
        }
        guard validPaths != folder.pinnedAppPaths else { return folder }
        var copy = folder
        copy.pinnedAppPaths = validPaths
        return copy
    }

    @discardableResult
    private func reconcileFolderQuickLaunchPinsInCurrentLayout() -> Bool {
        var normalizedByID: [String: FolderInfo] = [:]
        normalizedByID.reserveCapacity(folders.count)
        var didChange = false

        for index in folders.indices {
            let normalized = folderWithValidQuickLaunchPins(folders[index])
            if normalized.pinnedAppPaths != folders[index].pinnedAppPaths {
                folders[index] = normalized
                didChange = true
            }
            normalizedByID[normalized.id] = normalized
        }

        guard didChange else { return false }
        for index in items.indices {
            if case .folder(let folder) = items[index], let normalized = normalizedByID[folder.id] {
                items[index] = .folder(normalized)
            }
        }
        if let openFolder, let normalized = normalizedByID[openFolder.id] {
            self.openFolder = normalized
        }
        return true
    }

    deinit {
        applicationReconciliationWorkItem?.cancel()
        stopAutoRescan()
        let center = NSWorkspace.shared.notificationCenter
        volumeObservers.forEach { center.removeObserver($0) }
    }

    // MARK: - FSEvents wiring
    func startAutoRescan() {
        guard fsEventStream == nil else { return }

        let pathsToWatch = applicationSearchPaths
        guard !pathsToWatch.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, eventFlags, _) in
            guard let info = clientInfo else { return }
            let appStore = Unmanaged<AppStore>.fromOpaque(info).takeUnretainedValue()

            guard numEvents > 0 else {
                appStore.handleFSEvents(paths: [], flagsPointer: eventFlags, count: 0)
                return
            }

            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFString
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let nsArray = cfArray as NSArray
            guard let pathsArray = nsArray as? [String] else { return }

            appStore.handleFSEvents(paths: pathsArray, flagsPointer: eventFlags, count: numEvents)
        }

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        let latency: CFTimeInterval = 0.0

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        fsEventStream = stream
        FSEventStreamSetDispatchQueue(stream, fsEventsQueue)
        FSEventStreamStart(stream)
    }

    func stopAutoRescan() {
        guard let stream = fsEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsEventStream = nil
    }

    func restartAutoRescan() {
        stopAutoRescan()
        startAutoRescan()
    }

    @discardableResult
    func addCustomAppSource(path: String) -> Bool {
        guard let normalized = normalizeApplicationPath(path) else { return false }
        if customAppSourcePaths.contains(where: { normalizeApplicationPath($0) == normalized }) { return false }
        customAppSourcePaths.append(normalized)
        return true
    }

    func removeCustomAppSource(at index: Int) {
        guard customAppSourcePaths.indices.contains(index) else { return }
        let removed = customAppSourcePaths[index]
        purgeMissingPlaceholders(forRemovedSources: [removed])
        customAppSourcePaths.remove(at: index)
    }

    func removeCustomAppSources(at offsets: IndexSet) {
        let removed = offsets.compactMap { offset -> String? in
            guard customAppSourcePaths.indices.contains(offset) else { return nil }
            return customAppSourcePaths[offset]
        }
        purgeMissingPlaceholders(forRemovedSources: removed)
        customAppSourcePaths.remove(atOffsets: offsets)
    }

    func resetCustomAppSources() {
        guard !customAppSourcePaths.isEmpty else { return }
        let removed = customAppSourcePaths
        purgeMissingPlaceholders(forRemovedSources: removed)
        customAppSourcePaths.removeAll()
    }

    func removeCustomAppSource(path: String) {
        guard let normalized = normalizeApplicationPath(path) else { return }
        if let index = customAppSourcePaths.firstIndex(where: { normalizeApplicationPath($0) == normalized }) {
            let removed = customAppSourcePaths[index]
            purgeMissingPlaceholders(forRemovedSources: [removed])
            customAppSourcePaths.remove(at: index)
        }
    }

    private func setupVolumeObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let mountObserver = center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self.handleVolumeEvent(at: url, isMount: true)
        }

        let unmountObserver = center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self.handleVolumeEvent(at: url, isMount: false)
        }

        volumeObservers = [mountObserver, unmountObserver]
    }

    private func handleVolumeEvent(at url: URL, isMount: Bool) {
        let volumePath = url.standardizedFileURL.path
        guard !volumePath.isEmpty else { return }

        let relevant = customAppSourcePaths.contains { source in
            guard let normalized = normalizeApplicationPath(source) else { return false }
            return normalized.hasPrefix(volumePath)
        }

        guard relevant else { return }

        let delay: TimeInterval = isMount ? 1.0 : 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.restartAutoRescan()
            self.requestApplicationReconciliation(reason: .sourceChange)
        }
    }

    private func handleFSEvents(paths: [String], flagsPointer: UnsafePointer<FSEventStreamEventFlags>?, count: Int) {
        let maxCount = min(paths.count, count)
        var shouldReconcile = false
        
        for i in 0..<maxCount {
            let flags = flagsPointer?[i] ?? 0

            let created = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
            let removed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
            let renamed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0
            let modified = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
            let mustRescan = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)) != 0
                || (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)) != 0
                || (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)) != 0
                || (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)) != 0
                || (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)) != 0

            if created || removed || renamed || modified || mustRescan {
                shouldReconcile = true
                break
            }
        }

        guard shouldReconcile else { return }
        DispatchQueue.main.async { [weak self] in
            self?.requestApplicationReconciliation(
                reason: .fileSystemEvent,
                debounce: Self.applicationReconciliationEventDebounce
            )
        }
    }

    private func isInsideAnotherApp(_ url: URL) -> Bool {
        let appCount = url.pathComponents.filter { $0.hasSuffix(".app") }.count
        return appCount > 1
    }

    private func isValidApp(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) &&
        NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    private func appInfo(from url: URL, preferredName: String? = nil) -> AppInfo {
        AppInfo.from(url: url,
                     preferredName: preferredName,
                     customTitle: customTitles[url.path],
                     loadIcon: false)
    }
    
    // MARK: - Folder management
    func createFolder(with apps: [AppInfo], name: String = "Untitled") -> FolderInfo {
        return createFolder(with: apps, name: name, insertAt: nil)
    }

    func createFolder(with apps: [AppInfo], name: String = "Untitled", insertAt insertIndex: Int?) -> FolderInfo {
        let folder = FolderInfo(name: name, apps: apps)
        folders.append(folder)

        // Remove the apps that were added to the folder from the top-level apps list
        for app in apps {
            if let index = self.apps.firstIndex(of: app) {
                self.apps.remove(at: index)
            }
        }

        // In the current items: replace these apps' top-level entries with empty slots, and place the folder at the target position, keeping the total length unchanged
        var newItems = self.items
        // Find these apps' positions
        var placeholders: [(Int, AppInfo)] = []
        var remainingApps = apps
        for (idx, item) in newItems.enumerated() {
            guard !remainingApps.isEmpty else { break }
            if case let .app(a) = item, let matchIndex = remainingApps.firstIndex(of: a) {
                let match = remainingApps.remove(at: matchIndex)
                placeholders.append((idx, match))
            }
        }
        // Empty out the affected app slots first
        for (idx, _) in placeholders {
            newItems[idx] = .empty(UUID().uuidString)
        }
        // Pick where to place the folder: prefer insertIndex, otherwise the smallest index; clamp the range and replace rather than insert
        let baseIndex = placeholders.map { $0.0 }.min() ?? min(newItems.count - 1, max(0, insertIndex ?? (newItems.count - 1)))
        let desiredIndex = insertIndex ?? baseIndex
        let safeIndex = min(max(0, desiredIndex), max(0, newItems.count - 1))
        if newItems.isEmpty {
            newItems = [.folder(folder)]
        } else {
            newItems[safeIndex] = .folder(folder)
        }
        self.items = filteredItemsRemovingHidden(from: newItems)
        // Auto-fill within the page: move that page's empty slots to the end
        compactItemsWithinPages()
        removeEmptyPages()

        // Trigger a folder update, notifying every relevant view to refresh its icon
        DispatchQueue.main.async { [weak self] in
            self?.triggerFolderUpdate()
        }

        // Trigger a grid view refresh, so the UI updates right away
        triggerGridRefresh()

        // Refresh the cache, so search can find the apps inside the newly created folder
        refreshCacheAfterFolderOperation()

        saveAllOrder()
        return folder
    }

    func addAppToFolder(_ app: AppInfo, folder: FolderInfo) {
        guard let folderIndex = folders.firstIndex(of: folder) else { return }


        // Create a new FolderInfo instance so SwiftUI can detect the change
        var updatedFolder = folders[folderIndex]
        updatedFolder.apps.append(app)
        folders[folderIndex] = updatedFolder


        // Remove it from the apps list
        if let appIndex = apps.firstIndex(of: app) {
            apps.remove(at: appIndex)
        }

        // Set that app's top-level slot to empty (keeps pages independent)
        if let pos = items.firstIndex(of: .app(app)) {
            items[pos] = .empty(UUID().uuidString)
            // Auto-fill within the page
            compactItemsWithinPages()
            removeEmptyPages()
        } else {
            // Fall back to a full rebuild if it wasn't found
            rebuildItems()
        }

        // Make sure the matching folder entry in items is also updated to the latest content, so it's visible to search right away
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == updatedFolder.id {
                items[idx] = .folder(updatedFolder)
            }
        }

        // Trigger a folder update right away, notifying every relevant view to refresh its icon and name
        triggerFolderUpdate()

        // Trigger a grid view refresh, so the UI updates right away
        triggerGridRefresh()

        // Refresh the cache, so search can find the newly added app
        refreshCacheAfterFolderOperation()

        saveAllOrder()
    }

    func removeAppFromFolder(_ app: AppInfo, folder: FolderInfo) {
        guard let folderIndex = folders.firstIndex(of: folder) else { return }


        // Create a new FolderInfo instance so SwiftUI can detect the change
        var updatedFolder = folders[folderIndex]
        updatedFolder.apps.removeAll { $0 == app }
        updatedFolder = folderWithValidQuickLaunchPins(updatedFolder)


        // If the folder is now empty, delete it
        if updatedFolder.apps.isEmpty {
            folders.remove(at: folderIndex)
        } else {
            // Update the folder
            folders[folderIndex] = updatedFolder
        }

        // Sync-update that folder's entry in items too, so the UI stops referencing the old folder contents
        var emptiedSlots: [Int] = []
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == folder.id {
                if updatedFolder.apps.isEmpty {
                    // The folder is now empty and was deleted, so mark that position as an empty slot pending fill-in
                    items[idx] = .empty(UUID().uuidString)
                    emptiedSlots.append(idx)
                } else {
                    items[idx] = .folder(updatedFolder)
                }
            }
        }

        // Add the app back to the apps list (update it in place if it already exists, to avoid duplicates)
        if let existingIndex = apps.firstIndex(where: { $0.url == app.url }) {
            apps[existingIndex] = app
        } else {
            apps.append(app)
        }
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Prefer the slot we just emptied, then look for any other empty slot, and only append a new one as a last resort
        var targetSlot: Int? = nil
        if let firstEmptied = emptiedSlots.first, firstEmptied < items.count {
            targetSlot = firstEmptied
        } else {
            targetSlot = items.firstIndex {
                if case .empty = $0 { return true }
                return false
            }
        }
        if let slot = targetSlot {
            items[slot] = .app(app)
        } else {
            items.append(.app(app))
        }

        // Trigger a folder update right away, notifying every relevant view to refresh its icon and name
        triggerFolderUpdate()

        // Only compact empty slots within the page
        compactItemsWithinPages()
        removeEmptyPages()

        // Trigger a grid view refresh, so the UI updates right away
        triggerGridRefresh()

        // Refresh the cache, so search can find the app that was removed from the folder (refresh after the rebuild)
        refreshCacheAfterFolderOperation()

        saveAllOrder()
    }

    func renameFolder(_ folder: FolderInfo, newName: String) {
        guard let index = folders.firstIndex(of: folder) else { return }


        // Create a new FolderInfo instance so SwiftUI can detect the change
        var updatedFolder = folders[index]
        updatedFolder.name = newName
        folders[index] = updatedFolder

        // Sync-update that folder's entry in items too, so the main grid stops showing the old name
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == updatedFolder.id {
                items[idx] = .folder(updatedFolder)
            }
        }


        // Trigger a folder update right away, notifying every relevant view to refresh
        triggerFolderUpdate()

        // Trigger a grid view refresh, so the UI updates right away
        triggerGridRefresh()

        // Refresh the cache, so search keeps working correctly
        refreshCacheAfterFolderOperation()
        
        rebuildItems()
        saveAllOrder()
    }

    @discardableResult
    func reorderAppInFolder(folderID: String, from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return false }
        var updatedFolder = folders[folderIndex]
        guard updatedFolder.apps.indices.contains(sourceIndex) else { return false }

        let movingApp = updatedFolder.apps.remove(at: sourceIndex)
        let clampedDestination = min(max(0, destinationIndex), updatedFolder.apps.count)
        updatedFolder.apps.insert(movingApp, at: clampedDestination)
        updatedFolder = folderWithValidQuickLaunchPins(updatedFolder)
        folders[folderIndex] = updatedFolder

        for idx in items.indices {
            if case .folder(let folder) = items[idx], folder.id == folderID {
                items[idx] = .folder(updatedFolder)
            }
        }

        if openFolder?.id == folderID {
            openFolder = updatedFolder
        }

        triggerFolderUpdate()
        triggerGridRefresh()
        refreshCacheAfterFolderOperation()
        saveAllOrder()
        return true
    }

    @discardableResult
    func showAppInFinder(_ app: AppInfo) -> Bool {
        guard FileManager.default.fileExists(atPath: app.url.path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
        return true
    }

    @discardableResult
    func copyAppPath(_ app: AppInfo) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(app.url.path, forType: .string)
    }

    @MainActor
    func requestQuarantineRemovalInTerminal(for app: AppInfo) {
        let targetURL: URL
        do {
            targetURL = try QuarantineRemovalTerminalLauncher.validatedAppURL(for: app.url)
        } catch {
            presentQuarantineRemovalError(.invalidTarget)
            return
        }

        let command = QuarantineRemovalTerminalLauncher.command(for: targetURL)
        let alert = NSAlert()
        alert.messageText = localized(.quarantineRemovalConfirmationTitle)
        alert.informativeText = [
            app.name,
            targetURL.path,
            command,
            localized(.quarantineRemovalConfirmationWarning)
        ].joined(separator: "\n\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized(.quarantineRemovalOpenTerminalButton))
        alert.addButton(withTitle: localized(.cancel))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let confirmedTargetURL: URL
        do {
            confirmedTargetURL = try QuarantineRemovalTerminalLauncher.validatedAppURL(for: app.url)
            guard confirmedTargetURL == targetURL else {
                presentQuarantineRemovalError(.invalidTarget)
                return
            }
        } catch {
            presentQuarantineRemovalError(.invalidTarget)
            return
        }

        let messages = QuarantineRemovalTerminalLauncher.Messages(
            targetLabel: localized(.quarantineTerminalTargetLabel),
            commandLabel: localized(.quarantineTerminalCommandLabel),
            success: localized(.quarantineTerminalSuccess),
            failure: localized(.quarantineTerminalFailure),
            exitStatusLabel: localized(.quarantineTerminalExitStatusLabel),
            pressReturn: localized(.quarantineTerminalPressReturn)
        )

        let launch: QuarantineRemovalTerminalLauncher.PreparedLaunch
        do {
            launch = try QuarantineRemovalTerminalLauncher.prepareLaunch(
                for: confirmedTargetURL,
                messages: messages
            )
        } catch let error as QuarantineRemovalTerminalLauncher.LaunchError {
            presentQuarantineRemovalError(error)
            return
        } catch {
            presentQuarantineRemovalError(.scriptCreationFailed)
            return
        }

        AppDelegate.shared?.hideWindow()
        QuarantineRemovalTerminalLauncher.open(launch) { [weak self] result in
            guard case .failure(let error) = result else { return }
            AppDelegate.shared?.showWindow()
            self?.presentQuarantineRemovalError(error)
        }
    }

    @MainActor
    private func presentQuarantineRemovalError(_ error: QuarantineRemovalTerminalLauncher.LaunchError) {
        let body: String
        switch error {
        case .invalidTarget:
            body = localized(.quarantineRemovalInvalidTargetError)
        case .scriptCreationFailed:
            body = localized(.quarantineRemovalScriptCreationError)
        case .terminalUnavailable, .terminalLaunchFailed:
            body = localized(.quarantineRemovalTerminalLaunchError)
        }

        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = localized(.quarantineRemovalErrorTitle)
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized(.okButton))
        alert.runModal()
    }

    func requestRenameFolder(_ folder: FolderInfo) {
        let folderID = folder.id
        let resolvedFolder: FolderInfo
        if let latest = folders.first(where: { $0.id == folderID }) {
            resolvedFolder = latest
        } else if let item = items.first(where: {
            if case .folder(let existing) = $0 { return existing.id == folderID }
            return false
        }), case .folder(let existing) = item {
            resolvedFolder = existing
        } else {
            resolvedFolder = folder
        }

        openFolderActivatedByKeyboard = false
        openFolder = resolvedFolder
        folderRenameRequestID = folderID
    }

    @discardableResult
    func dissolveFolder(_ folder: FolderInfo) -> Bool {
        let folderID = folder.id

        let resolvedFolder: FolderInfo
        if let index = folders.firstIndex(where: { $0.id == folderID }) {
            resolvedFolder = folders[index]
            folders.remove(at: index)
        } else if let itemIndex = items.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folderID }
            return false
        }), case .folder(let fallbackFolder) = items[itemIndex] {
            resolvedFolder = fallbackFolder
        } else {
            return false
        }

        NotificationCenter.default.post(name: .launchpadFolderWillDissolve, object: resolvedFolder)

        let folderApps = resolvedFolder.apps
        let folderAppPaths = Set(folderApps.map { standardizedFilePath($0.url.path) })
        var newItems = items

        // Remove stale duplicates first; the folder slot will be reused for the first restored app.
        if !folderAppPaths.isEmpty {
            for idx in newItems.indices {
                if case .app(let app) = newItems[idx],
                   folderAppPaths.contains(standardizedFilePath(app.url.path)) {
                    newItems[idx] = .empty(UUID().uuidString)
                }
            }
        }

        if let folderItemIndex = newItems.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folderID }
            return false
        }) {
            // Replace the folder itself before inserting the remaining members.
            // Leaving an empty slot here makes cascadeInsert count an extra cell
            // and spill a real icon even when the restored apps fit this page.
            newItems[folderItemIndex] = folderApps.first.map { .app($0) } ?? .empty(UUID().uuidString)
            var insertIndex = folderItemIndex + 1
            for app in folderApps.dropFirst() {
                newItems = cascadeInsert(into: newItems, item: .app(app), at: insertIndex)
                insertIndex += 1
            }
        } else if !folderApps.isEmpty {
            newItems.append(contentsOf: folderApps.map { .app($0) })
        }

        var existingTopLevelPaths = Set(apps.map { standardizedFilePath($0.url.path) })
        for app in folderApps {
            let normalized = standardizedFilePath(app.url.path)
            if !existingTopLevelPaths.contains(normalized) {
                apps.append(app)
                existingTopLevelPaths.insert(normalized)
            }
        }
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        pruneHiddenAppsFromAppList()

        items = filteredItemsRemovingHidden(from: newItems)
        if openFolder?.id == folderID {
            openFolder = nil
        }

        compactItemsWithinPages()
        removeEmptyPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        refreshCacheAfterFolderOperation()
        saveAllOrder()
        return true
    }
    
    // One-click layout reset: fully rescan apps, deleting all folders, ordering and empty fill-ins
    func resetLayout() {
        // Close any open folder
        openFolder = nil

        // Clear all folder and ordering data
        folders.removeAll()

        // Clear all persisted ordering data
        clearAllPersistedData()

        // Clear the cache
        cacheManager.clearAllCaches()

        // Reset the scan flag to force a rescan
        hasPerformedInitialScan = false

        // Clear the current items list
        items.removeAll()
        missingPlaceholders.removeAll()

        // Rescan apps without loading persisted data
        scanApplications(loadPersistedOrder: false)

        // Reset to the first page
        currentPage = 0

        // Trigger a folder update, notifying every relevant view to refresh
        triggerFolderUpdate()

        // Trigger a grid view refresh, so the UI updates right away
        triggerGridRefresh()

        // Refresh the cache once the scan finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshCacheAfterFolderOperation()
        }
    }

    func resetAppearanceSettings() {
        let defaults = UserDefaults.standard
        let keysToClear: [String] = [
            Self.sidebarIconPresetKey,
            "appearancePreference",
            Self.backgroundStyleKey,
            Self.backgroundImageEnabledKey,
            Self.backgroundImageSourceKey,
            Self.customBackgroundImagePathKey,
            Self.backgroundMaskEnabledKey,
            Self.backgroundMaskLightKey,
            Self.backgroundMaskDarkKey,
            "isFullscreenMode",
            "showLabels",
            Self.folderLiquidGlassKey,
            Self.folderPreviewHighResKey,
            Self.folderQuickLaunchEnabledKey,
            Self.folderLayoutModeKey,
            "hideDock",
            Self.hideMenuBarKey,
            "scrollSensitivity",
            Self.gridColumnsKey,
            Self.gridRowsKey,
            Self.columnSpacingKey,
            Self.rowSpacingKey,
            Self.folderColumnSpacingKey,
            Self.folderRowSpacingKey,
            "enableDropPrediction",
            Self.folderDropZoneScaleKey,
            "enableAnimations",
            Self.hoverMagnificationKey,
            Self.hoverMagnificationScaleKey,
            Self.activePressEffectKey,
            Self.reverseWheelPagingKey,
            Self.reverseWheelVerticalKey,
            Self.trackpadVerticalDirectionKey,
            Self.activePressScaleKey,
            "iconScale",
            "iconLabelFontSize",
            Self.iconLabelFontWeightKey,
            "animationDuration",
            Self.windowOpenAnimationKey,
            Self.windowShadowEnabledKey,
            Self.compactWindowMaxWidthKey,
            Self.compactWindowMaxHeightKey,
            Self.windowAnimationDurationKey,
            "useLocalizedThirdPartyTitles",
            "pageIndicatorOffset",
            Self.pageIndicatorTopPaddingKey,
            Self.pageIndicatorPerDisplayEnabledKey,
            Self.pageIndicatorPerDisplayOverridesKey,
            Self.dualModeAppearanceSettingsKey,
            Self.rememberPageKey,
            Self.rememberedPageIndexKey,
            "folderPopoverWidthFactor",
            "folderPopoverHeightFactor",
            "showFPSOverlay"
        ]

        keysToClear.forEach { defaults.removeObject(forKey: $0) }
        Self.writeDefaultAppearancePreferences(to: defaults)
        reloadAppearancePreferencesFromDefaults()

        clearIconCachesForLayoutChange()
        triggerFolderUpdate()
        triggerGridRefresh()
    }
    
    /// Auto-fills gaps within each page: moves that page's `.empty` slots to its end, preserving the relative order of non-empty items
    func compactItemsWithinPages() {
        guard !items.isEmpty else { return }
        items = filteredItemsRemovingHidden(from: compactedItemsWithinPages(items))
    }

    private func compactedItemsWithinPages(_ source: [LaunchpadItem]) -> [LaunchpadItem] {
        guard !source.isEmpty else { return source }
        let itemsPerPage = self.itemsPerPage // Use the computed property
        var result: [LaunchpadItem] = []
        result.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            let end = min(index + itemsPerPage, source.count)
            let pageSlice = Array(source[index..<end])
            var nonEmpty: [LaunchpadItem] = []
            var emptyTokens: [String] = []
            nonEmpty.reserveCapacity(pageSlice.count)
            emptyTokens.reserveCapacity(pageSlice.count)

            for item in pageSlice {
                switch item {
                case .empty(let token):
                    emptyTokens.append(token)
                default:
                    nonEmpty.append(item)
                }
            }

            // Add the non-empty items first, preserving their original order
            result.append(contentsOf: nonEmpty)

            // Then append the empty items at the end of the page
            if !emptyTokens.isEmpty {
                result.append(contentsOf: emptyTokens.map { .empty($0) })
            }

            index = end
        }
        return result
    }

    // MARK: - Cross-page drag: cascading insert (a full page pushes its last item into the next)
    func moveSelectedAppsAcrossPagesWithCascade(appPathsOrdered: [String], to targetIndex: Int) {
        guard !appPathsOrdered.isEmpty else { return }

        var seenPaths = Set<String>()
        let normalizedOrderedPaths: [String] = appPathsOrdered.compactMap { raw in
            let normalized = standardizedFilePath(raw)
            guard seenPaths.insert(normalized).inserted else { return nil }
            return normalized
        }
        guard !normalizedOrderedPaths.isEmpty else { return }
        let movingPathSet = Set(normalizedOrderedPaths)

        var movingItemsByPath: [String: LaunchpadItem] = [:]
        for item in items {
            guard case .app(let app) = item else { continue }
            let path = standardizedFilePath(app.url.path)
            if movingPathSet.contains(path), movingItemsByPath[path] == nil {
                movingItemsByPath[path] = .app(app)
            }
        }

        let orderedMovingItems = normalizedOrderedPaths.compactMap { movingItemsByPath[$0] }
        guard !orderedMovingItems.isEmpty else { return }

        var result = items
        let sourceIndexes = result.indices.filter { index in
            guard case .app(let app) = result[index] else { return false }
            return movingPathSet.contains(standardizedFilePath(app.url.path))
        }
        guard !sourceIndexes.isEmpty else { return }

        for index in sourceIndexes {
            result[index] = .empty(UUID().uuidString)
        }

        result = compactedItemsWithinPages(result)
        var insertionIndex = max(0, min(targetIndex, result.count))

        for movingItem in orderedMovingItems {
            result = cascadeInsert(into: result, item: movingItem, at: insertionIndex)
            insertionIndex += 1
        }

        items = filteredItemsRemovingHidden(from: result)
        compactItemsWithinPages()
        removeEmptyPages()
        triggerGridRefresh()
        saveAllOrder()
    }

    func reorderGridItem(from sourceIndex: Int, to targetIndex: Int) {
        guard itemsPerPage > 0 else { return }
        applyGridReorder(from: sourceIndex, to: targetIndex,
                         cascading: sourceIndex / itemsPerPage != targetIndex / itemsPerPage)
    }

    func moveItemAcrossPagesWithCascade(item: LaunchpadItem, to targetIndex: Int) {
        guard let source = items.firstIndex(of: item) else { return }
        applyGridReorder(from: source, to: targetIndex, cascading: true)
    }

    private func applyGridReorder(from source: Int, to target: Int, cascading: Bool) {
        let snapshot = items
        let occupied = snapshot.map { item in
            if case .empty = item { return false }
            return true
        }
        guard let plan = GridReorderPlan.make(occupied: occupied, from: source, to: target,
                                               itemsPerPage: itemsPerPage, cascading: cascading) else { return }
        let reordered = plan.slots.map { slot in
            slot.map { snapshot[$0] } ?? .empty(UUID().uuidString)
        }
        // Publish only the final arrangement. A delayed second compaction would
        // move the landing target after its animation had already started.
        items = filteredItemsRemovingHidden(from: reordered)
        clampCurrentPageWithinBounds()
        triggerGridRefresh()
        saveAllOrder()
    }

    private func cascadeInsert(into array: [LaunchpadItem], item: LaunchpadItem, at targetIndex: Int) -> [LaunchpadItem] {
        var result = array
        let p = self.itemsPerPage // Use the computed property

        // Pad the length out to a whole page, to make this easier to handle
        if result.count % p != 0 {
            let remain = p - (result.count % p)
            for _ in 0..<remain { result.append(.empty(UUID().uuidString)) }
        }

        var currentPage = max(0, targetIndex / p)
        var localIndex = max(0, min(targetIndex - currentPage * p, p - 1))
        var carry: LaunchpadItem? = item

        while let moving = carry {
            let pageStart = currentPage * p
            let pageEnd = pageStart + p
            if result.count < pageEnd {
                let need = pageEnd - result.count
                for _ in 0..<need { result.append(.empty(UUID().uuidString)) }
            }
            var slice = Array(result[pageStart..<pageEnd])
            
            // Make sure the insertion point is within a valid range
            let safeLocalIndex = max(0, min(localIndex, slice.count))
            slice.insert(moving, at: safeLocalIndex)

            var spilled: LaunchpadItem? = nil
            if slice.count > p {
                spilled = slice.removeLast()
            }
            result.replaceSubrange(pageStart..<pageEnd, with: slice)
            if let s = spilled, case .empty = s {
                // What spilled over was empty: done
                carry = nil
            } else if let s = spilled {
                // What spilled over was non-empty: push it to the start of the next page
                carry = s
                currentPage += 1
                localIndex = 0
                // Pad the next page if we've run past the end
                let nextEnd = (currentPage + 1) * p
                if result.count < nextEnd {
                    let need = nextEnd - result.count
                    for _ in 0..<need { result.append(.empty(UUID().uuidString)) }
                }
            } else {
                carry = nil
            }
        }
        return result
    }
    
    func rebuildItems() {
        // Add debouncing and an optimization check
        let currentItemsCount = items.count
        let appsInFolders: Set<AppInfo> = Set(folders.flatMap { $0.apps })
        let folderById: [String: FolderInfo] = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        var newItems: [LaunchpadItem] = []
        newItems.reserveCapacity(currentItemsCount + 10) // Pre-allocate capacity
        var seenAppPaths = Set<String>()
        var seenFolderIds = Set<String>()
        seenAppPaths.reserveCapacity(apps.count)
        seenFolderIds.reserveCapacity(folders.count)

        for item in items {
            switch item {
            case .folder(let folder):
                if let updated = folderById[folder.id] {
                    newItems.append(.folder(updated))
                    seenFolderIds.insert(updated.id)
                }
                // If that folder was deleted, skip it (don't keep it around)
            case .app(let app):
                // If the app has moved into a folder, remove it from the top level; otherwise keep its original position
                if !appsInFolders.contains(app) {
                    newItems.append(.app(app))
                    seenAppPaths.insert(standardizedFilePath(app.url.path))
                }
            case .missingApp(let placeholder):
                if let item = currentMissingAppItem(for: placeholder) {
                    newItems.append(item)
                    if case .missingApp(let current) = item {
                        seenAppPaths.insert(standardizedFilePath(current.bundlePath))
                    }
                } else {
                    newItems.append(.empty(UUID().uuidString))
                }
            case .empty(let token):
                // Keep empty as a placeholder, preserving each page's independence
                newItems.append(.empty(token))
            }
        }

        // Append any free apps that were missed (absent from the top level, but also not in any folder)
        let missingFreeApps = apps.filter {
            guard !appsInFolders.contains($0) else { return false }
            return !seenAppPaths.contains(standardizedFilePath($0.url.path))
        }
        newItems.append(contentsOf: missingFreeApps.map { .app($0) })

        // Note: don't auto-append missing folders at the end -- otherwise, after
        // loading the persisted order, an incremental update triggering a
        // rebuild could push a folder onto the last page.

        // Only update items if something actually changed
        if newItems.count != items.count || !newItems.elementsEqual(items, by: { $0.id == $1.id }) {
            items = filteredItemsRemovingHidden(from: newItems)
        }
    }
    
    // MARK: - Persistence: per-page independent ordering (new) + legacy compatibility
    func loadAllOrder() {
        guard let modelContext else {
            print("LaunchNG: ModelContext is nil, cannot load persisted order")
            return
        }
        
        print("LaunchNG: Attempting to load persisted order data...")
        
        // Prefer reading from the newer "page-slot" model
        if loadOrderFromPageEntries(using: modelContext) {
            print("LaunchNG: Successfully loaded order from PageEntryData")
            return
        }
        
        print("LaunchNG: PageEntryData not found, trying legacy TopItemData...")
        // Fallback: the legacy global-order model
        loadOrderFromLegacyTopItems(using: modelContext)
        print("LaunchNG: Finished loading order from legacy data")
    }

    private func loadOrderFromPageEntries(using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<PageEntryData>(
                sortBy: [SortDescriptor(\.pageIndex, order: .forward), SortDescriptor(\.position, order: .forward)]
            )
            let saved = try modelContext.fetch(descriptor)
            guard !saved.isEmpty else { return false }

            // Build the folders in first-appearance order
            var folderMap: [String: FolderInfo] = [:]
            var foldersInOrder: [FolderInfo] = []

            // Collect every folder's appPaths first, to avoid building it twice
            for row in saved where row.kind == "folder" {
                guard let fid = row.folderId else { continue }
                if folderMap[fid] != nil { continue }

                let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                    if let existing = apps.first(where: { $0.url.path == path }) {
                        return existing
                    }
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        return self.appInfo(from: url)
                    }
                    return self.placeholderAppInfo(forMissingPath: path, preferredName: row.folderName)
                }
                let folder = folderWithValidQuickLaunchPins(FolderInfo(
                    id: fid,
                    name: row.folderName ?? "Untitled",
                    apps: folderApps,
                    pinnedAppPaths: row.pinnedAppPaths,
                    createdAt: row.createdAt
                ))
                folderMap[fid] = folder
                foldersInOrder.append(folder)
            }

            let folderAppPathSet: Set<String> = Set(foldersInOrder.flatMap { $0.apps.map { $0.url.path } })

            // Assemble the top-level items (in page-and-position order; keep empty entries to preserve each page's independent slots)
            var combined: [LaunchpadItem] = []
            combined.reserveCapacity(saved.count)
            for row in saved {
                switch row.kind {
                case "folder":
                    if let fid = row.folderId, let folder = folderMap[fid] {
                        combined.append(.folder(folder))
                    }
                case "app":
                    if let path = row.appPath, !folderAppPathSet.contains(path) {
                        if let existing = apps.first(where: { $0.url.path == path }) {
                            clearMissingPlaceholder(for: path)
                            combined.append(.app(existing))
                        } else {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: url.path) {
                                let info = self.appInfo(from: url)
                                clearMissingPlaceholder(for: path)
                                combined.append(.app(info))
                            } else if let placeholder = updateMissingPlaceholder(path: path,
                                                                                displayName: row.appDisplayName,
                                                                                removableSource: row.removableSource) {
                                combined.append(.missingApp(placeholder))
                            }
                        }
                    }
                case "missing":
                    if let path = row.appPath {
                        if let existing = apps.first(where: { $0.url.path == path }) {
                            clearMissingPlaceholder(for: path)
                            combined.append(.app(existing))
                        } else {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: url.path) {
                                let info = self.appInfo(from: url)
                                clearMissingPlaceholder(for: path)
                                combined.append(.app(info))
                            } else if let placeholder = updateMissingPlaceholder(path: path,
                                                                                displayName: row.appDisplayName,
                                                                                removableSource: row.removableSource) {
                                combined.append(.missingApp(placeholder))
                            }
                        }
                    }
                case "empty":
                    combined.append(.empty(row.slotId))
                default:
                    break
                }
            }

            DispatchQueue.main.async {
                self.folders = self.sanitizedFolders(foldersInOrder)
                if !combined.isEmpty {
                    self.items = self.filteredItemsRemovingHidden(from: combined)
                    // If the apps list is empty, restore it from the persisted data
                    if self.apps.isEmpty {
                        let freeApps: [AppInfo] = combined.compactMap { if case let .app(a) = $0 { return a } else { return nil } }
                        self.apps = freeApps
                        self.pruneHiddenAppsFromAppList()
                    }
                }
                self.refreshMissingPlaceholders()
                self.hasAppliedOrderFromStore = true
            }
            return true
        } catch {
            return false
        }
    }

    private func loadOrderFromLegacyTopItems(using modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<TopItemData>(sortBy: [SortDescriptor(\.orderIndex, order: .forward)])
            let saved = try modelContext.fetch(descriptor)
            guard !saved.isEmpty else { return }

            var folderMap: [String: FolderInfo] = [:]
            var foldersInOrder: [FolderInfo] = []
            let folderAppPathSet: Set<String> = Set(saved.filter { $0.kind == "folder" }.flatMap { $0.appPaths })
            for row in saved where row.kind == "folder" {
                let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                    if let existing = apps.first(where: { $0.url.path == path }) { return existing }
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        return self.appInfo(from: url)
                    }
                    return self.placeholderAppInfo(forMissingPath: path, preferredName: row.folderName)
                }
                let folder = FolderInfo(id: row.id, name: row.folderName ?? "Untitled", apps: folderApps, createdAt: row.createdAt)
                folderMap[row.id] = folder
                foldersInOrder.append(folder)
            }

            var combined: [LaunchpadItem] = saved.sorted { $0.orderIndex < $1.orderIndex }.compactMap { row in
                if row.kind == "folder" { return folderMap[row.id].map { .folder($0) } }
                if row.kind == "empty" { return .empty(row.id) }
                if row.kind == "app", let path = row.appPath {
                    if folderAppPathSet.contains(path) { return nil }
                    if let existing = apps.first(where: { $0.url.path == path }) {
                        clearMissingPlaceholder(for: path)
                        return .app(existing)
                    }
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        clearMissingPlaceholder(for: path)
                        return .app(self.appInfo(from: url))
                    }
                    if let placeholder = updateMissingPlaceholder(path: path) {
                        return .missingApp(placeholder)
                    }
                    return nil
                }
                return nil
            }

            let appsInFolders = Set(foldersInOrder.flatMap { $0.apps })
            let seenPaths = Set(combined.compactMap { item -> String? in
                switch item {
                case .app(let app):
                    return standardizedFilePath(app.url.path)
                case .missingApp(let placeholder):
                    return standardizedFilePath(placeholder.bundlePath)
                default:
                    return nil
                }
            })
            let missingFreeApps = apps
                .filter { !appsInFolders.contains($0) && !seenPaths.contains(standardizedFilePath($0.url.path)) }
                .map { LaunchpadItem.app($0) }
            combined.append(contentsOf: missingFreeApps)

            DispatchQueue.main.async {
                self.folders = self.sanitizedFolders(foldersInOrder)
                if !combined.isEmpty {
                    self.items = self.filteredItemsRemovingHidden(from: combined)
                    // If the apps list is empty, restore it from the persisted data
                    if self.apps.isEmpty {
                        let freeAppsAfterLoad: [AppInfo] = combined.compactMap { if case let .app(a) = $0 { return a } else { return nil } }
                        self.apps = freeAppsAfterLoad
                        self.pruneHiddenAppsFromAppList()
                    }
                }
                self.refreshMissingPlaceholders()
                self.hasAppliedOrderFromStore = true
            }
        } catch {
            // ignore
        }
    }

    func saveAllOrder() {
        guard let modelContext else {
            print("LaunchNG: ModelContext is nil, cannot save order")
            return
        }
        reconcileFolderQuickLaunchPinsInCurrentLayout()
        guard !items.isEmpty else {
            print("LaunchNG: Items list is empty, skipping save")
            return
        }

        print("LaunchNG: Saving order data for \(items.count) items...")
        
        // Write to the new model: by page-slot
        do {
            let existing = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            print("LaunchNG: Found \(existing.count) existing entries, clearing...")
            for row in existing { modelContext.delete(row) }

            // Build a folder lookup table
            let folderById: [String: FolderInfo] = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
            let itemsPerPage = self.itemsPerPage // Use the computed property

            for (idx, item) in items.enumerated() {
                let pageIndex = idx / itemsPerPage
                let position = idx % itemsPerPage
                let slotId = "page-\(pageIndex)-pos-\(position)"
                switch item {
                case .folder(let folder):
                    let authoritativeFolder = folderById[folder.id] ?? folder
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "folder",
                        folderId: authoritativeFolder.id,
                        folderName: authoritativeFolder.name,
                        appPaths: authoritativeFolder.apps.map { $0.url.path },
                        pinnedAppPaths: authoritativeFolder.pinnedAppPaths
                    )
                    modelContext.insert(row)
                case .app(let app):
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "app",
                        appPath: app.url.path,
                        appDisplayName: app.name,
                        removableSource: removableSourcePath(forAppPath: app.url.path)
                    )
                    modelContext.insert(row)
                case .missingApp(let placeholder):
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "missing",
                        appPath: placeholder.bundlePath,
                        appDisplayName: placeholder.displayName,
                        removableSource: placeholder.removableSource
                    )
                    modelContext.insert(row)
                case .empty:
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "empty"
                    )
                    modelContext.insert(row)
                }
            }
            try modelContext.save()
            print("LaunchNG: Successfully saved order data")
            
            // Clean up the legacy table so it doesn't waste space (ignore errors)
            do {
                let legacy = try modelContext.fetch(FetchDescriptor<TopItemData>())
                for row in legacy { modelContext.delete(row) }
                try? modelContext.save()
            } catch { }
        } catch {
            print("LaunchNG: Error saving order data: \(error)")
        }
    }

    // Trigger a folder update, notifying every relevant view to refresh its icon
    private func triggerFolderUpdate() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.triggerFolderUpdate()
            }
            return
        }

        guard !folderUpdateScheduled else { return }
        folderUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.folderUpdateScheduled = false
            self.folderUpdateTrigger = UUID()
            FolderPreviewCache.shared.clear()
        }
    }

    func scheduleSystemAppearanceRefresh() {
        guard appearancePreference == .system else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAppearanceEventAt < 0.2 { return }
        lastAppearanceEventAt = now

        appearanceRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clearIconCachesForLayoutChange()
            self.triggerFolderUpdate()
            self.triggerGridRefresh()
            self.iconCacheRefreshTrigger = UUID()
        }
        appearanceRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    func effectivePageIndicatorOffset(for screenID: String?) -> Double {
        guard pageIndicatorPerDisplayEnabled, let screenID,
              let override = pageIndicatorOverrides[screenID] else {
            return pageIndicatorOffset
        }
        return override.offset
    }

    func effectivePageIndicatorTopPadding(for screenID: String?) -> Double {
        guard pageIndicatorPerDisplayEnabled, let screenID,
              let override = pageIndicatorOverrides[screenID] else {
            return pageIndicatorTopPadding
        }
        return override.topPadding
    }

    func backgroundMaskColor(for colorScheme: ColorScheme) -> Color? {
        guard backgroundMaskEnabled else { return nil }
        let rgba = (colorScheme == .dark) ? backgroundMaskDarkColor : backgroundMaskLightColor
        return rgba.color
    }

    func pageIndicatorOverride(for screenID: String) -> PageIndicatorOverride? {
        pageIndicatorOverrides[screenID]
    }

    func setPageIndicatorOverride(_ override: PageIndicatorOverride?, for screenID: String) {
        var updated = pageIndicatorOverrides
        if let override {
            updated[screenID] = override
        } else {
            updated.removeValue(forKey: screenID)
        }
        pageIndicatorOverrides = updated
        persistPageIndicatorOverrides(updated)
    }

    func applyIndicatorDefaults(to screenID: String) {
        let override = PageIndicatorOverride(offset: pageIndicatorOffset,
                                             topPadding: pageIndicatorTopPadding)
        setPageIndicatorOverride(override, for: screenID)
    }

    func notifyFolderContentChanged(_ folder: FolderInfo) {
        let normalizedFolder = folderWithValidQuickLaunchPins(folder)
        if let folderIndex = folders.firstIndex(where: { $0.id == normalizedFolder.id }) {
            folders[folderIndex] = normalizedFolder
        }
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == normalizedFolder.id {
                items[idx] = .folder(normalizedFolder)
            }
        }
        if openFolder?.id == normalizedFolder.id {
            openFolder = normalizedFolder
        }
        triggerFolderUpdate()
        triggerGridRefresh()
        saveAllOrder()
    }

    private func clearIconCachesForLayoutChange() {
        FolderPreviewCache.shared.clear()
        IconStore.shared.clear()
        purgeIconRenderCaches()
    }

    private func purgeIconRenderCaches() {
        var seen = Set<ObjectIdentifier>()

        func purge(_ image: NSImage) {
            let identifier = ObjectIdentifier(image)
            guard seen.insert(identifier).inserted else { return }
            let originalCacheMode = image.cacheMode
            image.cacheMode = .never
            image.recache()
            image.cacheMode = originalCacheMode
        }

        for app in apps {
            purge(app.icon)
        }

        for folder in folders {
            for app in folder.apps {
                purge(app.icon)
            }
        }

        for item in items {
            if case let .app(app) = item {
                purge(app.icon)
            }
        }
    }
    
    // Trigger a grid view refresh, used to update the UI after a drag operation
    func triggerGridRefresh() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.triggerGridRefresh()
            }
            return
        }

        guard !gridRefreshScheduled else { return }
        gridRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.gridRefreshScheduled = false
            self.clampCurrentPageWithinBounds()
            self.gridRefreshTrigger = UUID()
        }
    }
    
    
    // Clear all persisted ordering and folder data
    private func clearAllPersistedData() {
        guard let modelContext else { return }

        do {
            // Clear the newer page-slot data
            let pageEntries = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            for entry in pageEntries {
                modelContext.delete(entry)
            }

            // Clear the legacy global-order data
            let legacyEntries = try modelContext.fetch(FetchDescriptor<TopItemData>())
            for entry in legacyEntries {
                modelContext.delete(entry)
            }

            // Save the changes
            try modelContext.save()
            missingPlaceholders.removeAll()
        } catch {
            // Ignore errors, so the reset flow keeps going
        }
    }

    private func clampCurrentPageWithinBounds() {
        let perPage = max(itemsPerPage, 1)
        let maxPageIndex = items.isEmpty ? 0 : max(0, (items.count - 1) / perPage)
        if currentPage > maxPageIndex {
            currentPage = maxPageIndex
        }
    }

    // MARK: - Auto-create a new page while dragging
    private var pendingNewPage: (pageIndex: Int, itemCount: Int)? = nil

    func createNewPageForDrag() -> Bool {
        let itemsPerPage = self.itemsPerPage
        let currentPages = (items.count + itemsPerPage - 1) / itemsPerPage
        let newPageIndex = currentPages

        // Add empty placeholders for the new page
        for _ in 0..<itemsPerPage {
            items.append(.empty(UUID().uuidString))
        }

        // Record the pending new page's info
        pendingNewPage = (pageIndex: newPageIndex, itemCount: itemsPerPage)

        // Trigger a grid view refresh
        triggerGridRefresh()

        return true
    }

    func cleanupUnusedNewPage() {
        guard let pending = pendingNewPage else { return }

        // Check whether the new page was actually used (does it have any non-empty items?)
        let pageStart = pending.pageIndex * pending.itemCount
        let pageEnd = min(pageStart + pending.itemCount, items.count)

        if pageStart < items.count {
            let pageSlice = Array(items[pageStart..<pageEnd])
            let hasNonEmptyItems = pageSlice.contains { item in
                if case .empty = item { return false } else { return true }
            }

            if !hasNonEmptyItems {
                // The new page was never used, delete it
                items.removeSubrange(pageStart..<pageEnd)

                // Trigger a grid view refresh
                triggerGridRefresh()
            }
        }

        // Clear the pending info
        pendingNewPage = nil
    }

    // MARK: - Auto-remove blank pages
    /// Auto-removes blank pages: deletes any page made up entirely of empty fill-ins
    func removeEmptyPages() {
        guard !items.isEmpty else { return }
        let itemsPerPage = self.itemsPerPage

        var newItems: [LaunchpadItem] = []
        var index = 0

        while index < items.count {
            let end = min(index + itemsPerPage, items.count)
            let pageSlice = Array(items[index..<end])

            // Check whether the current page is entirely empty
            let isEmptyPage = pageSlice.allSatisfy { item in
                if case .empty = item { return true } else { return false }
            }

            // If it's not a blank page, keep its contents
            if !isEmptyPage {
                newItems.append(contentsOf: pageSlice)
            }
            // If it is a blank page, skip it without adding it

            index = end
        }

        // Only update items if a blank page was actually removed
        if newItems.count != items.count {
            items = filteredItemsRemovingHidden(from: newItems)

            // After removing blank pages, make sure the current page index stays within range
            let maxPageIndex = max(0, (items.count - 1) / itemsPerPage)
            if currentPage > maxPageIndex {
                currentPage = maxPageIndex
            }

            // Trigger a grid view refresh
            triggerGridRefresh()
        }
    }

    private func handleGridConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.compactItemsWithinPages()
            self.removeEmptyPages()
            self.cleanupUnusedNewPage()
            let maxPageIndex = max(0, (self.items.count - 1) / max(self.itemsPerPage, 1))
            if self.currentPage > maxPageIndex {
                self.currentPage = maxPageIndex
            }
            self.triggerGridRefresh()
            self.cacheManager.refreshCache(from: self.apps,
                                           items: self.items,
                                           itemsPerPage: self.itemsPerPage,
                                           columns: self.gridColumnsPerPage,
                                           rows: self.gridRowsPerPage)
            if self.rememberLastPage {
                UserDefaults.standard.set(self.currentPage, forKey: Self.rememberedPageIndexKey)
            }
            self.saveAllOrder()
        }
    }
    
    // MARK: - Export app order feature
    /// Exports the app order as JSON
    func exportAppOrderAsJSON() -> String? {
        reconcileFolderQuickLaunchPinsInCurrentLayout()
        let exportData = buildExportData()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// Builds the export data
    private func buildExportData() -> [String: Any] {
        var pages: [[String: Any]] = []
        let itemsPerPage = self.itemsPerPage
        
        for (index, item) in items.enumerated() {
            let pageIndex = index / itemsPerPage
            let position = index % itemsPerPage
            
            var itemData: [String: Any] = [
                "pageIndex": pageIndex,
                "position": position,
                "kind": itemKind(for: item),
                "name": item.name,
                "path": itemPath(for: item),
                "folderApps": []
            ]
            
            // If it's a folder, add info about the apps inside it
            if case let .folder(folder) = item {
                itemData["folderApps"] = folder.apps.map { $0.name }
                itemData["folderAppPaths"] = folder.apps.map { $0.url.path }
                itemData["folderPinnedAppPaths"] = folder.pinnedAppPaths
            }
            
            pages.append(itemData)
        }
        
        return [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "totalPages": (items.count + itemsPerPage - 1) / itemsPerPage,
            "totalItems": items.count,
            "fullscreenMode": isFullscreenMode,
            "pages": pages
        ]
    }
    
    /// Returns a description of the item's kind
    private func itemKind(for item: LaunchpadItem) -> String {
        switch item {
        case .app:
            return "App"
        case .folder:
            return "Folder"
        case .empty:
            return "Empty slot"
        case .missingApp:
            return "Missing app"
        }
    }

    /// Returns the item's path
    private func itemPath(for item: LaunchpadItem) -> String {
        switch item {
        case let .app(app):
            return app.url.path
        case let .folder(folder):
            return "Folder: \(folder.name)"
        case .empty:
            return "Empty slot"
        case let .missingApp(placeholder):
            return "Missing app: \(placeholder.bundlePath)"
        }
    }

    /// Saves the export file using the system's file save dialog
    func saveExportFileWithDialog(content: String, filename: String, fileExtension: String, fileType: String) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Export File"
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        // Default the save location to the Desktop
        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = desktopURL
        }
        
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    // MARK: - Cache management

    /// Generates the cache once the scan finishes
    private func generateCacheAfterScan() {

        // Check whether the cache is valid
        if !cacheManager.isCacheValid {
            // Generate a new cache
            cacheManager.generateCache(from: apps,
                                      items: items,
                                      itemsPerPage: itemsPerPage,
                                      columns: gridColumnsPerPage,
                                      rows: gridRowsPerPage)
        }

        if isInitialLoading {
            isInitialLoading = false
        }
    }
    
    /// Manual refresh (simulates the full flow of a fresh launch)
    func refresh() {
        print("LaunchNG: Manual refresh triggered")

        // Reset the UI and state to approximate "first launch"
        openFolder = nil
        currentPage = 0
        if !searchText.isEmpty { searchText = "" }

        // Don't reset hasAppliedOrderFromStore, so the layout data is preserved
        hasPerformedInitialScan = true

        // Both the cache clear and the scan run through the unified coordinator, so they don't overlap with an automatic scan.
        requestApplicationReconciliation(reason: .manual)

        // Force a UI refresh
        triggerFolderUpdate()
        triggerGridRefresh()
    }

    /// Clears the cache
    func clearCache() {
        cacheManager.clearAllCaches()
    }

    /// Returns cache statistics
    var cacheStatistics: CacheStatistics {
        return cacheManager.cacheStatistics
    }

    /// Updates the cache after an incremental change
    private func updateCacheAfterChanges() {
        // Check whether the cache needs updating
        if !cacheManager.isCacheValid {
            // Cache is invalid, regenerate it
            cacheManager.generateCache(from: apps,
                                      items: items,
                                      itemsPerPage: itemsPerPage,
                                      columns: gridColumnsPerPage,
                                      rows: gridRowsPerPage)
        }
    }

    private var resolvedLanguage: AppLanguage {
        preferredLanguage == .system ? AppLanguage.resolveSystemDefault() : preferredLanguage
    }

    func localized(_ key: LocalizationKey) -> String {
        LocalizationManager.shared.localized(key, language: resolvedLanguage)
    }

    func localizedLanguageName(for language: AppLanguage) -> String {
        LocalizationManager.shared.languageDisplayName(for: language, displayLanguage: resolvedLanguage)
    }

    // MARK: - Hidden Apps

    @discardableResult
    func hideApp(_ app: AppInfo) -> Bool {
        hideApp(atPath: app.url.path)
    }

    @discardableResult
    func hideApp(at url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return false }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return false }
        return hideApp(atPath: resolved.path)
    }

    @discardableResult
    func hideApp(atPath path: String) -> Bool {
        var didInsert = false
        updateHiddenAppPaths { set in
            if !set.contains(path) {
                set.insert(path)
                didInsert = true
            }
        }
        guard didInsert else { return false }

        removeHiddenAppMetadata(forPath: path)
        items = filteredItemsRemovingHidden(from: items)
        folders = sanitizedFolders(folders)
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        removeEmptyPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
        return true
    }

    @discardableResult
    func hideApps(at urls: [URL]) -> Bool {
        let resolvedPaths = urls.compactMap { url -> String? in
            let resolved = url.resolvingSymlinksInPath()
            guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
            guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
            return resolved.path
        }

        guard !resolvedPaths.isEmpty else { return false }

        var inserted = false
        updateHiddenAppPaths { set in
            for path in resolvedPaths {
                if !set.contains(path) {
                    set.insert(path)
                    inserted = true
                }
            }
        }

        guard inserted else { return false }

        for path in resolvedPaths {
            removeHiddenAppMetadata(forPath: path)
        }

        items = filteredItemsRemovingHidden(from: items)
        folders = sanitizedFolders(folders)
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        removeEmptyPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
        return true
    }

    func unhideApp(path: String) {
        var didRemove = false
        updateHiddenAppPaths { set in
            if set.remove(path) != nil {
                didRemove = true
            }
        }
        guard didRemove else { return }

        guard FileManager.default.fileExists(atPath: path) else {
            triggerFolderUpdate()
            triggerGridRefresh()
            return
        }

        let url = URL(fileURLWithPath: path)
        let info = appInfo(from: url)
        if !apps.contains(info) {
            apps.append(info)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        rebuildItems()
        folders = sanitizedFolders(folders)
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
    }

    private func removeHiddenAppMetadata(forPath path: String) {
        if let index = apps.firstIndex(where: { $0.url.path == path }) {
            apps.remove(at: index)
        }
    }

    private func pruneHiddenAppsFromAppList() {
        guard !hiddenAppPaths.isEmpty else { return }
        apps.removeAll { hiddenAppPaths.contains($0.url.path) }
    }

    private func applyHiddenFilteringToOpenFolder() {
        guard let folder = openFolder else { return }
        let filtered = filteredFolderRemovingHidden(from: folder)
        if filtered.apps.count != folder.apps.count {
            openFolder = filtered
        }
    }

    private func sanitizedFolders(_ input: [FolderInfo]) -> [FolderInfo] {
        let hidden = hiddenAppPaths
        var result: [FolderInfo] = []
        result.reserveCapacity(input.count)
        var didChange = false
        for folder in input {
            let filtered = hidden.isEmpty ? folder : filteredFolderRemovingHidden(from: folder, hidden: hidden)
            let normalized = folderWithValidQuickLaunchPins(filtered)
            if normalized.apps.count != folder.apps.count || normalized.pinnedAppPaths != folder.pinnedAppPaths {
                didChange = true
            }
            result.append(normalized)
        }
        return didChange ? result : input
    }

    private func filteredItemsRemovingHidden(from input: [LaunchpadItem]) -> [LaunchpadItem] {
        guard !hiddenAppPaths.isEmpty else { return input }
        let hidden = hiddenAppPaths
        var result: [LaunchpadItem] = []
        result.reserveCapacity(input.count)
        var didChange = false
        for item in input {
            switch item {
            case .app(let app):
                if hidden.contains(app.url.path) {
                    didChange = true
                    continue
                }
                result.append(.app(app))
            case .missingApp(let placeholder):
                let rawPath = placeholder.bundlePath
                let path = standardizedFilePath(rawPath)
                if hidden.contains(rawPath) || hidden.contains(path) {
                    didChange = true
                    continue
                }
                result.append(.missingApp(placeholder))
            case .folder(let folder):
                let filteredFolder = filteredFolderRemovingHidden(from: folder, hidden: hidden)
                if filteredFolder.apps.count != folder.apps.count {
                    didChange = true
                }
                result.append(.folder(filteredFolder))
            case .empty:
                result.append(item)
            }
        }
        return didChange ? result : input
    }

    private func filteredFolderRemovingHidden(from folder: FolderInfo) -> FolderInfo {
        filteredFolderRemovingHidden(from: folder, hidden: hiddenAppPaths)
    }

    private func filteredFolderRemovingHidden(from folder: FolderInfo, hidden: Set<String>) -> FolderInfo {
        guard !hidden.isEmpty else { return folderWithValidQuickLaunchPins(folder) }
        let filteredApps = folder.apps.filter { !hidden.contains($0.url.path) }
        if filteredApps.count == folder.apps.count {
            return folderWithValidQuickLaunchPins(folder)
        }
        var copy = folder
        copy.apps = filteredApps
        return folderWithValidQuickLaunchPins(copy)
    }

    // MARK: - Custom Titles

    func customTitle(for app: AppInfo) -> String {
        customTitles[app.url.path] ?? ""
    }

    func setCustomTitle(_ rawValue: String, for app: AppInfo) {
        let key = app.url.path
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if customTitles[key] != nil {
                var updated = customTitles
                updated.removeValue(forKey: key)
                customTitles = updated
                applyCustomTitleOverride(for: app.url, title: nil)
            }
            return
        }

        if customTitles[key] == trimmed { return }

        var updated = customTitles
        updated[key] = trimmed
        customTitles = updated
        applyCustomTitleOverride(for: app.url, title: trimmed)
    }

    func clearCustomTitle(for app: AppInfo) {
        setCustomTitle("", for: app)
    }

    func appInfoForCustomTitle(path: String) -> AppInfo {
        if let existing = apps.first(where: { $0.url.path == path }) {
            return existing
        }
        for folder in folders {
            if let existing = folder.apps.first(where: { $0.url.path == path }) {
                return existing
            }
        }

        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return AppInfo.from(url: url,
                                customTitle: customTitles[path],
                                loadIcon: false)
        }

        let fallbackName = customTitles[path] ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(name: fallbackName, icon: AppInfo.transparentPlaceholderIcon, url: url)
    }

    func defaultDisplayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url.deletingPathExtension().lastPathComponent
        }
        return AppInfo.from(url: url, customTitle: nil, loadIcon: false).name
    }

    var uninstallToolAppURL: URL? {
        let trimmed = uninstallToolAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
        return resolved
    }

    var uninstallToolAppDisplayName: String {
        guard let url = uninstallToolAppURL else { return "" }
        return AppInfo.from(url: url, loadIcon: false).name
    }

    var uninstallToolBundleIdentifier: String {
        guard let url = uninstallToolAppURL else { return "" }
        return Bundle(url: url)?.bundleIdentifier ?? ""
    }

    var uninstallToolVersionText: String {
        guard let url = uninstallToolAppURL,
              let info = Bundle(url: url)?.infoDictionary else { return "" }

        let shortVersion = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buildVersion = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !shortVersion.isEmpty && !buildVersion.isEmpty && shortVersion != buildVersion {
            return "\(shortVersion) (\(buildVersion))"
        }
        if !shortVersion.isEmpty { return shortVersion }
        return buildVersion
    }

    var uninstallToolAppIcon: NSImage {
        let icon: NSImage
        if let url = uninstallToolAppURL {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            if let appType = UTType(filenameExtension: "app") {
                icon = NSWorkspace.shared.icon(for: appType)
            } else {
                icon = NSWorkspace.shared.icon(forFile: "/Applications")
            }
        }
        let rendered = (icon.copy() as? NSImage) ?? icon
        rendered.size = NSSize(width: 64, height: 64)
        return rendered
    }

    var uninstallToolConfiguredButMissing: Bool {
        let trimmed = uninstallToolAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && uninstallToolAppURL == nil
    }

    @discardableResult
    func setUninstallToolApplication(url: URL?) -> Bool {
        guard let url else {
            uninstallToolAppPath = ""
            return true
        }

        let resolved = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else { return false }
        guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return false }
        uninstallToolAppPath = resolved.path
        return true
    }

    @discardableResult
    func openConfiguredUninstallTool() -> Bool {
        guard let helper = uninstallToolAppURL else { return false }
        return NSWorkspace.shared.open(helper)
    }

    @discardableResult
    func openConfiguredUninstallTool(for app: AppInfo) -> Bool {
        guard let helper = uninstallToolAppURL else { return false }
        let target = app.url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        needsReconciliationAfterExternalUninstall = true
        NSWorkspace.shared.open([target], withApplicationAt: helper, configuration: configuration) { _, _ in }
        return true
    }

    @discardableResult
    func ensureCustomTitleEntry(for url: URL) -> AppInfo? {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "app" else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }

        let info = appInfo(from: resolved)
        if customTitles[resolved.path] == nil {
            setCustomTitle(info.name, for: info)
        } else {
            applyCustomTitleOverride(for: resolved, title: customTitles[resolved.path])
        }
        return info
    }

    private func applyCustomTitleOverride(for url: URL, title: String?) {
        let info = AppInfo.from(url: url, customTitle: title, loadIcon: false)
        var changed = false

        if let index = apps.firstIndex(where: { $0.url == url }) {
            apps[index] = info
            changed = true
        }

        for folderIndex in folders.indices {
            var folder = folders[folderIndex]
            var folderChanged = false
            for appIndex in folder.apps.indices where folder.apps[appIndex].url == url {
                folder.apps[appIndex] = info
                folderChanged = true
            }
            if folderChanged {
                folders[folderIndex] = folder
                changed = true
            }
        }

        for itemIndex in items.indices {
            switch items[itemIndex] {
            case .app(let app) where app.url == url:
                items[itemIndex] = .app(info)
                changed = true
            case .app:
                break
            case .folder(var folder):
                var folderChanged = false
                for appIndex in folder.apps.indices where folder.apps[appIndex].url == url {
                    folder.apps[appIndex] = info
                    folderChanged = true
                }
                if folderChanged {
                    items[itemIndex] = .folder(folder)
                    changed = true
                }
            case .empty:
                break
            case .missingApp:
                break
            }
        }

        if changed {
            triggerFolderUpdate()
            triggerGridRefresh()
            scheduleCustomTitleCacheRefresh()
        }
    }

    private func scheduleCustomTitleCacheRefresh() {
        customTitleRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cacheManager.refreshCache(from: self.apps,
                                           items: self.items,
                                           itemsPerPage: self.itemsPerPage,
                                           columns: self.gridColumnsPerPage,
                                           rows: self.gridRowsPerPage)
        }
        customTitleRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func setCustomAppIcon(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url),
              let normalized = AppStore.normalizedIconImage(from: image),
              let data = AppStore.pngData(from: normalized) else {
            return false
        }
        do {
            try data.write(to: customIconFileURL, options: .atomic)
            hasCustomAppIcon = true
            currentAppIcon = normalized
            return true
        } catch {
            return false
        }
    }

    func resetCustomAppIcon() {
        try? FileManager.default.removeItem(at: customIconFileURL)
        hasCustomAppIcon = false
        currentAppIcon = defaultAppIcon
    }

    private func applyCurrentAppIcon() {
        let icon = currentAppIcon
        let bundlePath = Bundle.main.bundlePath
        let hasCustomIconFile = FileManager.default.fileExists(atPath: customIconFileURL.path)
        DispatchQueue.main.async {
            let application = NSApplication.shared
            application.applicationIconImage = icon
            application.dockTile.display()

            let workspace = NSWorkspace.shared
            let success: Bool
            if hasCustomIconFile {
                success = workspace.setIcon(icon, forFile: bundlePath, options: [])
            } else {
                success = workspace.setIcon(nil, forFile: bundlePath, options: [])
            }

            if success {
                workspace.noteFileSystemChanged(bundlePath)
            } else {
                NSLog("LaunchNG: Failed to update application bundle icon at %@", bundlePath)
            }
        }
    }

    private static func loadStoredAppIcon(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private static func normalizedIconImage(from image: NSImage, size: CGFloat = 512) -> NSImage? {
        let targetSize = NSSize(width: size, height: size)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let scaledSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(x: (targetSize.width - scaledSize.width) / 2,
                              y: (targetSize.height - scaledSize.height) / 2,
                              width: scaledSize.width,
                              height: scaledSize.height)

        let output = NSImage(size: targetSize)
        output.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()
        let sourceRect = NSRect(origin: .zero, size: image.size)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        image.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: hints)
        output.unlockFocus()
        return output
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }

    private static func ensureAppSupportDirectory() -> URL {
        let fm = FileManager.default
        if let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = base.appendingPathComponent("LaunchNG", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private static var customIconFileURL: URL {
        ensureAppSupportDirectory().appendingPathComponent("CustomAppIcon.png", isDirectory: false)
    }

    /// Refreshes the cache after a folder operation, keeping search working correctly
    private func refreshCacheAfterFolderOperation() {
        // Refresh the cache directly, making sure it covers every app (including ones inside folders)
        cacheManager.refreshCache(from: apps,
                                  items: items,
                                  itemsPerPage: itemsPerPage,
                                  columns: gridColumnsPerPage,
                                  rows: gridRowsPerPage)

        // Clear the search text, resetting the search state
        // This avoids showing stale results the next time the user searches
        if !searchText.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.searchText = ""
            }
        }
    }

    func setGlobalHotKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let normalized = modifierFlags.normalizedShortcutFlags
        let configuration = HotKeyConfiguration(keyCode: keyCode, modifierFlags: normalized)
        if globalHotKey != configuration {
            globalHotKey = configuration
        }
    }

    func clearGlobalHotKey() {
        if globalHotKey != nil {
            globalHotKey = nil
        }
    }

    // func setAIOverlayHotKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
    //     let normalized = modifierFlags.normalizedShortcutFlags
    //     let configuration = HotKeyConfiguration(keyCode: keyCode, modifierFlags: normalized)
    //     if aiOverlayHotKey != configuration {
    //         aiOverlayHotKey = configuration
    //     }
    // }
    //
    // func clearAIOverlayHotKey() {
    //     if aiOverlayHotKey != nil {
    //         aiOverlayHotKey = nil
    //     }
    // }

    func persistCurrentPageIfNeeded() {
        guard rememberLastPage else { return }
        UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
    }

    func hotKeyDisplayText(nonePlaceholder: String) -> String {
        guard let config = globalHotKey else { return nonePlaceholder }
        let base = config.displayString
        if config.modifierFlags.isEmpty {
            return base + " • " + localized(.shortcutNoModifierWarning)
        }
        return base
    }

    func syncGlobalHotKeyRegistration() {
        AppDelegate.shared?.updateGlobalHotKey(configuration: globalHotKey)
    }

    // func aiOverlayHotKeyDisplayText(nonePlaceholder: String) -> String {
    //     guard let config = aiOverlayHotKey else { return nonePlaceholder }
    //     let base = config.displayString
    //     if config.modifierFlags.isEmpty {
    //         return base + " • " + localized(.shortcutNoModifierWarning)
    //     }
    //     return base
    // }
    //
    // func syncAIOverlayHotKeyRegistration() {
    //     // AppDelegate.shared?.updateAIOverlayHotKey(configuration: isAIEnabled ? aiOverlayHotKey : nil)
    // }
    
    // MARK: - Import app order feature
    /// Imports the app order from JSON data
    func importAppOrderFromJSON(_ jsonData: Data) -> Bool {
        do {
            let importData = try JSONSerialization.jsonObject(with: jsonData, options: [])
            return processImportedData(importData)
        } catch {
            return false
        }
    }

    @discardableResult
    func applyMacOS26PresetLayout() -> Bool {
        let candidates = presetCandidateAppsInCurrentOrder()
        guard !candidates.isEmpty else { return false }

        let candidateByPath = Dictionary(uniqueKeysWithValues: candidates.map { ($0.path, $0) })
        var unusedPaths = Set(candidates.map(\.path))
        var rebuiltItems: [LaunchpadItem] = []
        rebuiltItems.reserveCapacity(candidates.count + 1)
        var rebuiltFolders: [FolderInfo] = []

        for slot in LayoutPresetCatalog.macOS26Default.slots {
            switch slot {
            case let .app(bundleIdentifiers, aliases):
                guard let matchedPath = matchPresetSlot(bundleIdentifiers: bundleIdentifiers,
                                                        aliases: aliases,
                                                        candidates: candidates,
                                                        unusedPaths: unusedPaths),
                      let matched = candidateByPath[matchedPath] else {
                    continue
                }
                unusedPaths.remove(matchedPath)
                rebuiltItems.append(.app(matched.app))
            case .utilitiesFolder:
                let folderApps = candidates
                    .filter { unusedPaths.contains($0.path) && shouldIncludeInPresetOtherFolder($0) }
                    .map(\.app)

                guard !folderApps.isEmpty else { continue }
                for app in folderApps {
                    unusedPaths.remove(standardizedFilePath(app.url.path))
                }

                let folder = FolderInfo(name: localized(.layoutPresetOtherFolderTitle), apps: folderApps)
                rebuiltFolders.append(folder)
                rebuiltItems.append(.folder(folder))
            }
        }

        let remainingApps = candidates
            .filter { unusedPaths.contains($0.path) }
            .map(\.app)
        rebuiltItems.append(contentsOf: remainingApps.map { .app($0) })

        guard !rebuiltItems.isEmpty else { return false }

        apps = candidates.map(\.app)
        pruneHiddenAppsFromAppList()
        folders = sanitizedFolders(rebuiltFolders)
        items = filteredItemsRemovingHidden(from: rebuiltItems)
        openFolder = nil
        compactItemsWithinPages()
        removeEmptyPages()
        currentPage = 0
        if !searchText.isEmpty { searchText = "" }
        refreshMissingPlaceholders()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
        return true
    }

    private struct PresetAppCandidate {
        let app: AppInfo
        let path: String
        let bundleIdentifier: String?
        let normalizedNames: Set<String>
    }

    private func presetCandidateAppsInCurrentOrder() -> [PresetAppCandidate] {
        var orderedApps: [AppInfo] = []
        orderedApps.reserveCapacity(items.count + apps.count + folders.reduce(0) { $0 + $1.apps.count })

        for item in items {
            switch item {
            case .app(let app):
                orderedApps.append(app)
            case .folder(let folder):
                orderedApps.append(contentsOf: folder.apps)
            case .empty:
                break
            case .missingApp:
                break
            }
        }
        orderedApps.append(contentsOf: apps)
        for folder in folders {
            orderedApps.append(contentsOf: folder.apps)
        }

        var seenPaths = Set<String>()
        var result: [PresetAppCandidate] = []
        result.reserveCapacity(orderedApps.count)

        for app in orderedApps {
            let path = standardizedFilePath(app.url.path)
            guard !seenPaths.contains(path) else { continue }
            guard !hiddenAppPaths.contains(path) && !hiddenAppPaths.contains(app.url.path) else { continue }
            guard path.lowercased().hasSuffix(".app") else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            seenPaths.insert(path)
            result.append(presetCandidate(from: app, path: path))
        }

        return result
    }

    private func presetCandidate(from app: AppInfo, path: String) -> PresetAppCandidate {
        let appURL = URL(fileURLWithPath: path)
        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier?.lowercased()

        var nameCandidates: [String] = [
            app.name,
            appURL.deletingPathExtension().lastPathComponent
        ]
        if let bundleDisplayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            nameCandidates.append(bundleDisplayName)
        }
        if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            nameCandidates.append(bundleName)
        }

        let normalizedNames = Set(nameCandidates.map(normalizedPresetToken).filter { !$0.isEmpty })
        return PresetAppCandidate(app: app,
                                  path: path,
                                  bundleIdentifier: bundleIdentifier,
                                  normalizedNames: normalizedNames)
    }

    private func matchPresetSlot(bundleIdentifiers: [String],
                                 aliases: [String],
                                 candidates: [PresetAppCandidate],
                                 unusedPaths: Set<String>) -> String? {
        let normalizedBundleIDs = Set(bundleIdentifiers.map { $0.lowercased() }.filter { !$0.isEmpty })
        if !normalizedBundleIDs.isEmpty {
            for candidate in candidates where unusedPaths.contains(candidate.path) {
                if let bundleIdentifier = candidate.bundleIdentifier,
                   normalizedBundleIDs.contains(bundleIdentifier) {
                    return candidate.path
                }
            }
        }

        let normalizedAliases = Set(aliases.map(normalizedPresetToken).filter { !$0.isEmpty })
        guard !normalizedAliases.isEmpty else { return nil }

        for candidate in candidates where unusedPaths.contains(candidate.path) {
            if !normalizedAliases.isDisjoint(with: candidate.normalizedNames) {
                return candidate.path
            }
        }

        return nil
    }

    private func normalizedPresetToken(_ rawValue: String) -> String {
        let folded = rawValue.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                      locale: .current)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private func shouldIncludeInPresetOtherFolder(_ candidate: PresetAppCandidate) -> Bool {
        if isAppInPresetUtilitiesFolders(candidate.path) {
            return true
        }
        let lowerPath = candidate.path.lowercased()
        if LayoutPresetCatalog.otherExtraPathSuffixes.contains(where: { lowerPath.hasSuffix($0) }) {
            return true
        }
        if let bundleIdentifier = candidate.bundleIdentifier,
           LayoutPresetCatalog.otherExtraBundleIDs.contains(bundleIdentifier) {
            return true
        }
        let normalizedAliases = Set(LayoutPresetCatalog.otherExtraAliases.map(normalizedPresetToken))
        return !normalizedAliases.isDisjoint(with: candidate.normalizedNames)
    }

    private func isAppInPresetUtilitiesFolders(_ path: String) -> Bool {
        let normalizedPath = standardizedFilePath(path)
        for root in LayoutPresetCatalog.utilityRootPaths {
            if normalizedPath == root || normalizedPath.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    /// Imports the layout from the native macOS Launchpad
    func importFromNativeLaunchpad() async -> (success: Bool, message: String) {
        guard let modelContext = self.modelContext else {
            return (false, "Data store not initialized")
        }

        do {
            let importer = NativeLaunchpadImporter(modelContext: modelContext)
            let result = try importer.importFromNativeLaunchpad()

            // Refresh app data once the import succeeds
            DispatchQueue.main.async { [weak self] in
                self?.performInitialScanIfNeeded()
                // The newer version uses SwiftData's unified loading entry point
                self?.loadAllOrder()
                self?.triggerGridRefresh()
            }

            return (true, result.summary)
        } catch {
            return (false, "Import failed: \(error.localizedDescription)")
        }
    }

    /// Imports from a legacy archive (.lmy/.zip, or a raw db)
    func importFromLegacyLaunchpadArchive(url: URL) async -> (success: Bool, message: String) {
        guard let modelContext = self.modelContext else {
            return (false, "Data store not initialized")
        }

        do {
            let importer = NativeLaunchpadImporter(modelContext: modelContext)
            let result = try importer.importFromLegacyArchive(at: url)

            // Refresh app data once the import succeeds
            DispatchQueue.main.async { [weak self] in
                self?.performInitialScanIfNeeded()
                self?.loadAllOrder()
                self?.triggerGridRefresh()
            }

            return (true, result.summary)
        } catch {
            return (false, "Import failed: \(error.localizedDescription)")
        }
    }

    /// Processes the imported data and rebuilds the app layout
    private func processImportedData(_ importData: Any) -> Bool {
        guard let data = importData as? [String: Any],
              let pagesData = data["pages"] as? [[String: Any]] else {
            return false
        }

        // Build a map from app path to app object
        let appPathMap = Dictionary(uniqueKeysWithValues: apps.map { ($0.url.path, $0) })

        // Rebuild the items array
        var newItems: [LaunchpadItem] = []
        var importedFolders: [FolderInfo] = []

        // Process each page's data
        for pageData in pagesData {
            guard let kind = pageData["kind"] as? String,
                  let name = pageData["name"] as? String else { continue }

            // These case labels must keep matching itemKind(for:)'s return values exactly.
            switch kind {
            case "App":
                if let path = pageData["path"] as? String,
                   let app = appPathMap[path] {
                    newItems.append(.app(app))
                } else {
                    // App is missing, add an empty slot
                    newItems.append(.empty(UUID().uuidString))
                }

            case "Folder":
                if let folderApps = pageData["folderApps"] as? [String],
                   let folderAppPaths = pageData["folderAppPaths"] as? [String] {
                    let pinnedAppPaths = pageData["folderPinnedAppPaths"] as? [String] ?? []
                    // Rebuild the folder - prefer matching by app path for accuracy
                    let folderAppsList = folderAppPaths.compactMap { appPath in
                        // Match by app path, the most accurate approach
                        if let app = apps.first(where: { $0.url.path == appPath }) {
                            return app
                        }
                        // If path matching fails, fall back to matching by name
                        if let appName = folderApps.first(where: { _ in true }), // Get the corresponding app name
                           let app = apps.first(where: { $0.name == appName }) {
                            return app
                        }
                        return nil
                    }

                    if !folderAppsList.isEmpty {
                        // Try to find a matching existing folder, to keep the ID stable
                        let existingFolder = self.folders.first { existingFolder in
                            existingFolder.name == name &&
                            existingFolder.apps.count == folderAppsList.count &&
                            existingFolder.apps.allSatisfy { app in
                                folderAppsList.contains { $0.id == app.id }
                            }
                        }

                        if let existing = existingFolder {
                            // Reuse the existing folder, keeping its ID stable
                            var folder = existing
                            folder.apps = folderAppsList
                            folder.pinnedAppPaths = pinnedAppPaths
                            folder = folderWithValidQuickLaunchPins(folder)
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        } else {
                            // Create a new folder
                            let folder = folderWithValidQuickLaunchPins(FolderInfo(
                                name: name,
                                apps: folderAppsList,
                                pinnedAppPaths: pinnedAppPaths
                            ))
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        }
                    } else {
                        // Folder is empty, add an empty slot
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else if let folderApps = pageData["folderApps"] as? [String] {
                    // Legacy compatibility: only app names, no path info
                    let folderAppsList = folderApps.compactMap { appName in
                        apps.first { $0.name == appName }
                    }

                    if !folderAppsList.isEmpty {
                        // Try to find a matching existing folder, to keep the ID stable
                        let existingFolder = self.folders.first { existingFolder in
                            existingFolder.name == name &&
                            existingFolder.apps.count == folderAppsList.count &&
                            existingFolder.apps.allSatisfy { app in
                                folderAppsList.contains { $0.id == app.id }
                            }
                        }

                        if let existing = existingFolder {
                            // Reuse the existing folder, keeping its ID stable
                            var folder = existing
                            folder.apps = folderAppsList
                            folder.pinnedAppPaths = []
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        } else {
                            // Create a new folder
                            let folder = FolderInfo(name: name, apps: folderAppsList)
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        }
                    } else {
                        // Folder is empty, add an empty slot
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // Folder data is invalid, add an empty slot
                    newItems.append(.empty(UUID().uuidString))
                }

            case "Empty slot":
                newItems.append(.empty(UUID().uuidString))

            default:
                // Unknown kind, add an empty slot
                newItems.append(.empty(UUID().uuidString))
            }
        }

        // Handle apps left over (put them on the last page)
        let usedApps = Set(newItems.compactMap { item in
            if case let .app(app) = item { return app }
            return nil
        })
        
        let usedAppsInFolders = Set(importedFolders.flatMap { $0.apps })
        let allUsedApps = usedApps.union(usedAppsInFolders)
        
        let unusedApps = apps.filter { !allUsedApps.contains($0) }
        
        if !unusedApps.isEmpty {
            // Work out how many empty slots need to be added
            let itemsPerPage = self.itemsPerPage
            let currentPages = (newItems.count + itemsPerPage - 1) / itemsPerPage
            let lastPageStart = currentPages * itemsPerPage
            let lastPageEnd = lastPageStart + itemsPerPage

            // Make sure the last page has enough room
            while newItems.count < lastPageEnd {
                newItems.append(.empty(UUID().uuidString))
            }

            // Add the unused apps to the last page
            for (index, app) in unusedApps.enumerated() {
                let insertIndex = lastPageStart + index
                if insertIndex < newItems.count {
                    newItems[insertIndex] = .app(app)
                } else {
                    newItems.append(.app(app))
                }
            }

            // Make sure the last page is complete too
            let finalPageCount = newItems.count
            let finalPages = (finalPageCount + itemsPerPage - 1) / itemsPerPage
            let finalLastPageStart = (finalPages - 1) * itemsPerPage
            let finalLastPageEnd = finalLastPageStart + itemsPerPage

            // If the last page isn't full, add empty slots
            while newItems.count < finalLastPageEnd {
                newItems.append(.empty(UUID().uuidString))
            }
        }

        // Validate the imported data structure

        // Update the app state
        DispatchQueue.main.async {

            // Set the new data
            self.folders = self.sanitizedFolders(importedFolders)
            self.items = self.filteredItemsRemovingHidden(from: newItems)


            // Force a UI update
            self.triggerFolderUpdate()
            self.triggerGridRefresh()

            // Save the new layout
            self.saveAllOrder()


            // Don't fill gaps between pages for now, keep the imported data's original order
            // If filling is needed, it can be triggered after the user acts manually
        }

        return true
    }

    /// Validates the imported data's integrity
    func validateImportData(_ jsonData: Data) -> (isValid: Bool, message: String) {
        do {
            let importData = try JSONSerialization.jsonObject(with: jsonData, options: [])
            guard let data = importData as? [String: Any] else {
                return (false, "Invalid data format")
            }

            guard let pagesData = data["pages"] as? [[String: Any]] else {
                return (false, "Missing page data")
            }

            let totalPages = data["totalPages"] as? Int ?? 0
            let totalItems = data["totalItems"] as? Int ?? 0

            if pagesData.isEmpty {
                return (false, "No app data found")
            }

            return (true, "Data validated successfully: \(totalPages) page(s), \(totalItems) item(s)")
        } catch {
            return (false, "JSON parsing failed: \(error.localizedDescription)")
        }
    }

}

extension NSEvent.ModifierFlags {
    static let shortcutComponents: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var normalizedShortcutFlags: NSEvent.ModifierFlags {
        intersection(.deviceIndependentFlagsMask).intersection(Self.shortcutComponents)
    }

    var carbonFlags: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var displaySymbols: [String] {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        return symbols
    }
}
