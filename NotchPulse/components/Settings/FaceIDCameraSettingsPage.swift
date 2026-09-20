//
//  CameraSettingsPage.swift
//  NotchPulse
//

import SwiftUI

struct CameraSettingsPage: View {
    @Bindable private var pocController = NotchPulsePOCController.shared
    @State private var devices: [CameraDevice] = NotchPulseCameraDeviceCatalog.availableDevices()
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        unlockedState
            .onAppear {
                refreshDevices()
            }
    }

    // MARK: - Content

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                cameraPicker(title: "Default", selection: $settings.defaultCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "Built-in display", selection: $settings.builtInDisplayCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "External display", selection: $settings.externalDisplayCameraID)
            }
        }
    }

    private func cameraPicker(title: String, selection: Binding<String?>) -> some View {
        SettingsRowContent(title: title) {
            // Capsule chrome sits *behind* the Menu — macOS Menu labels
            // discard backgrounds applied inside the label hierarchy.
            ZStack {
                Capsule()
                    .fill(SettingsMetrics.pickerPillFill)

                Menu {
                    Button("System default") { selection.wrappedValue = nil }
                    ForEach(devices) { device in
                        Button(device.name) { selection.wrappedValue = device.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(cameraLabel(for: selection.wrappedValue))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(SettingsMetrics.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(SettingsMetrics.textSecondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                // Window-level accent tint otherwise paints the menu label blue.
                .tint(SettingsMetrics.textPrimary)
            }
            .frame(width: 160, height: 28)
            .overlay {
                Capsule()
                    .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            }
        }
    }

    /// Refreshes the list of available camera devices.
    private func refreshDevices() {
        devices = NotchPulseCameraDeviceCatalog.availableDevices()
    }

    private func cameraLabel(for id: String?) -> String {
        guard let id, let device = devices.first(where: { $0.id == id }) else {
            return "System default"
        }
        return device.name
    }
}
