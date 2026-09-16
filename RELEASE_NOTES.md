# NotchPulse v3.8.5

## 🔒 Face ID Improvements
- **Focus Stealing Fixed**: Fixed an issue where the Face ID scan window could unexpectedly steal focus from system password prompts (e.g., in System Settings) when the NotchPulse Settings window was open, preventing users from typing their password.
- **Camera Permissions**: Resolved an issue where clicking "Grant Camera Permission" would only open System Settings without actually requesting macOS for permission, preventing NotchPulse from appearing in the Privacy & Security list.

## 🔋 Battery Health & Charging
- **Battery Daemon Installation**: Fixed a critical bug where the app failed to guide the user to approve the Hardware SMC Battery Service (Battery Toolkit) in macOS System Settings. The app now correctly opens System Settings and waits for approval, ensuring that charge limits (e.g., Stop at 80%) actually take effect.

## 🐛 Bug Fixes
- **Settings UI Stability**: Fixed a crash/blank screen issue when opening Settings, caused by macOS destroying the view hierarchy during activation policy transitions.
