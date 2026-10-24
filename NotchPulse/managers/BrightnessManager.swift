
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
}

struct DisplayTarget: Equatable, Identifiable {
	let id: CGDirectDisplayID
	let isBuiltin: Bool
	let localizedName: String
	let shortName: String
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

	private init() {
		updateDisplayInfo()
		let displays = availableDisplays()
		let initial = displays.first(where: { $0.isBuiltin }) ?? displays.first ?? detectedDisplay()
		activeDisplayID = initial.id
		currentDisplayName = initial.shortName
		isCurrentBuiltin = initial.isBuiltin

		NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.updateDisplayInfo()
			self?.refreshAllDisplays()
		}

		refresh()
		refreshAllDisplays()
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
				if DisplayServicesBridge.canChangeBrightness(d.id),
				   let val = DisplayServicesBridge.getBrightness(d.id) {
					displayBrightnessCache[d.id] = val
				} else if let val = await client.currentDisplayBrightness(for: d.id) {
					displayBrightnessCache[d.id] = val
				}
			}
		}
	}

	func brightness(for displayID: CGDirectDisplayID) -> Float {
		displayBrightnessCache[displayID] ?? (displayID == activeDisplayID ? rawBrightness : 0.5)
	}

	func availableDisplays() -> [DisplayTarget] {
		var targets: [DisplayTarget] = []
		for screen in NSScreen.screens {
			guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
			let isBuiltin = CGDisplayIsBuiltin(id) != 0
			let name = screen.localizedName
			let short = isBuiltin ? "Retina" : "External"
			targets.append(DisplayTarget(id: id, isBuiltin: isBuiltin, localizedName: name, shortName: short))
		}
		if targets.isEmpty {
			let mainID = CGMainDisplayID()
			let isBuiltin = CGDisplayIsBuiltin(mainID) != 0
			targets.append(DisplayTarget(id: mainID, isBuiltin: isBuiltin, localizedName: "Main Display", shortName: isBuiltin ? "Retina" : "External"))
		}
		return targets
	}

	func detectedDisplay() -> DisplayTarget {
		let mouseLoc = NSEvent.mouseLocation
		let screen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main
		let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
		let isBuiltin = CGDisplayIsBuiltin(id) != 0
		let name = screen?.localizedName ?? (isBuiltin ? "Built-in Retina Display" : "External Display")
		let short = isBuiltin ? "Retina" : "External"
		return DisplayTarget(id: id, isBuiltin: isBuiltin, localizedName: name, shortName: short)
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
		NotchPulseViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .brightness,
			value: CGFloat(brightness),
			icon: target.isBuiltin ? "sun.max.fill" : "display"
		)
	}

	func currentDisplayIcon(_ value: CGFloat = 0.5) -> String {
		if !isCurrentBuiltin {
			return "display"
		}
		return value > 0.6 ? "sun.max" : "sun.min"
	}

	func refresh() {
		Task { @MainActor in
			let brightness = await currentBrightnessFor(displayID: activeDisplayID)
			publish(brightness: brightness, touchDate: false)
		}
	}

	private func currentBrightnessFor(displayID: CGDirectDisplayID) async -> Float {
		if DisplayServicesBridge.canChangeBrightness(displayID),
		   let val = DisplayServicesBridge.getBrightness(displayID) {
			displayBrightnessCache[displayID] = val
			return val
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

		NotchPulseViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .brightness,
			value: CGFloat(newBrightness),
			icon: target.isBuiltin ? "sun.max.fill" : "display"
		)

		if DisplayServicesBridge.canChangeBrightness(target.id) {
			_ = DisplayServicesBridge.setBrightness(displayID: target.id, value: newBrightness)
		} else {
			dispatchHardwareWrite(for: target.id, value: newBrightness)
		}
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

		if DisplayServicesBridge.canChangeBrightness(displayID) {
			_ = DisplayServicesBridge.setBrightness(displayID: displayID, value: clamped)
		} else {
			dispatchHardwareWrite(for: displayID, value: clamped)
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
