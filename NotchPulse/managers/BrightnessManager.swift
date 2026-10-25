
import AppKit
import CoreGraphics

// MARK: - Direct In-Process DisplayServices Bridge (0ms latency, zero XPC overhead)
enum DisplayServicesBridge {
	private static let handle: UnsafeMutableRawPointer? = {
		let paths = [
			"/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
			"/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
		]
		for p in paths {
			if let h = dlopen(p, RTLD_LAZY) { return h }
		}
		return nil
	}()

	static func canChangeBrightness(_ displayID: CGDirectDisplayID) -> Bool {
		if CGDisplayIsBuiltin(displayID) != 0 { return true }
		guard let handle = handle,
		      let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") else { return false }
		typealias Fn = @convention(c) (CGDirectDisplayID) -> Int32
		let fn = unsafeBitCast(sym, to: Fn.self)
		return fn(displayID) != 0
	}

	static func getBrightness(_ displayID: CGDirectDisplayID) -> Float? {
		guard let handle = handle,
		      let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
		typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
		let fn = unsafeBitCast(sym, to: Fn.self)
		var tmp: Float = 0
		if fn(displayID, &tmp) == 0 {
			return tmp
		}
		return nil
	}

	static func setBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
		guard let handle = handle,
		      let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
		typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
		let fn = unsafeBitCast(sym, to: Fn.self)
		return fn(displayID, value) == 0
	}

	private static let coreDisplayHandle: UnsafeMutableRawPointer? = {
		let paths = [
			"/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
			"/System/Library/Frameworks/CoreDisplay.framework/Versions/Current/CoreDisplay"
		]
		for p in paths {
			if let h = dlopen(p, RTLD_LAZY) { return h }
		}
		return nil
	}()

	static func coreDisplayInfoDictionary(_ displayID: CGDirectDisplayID) -> NSDictionary? {
		guard let handle = coreDisplayHandle,
		      let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
		typealias Fn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
		let fn = unsafeBitCast(sym, to: Fn.self)
		return fn(displayID)?.takeRetainedValue() as NSDictionary?
	}
}

struct DisplayTarget: Equatable, Identifiable {
	let id: CGDirectDisplayID
	let isBuiltin: Bool
	let localizedName: String
	let shortName: String
	var isSidecarOrVirtual: Bool = false
}

