# 🚀 NotchPulse v3.5.5

Welcome to NotchPulse **v3.5.5**! This release brings a major overhaul to the Lock Screen Face ID experience with authentic Glance-style drop-down animations, precise hover tracking, and real-time synchronized lyrics for full-screen media.

---

### 🚀 What's New
- **Authentic Large Drop-Down Notch**: Experience a fluid drop-down notch on the lock screen with smooth continuous rounded corners and an Apple-inspired Face ID scan-to-green-checkmark animation.
- **Independent AppleFaceIDGlyphView Component**: Cleanly modularized the Apple Face ID glyph component for seamless integration in settings and lock screen overlays.

### 🔒 Face ID Improvements
- **Restricted Hover Trigger Area**: Restricted hover detection strictly to the top physical notch area (210×38 pt), preventing accidental scans when moving the mouse below the notch.
- **Seamless Video Silhouette Clipping**: Applied direct `NotchShape` and continuous corner layer masks to the video player, eliminating rectangular background box artifacts.

### 🎵 Lock Screen Media
- **Real-Time Lyrics Sync & Auto-Scroll**: Fixed lock screen full-screen lyrics synchronization. Active lyric lines now immediately highlight with bold typography, dynamic glow effects, and auto-scroll smoothly as playback progresses.

---

Thank you for using **NotchPulse**!
