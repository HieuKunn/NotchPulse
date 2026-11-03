## NotchPulse v5.5

### ⚡️ Instant Update Prompt

- **Proactive Release Notifications**: When a new NotchPulse update is published, NotchPulse immediately presents a clear update prompt in the foreground right away upon launch or wake. You can view what's new and update with a single click without having to manually check or dig through settings.

### 🔒 Reliable Lock Screen & Fluid Unlock

- **Lock Screen Media Reliability**: Resolved an issue where the lock screen media view could disappear unexpectedly during the system lock transition. Integrated unified SkyLight lock-space delegation and robust session supervision to ensure media stays visible and responsive on the lock screen.
- **Smooth Unlock Fade**: Lock Screen media (both full-screen immersive and compact card views) now fades away seamlessly in step with macOS's native lock screen unlock animation, eliminating visual stutter and desktop hitching.
- **Unobstructed Media Controls**: Full-screen lock screen media controls and artwork thumbnails receive mouse clicks freely without interference from Face ID.
- **Top-Bezel Hover Sensor**: In full-screen media mode, Face ID hover activation is strictly confined to the physical notch bezel directly around the camera.

### 🎵 Smart Multi-Media Registry & Session Continuity

- **Intelligent Media Fallback & Switching**: NotchPulse now maintains an active session registry across multiple media apps and browser tabs. If a current media session stops or closes, playback automatically reverts to the previous session; if that session finishes, it intelligently prioritizes whichever media was newest without dropping or destroying sessions.
- **Direct Playback Control Routing**: Media controls (play, pause, next, previous) target the specific active application or browser tab matching the current track title directly, eliminating cross-talk between background paused players and active audio.
- **Precise Artwork Resolution**: Media player prioritizes official, high-resolution album artwork from streaming catalogs (iTunes Store & Deezer) for web and desktop players alike. Browser background YouTube tabs are never mistakenly matched as cover art for unrelated music.

### 🍏 Native Settings Experience

- **Native Search Bar**: Integrated a rounded macOS-style search field directly in the sidebar for searching preferences across all supported languages.
- **Clean Sidebar Navigation**: Streamlined tab icons with clean accent-colored system symbols and preserved solid system background surfaces for optimal legibility.
- **Quick App Access**: Convenient shortcut to quit the application directly from the settings header.
