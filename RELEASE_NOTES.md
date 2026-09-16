# NotchPulse v3.8.7

## 🔒 Face ID Improvements
- **Face Recognition Restored**: Reverted face matching threshold to proven v3.8.2 values (0.38/0.60) — the stricter values introduced in recent builds caused false negatives where enrolled faces were not recognized under normal lighting.
- **Lock Screen Password Entry Fixed**: After a Face ID scan fails, the overlay now becomes fully transparent to input so users can freely type their password or use Touch ID without any interference.
- **Lock Screen UI Visibility**: Ensured the Face ID drop-down reliably appears on the Lock Screen by using `orderFrontRegardless` to pierce macOS shielding layers.

## 🔋 Battery Health & Charging
- **Battery Daemon Installation**: Fixed a bug where the app failed to guide the user to approve the Hardware SMC Battery Service (Battery Toolkit). The app now correctly opens System Settings and waits for approval, ensuring that charge limits (e.g., Stop at 80%) actually take effect.

## 🐛 Bug Fixes
- **Settings UI Stability**: Fixed a crash/blank screen issue when opening Settings, caused by macOS destroying the view hierarchy during activation policy transitions.
- **Auto-Update Stability**: Resolved version numbering to ensure Sparkle auto-updates install successfully.
