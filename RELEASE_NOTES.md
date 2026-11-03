## NotchPulse v5.5

### ⚡️ Instant Update Prompt & Stability

- **Proactive Release Notifications**: When a new NotchPulse update is published, NotchPulse immediately presents a clear update prompt in the foreground right away upon launch or wake. You can view what's new and update with a single click without having to manually check or dig through settings.
- **Startup Reliability**: Fixed an issue where the application could terminate unexpectedly upon launch while initializing media services.

### 🔒 Reliable Lock Screen & Fluid Unlock

- **Lock Screen Media Visibility**: Resolved an issue where the lock screen media player could get trapped beneath the lock screen layer. The media player is now exclusively delegated to the native lock-space layer with progressive re-assertions and synchronous rasterization, ensuring it remains immediately visible and responsive when the screen locks.
- **Smooth Unlock Fade**: Lock Screen media (both full-screen immersive and compact card views) now fades away seamlessly in step with macOS's native lock screen unlock animation, eliminating visual stutter and desktop hitching.
- **Unobstructed Media Controls**: Full-screen lock screen media controls and artwork thumbnails receive mouse clicks freely without interference from Face ID.
- **Top-Bezel Hover Sensor**: In full-screen media mode, Face ID hover activation is strictly confined to the physical notch bezel directly around the camera.

### 🎵 Smart Multi-Media Registry & Session Continuity

- **Intelligent Media Fallback & Switching**: NotchPulse now maintains an active session registry across multiple media apps and browser tabs. If a current media session stops or closes, playback automatically reverts to the previous session; if that session finishes, it intelligently prioritizes whichever media was newest without dropping or destroying sessions.
- **Direct Playback Control Routing**: Media controls (play, pause, next, previous) target the specific active application or browser tab matching the current track title directly, eliminating cross-talk between background paused players and active audio.
- **Precise Artwork Resolution**: Media player prioritizes official, high-resolution album artwork from streaming catalogs (iTunes Store & Deezer) for web and desktop players alike. Browser background YouTube tabs are never mistakenly matched as cover art for unrelated music.

### 🍏 Native Settings Experience

- **Native AppKit Search Field**: Integrated macOS's genuine AppKit search field (`NSSearchField`) with native rounded bezel, depth shadow, clear button, and system focus rings for searching preferences across all supported languages.
- **Vibrant Squircle Badges**: Restored Apple System Settings-style gradient squircle icon badges across all settings categories for seamless visual harmony with macOS.
- **Quick App Access**: Convenient shortcut to quit the application directly from the settings header.
