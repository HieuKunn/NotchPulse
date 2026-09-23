# NotchPulse v4.6.5

## ⚡ Instant Face ID Animation Playback
- **Zero-Delay Video Start**: Removed player layer ready-observation delays and task sleep buffers so the Face ID blue scanning grid animation (`idleanimation.mp4`) begins playing frame-1 immediately as the overlay spring expands.

## 🏝️ Dynamic Island Expansion & Inline Layout
- **Proportional Expansion**: Dynamic Island inline HUDs, music activities, and face animations now expand dynamically to match the full notch camera width with balanced spacing.

## 📷 Notch Camera Mirror & Continuity Support
- **Full Camera Device Compatibility**: Added support for Continuity Camera and external webcams, eliminating session freeze when opening the live mirror.

## 🎵 Smart Lock Screen Media Routing
- **Display Mode Awareness**: When "Show on all displays" is active, lock screen media frames on `NSScreen.main`. When a single display is selected, media routes strictly to the user's preferred display.


