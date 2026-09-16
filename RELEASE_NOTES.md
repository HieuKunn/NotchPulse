# NotchPulse v3.8.6

## 🔒 Face ID Improvements
- **Lock Screen Unlocking Restored**: Fixed a critical bug where the Face ID UI was invisible on the Lock Screen due to a window ordering conflict, ensuring Face ID reliably drops down for unlocking your Mac.
- **System Authentication Prompts**: Face ID now elegantly drops down during system prompts (like Safari passwords, sudo, and System Settings) without stealing keyboard focus from the standard input field.

## 🔋 Battery Health & Charging
- **Battery Daemon Installation**: Fixed a bug where the app failed to guide the user to approve the Hardware SMC Battery Service (Battery Toolkit). The app now correctly opens System Settings and waits for approval, ensuring that charge limits (e.g., Stop at 80%) actually take effect.

## 🐛 Bug Fixes
- **Settings UI Stability**: Fixed a crash/blank screen issue when opening Settings, caused by macOS destroying the view hierarchy during activation policy transitions.
- **Auto-Update Stability**: Resolved an issue where Sparkle auto-update failed to install downloaded DMGs due to duplicate version tags.
