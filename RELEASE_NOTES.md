## 🚀 What's New in NotchPulse v5.2

### 🎵 Media Player & Browser Controls
- **Reliable Artwork Restoration**: Fixed an issue where album covers and app icons would disappear or fail to reload after pausing or leaving media idle in web browsers (Google Chrome, Arc, Safari, YouTube).
- **Responsive Browser Controls**: Next track, previous track, and play/pause buttons now respond instantly for web browser players even after long idle periods.
- **Sleep & Wake Auto-Reconnection**: Media player connections now seamlessly re-establish immediately when your Mac wakes from sleep.

### 🔒 Silky Smooth Face ID Unlock
- **Smooth Notch Retraction**: Resolved an issue where Face ID would abruptly vanish ("bụp") after recognizing your face. The success animation and checkmark now play cleanly and glide back into the Notch without stuttering.
- **Hover Conflict Prevention**: Prevented the desktop Notch from prematurely opening or jittering when your cursor is near the top of the screen right as Face ID unlocks.

### ⚡️ Battery & Performance Optimizations
- **Intelligent Background Polling**: Temporarily pauses clipboard monitoring while your screen is locked or asleep to conserve battery life.
- **Cleaner Memory Management**: Added proper teardown routines for video and animation resources, ensuring minimal RAM usage and zero idle battery drain.
