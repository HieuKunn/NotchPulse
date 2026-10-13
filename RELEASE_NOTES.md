## 🚀 What's New in NotchPulse v5.4

### 🔋 Ultra-Low Idle CPU & Memory Footprint
- **Near-Zero Background Overhead**: Background CPU usage has been reduced dramatically from 5–10% down to under 0.5%, giving your battery life and processing power back to your workflow.
- **Over 80–100MB Memory Saved**: The Face ID recognition model now sleeps completely in the background during normal desktop usage, waking up instantaneously in parallel only when your screen locks or an authentication dialog appears.
- **Throttled Media State Rendering**: Media playback and position tracking now render smoothly with 90% fewer redundant screen redraws.

### ⚡️ Activity Monitor Parity & Symmetrical Dashboard
- **True Real-Time RAM Metrics**: Memory consumption now precisely reflects Apple's official physical footprint standard, displaying exact real-time RAM usage without compressed memory distortion.
- **Full Process Names**: App and helper names are now displayed completely without abbreviation or cut-off text.
- **Instant Top Apps Inspection**: The top resource-consuming apps now appear instantly the moment you expand the dashboard with zero kernel delay or system stalls.
- **Symmetrical 3-Column Layout**: Perfectly balanced CPU, RAM, and GPU dashboard cards (33% each) with responsive typography, giving your GPU model name extra breathing room while keeping all labels clean and legible.

### ❄️ Interactive Thermal & Fan Controls
- **Dedicated Native Fan Helper**: NotchPulse now features its own native helper daemon for direct Apple Silicon SMC fan speed control without third-party app dependencies.
- **Zero-Prompt Fan Activation**: If you've enrolled your master password with Face ID, fan control installs and activates automatically in the background with zero extra prompts or popups.
- **70/30 Fan & Temperature Card**: Enjoy a dedicated thermal card featuring a 70/30 split between interactive fan controls and a real-time hardware temperature gauge.
- **One-Click Fan Profiles**: Instantly switch between Silent, Auto, Full Speed, and custom fan percentages directly from the Notch.

### 🎵 Refined Lock Screen Media Player
- **Clean Border & Zero Blurred Artifacts**: Eliminated unsightly diffuse shadows and window margins around the compact player for a clean, seamless card presentation.
- **Unified Control Button Icons**: Synchronized icon color fidelity across all media buttons (Shuffle, Previous, Play/Pause, Next, Repeat, Volume, Favorite, and Seek).
- **Reactive Dark & Light Mode Appearance**: Card background, borders, text, and icons dynamically transition between pure white and dark gray in sync with macOS system appearance.

### 🔒 Smarter Face ID Biometrics & Instant Verification
- **Seamless Parallel Pre-Warming**: AI facial models warm up concurrently while camera hardware starts up, ensuring instant recognition without perceptible wait times.
- **Single-Prompt Authorization**: System and password prompts verify your face once without annoying camera cycling.
- **Instant Wrong Face Rejection**: Quickly detects and signals unrecognized faces within a fraction of a second instead of waiting until timeout.
- **Seamless Sleep Recovery**: Camera connections now reliably re-negotiate upon waking from sleep so Face ID is always ready.

### 📋 Instant Event-Driven Clipboard
- **Lightning-Fast Copying**: Captures copy and cut actions (`Cmd + C` / `Cmd + X`) instantaneously without missing rapid copy sequences, while drawing 0% CPU in the background.
