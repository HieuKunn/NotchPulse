import AppKit
import Defaults
import SwiftUI

struct ShelfSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.notchPulseShelf) var notchPulseShelf: Bool
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.shakeAutoCloseDelay) var shakeAutoCloseDelay
    @Default(.shelfDragOpenPadding) var shelfDragOpenPadding
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Shelf"))
                            .font(.headline)
                        Text(loc("Temporary storage for drag & drop files and quick sharing directly in the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .notchPulseShelf)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: notchPulseShelf) {
                            NotificationCenter.default.post(
                                name: Notification.Name.expandedDragDetectionChanged,
                                object: nil
                            )
                        }
                }
            }
            .id("shelf_general")
            .searchHighlight(highlightedId == "shelf_general")

            Section {
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text(loc("Open shelf by default if items are present"))
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text(loc("Copy items on drag"))
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text(loc("Remove from shelf after dragging"))
                }

                Slider(value: $shakeAutoCloseDelay, in: 1.0...10.0, step: 0.5) {
                    HStack {
                        Text(loc("Shelf auto-close delay"))
                        Spacer()
                        Text(String(format: "%.1fs", shakeAutoCloseDelay))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(loc("After the shelf opens — by shaking while dragging a file, or by hovering the dragged file near the notch — it closes automatically after this many seconds if you do not drop anything. While you keep holding the file over the shelf, it never closes."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $shelfDragOpenPadding, in: 0...240, step: 10) {
                    HStack {
                        Text(loc("File-drag open area"))
                        Spacer()
                        Text(shelfDragOpenPadding == 0 ? loc("Off") : "+\(Int(shelfDragOpenPadding))px")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: shelfDragOpenPadding) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Text(loc("While dragging a file, hovering this close to the notch opens the shelf instantly — no shake needed. Lets you drag files straight out of the Dock (e.g. the Downloads stack) into the shelf. Set to 0 to require the shake gesture instead."))
                    .font(.caption)
                    .foregroundColor(.secondary)

            } header: {
                Text(loc("General"))
            }

            Section {
                Picker(loc("Quick Share Service"), selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(loc("Currently selected")): \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(loc("Files dropped on the shelf will be shared via this service"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

            } header: {
                Text(loc("Quick Share"))
            } footer: {
                Text(loc("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .id("shelf_storage")
            .searchHighlight(highlightedId == "shelf_storage")
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
        .task {
            if quickShareService.availableProviders.isEmpty {
                await quickShareService.discoverAvailableProviders()
            }
        }
    }
}

typealias Shelf = ShelfSettingsView

