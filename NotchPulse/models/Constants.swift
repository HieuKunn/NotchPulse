//
//  Constants.swift
//  NotchPulse
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
    static let previewNotchWidth = Notification.Name("previewNotchWidth")
    static let closeNotchPreview = Notification.Name("closeNotchPreview")
    static let notchDidOpen = Notification.Name("notchDidOpen")
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    static let faceIDPhaseChanged = Notification.Name("faceIDPhaseChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

// Display style: MacBook Notch vs Floating Dynamic Island
enum NotchStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case notch = "MacBook Notch"
    case dynamicIsland = "Dynamic Island"

    var id: String { self.rawValue }
}

// Alternate / Lunar calendar regions and systems
enum AlternateCalendarType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case vietnamese = "vietnamese"
    case chinese = "chinese"
    case islamic = "islamic"
    case hebrew = "hebrew"
    case buddhist = "buddhist"
    case persian = "persian"

    var id: String { self.rawValue }

    var displayName: String {
        localizedName(for: Defaults[.appLanguage])
    }

    func localizedName(isVietnamese: Bool) -> String {
        localizedName(for: isVietnamese ? .vietnamese : .english)
    }

    func localizedName(for language: AppLanguage) -> String {
        switch language {
        case .vietnamese:
            switch self {
            case .vietnamese: return "Việt Nam (Âm lịch VN - UTC+7)"
            case .chinese: return "Đài Loan / Trung Quốc / HK (Nông lịch - UTC+8)"
            case .islamic: return "Hồi giáo (Lịch Hijri)"
            case .hebrew: return "Do Thái (Lịch Hebrew)"
            case .buddhist: return "Phật lịch (Buddhist)"
            case .persian: return "Ba Tư (Lịch Jalali)"
            }
        case .traditionalChinese:
            switch self {
            case .vietnamese: return "越南 (越南農曆 - UTC+7)"
            case .chinese: return "台灣 / 中國 / 香港 (農曆 - UTC+8)"
            case .islamic: return "伊斯蘭曆 (Hijri)"
            case .hebrew: return "希伯來曆 (Hebrew)"
            case .buddhist: return "佛曆 (Buddhist)"
            case .persian: return "波斯曆 (Jalali)"
            }
        case .simplifiedChinese:
            switch self {
            case .vietnamese: return "越南 (越南农历 - UTC+7)"
            case .chinese: return "台湾 / 中国 / 香港 (农历 - UTC+8)"
            case .islamic: return "伊斯兰历 (Hijri)"
            case .hebrew: return "希伯来历 (Hebrew)"
            case .buddhist: return "佛历 (Buddhist)"
            case .persian: return "波斯历 (Jalali)"
            }
        case .japanese:
            switch self {
            case .vietnamese: return "ベトナム (旧暦 - UTC+7)"
            case .chinese: return "台湾・中国・香港 (旧暦 - UTC+8)"
            case .islamic: return "ヒジュラ暦 (イスラム暦)"
            case .hebrew: return "ユダヤ暦"
            case .buddhist: return "仏暦"
            case .persian: return "ペルシア暦"
            }
        case .arabic:
            switch self {
            case .vietnamese: return "فيتنام (التقويم القمري الفيتنامي - UTC+7)"
            case .chinese: return "تايوان / الصين / هونغ كونغ (التقويم القمري - UTC+8)"
            case .islamic: return "التقويم الهجري الإسلامي"
            case .hebrew: return "التقويم العبري"
            case .buddhist: return "التقويم البوذي"
            case .persian: return "التقويم الفارسي (الجلالي)"
            }
        default:
            switch self {
            case .vietnamese: return "Vietnam (Vietnamese Lunar - UTC+7)"
            case .chinese: return "Taiwan / China / HK (Chinese Lunar - UTC+8)"
            case .islamic: return "Islamic (Hijri)"
            case .hebrew: return "Hebrew"
            case .buddhist: return "Buddhist"
            case .persian: return "Persian (Jalali)"
            }
        }
    }
}

// App interface language
enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case english = "en"
    case vietnamese = "vi"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case arabic = "ar"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt (Vietnamese)"
        case .traditionalChinese: return "繁體中文 (Traditional Chinese)"
        case .simplifiedChinese: return "简体中文 (Simplified Chinese)"
        case .japanese: return "日本語 (Japanese)"
        case .german: return "Deutsch (German)"
        case .french: return "Français (French)"
        case .spanish: return "Español (Spanish)"
        case .arabic: return "العربية (Arabic)"
        }
    }
}

extension Defaults.Keys {
    // MARK: General
    static let notchStyle = Key<NotchStyle>("notchStyle", default: .notch)
    static let dynamicIslandTopOffset = Key<CGFloat>("dynamicIslandTopOffset", default: 8)
    static let notchOpenWidth = Key<CGFloat>("notchOpenWidth", default: 740)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .english)

    // MARK: Alternate / Lunar Calendar
    static let alternateCalendarType = Key<AlternateCalendarType>("alternateCalendarType", default: .vietnamese)
    static let showLunarCalendar = Key<Bool>("showLunarCalendar", default: false)

    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let hoverAreaPadding = Key<Double>("hoverAreaPadding", default: 30.0)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: true)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Face ID & Lock Screen (v2.0)
    static let enableFaceID = Key<Bool>("enableFaceID", default: false)
    static let enableFaceIDForSystemPrompts = Key<Bool>("enableFaceIDForSystemPrompts", default: false)
    static let faceIDSound = Key<Bool>("faceIDSound", default: true)
    static let faceIDEnterPressCount = Key<Int>("faceIDEnterPressCount", default: 1)
    static let faceIDMatchThreshold = Key<Double>("faceIDMatchThreshold", default: 0.64)
    static let enableLockScreenPlayer = Key<Bool>("enableLockScreenPlayer", default: true)
    static let lockScreenPlayerShowLyrics = Key<Bool>("lockScreenPlayerShowLyrics", default: true)
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: System Monitor (Stats)
    static let enableSystemMonitor = Key<Bool>("enableSystemMonitor", default: true)
    static let systemMonitorInterval = Key<Double>("systemMonitorInterval", default: 1.5)
    static let systemMonitorShowProcesses = Key<Bool>("systemMonitorShowProcesses", default: true)
    
    // MARK: Shelf
    static let notchPulseShelf = Key<Bool>("notchPulseShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: false)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let shakeAutoCloseDelay = Key<Double>("shakeAutoCloseDelay", default: 5.0)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    static let dragDetectionPadding = Key<Double>("dragDetectionPadding", default: 40.0)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)

    // MARK: Clipboard Manager
    static let enableClipboardManager = Key<Bool>("enableClipboardManager", default: true)
    static let clipboardMaxItems = Key<Int>("clipboardMaxItems", default: 10)
}
