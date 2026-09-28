# NotchPulse v5.0.0 (Build 195) Release Notes

## 🚀 What's New in v5.0.0

### ✨ Pixel-Perfect Spotlight Tour & Interactive Cutout
- **Precise Highlight Framing**: The Spotlight Tour highlight cutout now dynamically computes the exact geometry of the open Notch and Dynamic Island, creating a smooth glowing ring that wraps cleanly around the active controls.
- **Top Bezel Integration**: On standard Mac notches, the highlight cleanly merges into the top bezel without stray lines across the menu bar or camera housing.
- **Adaptive Tooltip Cards**: Tour guidance cards now follow the height of active tabs (such as the full month calendar or clipboard history) and stay neatly positioned right below the notch.

### 🔄 Automatic Tab Switching During Onboarding
- **Interactive Feature Previews**: Navigating through the onboarding tour automatically switches to the corresponding tab—previewing Shelf drop targets, full-month calendar grids, live clipboard history, and media player layouts in real time.
- **Immediate Content Readiness**: Removed initial startup gates so the Home dashboard and quick controls render immediately on first launch.

### 🛡️ Non-Quitting App Lifecycle & Setup Safety
- **No Unexpected Termination**: Completing, closing, or skipping onboarding now safely dismisses the setup windows while keeping NotchPulse running and ready at the top of your screen.
- **Protected App Exit**: Quitting the application is strictly reserved for the Quit button in Settings and the Menu Bar status menu item, ensuring accidental exits never occur during initial setup.

### 🪶 Buttery-Smooth Notch Hover Animations
- **Spring-Animated Open & Close**: Restored fluid interactive spring animations for both opening on hover and auto-closing on mouse exit.
- **Conflict-Free Hover Tracking**: Cleaned up hover detection timers so mouse movements over the notch never stutter or snap shut abruptly.
