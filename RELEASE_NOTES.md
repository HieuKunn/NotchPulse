# NotchPulse v4.7.6

## 🔒 Proportional 80% Face ID Scale & Fluid Animation
- **Custom 80% Scale Face ID**: Preserved the lightweight zero-delay Glance rendering architecture while sizing the Face ID scan animation to a refined 80% scale with silky-smooth breathing pulses.
- **Instant Response & Zero Delay**: Instantaneous CALayer appearance on hover, transitioning seamlessly to the green checkmark unlock animation upon verification.

# NotchPulse v4.7.5

## 🔒 Authentic Glance-Parity Face ID & Layout Polish
- **1:1 Glance Parity Face ID**: Rewrote the Face ID scanning layer to match Glance's authentic architecture with zero decode latency. Uses instant CALayer still rendering at rest and breathing pulse (`unlockstatic.png`), transitioning into the smooth green checkmark animation (`unlockanimation.mp4`) upon successful match.
- **Harmonized Open Margins**: Refined horizontal and bottom padding across Notch and Dynamic Island open states to ensure consistent, balanced borders without redundant spacing.
- **Clean Settings Sidebar**: Removed the redundant Quit button from the left navigation sidebar while keeping the dedicated "Quit app" button in the top-right header bar.

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


