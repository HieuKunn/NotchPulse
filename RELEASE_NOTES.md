## 🚀 What's New in NotchPulse v5.4

### 🔒 Rock-Solid Face ID Unlock & Wake Reliability
- **Glance-Aligned Architecture**: Aligned the camera capture lifecycle, wake evaluation, and lock screen monitoring directly with the proven Glance architecture. Face ID now triggers instantaneously and reliably on lock screen wake, even after prolonged sleep or closed-lid sessions.
- **Deep Sleep Recovery**: Completely eliminated camera session stalls and permission edge cases when opening your Mac lid after extended sleep, ensuring you are recognized and unlocked without delay.

### 🎵 Persistent Media Album Art & Seamless Playback
- **Persistent Artwork Display**: Resolved an issue where album artwork and video thumbnails could disappear or render blank after waking your Mac from sleep. NotchPulse now securely caches and seamlessly refreshes media artwork across sleep cycles.
- **Auto-Reconnecting Media Stream**: Enhanced the background media listener to instantly re-establish connections to Apple Music, Spotify, and system media players upon wake, keeping track titles, playback controls, and artwork perfectly in sync.

### ⚡️ GPU-Accelerated Fluid Animations & Micro-Stutter Elimination
- **GPU Layer Compositing**: Inner contents, music player controls, and calendar cards are grouped into dedicated Metal texture layers. When the Notch or Dynamic Island expands, motion scaling and fades are composited directly on the GPU, completely eliminating layout thrashing and delivering silky-smooth 120 FPS ProMotion animations.
- **Streamlined Spring Physics**: Consolidated concurrent spring animation solvers down to primary state drivers, cutting redundant layout passes while preserving 100% natural, continuous Apple Dynamic Island spring dynamics.
- **Hardware-Driven Music Visualizer**: Upgraded the mini audio spectrum to pure Core Animation running entirely on the GPU compositor, eliminating periodic background timers and bringing main-thread CPU usage during playback down to 0%.

### 📋 Clipboard History & Image Capture Reliability
- **Ultra-Responsive Polling**: Accelerated clipboard polling to 150ms with instant change detection, ensuring continuous copying of multiple items or rapid screenshots captures every item without omission.
- **Multi-Format Image Support**: Expanded native clipboard capture for WebP, HEIC, GIF, and direct image files copied from Finder.
- **Image Priority Detection**: When copying items containing both rich image data and file paths, NotchPulse intelligently prioritizes the graphic image preview for immediate visual reuse.

### 🖱️ Bulletproof Notch Hover & Expansion Lifecycle
- **Reliable Hover Re-open**: Resolved an issue where closing the Notch after expanding and unpinning the Calendar or switching tabs could prevent subsequent hover gestures from expanding the Notch.
- **Rock-Solid Bezel Anchoring**: Eliminated all potential scenarios where the Notch could drift, drop downwards, or center in the middle of your screen after checking for updates or waking from sleep.
