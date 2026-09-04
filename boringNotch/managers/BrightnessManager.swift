//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.
//

import AppKit
import CoreGraphics

struct DisplayTarget: Equatable, Identifiable {
	let id: CGDirectDisplayID
	let isBuiltin: Bool
	let localizedName: String
	let shortName: String
}

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	@Published private(set) var activeDisplayID: CGDirectDisplayID = CGMainDisplayID()
	@Published private(set) var currentDisplayName: String = "Retina"
	@Published private(set) var isCurrentBuiltin: Bool = true
	@Published private(set) var hasExternalDisplay: Bool = false

	private var displayBrightnessCache: [CGDirectDisplayID: Float] = [:]
	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() {
		updateDisplayInfo()
		let initial = detectedDisplay()
		activeDisplayID = initial.id
		currentDisplayName = initial.shortName
		isCurrentBuiltin = initial.isBuiltin

		NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.updateDisplayInfo()
		}

		refresh()
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func updateDisplayInfo() {
		let displays = availableDisplays()
		hasExternalDisplay = displays.contains(where: { !$0.isBuiltin }) && displays.contains(where: { $0.isBuiltin })
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

		Task { @MainActor in
			let brightness = await currentBrightnessFor(displayID: target.id)
			publish(brightness: brightness, touchDate: true)
			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .brightness,
				value: CGFloat(brightness),
				icon: target.isBuiltin ? "sun.max.fill" : "display"
			)
		}
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
		if let val = await client.currentDisplayBrightness(for: displayID) {
			displayBrightnessCache[displayID] = val
			return val
		}
		return displayBrightnessCache[displayID] ?? 0.5
	}

	@MainActor func setRelative(delta: Float, alternateScreen: Bool = false) {
		let displays = availableDisplays()
		let builtinDisplay = displays.first(where: { $0.isBuiltin }) ?? detectedDisplay()
		let target: DisplayTarget
		if alternateScreen {
			target = displays.first(where: { !$0.isBuiltin }) ?? builtinDisplay
		} else {
			// Normal F key press always adjusts the Mac built-in Retina screen!
			target = builtinDisplay
		}

		activeDisplayID = target.id
		currentDisplayName = target.shortName
		isCurrentBuiltin = target.isBuiltin

		Task { @MainActor in
			let starting = await currentBrightnessFor(displayID: target.id)
			let newBrightness = max(0, min(1, starting + delta))
			_ = await client.setDisplayBrightness(newBrightness, for: target.id)
			displayBrightnessCache[target.id] = newBrightness
			publish(brightness: newBrightness, touchDate: true)

			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .brightness,
				value: CGFloat(newBrightness),
				icon: target.isBuiltin ? "sun.max.fill" : "display"
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		let displayID = activeDisplayID
		displayBrightnessCache[displayID] = clamped

		Task { @MainActor in
			_ = await client.setDisplayBrightness(clamped, for: displayID)
			publish(brightness: clamped, touchDate: true)
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
				self.animatedBrightness = brightness
			}
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
			BoringViewCoordinator.shared.toggleSneakPeek(
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
