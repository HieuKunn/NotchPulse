//
//  FaceIDSettingsView.swift
//  NotchPulse
//
//  NOTE: Tất cả mọi thứ mọi dòng hiển thị trong setting đều dùng tiếng anh (All labels, descriptions, and UI text in Settings MUST be in English).
//
//  Created for NotchPulse v2.0 - Face ID & Lock Screen Settings
//  Updated for v3.5: Guided 80-Tick Circular Face ID Enrollment & Live ArcFace Biometric Metrics
//

import Defaults
import SwiftUI
import AVFoundation
import ApplicationServices

struct FaceIDSettingsView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    @State private var passwordInput: String = ""
    @State private var showPasswordSavedAlert: Bool = false
    @State private var showGuidedEnrollmentModal: Bool = false
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var isCameraGranted: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    
    @Default(.faceIDEnterPressCount) var faceIDEnterPressCount
    
    var body: some View {
        Form {
            // MARK: - Section 0: System Permissions Check
            if !isAccessibilityGranted || !isCameraGranted {
                Section {
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
                                Button("Grant Camera Permission") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                        NSWorkspace.shared.open(url)
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
                                Button("Open Accessibility Settings") {
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
                    .padding(.vertical, 4)
                } header: {
                    Text("System Permissions Status")
                }
            }

            // MARK: - Section 1: Face ID Unlock (Zero-Overhead)
            Section {
                Defaults.Toggle(key: .enableFaceID) {
                    Text("Enable Face ID Unlock")
                        .font(.headline)
                }
                .disabled(!faceIDManager.isEnrolled || !faceIDManager.hasPasswordSet)
                
                Text("Uses Apple Vision & ArcFace (512D) Deep Neural Network on Apple Neural Engine. Automatically verifies upon screen lock or wake (up to 4.0s) with 0% idle battery drain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Divider()

                Defaults.Toggle(key: .enableFaceIDForSystemPrompts) {
                    Text("Auto-Authenticate System Prompts")
                        .font(.subheadline)
                }
                .disabled(!Defaults[.enableFaceID] || !faceIDManager.isEnrolled || !faceIDManager.hasPasswordSet)

                Text("Automatically presents Face ID when macOS prompts for administrator authorization, Touch ID, or system password (e.g. installing helper tools or changing system settings). Touch ID or manual password entry remains available as a fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                
                Defaults.Toggle(key: .faceIDSound) {
                    Text("Face ID Sound Effect (Chime)")
                }

                HStack {
                    Text("Enter key presses on unlock")
                    Spacer()
                    Stepper("\(faceIDEnterPressCount) time(s)", value: $faceIDEnterPressCount, in: 1...5)
                }
                Text("Number of Enter/Return keystrokes sent to wake and unlock the display upon successful recognition (1 - 5).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Face ID Unlock (ArcFace CoreML)", systemImage: "faceid")
            }
            
            // MARK: - Section 2: Guided Face Enrollment & Multi-Pose Storage
            Section {
                if !faceIDManager.isEnrolled {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "faceid")
                                .font(.system(size: 26))
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("No Face ID Enrolled")
                                .font(.headline)
                            Text("Scan your face in 8 directions to enable instant Face ID unlock on your Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            showGuidedEnrollmentModal = true
                        } label: {
                            Label("Set Up Face ID", systemImage: "camera.viewfinder")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.04, green: 0.52, blue: 1.0))
                    }
                    .padding(.vertical, 6)
                } else {
                    // Enrolled Identity Card with 80-Tick Circular Re-scan & Details
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            AppleFaceIDGlyphView(
                                isScanning: false,
                                isSuccess: true,
                                size: 36
                            )
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("Enrolled Face")
                                        .font(.headline)
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(Color(red: 0.188, green: 0.855, blue: 0.376))
                                        .font(.system(size: 14))
                                }
                                
                                Text("ArcFace 512D + TTA Preprocessing • 9 Guided Poses Enrolled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                showGuidedEnrollmentModal = true
                            } label: {
                                Label("Rescan Face", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        HStack {
                            Button(role: .destructive) {
                                faceIDManager.resetEnrollment()
                            } label: {
                                Label("Delete Face ID Data", systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            
                            Spacer()
                            
                            Text("Encrypted under Keychain AES-256 Vault")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Biometric Recognition Data")
            } footer: {
                Text("Face ID enrollment uses an 80-tick guided rotation modeled after iOS Face ID for comprehensive facial coverage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Section 3: Face Recognition Live Tester
            if faceIDManager.isEnrolled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Verify camera detection sensitivity and facial similarity score in real time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            if faceIDManager.isTestingMode {
                                Button("Stop Test") {
                                    faceIDManager.stopTestRecognition()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            } else {
                                Button {
                                    faceIDManager.startTestRecognition()
                                } label: {
                                    Label("Start Recognition Test", systemImage: "faceid")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(faceIDManager.isScanning)
                            }
                            
                            if faceIDManager.isTestingMode {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        
                        if !faceIDManager.testResultText.isEmpty {
                            HStack(spacing: 14) {
                                AppleFaceIDGlyphView(
                                    isScanning: faceIDManager.isTestingMode,
                                    isSuccess: faceIDManager.testResultColor == .green,
                                    isFailure: faceIDManager.testResultColor == .red,
                                    size: 28
                                )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(faceIDManager.testResultText)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(faceIDManager.testResultColor)
                                    
                                    if faceIDManager.testConfidence > 0 {
                                        Text("Cosine Similarity: \(faceIDManager.testConfidence)% (Threshold: 40%)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(faceIDManager.testResultColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Live Recognition Tester", systemImage: "checkmark.shield")
                }
            }
            
            // MARK: - Section 4: Lock Screen Password Setup
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your Mac password so Face ID can automatically unlock your screen. Stored securely with AES-256 in Apple Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        SecureField(faceIDManager.hasPasswordSet ? "••••••••••••" : "Enter Mac password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Save to Keychain") {
                            if !passwordInput.isEmpty {
                                if let data = passwordInput.data(using: .utf8) {
                                    do {
                                        try NotchPulseVault.savePassword(data)
                                        faceIDManager.refreshState()
                                        passwordInput = ""
                                        showPasswordSavedAlert = true
                                    } catch {
                                        print("[FaceID] Failed to save password: \(error)")
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(passwordInput.isEmpty)
                    }
                    
                    if faceIDManager.hasPasswordSet {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.188, green: 0.855, blue: 0.376))
                            Text("Password encrypted and securely saved in Keychain")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.188, green: 0.855, blue: 0.376))
                        }
                    }
                }
            } header: {
                Text("Unlock Credentials")
            }
            
            // MARK: - Section 5: Lock Screen Media Player
            Section {
                Defaults.Toggle(key: .enableLockScreenPlayer) {
                    Text("Show Media Player on Lock Screen")
                        .font(.headline)
                }
                
                Text("Displays an iPhone-style Dynamic Island media widget directly on the macOS lock screen when music is playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Defaults.Toggle(key: .lockScreenPlayerShowLyrics) {
                    Text("Show Real-time Synced Lyrics (Karaoke)")
                }
            } header: {
                Label("Lock Screen Media Player", systemImage: "music.note.tv")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showGuidedEnrollmentModal) {
            NotchPulseGuidedEnrollmentView(
                onFinished: {
                    showGuidedEnrollmentModal = false
                },
                onCancelled: {
                    showGuidedEnrollmentModal = false
                }
            )
        }
        .alert("Password Saved", isPresented: $showPasswordSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your Mac unlock password has been encrypted and securely saved in macOS Keychain.")
        }
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
    }

    private func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
        isCameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}
