# 🚨 IMPORTANT RELEASE — NotchPulse v5.0.0 (Build 177)

## 🚀 What's New & Major Highlights

- **🤝 Smart Shake-to-Open Shelf & Drag Targeting Fixes**:
  - **Multi-Screen ViewModel Target Reset**: Resetting targeting flags (`dragDetectorTargeting`, `dropZoneTargeting`, `generalDropTargeting`, `anyDropZoneTargeting`) now operates globally across all screen viewModels and automatically when switching tabs, preventing the Notch from unexpectedly snapping back to Shelf when navigating to other pages.
  - **Automatic Reversion to Home**: When closing the Notch or exiting hover after a shake, `currentView` cleanly reverts to `.home` unless pinned.
  - **Distance Threshold Protection**: Standard button clicks and stationary mouse taps (< 10pt movement) are strictly ignored by the drag detector.

- **✨ All-New Interactive Spotlight Onboarding Tour**:
  - **Hole-Punch Spotlight Overlay**: Dark background with elegant glowing white border highlighting active features step-by-step.
  - **Live UI Synchronization**: Each tour step automatically expands the Notch to the exact relevant tab and view (Home, Shelf, Full Month Calendar, Clipboard, etc.) so you can preview features in action.
  - **Spacious 75% Screen View for Shelf**: Step 2 (Smart Shake) provides a generous 75% screen width illuminated area with mouse pass-through, giving you plenty of room to select and drag files from Finder or your desktop.
  - **Seamless One-Click Face ID Setup**: Clicking "Yes" in the Face ID step now launches the native identity enrollment flow while temporarily minimizing the tour, returning seamlessly once completed.
  - **Guaranteed Zero-Quit Policy**: Dismissing or skipping onboarding or declining setup will never quit the application.

- **⚡ Automatic Notch Auto-Close**:
  - Smooth 250ms hover exit delay across all interactions. Releasing a file or moving away closes the Notch automatically.

- **🔒 Multi-Display Face ID Routing**:
  - Notch and Dynamic Island remain intact on external monitors while Face ID authorization smoothly drops down under your physical Mac camera screen.

- **📅 Revamped Calendar & Lunar Integration**:
  - Navigation controls (`<` and `>`) placed on the left, today indicator badge, and right-aligned Moon icon for Lunar date details, Can Chi, and Auspicious hours.
