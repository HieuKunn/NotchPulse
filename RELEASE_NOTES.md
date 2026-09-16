# NotchPulse v3.8.6

## 🐛 Bug Fixes
- **Face ID Hotfix**: Reverted camera resolution scaling (from 1280 to 640) to fix an issue where the CoreML Anti-Spoofing AI would reject all faces due to interpolation artifacts, causing Face ID to freeze and fail to autofill passwords.
