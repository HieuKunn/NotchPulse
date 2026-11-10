import SwiftUI

struct CameraSettingsPage: View {
    @Bindable private var pocController = NotchPulsePOCController.shared
    @State private var devices: [CameraDevice] = NotchPulseCameraDeviceCatalog.availableDevices()
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        Section {
            Picker(loc("Default camera"), selection: $settings.defaultCameraID) {
                Text(loc("System default")).tag(nil as String?)
                ForEach(devices) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }

            Picker(loc("Built-in display camera"), selection: $settings.builtInDisplayCameraID) {
                Text(loc("System default")).tag(nil as String?)
                ForEach(devices) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }

            Picker(loc("External display camera"), selection: $settings.externalDisplayCameraID) {
                Text(loc("System default")).tag(nil as String?)
                ForEach(devices) { device in
                    Text(device.name).tag(device.id as String?)
                }
            }
        } header: {
            Text(loc("Camera"))
        } footer: {
            Text(loc("NotchPulse automatically selects the active display's camera for facial detection."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            refreshDevices()
        }
    }

    private func refreshDevices() {
        devices = NotchPulseCameraDeviceCatalog.availableDevices()
    }
}
