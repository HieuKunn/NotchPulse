## NotchPulse v5.5 (Build 452)

### 🎵 Real-Time Artwork & Universal Media Synchronization
- **Background Artwork Synchronization**: Album covers and video thumbnails now resolve immediately in the background without needing to hover or open the notch first.
- **Zero Artwork Cross-Bleed**: Solved artwork desynchronization when switching between multiple media apps or browser tabs in the background. Previous track thumbnails and in-flight resolution requests are immediately purged upon session change.
- **Lightning-Fast Browser YouTube Thumbnails**: Upgraded browser media extraction (Arc, Safari, Chrome, Brave, Edge) to use high-speed non-blocking tab inspection with a 2-second safety timeout, preventing freezes.
- **Universal Browser & Media Controls**: Overhauled playback controls (Play/Pause, Next, Previous, and seeking) across all web browsers and native players matching Apple's native Now Playing routing.

### 🔒 Face ID Unlock & Security
- **Reliable Password Auto-Fill**: Resolved an unlock sequencing race condition so your stored password is typed immediately and reliably upon face recognition.
- **Non-Intrusive Permissions**: Eliminated bulk startup permission dialogs on app updates; permissions are now requested only when onboarding or configuring features.
