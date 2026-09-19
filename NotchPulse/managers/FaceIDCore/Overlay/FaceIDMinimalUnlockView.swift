//
//  FaceIDMinimalUnlockView.swift
//  NotchPulse
//
//  Layout: [ lock ][ gap ][ video ]. For `.notch` the gap is the physical
//  cutout (nothing may be drawn there); for `.pill` it's just negative space.

import SwiftUI

struct FaceIDMinimalUnlockView: View {
    let media: ScanMedia
    /// Owned by the caller (not derived from `media`) so the glyph and video can be offset from each other.
    let isUnlocked: Bool
    /// Inset from the silhouette's left/right edges. The caller adds the
    /// notch's flare allowance into this where it applies.
    let edgeInset: CGFloat
    var lockIconSize: CGFloat = FaceIDOverlayGeometry.minimalLockIconSize
    var mediaWidth: CGFloat = FaceIDOverlayGeometry.minimalMediaWidth
    var mediaVerticalInset: CGFloat = FaceIDOverlayGeometry.minimalMediaVerticalInset
    /// Applied to the video only; defaults to identity so most callers can ignore it.
    var pulseScale: CGFloat = 1
    var pulseOpacity: Double = 1

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: lockIconSize, weight: .semibold))
                .foregroundStyle(FaceIDTheme.textPrimary)
                // The explicit `.animation` below is required: the phase change that flips
                // `isUnlocked` isn't itself wrapped in an animation transaction.
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .animation(
                    .smooth(duration: FaceIDOverlayGeometry.minimalLockAnimationDuration),
                    value: isUnlocked
                )
                .frame(width: mediaWidth)

            Spacer(minLength: 0)

            FaceIDScanAnimationView(media: media)
                .padding(.vertical, mediaVerticalInset)
                .frame(width: mediaWidth)
                // Scoped to the video alone — the lock icon on the left
                // must stay steady while this breathes.
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, edgeInset)
    }
}
