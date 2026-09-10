//
//  NotchPulseEnrollmentRingView.swift
//  NotchPulse
//
//  Apple Face ID 80-Tick Circular Guided Head Sweep & Enrollment Ring.
//  Adapted from Glance with mirrored selfie preview, natural head tracking & instant ArcFace embedding.
//

import SwiftUI
import AppKit
import CoreGraphics
import Defaults

// MARK: - Guided Head Poses (Center + 8 Compass Directions in Clockwise Sweep)

enum GuidedEnrollmentPose: Int, CaseIterable, Identifiable {
    case center = 0
    case left = 1
    case topLeft = 2
    case top = 3
    case topRight = 4
    case right = 5
    case bottomRight = 6
    case bottom = 7
    case bottomLeft = 8
    
    var id: Int { rawValue }
    
    var compassAngle: Double? {
        switch self {
        case .center: return nil
        case .left: return 270
        case .topLeft: return 315
        case .top: return 0
        case .topRight: return 45
        case .right: return 90
        case .bottomRight: return 135
        case .bottom: return 180
        case .bottomLeft: return 225
        }
    }
    
    var instruction: String {
        switch self {
        case .center: return "Nhìn thẳng vào camera"
        case .left: return "Nghiêng đầu sang trái"
        case .topLeft: return "Nghiêng sang góc trên bên trái"
        case .top: return "Ngước đầu lên trên"
        case .topRight: return "Nghiêng sang góc trên bên phải"
        case .right: return "Nghiêng đầu sang phải"
        case .bottomRight: return "Nghiêng sang góc dưới bên phải"
        case .bottom: return "Cúi nhẹ đầu xuống"
        case .bottomLeft: return "Nghiêng sang góc dưới bên trái"
        }
    }
    
    /// Vision Reports: +yaw turns left, -yaw turns right; +pitch looks down, -pitch looks up.
    func matches(yaw: Float, pitch: Float) -> Bool {
        let yawThresh: Float = 0.16
        let yawCenter: Float = 0.18
        let pitchThresh: Float = 0.12
        let pitchCenter: Float = 0.16
        
        switch self {
        case .center:
            return abs(yaw) < yawCenter && abs(pitch) < pitchCenter
        case .left:
            return yaw > yawThresh && abs(pitch) < pitchCenter * 1.5
        case .right:
            return yaw < -yawThresh && abs(pitch) < pitchCenter * 1.5
        case .top:
            return pitch < -pitchThresh && abs(yaw) < yawCenter * 1.5
        case .bottom:
            return pitch > pitchThresh && abs(yaw) < yawCenter * 1.5
        case .topLeft:
            return yaw > (yawThresh * 0.65) && pitch < -(pitchThresh * 0.65)
        case .topRight:
            return yaw < -(yawThresh * 0.65) && pitch < -(pitchThresh * 0.65)
        case .bottomLeft:
            return yaw > (yawThresh * 0.65) && pitch > (pitchThresh * 0.65)
        case .bottomRight:
            return yaw < -(yawThresh * 0.65) && pitch > (pitchThresh * 0.65)
        }
    }
}

// MARK: - Animated Completion Checkmark

private struct NotchPulseCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.24))
        return path
    }
}

struct NotchPulseAnimatedCheckmark: View {
    var color: Color = Color(red: 0.188, green: 0.855, blue: 0.376) // Apple Green (#30D158)
    var lineWidth: CGFloat = 6
    @State private var progress: CGFloat = 0

    var body: some View {
        NotchPulseCheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                withAnimation(.timingCurve(0.65, 0.0, 0.35, 1.0, duration: 0.35)) {
                    progress = 1
                }
            }
    }
}

// MARK: - 80-Tick Circular Enrollment Ring

struct NotchPulseEnrollmentRingView: View {
    var capturedPoses: Set<GuidedEnrollmentPose>
    var currentTurnAngle: Double?
    var currentTurnIntensity: Double
    var isComplete: Bool
    var pulseCenter: Bool
    