@MainActor
final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	@Published private(set) var activeDisplayID: CGDirectDisplayID = CGMainDisplayID()
	@Published private(set) var currentDisplayName: String = "Retina"
	@Published private(set) var isCurrentBuiltin: Bool = true
	@Published private(set) var hasExternalDisplay: Bool = false

	@Published private(set) var displayBrightnessCache: [CGDirectDisplayID: Float] = [:]
	@Published private(set) var ddcSupportedDisplays: Set<CGDirectDisplayID> = []

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private var pendingHardwareWrites: [CGDirectDisplayID: Float] = [:]
	private var activeWriteTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

	private init() {
		updateDisplayInfo()
		let displays = availableDisplays()
		let initial = displays.first(where: { $0.isBuiltin }) ?? displays.first ?? detectedDisplay()
		activeDisplayID = initial.id
		currentDisplayName = initial.shortName
		isCurrentBuiltin = initial.isBuiltin

		setupObservers()
		refresh()
		refreshAllDisplays()
	}

	private func setupObservers() {
		// Màn hình cắm/rút hoặc thay đổi độ phân giải
		NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.handleScreenChange()
		}

		// 🔄 Lắng nghe sự kiện Mac thức dậy sau giấc ngủ (Sleep/Wake)
		NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didWakeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.handleSystemWake()
		}

		NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.screensDidWakeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.handleSystemWake()
		}
	}

	private func handleSystemWake() {
		Task { @MainActor [weak self] in
			guard let self = self else { return }
			// 1. Huỷ con trỏ DDC cũ đã chết trong helper
			_ = await self.client.resetDDCCache()
			// 2. Chờ 1.5s để chip scaler của màn hình ngoài thức dậy và ổn định vi điều khiển I2C
			try? await Task.sleep(nanoseconds: 1_500_000_000)
			self.updateDisplayInfo()
			self.refreshAllDisplays()
		}
	}

	private func handleScreenChange() {
		Task { @MainActor [weak self] in
			guard let self = self else { return }
			_ = await self.client.resetDDCCache()
			self.updateDisplayInfo()
			self.refreshAllDisplays()
		}
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func updateDisplayInfo() {
		let displays = availableDisplays()
		hasExternalDisplay = displays.contains(where: { !$0.isBuiltin }) && displays.contains(where: { $0.isBuiltin })
	}

	func refreshAllDisplays() {
		let displays = availableDisplays()
		Task { @MainActor in
			for d in displays {
				if (CGDisplayIsBuiltin(d.id) != 0 || CGDisplayVendorNumber(d.id) == 0x0610) && DisplayServicesBridge.canChangeBrightness(d.id),
				   let val = DisplayServicesBridge.getBrightness(d.id) {
					displayBrightnessCache[d.id] = val
				} else if d.isSidecarOrVirtual {
					// Sidecar / Virtual display: giữ giá trị cache hoặc mặc định 0.8
					if displayBrightnessCache[d.id] == nil {
						displayBrightnessCache[d.id] = 0.8
					}
				} else {
					// Màn hình ngoài vật lý: kiểm tra DDC và đọc độ sáng thật từ phần cứng
					let isDDC = await client.isDDCSupported(for: d.id)
					if isDDC {
						ddcSupportedDisplays.insert(d.id)
					}
					if let val = await client.currentDisplayBrightness(for: d.id) {
						displayBrightnessCache[d.id] = val
					}
				}
			}
		}
	}

	func brightness(for displayID: CGDirectDisplayID) -> Float {
		displayBrightnessCache[displayID] ?? (displayID == activeDisplayID ? rawBrightness : 0.5)
	}

	func isDisplaySidecarOrVirtual(_ displayID: CGDirectDisplayID, screenName: String? = nil) -> Bool {
		if CGDisplayIsBuiltin(displayID) != 0 { return false }
		let name = screenName ?? NSScreen.screens.first(where: {
			($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
		})?.localizedName ?? ""

		if name.localizedCaseInsensitiveContains("ipad") ||
		   name.localizedCaseInsensitiveContains("sidecar") ||
		   name.localizedCaseInsensitiveContains("airplay") {
			return true
		}

		if let dict = DisplayServicesBridge.coreDisplayInfoDictionary(displayID) {
			if let isAirPlay = dict["kCGDisplayIsAirPlay"] as? Bool, isAirPlay { return true }
			if let isAirPlayInt = dict["kCGDisplayIsAirPlay"] as? Int, isAirPlayInt != 0 { return true }
			if let isVirtual = dict["kCGDisplayIsVirtualDevice"] as? Bool, isVirtual { return true }
			if let isVirtualInt = dict["kCGDisplayIsVirtualDevice"] as? Int, isVirtualInt != 0 { return true }
		}

		if CGDisplayVendorNumber(displayID) == 0 && CGDisplayModelNumber(displayID) == 0 {
			return true
		}
		return false
	}

	func availableDisplays() -> [DisplayTarget] {
		var targets: [DisplayTarget] = []
		for screen in NSScreen.screens {
			guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
			let isBuiltin = CGDisplayIsBuiltin(id) != 0
			let name = screen.localizedName
			let isVirtual = isDisplaySidecarOrVirtual(id, screenName: name)
			let short: String
			if isBuiltin {
				short = "Retina"
			} else if isVirtual {
				short = name.localizedCaseInsensitiveContains("ipad") ? "iPad" : "Sidecar"
			} else {
				short = "External"
			}
			targets.append(DisplayTarget(id: id, isBuiltin: isBuiltin, localizedName: name, shortName: short, isSidecarOrVirtual: isVirtual))
		}
		if targets.isEmpty {
			let mainID = CGMainDisplayID()
			let isBuiltin = CGDisplayIsBuiltin(mainID) != 0
			targets.append(DisplayTarget(id: mainID, isBuiltin: isBuiltin, localizedName: "Main Display", shortName: isBuiltin ? "Retina" : "External", isSidecarOrVirtual: false))
		}
		return targets
	}

	func detectedDisplay() -> DisplayTarget {
		let mouseLoc = NSEvent.mouseLocation
		let screen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main
		let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
		let isBuiltin = CGDisplayIsBuiltin(id) != 0
		let name = screen?.localizedName ?? (isBuiltin ? "Built-in Retina Display" : "External Display")
		let isVirtual = isDisplaySidecarOrVirtual(id, screenName: name)
		let short: String
		if isBuiltin {
			short = "Retina"
		} else if isVirtual {
			short = name.localizedCaseInsensitiveContains("ipad") ? "iPad" : "Sidecar"
		} else {
			short = "External"
		}
		return DisplayTarget(id: id, isBuiltin: isBuiltin, localizedName: name, shortName: short, isSidecarOrVirtual: isVirtual)
	}

	func toggleTargetDisplay() {
		let displays = availableDisplays()
		guard displays.count > 1 else { return }
		if let currentIdx = displays.firstIndex(where: { $0.id == activeDisplayID }) {
			let nextIdx = (currentIdx + 1) % displays.count
			selectDisplay(displays[nextIdx])
		} else if let first = displays.first {
			selectDisplay(first)
		}
	}

	func selectDisplay(_ target: DisplayTarget) {
		activeDisplayID = target.id
		currentDisplayName = target.shortName
		isCurrentBuiltin = target.isBuiltin

		let brightness = displayBrightnessCache[target.id] ?? (target.isBuiltin ? rawBrightness : 0.5)
		publish(brightness: brightness, touchDate: true)
		let iconName: String
		if target.isBuiltin {
			iconName = "sun.max.fill"
		} else if target.isSidecarOrVirtual {
			iconName = "ipad.and.iphone"
		} else {
			iconName = "display"
		}

		NotchPulseViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .brightness,
			value: CGFloat(brightness),
			icon: iconName
		)
	}

	func currentDisplayIcon(_ value: CGFloat = 0.5) -> String {
		if isCurrentBuiltin {
			return value > 0.6 ? "sun.max" : "sun.min"
		}
		if let target = availableDisplays().first(where: { $0.id == activeDisplayID }), target.isSidecarOrVirtual {
			return "ipad.and.iphone"
		}
		return "display"
	}

	func refresh() {
		Task { @MainActor in
			let brightness = await currentBrightnessFor(displayID: activeDisplayID)
			publish(brightness: brightness, touchDate: false)
		}
	}

	private func currentBrightnessFor(displayID: CGDirectDisplayID) async -> Float {
		if (CGDisplayIsBuiltin(displayID) != 0 || CGDisplayVendorNumber(displayID) == 0x0610) && DisplayServicesBridge.canChangeBrightness(displayID),
		   let val = DisplayServicesBridge.getBrightness(displayID) {
			displayBrightnessCache[displayID] = val
			return val
		}
		if isDisplaySidecarOrVirtual(displayID) {
			return displayBrightnessCache[displayID] ?? 0.8
		}
		if let val = await client.currentDisplayBrightness(for: displayID) {
			displayBrightnessCache[displayID] = val
			return val
		}
		return displayBrightnessCache[displayID] ?? 0.5
	}

	func setRelative(delta: Float, alternateScreen: Bool = false) {
		let displays = availableDisplays()
		guard !displays.isEmpty else { return }

		let currentUnderCursor = detectedDisplay()
		let otherDisplays = displays.filter { $0.id != currentUnderCursor.id }

		// Follow mouse cursor naturally (matching user expectation & MonitorControl)
		// Holding Control acts as alternate target override
		let target: DisplayTarget = alternateScreen
			? (otherDisplays.first ?? currentUnderCursor)
			: currentUnderCursor

		activeDisplayID = target.id
		currentDisplayName = target.shortName
		isCurrentBuiltin = target.isBuiltin

		// Read immediately from memory cache — NEVER block or await slow I2C/DDC hardware reads on keypress!
		let current = displayBrightnessCache[target.id] ?? (target.isBuiltin ? rawBrightness : 0.5)
		let newBrightness = max(0, min(1, current + delta))

		displayBrightnessCache[target.id] = newBrightness
		if target.id == activeDisplayID {
			publish(brightness: newBrightness, touchDate: true)
		}

		let iconName: String
		if target.isBuiltin {
			iconName = "sun.max.fill"
		} else if target.isSidecarOrVirtual {
			iconName = "ipad.and.iphone"
		} else {
			iconName = "display"
		}

		NotchPulseViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .brightness,
			value: CGFloat(newBrightness),
			icon: iconName
		)

		setBrightness(for: target.id, value: newBrightness)
	}

	func setAbsolute(value: Float) {
		setBrightness(for: activeDisplayID, value: value)
	}

	func setBrightness(for displayID: CGDirectDisplayID, value: Float) {
		let clamped = max(0, min(1, value))
		displayBrightnessCache[displayID] = clamped
		if displayID == activeDisplayID {
			publish(brightness: clamped, touchDate: true)
		}

		// 1. Built-in Retina & Apple-branded (Studio Display / Pro Display XDR): Native DisplayServices
		if (CGDisplayIsBuiltin(displayID) != 0 || CGDisplayVendorNumber(displayID) == 0x0610) && DisplayServicesBridge.canChangeBrightness(displayID) {
			DisplayShadeManager.shared.restoreNativeDisplay(for: displayID)
			_ = DisplayServicesBridge.setBrightness(displayID: displayID, value: clamped)
			return
		}

		// 2. Màn hình ngoài vật lý (HKC, Dell, LG...):
		// ⚠️ BẮT BUỘC 100% dùng dispatchHardwareWrite để gửi DDC/CI phần cứng thật, KHÔNG dùng shadow!
		let isVirtual = isDisplaySidecarOrVirtual(displayID)
		if !isVirtual {
			// Đảm bảo không còn bất kỳ hiệu ứng gamma shadow nào trên màn hình vật lý
			DisplayShadeManager.shared.restoreNativeDisplay(for: displayID)
			dispatchHardwareWrite(for: displayID, value: clamped)
		} else {
			// 3. Màn hình Sidecar (iPad), AirPlay hoặc màn hình ảo KHÔNG có chip DDC:
			// Áp dụng Software Dimming (Gamma)
			DisplayShadeManager.shared.setBrightness(clamped, for: displayID)
		}
	}

	private func dispatchHardwareWrite(for displayID: CGDirectDisplayID, value: Float) {
		pendingHardwareWrites[displayID] = value

		if activeWriteTasks[displayID] == nil {
			activeWriteTasks[displayID] = Task { [weak self] in
				while let nextValue = self?.pendingHardwareWrites.removeValue(forKey: displayID) {
					_ = await self?.client.setDisplayBrightness(nextValue, for: displayID)
					// If this is an external display, space writes slightly so the hardware I2C bus settles cleanly
					try? await Task.sleep(nanoseconds: 35_000_000) // 35ms
				}
				self?.activeWriteTasks[displayID] = nil
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		if self.rawBrightness != brightness || touchDate {
			if touchDate { self.lastChangeAt = Date() }
			self.rawBrightness = brightness
			self.animatedBrightness = brightness
		}
	}
}

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			NotchPulseViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}
