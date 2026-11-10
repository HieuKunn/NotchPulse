import Defaults
import SwiftUI
import AVFoundation
import ApplicationServices

struct FaceIDSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Bindable private var pocController = NotchPulsePOCController.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    @State private var isMusicSyncConfirmed: Bool = MediaAutomationPermissionHelper.isSyncConfirmed()
    @State private var isSyncing: Bool = false

    var body: some View {
        Form {
            if !permissions.cameraStatus.isSatisfied || !permissions.accessibilityStatus.isSatisfied {
                permissionsWarningSection
            }

            // 1. Face Unlock Options (General & Behaviour & Animation)
            FaceIDUnlockOptionsPage()
                .id("faceid_general")
                .searchHighlight(highlightedId == "faceid_general")

            // 2. Enrolled Faces
            YourFaceSettingsPage()
                .id("faceid_enrolled")
                .searchHighlight(highlightedId == "faceid_enrolled")

            // 3. Password & Security
            PasswordSettingsPage()
                .id("faceid_security")
                .searchHighlight(highlightedId == "faceid_security")

            // 4. Recognition & Liveness
            RecognitionSettingsPage()
                .id("faceid_tolerance")
                .searchHighlight(highlightedId == "faceid_tolerance")

            // 5. Lock Screen Media Player
            lockScreenMediaPlayerSection
                .id("faceid_media_player")
                .searchHighlight(highlightedId == "faceid_media_player")
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .onAppear {
            permissions.refreshAll()
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
            pocController.refreshCredentialStatus()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refreshAll()
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
            pocController.refreshCredentialStatus()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        }
    }

    private var permissionsWarningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(loc("Permissions Required for Face ID"))
                        .font(.headline)
                        .foregroundStyle(.orange)
                }

                Text(loc("Face ID requires Camera permission for face detection and Accessibility permission to automatically enter your password on unlock."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if !permissions.cameraStatus.isSatisfied {
                HStack {
                    Label(loc("Camera Permission Missing"), systemImage: "camera.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Button(loc("Grant Camera")) {
                        permissions.request(permission: .camera)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !permissions.accessibilityStatus.isSatisfied {
                HStack {
                    Label(loc("Accessibility Permission Missing"), systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(loc("Open Settings")) {
                        permissions.openSystemSettings(for: .accessibility)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
        } header: {
            Text(loc("System Permissions"))
        }
    }

    private var lockScreenMediaPlayerSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenPlayer) {
                Text(loc("Show Media Player on Lock Screen"))
            }

            Defaults.Toggle(key: .lockScreenPlayerShowLyrics) {
                Text(loc("Show Real-time Synced Lyrics"))
            }

            HStack {
                Button {
                    Task {
                        isSyncing = true
                        isMusicSyncConfirmed = await MediaAutomationPermissionHelper.requestAndVerify()
                        isSyncing = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else if isMusicSyncConfirmed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(loc("Music Sync Confirmed (Spotify & Apple Music)"))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(loc("Sync Music Permissions (Spotify & Apple Music)"))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(isMusicSyncConfirmed ? .green : nil)
            }
            .padding(.vertical, 2)
        } header: {
            Text(loc("Lock Screen Media Player"))
        } footer: {
            Text(loc("Displays current track details, album art, and synchronized lyrics directly on your lock screen when media is active."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