    private let tickCount = 80
    private let diameter: CGFloat = 205
    private var radius: CGFloat { diameter / 2 }
    private let accentColor = Color(red: 0.188, green: 0.855, blue: 0.376) // Apple Neon Green
    private let activeBlue = Color(red: 0.04, green: 0.52, blue: 1.0)     // Apple Electric Blue

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let intensity = turnIntensity(for: index)
                let length = tickLength(for: index, intensity: intensity)
                Capsule()
                    .fill(tickColor(for: index, intensity: intensity))
                    .frame(width: isComplete ? 3.5 : 2.4, height: length)
                    .offset(y: -(radius + length / 2))
                    .rotationEffect(.degrees(angle(for: index)))
                    .opacity(isComplete ? 0 : 1)
                    .animation(.easeOut(duration: 0.25).delay(Double(index % 10) * 0.008), value: isLit(index))
                    .animation(.easeOut(duration: 0.15), value: intensity)
                    .animation(.easeInOut(duration: 0.45).delay(Double(index) * 0.003), value: isComplete)
            }

            // Solid Completion Ring
            Circle()
                .stroke(accentColor, lineWidth: 12)
                .frame(width: diameter + 16, height: diameter + 16)
                .opacity(isComplete ? 1 : 0)
                .scaleEffect(isComplete ? 1 : 0.90)
                .animation(.easeInOut(duration: 0.45), value: isComplete)
        }
        .frame(width: diameter + 40, height: diameter + 40)
    }

    private func angle(for index: Int) -> Double {
        Double(index) * (360.0 / Double(tickCount))
    }

    private func sectorPose(for index: Int) -> GuidedEnrollmentPose? {
        let raw = Int((angle(for: index) / 45.0).rounded()) % 8
        let sectorAngle = Double(raw) * 45
        return GuidedEnrollmentPose.allCases.first { $0.compassAngle == sectorAngle }
    }

    private func isLit(_ index: Int) -> Bool {
        if isComplete { return true }
        guard let pose = sectorPose(for: index) else { return false }
        return capturedPoses.contains(pose)
    }

    private func tickLength(for index: Int, intensity: Double) -> CGFloat {
        if isLit(index) || pulseCenter { return 18 }
        return 11 + CGFloat(6 * intensity)
    }

    private func tickColor(for index: Int, intensity: Double) -> Color {
        if isLit(index) || isComplete { return accentColor }
        if intensity > 0.05 {
            return activeBlue.opacity(0.4 + intensity * 0.6)
        }
        return Color.white.opacity(0.25)
    }

    private func turnIntensity(for index: Int) -> Double {
        guard let currentTurnAngle, !isComplete, !isLit(index) else { return 0 }

        var delta = abs(angle(for: index) - currentTurnAngle)
        if delta > 180 { delta = 360 - delta }

        let degreesPerTick = 360.0 / Double(tickCount)
        let halfSpan = 3.5 // width of pointer in ticks
        let falloff = max(0, 1 - (delta / degreesPerTick) / halfSpan)
        return currentTurnIntensity * falloff
    }
}

// MARK: - Guided Circular Face ID Setup Modal

