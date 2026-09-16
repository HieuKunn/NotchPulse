# NotchPulse v3.8.8

## 🐛 Bug Fixes
- **Settings UI**: Resolved a critical issue where the Settings window would appear as a blank gray screen upon reopening. This was caused by macOS destroying the window's backing layer when the app transitions to a background accessory. The Settings interface is now explicitly re-rendered on every open.
