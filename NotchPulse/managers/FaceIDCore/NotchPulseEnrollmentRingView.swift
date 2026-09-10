//
//  NotchPulseEnrollmentRingView.swift
//  NotchPulse
//
//  Apple Face ID 80-Tick Circular Guided Head Sweep & Enrollment Ring.
//  Adapted from Glance with NotchPulse theme & native camera pipeline.
//

import SwiftUI
import AppKit
import CoreGraphics
import Defaults

// MARK: - Guided Head Poses (Center + 8 Compass Directions)

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
    
    func matches(yaw: Float, roll: Float, pitch: Float) -> Bool {
        switch self {
        case .center:
            return abs(yaw) < 0.18 && abs(roll) < 0.18
        case .left:
            return yaw > 0.14 && abs(roll) < 0.22
        case .right:
            return yaw < -0.14 && abs(roll) < 0.22
        case .top:
            return roll > 0.12 || (abs(yaw) < 0.25 && pitch > 0.10)
        case .bottom:
            return roll < -0.12 || (abs(yaw) < 0.25 && pitch < -0.10)
        case .topLeft:
            return yaw > 0.10 && roll > 0.08
        case .topRight:
            return yaw < -0.10 && roll > 0.08
        case .bottomLeft:
            return yaw > 0.10 && roll < -0.08
        case .bottomRight:
            return yaw < -0.10 && roll < -0.08
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
    @State private var collectedEmbeddings: [[Float]] = []
    @State private var poseEmbeddings: [[Float]] = []
    
    @State private var currentTurnAngle: Double? = nil
    @State private var currentTurnIntensity: Double = 0.0
    @State private var isComplete = false
    @State private var pulseCenter = false
    @State private var statusPrompt = "Định vị khuôn mặt trong vòng tròn"
    @State private var frameCounter = 0
    
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
                // Live Camera Frame
                if let image = camera.currentFrame?.image {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                        .fill(Color.black.opacity(0.45))
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
            try? await Task.sleep(for: .milliseconds(60))
        }
    }
    
    private func processFrame(_ image: CGImage) async {
        guard let faces = try? NotchPulseFaceDetector.detectFaces(in: image),
              let face = faces.first, faces.count == 1 else {
            statusPrompt = "Định vị khuôn mặt trong vòng tròn"
            currentTurnIntensity = 0
            return
        }
        
        let yaw = face.yaw ?? 0
        let roll = face.roll ?? 0
        let pitch = face.pitch ?? 0
        
        // Calculate live head angle for ring indicator
        let angleRad = atan2(Double(roll), Double(-yaw))
        var deg = angleRad * (180.0 / .pi) + 90.0
        if deg < 0 { deg += 360 }
        currentTurnAngle = deg
        currentTurnIntensity = min(1.0, Double(hypot(yaw, roll)) * 3.0)
        
        // Check active pose
        if activePose.matches(yaw: yaw, roll: roll, pitch: pitch) {
            if let aligned = NotchPulseFaceAligner.align(face, from: image),
               let embedding = try? embedder.embedding(for: aligned.image) {
                poseEmbeddings.append(embedding)
                
                if poseEmbeddings.count >= 4 {
                    if let avg = FaceEmbedding.average(poseEmbeddings) {
                        collectedEmbeddings.append(avg)
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
                    statusPrompt = "Giữ nguyên góc này..."
                }
            }
        } else {
            statusPrompt = activePose.instruction
        }
    }
    
    private func finishEnrollment() async {
        isComplete = true
        if Defaults[.faceIDSound] { NSSound(named: "Ping")?.play() }
        
        let samples = collectedEmbeddings.map { emb in
            FaceSample(embedding: emb, pose: nil, capturedAt: Date(), quality: 0.95)
        }
        let identity = FaceIdentity(
            id: UUID(),
            name: "My Face",
            samples: samples,
            modelIdentifier: embedder.modelIdentifier,
            embeddingDimension: embedder.embeddingDimension,
            createdAt: Date(),
            isEnabled: true
        )
        try? NotchPulseSecureFaceStore.save([identity])
        faceIDManager.refreshState()
        
        try? await Task.sleep(for: .seconds(2.2))
        camera.stop()
        onFinished()
    }
}
