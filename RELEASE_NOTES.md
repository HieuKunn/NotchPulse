# NotchPulse v4.7.4

## 🧸 New Teddy Bear Menu Icon & Reliable Controls
- **Cute Teddy Bear Menu Bar Icon**: Replaced the previous sparkle icon with a cute brown teddy bear SF symbol (`teddybear.fill`).
- **Fixed Shortcut Conflict**: Ensured only pure `Command+Q` (and NOT `Command+Shift+Q`) quits the application, preventing accidental triggers of macOS system log-out.
- **Clickable Settings Quit Button**: Fixed window background drag capturing so clicking "Quit app" in the Settings window header and sidebar terminates the app reliably.
- **Harmonized Open Notch & Dynamic Island Spacing**: Increased inner horizontal padding to 12pt so Calendar times and Music player controls stay comfortably inset from the curved corners.

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


