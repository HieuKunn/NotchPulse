## NotchPulse v5.7 (Build 472) - Important Release

This release updates NotchPulse v5.7 with smoother 60Hz HUD transitions, faster Launchpad Home rendering, improved permission handling, and more reliable system Launchpad replacement.

### 🚀 What's New: Launchpad Home
- **Full-Screen Paged App Grid**: Brings back the classic multi-page application grid on macOS with mouse click-and-drag paging, two-finger trackpad swipes, folders, drag-and-drop organization, and instant keyboard search.
- **Full-Screen External Display Scaling**: Automatically adapts icon sizes, grid spacing, and margins proportionally so Launchpad fills large external monitors cleanly edge-to-edge.
- **Seamless System Replacement**: Intercepts built-in and external keyboard Launchpad keys, system shortcuts, Hot Corners, Dock triggers, and four-finger trackpad pinches to open Launchpad Home directly while keeping macOS's native overlay out of the way.
- **Cleaner Layout & Smoother 120Hz Rendering**: Removed the floating Done button (click empty space, tap an app, or press Escape to finish arranging) and eliminated frame drops while swiping pages or dragging icons.
- **Customizable Grid & Quick Access**: Choose your grid columns and rows, icon size, wallpaper background style, and optional Hot Corner trigger in Settings > Productivity > Launchpad, or open anytime via the Notch button, menu bar icon, or Shift+Command+L.

### 🎚️ Smoother Notch & Inline HUDs
- **Fluid Volume & Brightness Holds**: Holding down volume, display brightness, or keyboard backlight keys now glides smoothly across the HUD slider instead of stepping jerkily.
- **Reliable HUD Activation**: Improved Accessibility checks so custom Volume and Brightness notch HUDs connect automatically as soon as permission is granted without showing overlapping system overlays.

### ✨ Settings & Permissions Improvements
- **No Unwanted Startup Prompts**: Fixed an issue where Accessibility and Bluetooth permission dialogs could pop up unexpectedly right at app launch before you enable those features.
- **Native Sidebar Search & Unified Appearance**: Switched to macOS's native sidebar search bar, synchronized the Settings window with Light/Dark Mode, and kept tab switching responsive.

### 🐛 Bug Fixes
- **Face ID Setup in Light Mode**: Fixed an issue where step titles and password prompts blended into the dark notch background in Light Mode, ensuring crisp contrast across themes.
