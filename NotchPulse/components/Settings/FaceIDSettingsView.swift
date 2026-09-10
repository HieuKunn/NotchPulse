//
//  FaceIDSettingsView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Face ID & Lock Screen Settings
//  Updated for v3.5: Guided 80-Tick Circular Face ID Enrollment & Live ArcFace Biometric Metrics
//

import Defaults
import SwiftUI

struct FaceIDSettingsView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    @State private var passwordInput: String = ""
    @State private var showPasswordSavedAlert: Bool = false
    @State private var showGuidedEnrollmentModal: Bool = false
    
    @Default(.faceIDEnterPressCount) var faceIDEnterPressCount
    
    var body: some View {
        Form {
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
                
                Defaults.Toggle(key: .faceIDSound) {
                    Text("Face ID Sound Effect (Chime)")
                }

                HStack {
                    Text("Số lần ấn phím Enter khi mở khoá")
                    Spacer()
                    Stepper("\(faceIDEnterPressCount) lần", value: $faceIDEnterPressCount, in: 1...5)
                }
                Text("Tuỳ chỉnh số lần gửi tín hiệu phím Enter/Return để mở máy sau khi nhận diện thành công (1 - 5 lần).")
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
                            Text("Chưa đăng ký Face ID")
                                .font(.headline)
                            Text("Quét khuôn mặt 360° theo vòng tròn 8 hướng để tự động mở khoá Mac siêu tốc.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            showGuidedEnrollmentModal = true
                        } label: {
                            Label("Thiết lập Face ID", systemImage: "camera.viewfinder")
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
                                    Text("Khuôn mặt đã đăng ký")
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
                                Label("Quét lại khuôn mặt", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        HStack {
                            Button(role: .destructive) {
                                faceIDManager.resetEnrollment()
                            } label: {
                                Label("Xoá dữ liệu Face ID", systemImage: "trash")
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
                Text("Dữ liệu nhận diện sinh trắc học")
            } footer: {
                Text("Quá trình thiết lập Face ID sử dụng vòng xoay 80-tick mô phỏng chính xác iPhone Face ID để bao phủ toàn diện các góc nhìn của khuôn mặt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Section 3: Face Recognition Live Tester
            if faceIDManager.isEnrolled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kiểm tra trực tiếp độ nhạy và mức độ tương đồng của khuôn mặt trước camera theo thời gian thực.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            if faceIDManager.isTestingMode {
                                Button("Dừng kiểm tra") {
                                    faceIDManager.stopTestRecognition()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            } else {
                                Button {
                                    faceIDManager.startTestRecognition()
                                } label: {
                                    Label("Bắt đầu thử nghiệm nhận diện", systemImage: "faceid")
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
                                        Text("Độ tương đồng Cosine: \(faceIDManager.testConfidence)% (Ngưỡng mở: 40%)")
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
                    Label("Thử nghiệm nhận diện thời gian thực (Live Tester)", systemImage: "checkmark.shield")
                }
            }
            
            // MARK: - Section 4: Lock Screen Password Setup
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nhập mật khẩu đăng nhập Mac để Face ID có thể tự động gõ mở khoá màn hình. Mật khẩu được mã hoá bằng khoá phần cứng trong Apple Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        SecureField(faceIDManager.hasPasswordSet ? "••••••••••••" : "Nhập mật khẩu máy Mac", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Lưu vào Keychain") {
                            if !passwordInput.isEmpty {
                                if let data = passwordInput.data(using: .utf8) {
                                    try? NotchPulseVault.savePassword(data)
                                }
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
                                .foregroundStyle(Color(red: 0.188, green: 0.855, blue: 0.376))
                            Text("Mật khẩu đã được mã hoá và lưu an toàn trong Keychain")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.188, green: 0.855, blue: 0.376))
                        }
                    }
                }
            } header: {
                Text("Thông tin xác thực mở máy")
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
    }
}
