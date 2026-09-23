# NotchPulse v4.7.3

## 🎯 Smart Display Routing & Normal Hover Separation
- **Precise Screen Routing**: Multi-display camera screen switching is now strictly reserved for active Face ID unlock sessions (such as on the lock screen or during onboarding).
- **Separated Notch Navigation**: Hovering over the Notch on secondary displays to view your Music, Calendar, or Shelf now stays on your active screen without unexpectedly switching to the camera screen.
- **Zero-Latency Face ID & Instant Quit**: Includes all instant hover scan animations and clean application exit improvements.

# NotchPulse v4.7 (Important Release)

## ⚡ Instant Face ID & Optimized Scanning Layout
- **Zero-Delay Activation**: Hovering over the Face ID notch now instantly triggers the Face ID scan animation without any artificial delays. It shows up immediately when you need it.
- **Perfect Fit Face ID**: Removed the excess horizontal black borders ("long sides") during the Face ID scanning animation. The drop-down overlay now perfectly hugs the video animation for a much cleaner and tighter look on both Notch and Dynamic Island styles.

## 🎚️ Smooth HUD Animations
- **Silky Smooth Volume & Brightness**: Adjusting system volume and display brightness now features beautifully smooth, fluid spring animations for both the Inline and Default HUD styles, replacing the old instant jumps.
- **Fluid Icon Transitions**: Speaker and brightness icons now smoothly morph and crossfade between states when levels change.

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


