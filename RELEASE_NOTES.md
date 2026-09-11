# 🚀 NotchPulse v3.5.7

Welcome to NotchPulse **v3.5.7**! This release resolves camera wake activation and makes lock screen Face ID unlock instant, reliable, and lag-free.

---

### 🔒 Face ID & Lock Screen Improvements
- **Seamless Camera Wake Trigger**: Fixed an issue where the camera would not activate on wake. Streamlined the Keychain Vault encryption layer so Face ID scans immediately upon display power-on or hover.
- **Lag-Free Native Unlock Injection**: Eliminated background AppleScript bottlenecks and added strict concurrency locking during password typing, ensuring smooth, instant macOS lock screen unlocking without overlapping input.

### 🎨 UI & Media Fixes
- **Notch Hover Area**: Refined the hover hitbox on the lock screen so the Face ID dropdown only expands when hovering precisely over the physical notch, preventing accidental early triggers.
- **Full-Screen Lyrics Sync**: Rebuilt the karaoke rendering engine for full-screen lock screen media to ensure real-time highlighted lyrics scroll smoothly without glitches.
- **Face ID Notch Scaling**: Reduced the Face ID scanning animation size and widened the surrounding notch boundary to ensure the entire Face ID glyph is fully visible without clipping.

---

Thank you for using **NotchPulse**!
