//
//  ClipboardManager.swift
//  NotchPulse
//
//  Created by Alexander on 2026-09-26.
//

import AppKit
import Combine
import Defaults
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let contentString: String?
    let timestamp: Date
    let isImage: Bool
    
    var displayString: String {
        if let text = contentString {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Image / Rich Data"
    }
}

final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var history: [ClipboardItem] = []
    @Published var isEnabled: Bool = Defaults[.enableClipboardManager] {
        didSet {
            Defaults[.enableClipboardManager] = isEnabled
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var maxItems: Int = Defaults[.clipboardMaxItems] {
        didSet {
            Defaults[.clipboardMaxItems] = maxItems
            trimHistory()
        }
    }

    private var pollTimer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1

    private init() {
        self.lastChangeCount = pasteboard.changeCount
        if isEnabled {
            startMonitoring()
        }
        
        // Listen to default changes
        Defaults.publisher(.enableClipboardManager)
            .sink { [weak self] val in
                self?.isEnabled = val.newValue
            }
            .store(in: &cancellables)
            
        Defaults.publisher(.clipboardMaxItems)
            .sink { [weak self] val in
                self?.maxItems = val.newValue
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = pasteboard.changeCount

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForChanges() {
        guard isEnabled else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Read string or content
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            // Avoid duplicates at the top
            if history.first?.contentString == string {
                return
            }
            
            let newItem = ClipboardItem(
                id: UUID(),
                contentString: string,
                timestamp: Date(),
                isImage: false
            )
            
            DispatchQueue.main.async {
                self.history.insert(newItem, at: 0)
                self.trimHistory()
            }
        } else if let _ = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let newItem = ClipboardItem(
                id: UUID(),
                contentString: "[Copied Image]",
                timestamp: Date(),
                isImage: true
            )
            
            DispatchQueue.main.async {
                self.history.insert(newItem, at: 0)
                self.trimHistory()
            }
        }
    }

    private func trimHistory() {
        let limit = max(5, maxItems)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        guard let text = item.contentString, !item.isImage else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func clearHistory() {
        history.removeAll()
    }
}
