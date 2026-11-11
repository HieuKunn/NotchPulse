import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreBluetooth
import EventKit
import Foundation

public enum PermissionStatus: Equatable, Sendable {
    case granted
    case partiallyAuthorized
    case notDetermined
    case denied
    case restricted
    case notNeeded

    public var title: String {
        switch self {
        case .granted: return "Granted"
        case .partiallyAuthorized: return "Partially Authorized"
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notNeeded: return "Not Needed"
        }
    }

    public var systemIcon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .partiallyAuthorized: return "exclamationmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "exclamationmark.triangle.fill"
        case .restricted: return "lock.circle.fill"
        case .notNeeded: return "minus.circle"
        }
    }

    public var isSatisfied: Bool {
        self == .granted || self == .notNeeded || self == .partiallyAuthorized
    }
}

public enum AppPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case camera
    case accessibility
    case bluetooth
    case calendar
    case reminders
    case musicAutomation
    case screenRecording
    case fullDiskAccess

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .accessibility: return "Accessibility"
        case .bluetooth: return "Bluetooth"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .musicAutomation: return "Automation (Music)"
        case .screenRecording: return "Screen Recording"
        case .fullDiskAccess: return "Full Disk Access"
        }
    }

    public var systemIcon: String {
        switch self {
        case .camera: return "camera.fill"
        case .accessibility: return "hand.raised.fill"
        case .bluetooth: return "headphones"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .musicAutomation: return "music.note"
        case .screenRecording: return "display"
        case .fullDiskAccess: return "internaldrive"
        }
    }

    public var featureDescription: String {
        switch self {
        case .camera:
            return "Powers Face Unlock and the live Camera Mirror inside the Notch or Dynamic Island."
        case .accessibility:
            return "Allows Face Unlock to automatically enter your password on the macOS lock screen via keystroke simulation."
        case .bluetooth:
            return "Detects wireless headphones and displays battery HUD status."
        case .calendar:
            return "Displays your upcoming agenda and schedule directly in the Notch Calendar tab."
        case .reminders:
            return "Displays your to-do checklist and reminders directly in the Notch Calendar tab."
        case .musicAutomation:
            return "Reads track info, synced lyrics, and playback controls for Spotify and Apple Music."
        case .screenRecording:
            return "Not requested by NotchPulse. Standard notch overlays and HUD indicators do not require screen recording permission."
        case .fullDiskAccess:
            return "Not requested by NotchPulse. Shelf and clipboard operate without full disk access by only accessing items you explicitly drop or copy."
        }
    }

    public var isRequiredForCoreFeatures: Bool {
        switch self {
        case .camera, .accessibility, .bluetooth, .calendar, .reminders, .musicAutomation:
            return true
        case .screenRecording, .fullDiskAccess:
            return false
        }
    }
}

