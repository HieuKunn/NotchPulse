## 🚀 What's New in NotchPulse v5.4

### ⚡️ GPU-Accelerated Fluid Animations & Micro-Stutter Elimination
- **GPU Layer Compositing**: Inner contents, music player controls, and calendar cards are now grouped into dedicated Metal texture layers. When the Notch or Dynamic Island expands, motion scaling and fades are composited directly on the GPU, completely eliminating CPU layout thrashing and delivering silky-smooth 120 FPS ProMotion animations.
- **Streamlined Spring Physics**: Consolidated concurrent spring animation solvers down to primary state drivers, cutting redundant layout passes while preserving 100% natural, continuous Apple Dynamic Island spring dynamics.
- **Intelligent Artwork Downsampling**: High-resolution album artwork is now processed asynchronously on background threads and scaled to crisp Retina thumbnails, preventing memory and decoding spikes when launching or switching tracks.
- **Choreographed Natural Staging**: Refined inner content appearance with a subtle scale and smooth opacity transition, ensuring zero visual squishing or hitching during rapid expansions.
- **Hardware-Driven Music Visualizer**: Upgraded the mini audio spectrum to pure Core Animation running entirely on the GPU compositor, eliminating periodic background timers and bringing main-thread CPU usage during playback down to 0%.
- **Harmonious Audio Spectrum Rhythm**: Fine-tuned wave frequency and easing curves so the mini visualizer dances gently with natural music dynamics rather than flickering erratically.
- **Orphaned Layout Cleanup**: Removed redundant geometry tracking bindings, eliminating unnecessary SwiftUI layout passes during notch transitions.

### 🔒 Rock-Solid Face ID & Instant Recognition
- **Glance-Aligned Architecture**: Aligned the Face ID camera capture pipeline, scoring thresholds, and liveness validation strictly with Glance's battle-tested engine, ensuring instant and 100% dependable recognition on every lock screen wake.

### 📋 Clipboard History & Image Capture Reliability
- **Ultra-Responsive Polling**: Accelerated clipboard polling to 150ms with instant change detection, ensuring continuous copying of multiple items or rapid screenshots captures every item without omission.
- **Multi-Format Image Support**: Expanded native clipboard capture for WebP, HEIC, GIF, and direct image files copied from Finder.
- **Image Priority Detection**: When copying items containing both rich image data and file paths, NotchPulse intelligently prioritizes the graphic image preview for immediate visual reuse.

### 🖱️ Bulletproof Notch Hover & Expansion Lifecycle
- **Reliable Hover Re-open**: Resolved an issue where closing the Notch after expanding and unpinning the Calendar or switching tabs could prevent subsequent hover gestures from expanding the Notch.
- **Synchronized State Teardown**: Enhanced tab switching and closure lifecycles across Calendar, Shelf, and Stats to automatically reset stale pin and expansion flags, ensuring seamless 100% reliable hover interactions.

### 🛡️ Notch Position Stability & Auto-Update Polish
- **Rock-Solid Bezel Anchoring**: Eliminated all potential scenarios where the Notch could drift, drop downwards, or center in the middle of your screen after checking for updates or waking from sleep.
- **Elevated Updater Dialogs**: Update notifications and alerts stay firmly elevated in the foreground over the settings window without getting lost or hidden underneath.
