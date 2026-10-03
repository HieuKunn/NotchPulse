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
    
    @Default(.standbyClockStyle) private var standbyClockStyle
    @Default(.standbyTheme) private var standbyTheme
    
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
                SettingsSectionTitle(text: loc("Face Unlock"))
                FaceIDUnlockOptionsPage()

                // 2. Enrolled Faces
                SettingsSectionTitle(text: loc("Enrolled Faces"))
                YourFaceSettingsPage()

                // 3. Password & Security
                SettingsSectionTitle(text: loc("Password & Security"))
                PasswordSettingsPage()

                // 4. Camera
                SettingsSectionTitle(text: loc("Camera"))
                CameraSettingsPage()

                // 5. Recognition & Liveness
                SettingsSectionTitle(text: loc("Recognition"))
                RecognitionSettingsPage()

                // 6. Lock Screen Media Player
                SettingsSectionTitle(text: loc("Lock Screen Media Player"))
                lockScreenMediaPlayerSection
                
                // 7. Lock Screen StandBy Mode (iPhone Style)
                SettingsSectionTitle(text: loc("Lock Screen StandBy Mode (iPhone Style)"))
                standBySettingsSection
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
            SettingsRowContent(title: loc("Show Media Player on Lock Screen")) {
                Defaults.Toggle(key: .enableLockScreenPlayer) {
                    Text("")
                }
            }
            SettingsGroupDivider()
            SettingsRowContent(title: loc("Show Real-time Synced Lyrics")) {
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
                Spacer()
            }
            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
            .padding(.vertical, 12)
        }
    }
    
    private var permissionsWarning: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Label(loc("System Permissions Required"), systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                
                Text(loc("Face ID requires Camera permission for face detection and Accessibility permission to automatically enter your password on unlock."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !isCameraGranted {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.red)
                        Text(loc("Camera Permission Missing"))
                            .font(.subheadline)
                        Spacer()
                        Button(loc("Grant")) {
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
                        Text(loc("Accessibility Permission Missing"))
                            .font(.subheadline)
                        Spacer()
                        Button(loc("Open Settings")) {
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
    
    private var standBySettingsSection: some View {
        SettingsGroup {
            SettingsRowContent(title: loc("Enable StandBy Mode on Lock Screen")) {
                Defaults.Toggle(key: .enableLockScreenStandBy) {
                    Text("")
                }
            }
            
            if Defaults[.enableLockScreenStandBy] {
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Clock Face Style")) {
                    Picker("", selection: $standbyClockStyle) {
                        ForEach(StandbyClockStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemIcon).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }
                
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Color Theme")) {
                    Picker("", selection: $standbyTheme) {
                        ForEach(StandbyTheme.allCases) { th in
                            Text(th.displayName).tag(th)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }
                
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Night Mode (Red Glow for Dark Rooms)")) {
                    Defaults.Toggle(key: .standbyNightMode) {
                        Text("")
                    }
                }
                
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Show Live Seconds")) {
                    Defaults.Toggle(key: .standbyShowSeconds) {
                        Text("")
                    }
                }
                
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Show Mac Battery Indicator")) {
                    Defaults.Toggle(key: .standbyShowBattery) {
                        Text("")
                    }
                }
                
                SettingsGroupDivider()
                HStack {
                    Button {
                        LockScreenMediaWindow.shared.togglePreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.tv")
                            Text(loc("Preview StandBy Mode on Screen"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.effectiveAccent)
                    
                    Spacer()
                    
                    Text(loc("Press Esc anytime to exit preview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