@MainActor
public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public private(set) var cameraStatus: PermissionStatus = .notDetermined
    @Published public private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    @Published public private(set) var bluetoothStatus: PermissionStatus = .notDetermined
    @Published public private(set) var calendarStatus: PermissionStatus = .notDetermined
    @Published public private(set) var remindersStatus: PermissionStatus = .notDetermined
    @Published public private(set) var musicAutomationStatus: PermissionStatus = .notDetermined

    private var appActivationObserver: NSObjectProtocol?

    private init() {
        refreshAll()

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
    }

    deinit {
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func status(for permission: AppPermissionKind) -> PermissionStatus {
        switch permission {
        case .camera: return cameraStatus
        case .accessibility: return accessibilityStatus
        case .bluetooth: return bluetoothStatus
        case .calendar: return calendarStatus
        case .reminders: return remindersStatus
        case .musicAutomation: return musicAutomationStatus
        case .screenRecording, .fullDiskAccess: return .notNeeded
        }
    }

    public func refreshAll() {
        refreshCamera()
        refreshAccessibility()
        refreshBluetooth()
        refreshCalendar()
        refreshReminders()
        refreshMusicAutomation()
    }

    public func refreshCamera() {
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        switch auth {
        case .authorized:
            cameraStatus = .granted
        case .notDetermined:
            cameraStatus = .notDetermined
        case .denied:
            cameraStatus = .denied
        case .restricted:
            cameraStatus = .restricted
        @unknown default:
            cameraStatus = .notDetermined
        }
    }

    public func refreshAccessibility() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    public func refreshBluetooth() {
        switch CBManager.authorization {
        case .allowedAlways:
            bluetoothStatus = .granted
        case .notDetermined:
            bluetoothStatus = .notDetermined
        case .denied:
            bluetoothStatus = .denied
        case .restricted:
            bluetoothStatus = .restricted
        @unknown default:
            bluetoothStatus = .notDetermined
        }
    }

    public func refreshCalendar() {
        let auth = EKEventStore.authorizationStatus(for: .event)
        switch auth {
        case .authorized, .fullAccess:
            calendarStatus = .granted
        case .writeOnly:
            calendarStatus = .restricted
        case .notDetermined:
            calendarStatus = .notDetermined
        case .denied:
            calendarStatus = .denied
        case .restricted:
            calendarStatus = .restricted
        @unknown default:
            calendarStatus = .notDetermined
        }
    }

    public func refreshReminders() {
        let auth = EKEventStore.authorizationStatus(for: .reminder)
        switch auth {
        case .authorized, .fullAccess:
            remindersStatus = .granted
        case .writeOnly:
            remindersStatus = .restricted
        case .notDetermined:
            remindersStatus = .notDetermined
        case .denied:
            remindersStatus = .denied
        case .restricted:
            remindersStatus = .restricted
        @unknown default:
            remindersStatus = .notDetermined
        }
    }

    public func refreshMusicAutomation() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = MediaAutomationPermissionHelper.overallMusicAutomationStatus()
            DispatchQueue.main.async {
                self?.musicAutomationStatus = status
            }
        }
    }

    // MARK: - Request Actions

    public func request(permission: AppPermissionKind) {
        switch permission {
        case .camera:
            let current = AVCaptureDevice.authorizationStatus(for: .video)
            if current == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.refreshCamera()
                    }
                }
            } else {
                openSystemSettings(for: .camera)
            }

        case .accessibility:
            XPCHelperClient.shared.requestAccessibilityAuthorization()
            refreshAccessibility()

        case .bluetooth:
            let current = CBManager.authorization
            if current == .notDetermined {
                BluetoothHeadphoneManager.shared.requestBluetoothAuthorizationIfNeeded()
                refreshBluetooth()
            } else {
                openSystemSettings(for: .bluetooth)
            }

        case .calendar:
            let current = EKEventStore.authorizationStatus(for: .event)
            if current == .notDetermined {
                Task {
                    await CalendarManager.shared.checkCalendarAuthorization()
                    refreshCalendar()
                }
            } else {
                openSystemSettings(for: .calendar)
            }

        case .reminders:
            let current = EKEventStore.authorizationStatus(for: .reminder)
            if current == .notDetermined {
                Task {
                    await CalendarManager.shared.checkReminderAuthorization()
                    refreshReminders()
                }
            } else {
                openSystemSettings(for: .reminders)
            }

        case .musicAutomation:
            Task {
                _ = await MediaAutomationPermissionHelper.requestAndVerify()
                refreshMusicAutomation()
            }

        case .screenRecording, .fullDiskAccess:
            break
        }
    }

    // MARK: - Open System Settings Panes

    nonisolated public static func systemSettingsURL(for permission: AppPermissionKind) -> (primary: URL, fallback: URL) {
        let primaryUrlString: String
        let fallbackUrlString: String

        switch permission {
        case .camera:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .accessibility:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .bluetooth:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case .calendar:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        case .musicAutomation:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .screenRecording:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .fullDiskAccess:
            primaryUrlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
            fallbackUrlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        }

        return (URL(string: primaryUrlString)!, URL(string: fallbackUrlString)!)
    }

    public func openSystemSettings(for permission: AppPermissionKind) {
        let (primaryUrl, fallbackUrl) = Self.systemSettingsURL(for: permission)
        if NSWorkspace.shared.open(primaryUrl) {
            return
        }
        if NSWorkspace.shared.open(fallbackUrl) {
            return
        }
        if let generalUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(generalUrl)
        }
    }
}
