# NotchPulse v4.6.1 (Build 99)

## 📁 Enhanced File Shelf & Drag Detection
- **Dynamic Drag Hover Detection**: The shelf now accurately opens as soon as you drag a file into the expanded detection zone (10–120px) and smoothly remains open as you move anywhere across the shelf to drop your files.
- **Reliable Exit Handling**: Moving a file away from the notch gracefully debounces before closing, eliminating frustrating premature closures.
- **Window Move Protection**: Moving ordinary application windows near the top edge is safely ignored and will never accidentally open the file shelf.

## ⚡ Instant App Exit
- **Zero-Lag App Termination**: Cleaned up background observers and connection hooks so NotchPulse quits instantly and cleanly when clicking "Quit" without hanging or requiring Force Quit.

## 🎛️ Refined Inline & Dropdown HUDs
- **Seamless Notch HUDs**: Volume and brightness indicators fluidly embrace the notch outline without any clipping or distortion.
- **Reliable Startup Activation**: Volume and media HUD replacements stay active automatically upon launching NotchPulse without requiring manual toggle resets.

## 🏝️ Dynamic Island Mode Stability
- **Smoother Floating Pill**: Fixed sizing and aspect ratio issues when running in Dynamic Island mode for external screens.
- **Crash Prevention**: Resolved unexpected termination and memory issues when switching interface modes.

## 🔒 Face ID Display Intelligence
- **Precise Screen Placement**: Camera enrollment and Face ID setup reliably remain under the camera display instead of defaulting away.

