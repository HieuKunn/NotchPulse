//
//  FaceIDSettingsView.swift
//  NotchPulse
//
//  CRITICAL DESIGN REQUIREMENT (MANDATORY):
//  ========================================================================================
//  GIỮ NGUYÊN GIAO DIỆN SIDEBAR NÀY Ở PHÍA BÊN TRÁI. TUYỆT ĐỐI KHÔNG TỰ Ý THAY ĐỔI
//  SANG DẠNG SEGMENTED BAR HOẶC DẠNG NÀO KHÁC NẾU NGƯỜI DÙNG KHÔNG YÊU CẦU!
//  KEEP THIS LEFT SIDEBAR LAYOUT AS-IS. DO NOT CHANGE TO SEGMENTED CONTROL OR ANYTHING ELSE
//  UNLESS EXPLICITLY INSTRUCTED BY THE USER!
//  ========================================================================================
//  NOTE: Tất cả mọi thứ mọi dòng hiển thị trong setting đều dùng tiếng anh (All labels, descriptions, and UI text in Settings MUST be in English).
//

import Defaults
import SwiftUI
import AVFoundation
import ApplicationServices

struct FaceIDSettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var isCameraGranted: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar - DO NOT REMOVE OR CHANGE TO SEGMENTED BAR
            FaceIDSettingsSidebar(
                selection: $selectedTab,
                pocController: NotchPulsePOCController.shared
            )

            Divider()
                .opacity(0.3)

            // Right Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                    if !isAccessibilityGranted || !isCameraGranted {
                        permissionsWarning
                            .padding(.bottom, 8)
                    }
                    
                    switch selectedTab {
                    case .general:
                        GeneralSettingsPage()
                    case .yourFace:
                        YourFaceSettingsPage()
                    case .password:
                        PasswordSettingsPage()
                    case .camera:
                        CameraSettingsPage()
                    case .recognition:
                        RecognitionSettingsPage()
                    default:
                        EmptyView()
                    }
                    
                    // Lock Screen Media Player section preserved from NotchPulse (visible in General tab)
                    if selectedTab == .general {
                        SettingsSectionTitle(text: "Lock Screen Media Player")
                            .padding(.top, 16)
                        SettingsGroup {
                            SettingsRowContent(title: "Show Media Player on Lock Screen") {
                                Defaults.Toggle(key: .enableLockScreenPlayer) {
                                    Text("")
                                }
                            }
                            SettingsGroupDivider()
                            SettingsRowContent(title: "Show Real-time Synced Lyrics (Karaoke)") {
                                Defaults.Toggle(key: .lockScreenPlayerShowLyrics) {
                                    Text("")
                                }
                            }
                            SettingsGroupDivider()
                            HStack {
                                Button {
                                    MediaAutomationPermissionHelper.requestAllPermissions()
                                } label: {
                                    Text("Sync Music Permissions (Spotify & Apple Music)")
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, SettingsMetrics.contentHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
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
