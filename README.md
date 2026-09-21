<div align="center">

  <!-- Sleek Dark Mode Header Banner (Clean Full-Bleed Logo, Caveat / Comic Font) -->
  <img src="docs/assets/banner.svg?v=3" width="100%" alt="NotchPulse Banner" />

  <br/><br/>

  <!-- Clean Badges -->
  <a href="https://github.com/HieuKunn/NotchPulse/releases"><img src="https://img.shields.io/github/v/release/HieuKunn/NotchPulse?color=007AFF&logo=apple&style=flat-square" alt="Release" /></a>
  <a href="https://github.com/HieuKunn/NotchPulse"><img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-blue?style=flat-square&logo=apple" alt="Platform" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?style=flat-square&logo=swift" alt="Swift" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" /></a>

</div>

<br/>

---

## Overview

**NotchPulse** transforms your MacBook camera cutout and external displays into a dynamic, responsive, and powerful workspace center. Engineered natively with Swift and SwiftUI, it integrates on-device biometric Face ID recognition, synced karaoke lyrics, interactive media widgets, drag-and-drop file shelf, and battery status right in your menu bar.

---

## Core Features

### 1. Seamless Face ID & Unified Morphing
- **Native Hardware Morphing**: Face ID expands directly out of the physical MacBook Notch or floating Dynamic Island, dynamically adapting corner radii and silhouettes without separate floating windows.
- **Lock Screen to Desktop Continuity**: Authenticates instantly upon screen wake and carries smoothly from the lock screen directly into your active desktop workspace.
- **macOS System Prompt Interception**: Automatically intercepts administrative privilege prompts and Touch ID requests, enabling hands-free face verification throughout macOS.
- **Privacy-Preserving On-Device AI**: Powered by on-device neural embeddings and Apple Vision framework with secure Keychain credential injection.

### 2. Dynamic Island & Notch Dual Architecture
- **Adaptive Display Modes**: Switch effortlessly between the native MacBook Notch profile and an iPhone-inspired floating Dynamic Island pill.
- **Multi-Monitor Awareness**: Automatically detects hardware cutouts on built-in Retina screens while rendering centered, symmetrical designs on external monitors.
- **Fluid Spring Physics**: Every transition is driven by custom interactive springs tuned for Apple ProMotion 120Hz displays (`response: 0.38`, `dampingFraction: 0.8`).

### 3. Lock Screen Media & Synced Lyrics
- **Live Karaoke Lyrics**: Real-time synchronized lyric stream with active line tracking, smooth autoscroll, and expanded full-screen reading mode.
- **Adaptive Lock Screen Widget**: Dedicated glassmorphic player accessible during playback from Spotify, Apple Music, and web browsers.
- **Smart Queue Retention**: The media card remains accessible while paused and automatically tucks away when audio sessions conclude.

### 4. Media Hub & Audio Visualizer
- Integrated transport controls, track scrubbing, volume adjustments, and responsive audio visualizers directly inside the notch.
- Intelligent graphics throttling pauses all GPU animation passes when playback is paused or hidden.

### 5. Notch Shelf & Quick Share
- Drag and drop files, images, and text onto the notch to temporarily stash them.
- Quick AirDrop forwarding, clipboard copying, and shelf pinning for multitasking.

### 6. Multi-Display Hardware HUD
- Fine-grained brightness and audio control across both built-in Apple Silicon panels and third-party external monitors via DDC.

### 7. Power Status & Battery HUD
- Real-time battery percentage tracking, charging connection notifications, and quick power status popover in the notch.

### 8. Resource-Efficient Engineering
- **Zero-Idle Overhead**: On-demand CoreML model loading saves memory at launch; background timers and sensors are strictly gated by visibility and active state.
- **Lightweight Footprint**: Native AppKit and SwiftUI implementation with no web-engine or Electron overhead.

---

<details>
<summary><b>🕹️ Interactive Gestures & Controls (Click to expand)</b></summary>
<br/>

| Interaction | Action | Description |
| :--- | :--- | :--- |
| **Hover on Notch** | Open / Expand | Smoothly expands the notch down to access media, shelf, and status |
| **Swipe Down** | Force Expand | Gesture downwards over the notch to quickly pull open the panel |
| **Swipe Up** | Quick Tuck | Gesture upwards to collapse the notch back into closed resting state |
| **Drag & Drop** | Shelf Stash | Drag files, images, or text URLs onto the notch to park them on the Shelf |
| **Hover on Lock** | Face ID Retry | Hover over the closed or failed indicator at the lock screen to trigger re-scan |

</details>

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer (including macOS 15 Sequoia)
- **Hardware**: Apple Silicon Mac (M1/M2/M3/M4) or Intel-based Mac
- **Camera Access**: Required for live camera previews and Face ID recognition

---

## Installation

### Option 1: Via Homebrew (Recommended)

Install directly via Homebrew Cask:
```bash
brew install --cask https://raw.githubusercontent.com/HieuKunn/NotchPulse/main/Casks/notchpulse.rb
```

Or tap the repository for easy future updates:
```bash
brew tap HieuKunn/notchpulse https://github.com/HieuKunn/NotchPulse
brew install --cask notchpulse
```

To update in the future via Homebrew:
```bash
brew upgrade --cask notchpulse
```

---

### Option 2: Direct Download

1. Download the latest `NotchPulse.dmg` package from [Releases](https://github.com/HieuKunn/NotchPulse/releases/latest).
2. Open `NotchPulse.dmg` and drag `NotchPulse.app` into your `/Applications` directory.
3. Launch **NotchPulse** from Spotlight or `/Applications`.

> [!NOTE]
> **First Launch Gatekeeper Note**  
> Because NotchPulse is self-signed, macOS may present an unrecognized developer warning on first launch. Right-click `NotchPulse.app`, select **Open**, and confirm. Alternatively, run the following command in Terminal:
> ```bash
> xattr -cr /Applications/NotchPulse.app
> ```

---

## Built With

- **Swift & SwiftUI** - Fluid declarative interfaces and 120Hz micro-animations
- **CoreML & Vision** - On-device facial detection and neural feature embeddings
- **AppKit & SkyLight** - Window management and lock screen integration
- **AVFoundation & CoreAudio** - Low-latency camera capture and audio spectrum analysis
- **Sparkle 2** - In-app auto-update framework with EdDSA cryptographic verification

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
