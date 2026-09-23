# NotchPulse v4.6.5

## 📷 Smart Multi-Display Camera Screen Routing
- **Active Camera Binding**: Automatically detects the active camera being used for Face ID (built-in MacBook webcam or external display / webcam) and routes the Notch/Face ID overlay directly to the corresponding screen.

## ⚡ Instant Face ID Animation Playback & Rendering Fixes
- **No More Blank Dropdowns**: Fixed CALayer and AVPlayerLayer frame sizing and autoresizing so `idleanimation.mp4` / `unlockanimation.mp4` renders and plays with zero delay when hovering or waking up on the lock screen.
- **Immediate Hover Activation**: Hovering over the Face ID notch triggers instant recognition and video scan animation without waiting.

## 🏝️ Dynamic Island Expansion & Inline Layout
- **Proportional Expansion**: Dynamic Island inline HUDs, music activities, and face animations now expand dynamically to match the full notch camera width with balanced spacing.

## 🚪 Clean App Termination
- **Instant Quit**: Quitting NotchPulse now instantly closes all active overlays and background observers cleanly without hanging.


