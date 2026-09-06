//
//  FaceIDSettingsView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Face ID & Lock Screen Settings
//

import Defaults
import SwiftUI

struct FaceIDSettingsView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    @State private var passwordInput: String = ""
    @State private var showPasswordSavedAlert: Bool = false
    @State private var isEnrollingFace: Bool = false
    
    var body: some View {
        Form {
            // MARK: - Section 1: Face ID Unlock (Zero-Overhead)
            Section {
                Defaults.Toggle(key: .enableFaceID) {
                    Text("Enable Face ID Unlock")
                        .font(.headline)
                }
                .disabled(!faceIDManager.isEnrolled || !faceIDManager.hasPasswordSet)
                
                Text("Uses Apple Vision & Apple Neural Engine (NPU) for instant face recognition (0.2s - 0.4s) when the lock screen lights up. Automatically stops after 1s with 0% idle CPU/RAM usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Defaults.Toggle(key: .faceIDSound) {
                    Text("Face ID Sound Effect (Chime)")
                }
            } header: {
                Label("Face ID Unlock (Zero-Overhead)", systemImage: "faceid")
            }
            
            // MARK: - Section 2: Face Enrollment & Multiple Profiles
            Section {
                if faceIDManager.enrolledFaces.isEmpty {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Face Enrolled")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Enroll your face to unlock Mac automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if faceIDManager.isScanning {
                            Button("Cancel") {
                                faceIDManager.cancelCurrentSession()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Enroll Face") {
                                faceIDManager.startEnrollment(name: "Face 1")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // List all enrolled faces
                    ForEach(faceIDManager.enrolledFaces) { face in
                        HStack(spacing: 12) {
                            Image(systemName: "faceid")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(face.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Registered \(face.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                faceIDManager.deleteFace(id: face.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Delete this Face ID")
                        }
                        .padding(.vertical, 3)
                    }

                    // Add alternate face button
                    if faceIDManager.enrolledFaces.count < 5 {
                        if faceIDManager.isScanning {
                            Button("Cancel Scanning") {
                                faceIDManager.cancelCurrentSession()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                faceIDManager.startEnrollment(name: "Appearance \(faceIDManager.enrolledFaces.count + 1)")
                            } label: {
                                Label("Set Up an Alternative Appearance", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                if faceIDManager.isScanning && faceIDManager.enrollmentProgress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: faceIDManager.enrollmentProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text(faceIDManager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !faceIDManager.enrolledFaces.isEmpty {
                    Button(role: .destructive, action: {
                        faceIDManager.resetEnrollment()
                    }) {
                        Text("Reset All Face ID Data")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                HStack {
                    Text("Face Data (\(faceIDManager.enrolledFaces.count)/5)")
                    Spacer()
                }
            } footer: {
                Text("You can register up to 5 faces or alternative appearances (e.g. with/without glasses, hats, different angles, or family members).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Section 3: Lock Screen Password Setup
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your Mac login password to allow Face ID to unlock the screen. Password is encrypted and stored securely in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        SecureField(faceIDManager.hasPasswordSet ? "••••••••••••" : "Enter Mac Login Password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Save to Keychain") {
                            if !passwordInput.isEmpty {
                                KeychainHelper.shared.savePassword(passwordInput)
                                faceIDManager.hasPasswordSet = true
                                passwordInput = ""
                                showPasswordSavedAlert = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(passwordInput.isEmpty)
                    }
                    
                    if faceIDManager.hasPasswordSet {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Password securely stored in Keychain")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Security Credentials")
            }
            
            // MARK: - Section 4: Lock Screen Media Player
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
        .alert("Password Saved", isPresented: $showPasswordSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your Mac unlock password has been encrypted and securely saved in macOS Keychain.")
        }
    }
}
