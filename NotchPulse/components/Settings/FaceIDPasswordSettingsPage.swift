import SwiftUI

struct PasswordSettingsPage: View {
    @Bindable private var pocController = NotchPulsePOCController.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    @State private var statusMessage: String?

    var body: some View {
        Section {
            if !pocController.hasStoredPassword {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "lock.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("No Password Stored"))
                            .font(.headline)
                        Text(loc("Set a password so Face ID can automatically unlock your Mac upon recognition."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(loc("Set password")) {
                        FaceIDEnrollmentController.startPasswordOnly()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Label(loc("Password encrypted in Keychain"), systemImage: "lock.fill")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                HStack {
                    Button(loc("Change password")) {
                        FaceIDEnrollmentController.startPasswordOnly()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    HoldToConfirmButton(title: loc("Remove password"), action: removePassword)
                        .controlSize(.small)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(loc("Password & Security"))
        } footer: {
            Text(loc("Your password is stored securely in macOS Keychain using hardware-backed keys. It is decrypted strictly in memory upon face match to type your unlock credentials."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { pocController.refreshCredentialStatus() }
        .onChange(of: FaceIDOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        }
    }

    private func removePassword() {
        do {
            try NotchPulseVault.deletePassword()
            try NotchPulseFaceEnrollmentStore.shared.deleteAll()
            pocController.refreshCredentialStatus()
            statusMessage = loc("Password and face enrollment removed.")
        } catch {
            statusMessage = "\(loc("Couldn't remove")): \(error.localizedDescription)"
        }
    }
}
