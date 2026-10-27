import AppKit
import Defaults
import SwiftUI

struct ShelfSettingsPage: View {
    @Default(.notchPulseShelf) var notchPulseShelf: Bool
    @Default(.openShelfByDefault) var openShelfByDefault: Bool
    @Default(.copyOnDrag) var copyOnDrag: Bool
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems: Bool
    @Default(.quickShareProvider) var quickShareProvider: String
    @Default(.shakeAutoCloseDelay) var shakeAutoCloseDelay: Double
    @Default(.shelfDragOpenPadding) var shelfDragOpenPadding: Double
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $notchPulseShelf) {
                    Text(loc("Enable Shelf"))
                        .font(.headline)
                    Text(loc("Temporary storage for drag & drop files and quick sharing directly in the Notch."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
            }

            Section {
                Toggle(loc("Open shelf by default if items are present"), isOn: $openShelfByDefault)
                Toggle(loc("Copy items on drag"), isOn: $copyOnDrag)
                Toggle(loc("Remove from shelf after dragging"), isOn: $autoRemoveShelfItems)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc("Shelf auto-close delay"))
                        Spacer()
                        Text("\(Int(shakeAutoCloseDelay))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $shakeAutoCloseDelay, in: 2...20, step: 1)
                    Text(loc("After the shelf opens — by shaking while dragging a file, or by hovering the dragged file near the notch — it closes automatically after this many seconds if you do not drop anything. While you keep holding the file over the shelf, it never closes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc("File-drag open area"))
                        Spacer()
                        Text(shelfDragOpenPadding == 0 ? loc("Off") : "+\(Int(shelfDragOpenPadding))px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $shelfDragOpenPadding, in: 0...240, step: 10)
                    Text(loc("While dragging a file, hovering this close to the notch opens the shelf instantly — no shake needed. Lets you drag files straight out of the Dock (e.g. the Downloads stack) into the shelf. Set to 0 to require the shake gesture instead."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text(loc("General"))
            }
            .disabled(!notchPulseShelf)

            Section {
                Picker(loc("Quick Share Service"), selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 16, height: 16)
                            }
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                if let selected = selectedProvider {
                    HStack(spacing: 12) {
                        if let imgData = selected.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(Color.effectiveAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(loc("Currently selected")): \(selected.id)")
                                .font(.subheadline)
                            Text(loc("Files dropped on the shelf will be shared via this service"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(loc("Quick Share"))
            } footer: {
                Text(loc("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!notchPulseShelf)
        }
        .formStyle(.grouped)
    }
}