struct NotchPulseGuidedEnrollmentView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    var onFinished: () -> Void
    var onCancelled: () -> Void
    
    @State private var camera = NotchPulseCamera()
    @State private var capturedPoses: Set<GuidedEnrollmentPose> = []
    @State private var activePose: GuidedEnrollmentPose = .center
    @State private var collectedSamples: [FaceSample] = []
    @State private var poseEmbeddings: [[Float]] = []
    
    @State private var currentTurnAngle: Double? = nil
    @State private var currentTurnIntensity: Double = 0.0
    @State private var isComplete = false
    @State private var pulseCenter = false
    @State private var statusPrompt = "Nhìn thẳng vào camera"
    
    private let embedder: NotchPulseFaceEmbedder = (try? NotchPulseArcFaceEmbedder()) ?? NotchPulseVisionFeaturePrintEmbedder()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Thiết lập Face ID")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    camera.stop()
                    onCancelled()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            
            // Circular Camera & 80-Tick Ring Cluster
            ZStack {
                // Live Camera Frame - Mirrored as a selfie mirror view
                if let image = camera.currentFrame?.image {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(x: -1, y: 1) // Mirrored for intuitive selfie preview
                        .frame(width: 175, height: 175)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 175, height: 175)
                    ProgressView()
                }
                
                // 80-Tick Enrollment Ring
                NotchPulseEnrollmentRingView(
                    capturedPoses: capturedPoses,
                    currentTurnAngle: currentTurnAngle,
                    currentTurnIntensity: currentTurnIntensity,
                    isComplete: isComplete,
                    pulseCenter: pulseCenter
                )
                
                // Animated Checkmark on finish
                if isComplete {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 175, height: 175)
                    NotchPulseAnimatedCheckmark(lineWidth: 7)
                        .frame(width: 72, height: 72)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 250, height: 250)
            
            // Guided Instruction Banner
            VStack(spacing: 6) {
                Text(isComplete ? "Hoàn tất đăng ký Face ID! 🎉" : statusPrompt)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(isComplete ? "Khuôn mặt của bạn đã được mã hoá và bảo vệ an toàn trong Keychain." : "Xoay nhẹ đầu theo vòng tròn để ghi lại đầy đủ các góc cạnh của khuôn mặt.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(height: 52)
            
            // Progress Bar
            ProgressView(value: Double(capturedPoses.count), total: Double(GuidedEnrollmentPose.allCases.count))
                .progressViewStyle(.linear)
                .tint(Color(red: 0.188, green: 0.855, blue: 0.376))
                .padding(.horizontal, 36)
                .padding(.bottom, 16)
        }
        .frame(width: 360, height: 440)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
        .task {
            await startEnrollmentSequence()
        }
        .onDisappear {
            camera.stop()
        }
    }
    
    private func startEnrollmentSequence() async {
        _ = await faceIDManager.ensureSessionUnlocked()
        await camera.requestAccessAndStart()
        
        while !Task.isCancelled && !isComplete {
            guard let frame = camera.currentFrame?.image else {
                try? await Task.sleep(for: .milliseconds(40))
                continue
            }
            
            await processFrame(frame)
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
    
    private func processFrame(_ image: CGImage) async {
        guard let faces = try? NotchPulseFaceDetector.detectFaces(in: image),
              let face = faces.first, faces.count == 1 else {
            statusPrompt = "Định vị khuôn mặt trong vòng tròn"
            currentTurnIntensity = 0
            currentTurnAngle = nil
            return
        }
        
        let yaw = face.yaw ?? 0
        let pitch = face.pitch ?? 0
        
        // Accurate Head Turn Angle matching Glance (+yaw left, +pitch down; Screen: x right, y down)
        let x = Double(-yaw / 0.20)
        let y = Double(-pitch / 0.14)
        let magnitude = (x * x + y * y).squareRoot()
        if magnitude > 0.10 {
            let deg = atan2(x, y) * 180.0 / .pi
            currentTurnAngle = deg < 0 ? deg + 360.0 : deg
            currentTurnIntensity = min(1.0, magnitude)
        } else {
            currentTurnAngle = nil
            currentTurnIntensity = 0.0
        }
        
        // Check active pose
        if activePose.matches(yaw: yaw, pitch: pitch) {
            if let aligned = NotchPulseFaceAligner.align(face, from: image),
               let embedding = try? embedder.embedding(for: aligned.image) {
                poseEmbeddings.append(embedding)
                
                // 2 high-quality captures per pose is fast and stable
                if poseEmbeddings.count >= 2 {
                    if let avg = FaceEmbedding.average(poseEmbeddings) {
                        collectedSamples.append(FaceSample(
                            embedding: avg,
                            pose: "\(activePose.rawValue)",
                            capturedAt: Date(),
                            quality: face.quality ?? 0.9
                        ))
                    }
                    capturedPoses.insert(activePose)
                    poseEmbeddings.removeAll()
                    
                    if Defaults[.faceIDSound] { NSSound(named: "Tink")?.play() }
                    
                    // Advance to next uncaptured pose
                    if let next = GuidedEnrollmentPose.allCases.first(where: { !capturedPoses.contains($0) }) {
                        activePose = next
                        statusPrompt = next.instruction
                    } else {
                        // All 9 poses captured!
                        await finishEnrollment()
                    }
                } else {
                    statusPrompt = "Giữ nguyên..."
                }
            }
        } else {
            statusPrompt = activePose.instruction
        }
    }
    
    private func finishEnrollment() async {
        isComplete = true
        if Defaults[.faceIDSound] { NSSound(named: "Ping")?.play() }
        
        let targetID = NotchPulseFaceEnrollmentStore.shared.activeIdentities.first?.id
        _ = try? NotchPulseFaceEnrollmentStore.shared.commitEnrollment(
            replacing: targetID,
            name: "My Face",
            samples: collectedSamples,
            embedder: embedder
        )
        
        faceIDManager.refreshState()
        
        try? await Task.sleep(for: .seconds(1.8))
        camera.stop()
        onFinished()
    }
}
