
import AppKit
import CoreGraphics
import Defaults

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

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private var pendingHardwareWrites: [CGDirectDisplayID: Float] = [:]
	private var activeWriteTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

	private var wakeTask: Task<Void, Never>?
	private var screenChangeTask: Task<Void, Never>?

	// MARK: - Persistent Display Brightness Engine

	static func persistentKeys(for displayID: CGDirectDisplayID) -> [String] {
		if CGDisplayIsBuiltin(displayID) != 0 {
			return ["builtin_retina"]
		}
		var keys: [String] = []
		if let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) {
			let uuid = unmanaged.takeRetainedValue()
			let uuidString = CFUUIDCreateString(nil, uuid) as String
			if !uuidString.isEmpty {
				keys.append(uuidString)
			}
		}
		let vendor = CGDisplayVendorNumber(displayID)
		let model = CGDisplayModelNumber(displayID)
		let serial = CGDisplaySerialNumber(displayID)
		if vendor != 0 || model != 0 {
			keys.append("display_\(vendor)_\(model)_\(serial)")
		}
		if let name = (NSScreen.screens.first(where: {
			($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
		})?.localizedName), !name.isEmpty {
			keys.append("name_\(name)")
		}
		keys.append("id_\(displayID)")
		return keys
	}

	static func savedBrightness(for displayID: CGDirectDisplayID) -> Float? {
		let dict = Defaults[.savedDisplayBrightness]
		for key in persistentKeys(for: displayID) {
			if let val = dict[key] {
				return Float(val)
			}
		}
		return nil
	}

	static func saveBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
		var dict = Defaults[.savedDisplayBrightness]
		guard let primaryKey = persistentKeys(for: displayID).first else { return }
		dict[primaryKey] = Double(value)
		Defaults[.savedDisplayBrightness] = dict
	}

	private init() {
		updateDisplayInfo()
		let displays = availableDisplays()
		let initial = displays.first(where: { $0.isBuiltin }) ?? displays.first ?? detectedDisplay()
		activeDisplayID = initial.id
		currentDisplayName = initial.shortName
		isCurrentBuiltin = initial.isBuiltin

		// Nạp trước toàn bộ độ sáng đã lưu vào cache bộ nhớ ngay từ frame 0
		for d in displays {
			if let saved = Self.savedBrightness(for: d.id) {
				displayBrightnessCache[d.id] = saved
			}
		}

		setupObservers()
		refresh()
		refreshAllDisplays(restoreSavedExternal: true)
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

		// 🔄 Lắng nghe sự kiện Mac thức dậy sau giấc ngủ (Sleep/Wake & Screens Sleep/Wake)
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

	private nonisolated func handleSystemWake() {
		Task { @MainActor [weak self] in
			guard let self = self else { return }
			self.wakeTask?.cancel()
			self.wakeTask = Task { @MainActor [weak self] in
				guard let self = self else { return }
				// 1. Huỷ con trỏ DDC cũ đã chết trong helper sau giấc ngủ
				_ = await self.client.resetDDCCache()

				// 2. Chờ 1.5s để chip scaler của màn hình ngoài thức dậy và ổn định vi điều khiển I2C
				try? await Task.sleep(nanoseconds: 1_500_000_000)
				guard !Task.isCancelled else { return }

				self.updateDisplayInfo()
				let displays = self.availableDisplays()

				// 3. Nạp lại cache bộ nhớ ngay lập tức từ Defaults
				for d in displays {
					if let saved = Self.savedBrightness(for: d.id) {
						self.displayBrightnessCache[d.id] = saved
					}
				}

				if let target = Self.determineActiveDisplay(currentID: self.activeDisplayID, availableDisplays: displays) {
					if self.activeDisplayID != target.id {
						self.activeDisplayID = target.id
						self.currentDisplayName = target.shortName
						self.isCurrentBuiltin = target.isBuiltin
						self.refresh()
					}
				}
				self.refreshAllDisplays()

				// 4. Khôi phục độ sáng phần cứng thật cho các màn hình ngoài:
				// Sau khi ngủ/standby, chip scaler thường tự reset về 50% hoặc 70%.
				// Gửi lệnh ghi DDC đợt 1 (1.5s sau wake).
				for d in displays where !d.isBuiltin && !d.isSidecarOrVirtual {
					if let saved = Self.savedBrightness(for: d.id) {
						self.dispatchHardwareWrite(for: d.id, value: saved)
					}
				}

				// Gửi lệnh ghi DDC đợt 2 (3.0s sau wake) để đảm bảo scaler đã hoàn tất handshake video
				try? await Task.sleep(nanoseconds: 1_500_000_000)
				guard !Task.isCancelled else { return }
				for d in displays where !d.isBuiltin && !d.isSidecarOrVirtual {
					if let saved = Self.savedBrightness(for: d.id) {
						self.dispatchHardwareWrite(for: d.id, value: saved)
					}
				}
			}
		}
	}

	private nonisolated func handleScreenChange() {
		Task { @MainActor [weak self] in
			guard let self = self else { return }
			self.screenChangeTask?.cancel()
			self.screenChangeTask = Task { @MainActor [weak self] in
				guard let self = self else { return }
				_ = await self.client.resetDDCCache()
				// Chờ 0.8s để IORegistry cập nhật đầy đủ màn hình mới
				try? await Task.sleep(nanoseconds: 800_000_000)
				guard !Task.isCancelled else { return }

				self.updateDisplayInfo()
				let displays = self.availableDisplays()
				for d in displays {
					if let saved = Self.savedBrightness(for: d.id) {
						self.displayBrightnessCache[d.id] = saved
					}
				}
				if let target = Self.determineActiveDisplay(currentID: self.activeDisplayID, availableDisplays: displays) {
					if self.activeDisplayID != target.id {
						self.activeDisplayID = target.id
						self.currentDisplayName = target.shortName
						self.isCurrentBuiltin = target.isBuiltin
						self.refresh()
					}
				}
				self.refreshAllDisplays()

				// Khôi phục độ sáng cho màn hình ngoài vừa cắm vào
				for d in displays where !d.isBuiltin && !d.isSidecarOrVirtual {
					if let saved = Self.savedBrightness(for: d.id) {
						self.dispatchHardwareWrite(for: d.id, value: saved)
					}
				}
			}
		}
	}

	nonisolated static func determineActiveDisplay(
		currentID: CGDirectDisplayID?,
		availableDisplays: [DisplayTarget]
	) -> DisplayTarget? {
		guard !availableDisplays.isEmpty else { return nil }
		if let currentID = currentID, let match = availableDisplays.first(where: { $0.id == currentID }) {
			return match
		}
		return availableDisplays.first(where: { $0.isBuiltin }) ?? availableDisplays.first
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func updateDisplayInfo() {
		let displays = availableDisplays()
		hasExternalDisplay = displays.contains(where: { !$0.isBuiltin }) && displays.contains(where: { $0.isBuiltin })
	}

	func refreshAllDisplays(restoreSavedExternal: Bool = false) {
		let displays = availableDisplays()
		Task { @MainActor in
			for d in displays {
				if (CGDisplayIsBuiltin(d.id) != 0 || CGDisplayVendorNumber(d.id) == 0x0610) && DisplayServicesBridge.canChangeBrightness(d.id),
				   let val = DisplayServicesBridge.getBrightness(d.id) {
					displayBrightnessCache[d.id] = val
					Self.saveBrightness(val, for: d.id)
				} else if d.isSidecarOrVirtual {
					// Sidecar / Virtual display: giữ giá trị đã lưu hoặc mặc định 0.8
					let val = Self.savedBrightness(for: d.id) ?? displayBrightnessCache[d.id] ?? 0.8
					displayBrightnessCache[d.id] = val
					DisplayShadeManager.shared.setBrightness(val, for: d.id)
				} else {
					// Màn hình ngoài vật lý:
					// Luôn ưu tiên giá trị người dùng đã lưu làm chuẩn (tránh đọc DDC lúc wake/cắm lại làm ghi đè mất độ sáng cũ).
					if let saved = Self.savedBrightness(for: d.id) {
						displayBrightnessCache[d.id] = saved
						if restoreSavedExternal {
							self.dispatchHardwareWrite(for: d.id, value: saved)
						}
					} else if let val = await client.currentDisplayBrightness(for: d.id) {
						// Chỉ đọc phần cứng để khởi tạo lần đầu khi chưa có giá trị lưu
						displayBrightnessCache[d.id] = val
						Self.saveBrightness(val, for: d.id)
					}
				}
			}
		}
	}

	func brightness(for displayID: CGDirectDisplayID) -> Float {
		if let cached = displayBrightnessCache[displayID] {
			return cached
		}
		if let saved = Self.savedBrightness(for: displayID) {
			displayBrightnessCache[displayID] = saved
			return saved
		}
		return (displayID == activeDisplayID ? rawBrightness : 0.5)
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
			} else if !name.isEmpty && name != "External Display" && name != "Display" {
				short = name.count <= 10 ? name : (name.components(separatedBy: " ").first ?? "External")
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
		} else if !name.isEmpty && name != "External Display" && name != "Display" {
			short = name.count <= 10 ? name : (name.components(separatedBy: " ").first ?? "External")
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

		let brightness = self.brightness(for: target.id)
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
			Self.saveBrightness(val, for: displayID)
			return val
		}
		if isDisplaySidecarOrVirtual(displayID) {
			let val = Self.savedBrightness(for: displayID) ?? displayBrightnessCache[displayID] ?? 0.8
			displayBrightnessCache[displayID] = val
			return val
		}
		if let saved = Self.savedBrightness(for: displayID) {
			displayBrightnessCache[displayID] = saved
			return saved
		}
		if let val = await client.currentDisplayBrightness(for: displayID) {
			displayBrightnessCache[displayID] = val
			Self.saveBrightness(val, for: displayID)
			return val
		}
		return brightness(for: displayID)
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

		// Read immediately from memory cache or persistent storage — NEVER block or await slow I2C/DDC hardware reads on keypress!
		let current = brightness(for: target.id)
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
		Self.saveBrightness(clamped, for: displayID)

		if displayID == activeDisplayID {
			publish(brightness: clamped, touchDate: true)
		}

		// 1. Built-in Retina & Apple-branded (Studio Display / Pro Display XDR): Native DisplayServices
		if (CGDisplayIsBuiltin(displayID) != 0 || CGDisplayVendorNumber(displayID) == 0x0610) && DisplayServicesBridge.canChangeBrightness(displayID) {
			DisplayShadeManager.shared.removeShade(for: displayID)
			_ = DisplayServicesBridge.setBrightness(displayID: displayID, value: clamped)
			return
		}

		// 2. Màn hình ngoài vật lý (HKC, Dell, LG...):
		// ⚠️ BẮT BUỘC 100% dùng dispatchHardwareWrite để gửi DDC/CI phần cứng thật, KHÔNG dùng shadow!
		let isVirtual = isDisplaySidecarOrVirtual(displayID)
		if !isVirtual {
			// Đảm bảo không còn bất kỳ window shade overlay nào trên màn hình vật lý
			DisplayShadeManager.shared.removeShade(for: displayID)
			dispatchHardwareWrite(for: displayID, value: clamped)
		} else {
			// 3. Màn hình Sidecar (iPad), AirPlay hoặc màn hình ảo KHÔNG có chip DDC:
			// Áp dụng Software Dimming (Black Window Shade Overlay)
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
