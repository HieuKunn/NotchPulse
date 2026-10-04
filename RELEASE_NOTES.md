## 🚀 What's New in NotchPulse v5.2

### 🎵 Media Player & Browser Controls
- **Enhanced Browser Media Controls**: Fixed track switching (next & previous track) for web browsers (Google Chrome, Arc, Safari, Brave, Edge, Opera) on YouTube and web music players.
- **Smooth Play/Pause Execution**: Resolved an issue where clicking play would start audio for a split second before immediately pausing due to duplicate command triggers.
- **Reliable Artwork Restoration**: Fixed an issue where album covers and app icons would disappear or fail to reload after leaving media idle in web browsers.
- **Sleep & Wake Auto-Reconnection**: Media player connections now seamlessly re-establish immediately when your Mac wakes from sleep.

### 🔒 Silky Smooth Face ID Unlock
- **Smooth Notch Retraction**: Resolved an issue where Face ID would abruptly vanish after recognizing your face. The success animation and checkmark now play cleanly and glide back into the Notch without stuttering.
- **Hover Conflict Prevention**: Prevented the desktop Notch from prematurely opening or jittering when your cursor is near the top of the screen right as Face ID unlocks.

### ⚡️ Battery & Performance Optimizations
- **Intelligent Background Polling**: Temporarily pauses clipboard monitoring while your screen is locked or asleep to conserve battery life.
- **Cleaner Memory Management**: Added proper teardown routines for video and animation resources, ensuring minimal RAM usage and zero idle battery drain.
