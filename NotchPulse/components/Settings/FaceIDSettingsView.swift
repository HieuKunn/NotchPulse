//
//  FaceIDSettingsView.swift
//  NotchPulse
//
//  Continuous scrollable settings page for Face ID, credentials, camera, recognition, and lock screen media player.
//  NOTE: All labels, descriptions, and UI text in Settings MUST be in English.
//

import Defaults
import SwiftUI
import AVFoundation
import ApplicationServices

struct FaceIDSettingsView: View {
    @Bindable private var pocController = NotchPulsePOCController.shared
    
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var isCameraGranted: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var isMusicSyncConfirmed: Bool = MediaAutomationPermissionHelper.isSyncConfirmed()
    @State private var isSyncing: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                if !isAccessibilityGranted || !isCameraGranted {
                    permissionsWarning
                }

                // 1. Face Unlock
                SettingsSectionTitle(text: "Face Unlock")
                FaceIDUnlockOptionsPage()

                // 2. Enrolled Faces
                SettingsSectionTitle(text: "Enrolled Faces")
                YourFaceSettingsPage()

                // 3. Password & Security
                SettingsSectionTitle(text: "Password & Security")
                PasswordSettingsPage()

                // 4. Camera
                SettingsSectionTitle(text: "Camera")
                CameraSettingsPage()

                // 5. Recognition & Liveness
                SettingsSectionTitle(text: "Recognition")
                RecognitionSettingsPage()

                // 6. Lock Screen Media Player
                SettingsSectionTitle(text: "Lock Screen Media Player")
                lockScreenMediaPlayerSection
            }
            .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkPermissions()
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
            pocController.refreshCredentialStatus()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
            pocController.refreshCredentialStatus()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        }
    }

    private var lockScreenMediaPlayerSection: some View {
        SettingsGroup {
            SettingsRowContent(title: "Show Media Player on Lock Screen") {
                Defaults.Toggle(key: .enableLockScreenPlayer) {
                    Text("")
                }
            }
            SettingsGroupDivider()
            SettingsRowContent(title: "Show Real-time Synced Lyrics") {
                Defaults.Toggle(key: .lockScreenPlayerShowLyrics) {
                    Text("")
                }
            }
            SettingsGroupDivider()
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
                            Text("Music Sync Confirmed (Spotify & Apple Music)")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Music Permissions (Spotify & Apple Music)")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(isMusicSyncConfirmed ? .green : nil)
                Spacer()
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 12)
        }
    }
    
    private var permissionsWarning: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Label("System Permissions Required", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                
                Text("Face ID requires Camera permission for face detection and Accessibility permission to automatically enter your password on unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !isCameraGranted {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.red)
                        Text("Camera Permission Missing")
                            .font(.subheadline)
                        Spacer()
                        Button("Grant") {
                            let status = AVCaptureDevice.authorizationStatus(for: .video)
                            if status == .notDetermined {
                                AVCaptureDevice.requestAccess(for: .video) { _ in
                                    DispatchQueue.main.async { checkPermissions() }
                                }
                            } else {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                if !isAccessibilityGranted {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility Permission Missing")
                            .font(.subheadline)
                        Spacer()
                        Button("Open Settings") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 12)
        }
    }

    private func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isCameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}
