## NotchPulse v5.7 (Build 473) - Important Release

This release updates NotchPulse v5.7 with smoother volume adjustments, comprehensive Launchpad Home editing gestures, permission and keychain reliability improvements, and macOS Tahoe native styling across Settings.

### 🚀 Launchpad Home: Natural Editing & Organization
- **Intuitive Touch & Hold to Edit**: Long-press any app or folder icon to enter jiggle mode with subtle haptic feedback, matching iOS, iPadOS, and classic macOS Launchpad without requiring extra toolbar edit buttons.
- **Continuous Press-and-Drag**: Seamlessly drag icons to reorder, move across pages, or group them into folders without having to release your finger after holding.
- **Reliable Folder Navigation**: Fixed an issue where clicking on a folder tile closed Launchpad back to the desktop, allowing folders to open and close smoothly.
- **Classic Folder Thumbnail Alignment**: Icons inside folder preview thumbnails are now aligned cleanly from the top-left rather than floating centered in the box.
- **Inline Folder Renaming**: Easily rename any folder with an updated title field and quick clear button when in edit mode.
- **Fluid Folder Extraction**: Drag an app out of an open folder to place it back on the main grid or merge it into another folder with accurate placement indicators.

### 🎚️ Butter-Smooth Volume Adjustments
- **Zero-Stutter Volume Steps**: Offloaded feedback sound preloading and CoreAudio HAL communication off the main thread and event tap callback, making volume adjustments and 60Hz holds just as responsive and fluid as display brightness.
- **Optimistic Volume Updates**: Volume changes display immediately on the HUD while hardware changes are smoothly coalesced in the background.

### ✨ Native macOS Tahoe Settings & Search
- **Native Liquid Glass UI**: Switched the Settings window to AppKit's native hosting controller so sidebar vibrancy, toggles, and search fields render cleanly with macOS Tahoe styling.
- **Pure Apple Search Bar**: Launchpad Home features a refined, native glass search capsule without redundant control icons.

### 🔒 Permissions & Security Fixes
- **Robust System Access**: Resolved permission verification checks for Accessibility, Bluetooth, Calendars, and Reminders to prevent repetitive system authorization prompts.
- **Face ID Keychain Migration**: Added safe Keychain migration handling to prevent lockout or repeated password requests after app updates.
