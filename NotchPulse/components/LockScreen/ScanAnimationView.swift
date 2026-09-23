//
//  ScanAnimationView.swift
//  NotchPulse
//
//  Plays the authentic Face ID scan & green checkmark unlock animation from video assets.
//

import SwiftUI
import AppKit

enum ScanMedia: Equatable {
    case idle
    case scanning
    case success
    case failure

    var videoResourceName: String? {
        switch self {
        case .idle: return nil
        case .scanning: return "idleanimation"
        case .success: return "unlockanimation"
        case .failure: return "unsuccessfulunlockanimation"
        }
    }
}

struct ScanAnimationView: View {
    let media: ScanMedia

    private var faceIDMedia: FaceIDScanMedia {
        switch media {
        case .idle: return .idle
        case .scanning: return .scanning
        case .success: return .success
        case .failure: return .failure
        }
    }

    var body: some View {
        FaceIDScanAnimationView(media: faceIDMedia)
    }
}
