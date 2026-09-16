# 🚀 NotchPulse v3.8.5

Welcome to NotchPulse **v3.8.5**! This update focuses strictly on Face ID reliability by fine-tuning the biometric matching engine and fixing UI smoothness issues.

---

### 🔒 Face ID & Security Fixes
- **Improved Face ID Detection Range**: Upgraded the camera resolution from 640p to 1280p, allowing the Face ID engine to easily recognize you from a much further distance (similar to Glance).
- **Fine-tuned Anti-Spoofing AI**: Adjusted the Liveness AI threshold from `50%` to `35%`. This ensures that Face ID is significantly easier and faster to scan your face in low light or complex angles, while still remaining completely secure against photos and video replays.
- **Fixed Scanning Timeout (Streak Threshold)**: Resolved an issue where Face ID would give up and show "Face Not Recognized" after just 0.2 seconds if it temporarily lost track of your face. You can now scan your face comfortably without it failing instantly.

---

### 🐛 Bug Fixes
- **Fixed Settings UI Glitch**: Fixed a major bug on macOS where the Settings window (including Face ID settings) would sometimes open as a completely blank white screen and required closing and reopening to fix. Settings now opens instantly and reliably every time.

---

*Note: Due to the underlying Face ID engine updates, if you experience any issues, please delete your old face and scan a new one in Settings -> Face ID Unlock.*

Thank you for using **NotchPulse**!
