# NotchPulse

A dynamic, unified Dynamic Island, Face ID authentication system, and productivity center for macOS.

[![Release](https://img.shields.io/github/v/release/HieuKunn/NotchPulse?color=007AFF&logo=apple)](https://github.com/HieuKunn/NotchPulse/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)](https://github.com/HieuKunn/NotchPulse)
[![Swift](https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Overview

NotchPulse transforms the MacBook camera cutout and external displays into a versatile, responsive workspace companion. Engineered natively with Swift and SwiftUI, it integrates on-device biometric Face ID authentication, synced karaoke lyrics, media controls, file stashing, and power management directly into your menu bar.

---

## Core Features

### Seamless Face ID & Unified Morphing
- **Native Hardware Morphing**: Face ID expands directly out of the physical MacBook Notch or floating Dynamic Island, dynamically adapting corner radii and silhouette without separate floating windows.
- **Lock Screen to Desktop Continuity**: Authenticates instantly upon screen wake and carries smoothly from the lock screen directly into your active desktop workspace.
- **macOS System Prompt Interception**: Automatically intercepts administrative privilege prompts and Touch ID requests, enabling hands-free face verification throughout macOS.
- **Privacy-Preserving On-Device AI**: Powered by on-device neural embeddings and Apple Vision framework with secure Keychain credential injection.

### Dynamic Island & Notch Dual Architecture
- **Adaptive Display Modes**: Switch effortlessly between the native MacBook Notch profile and an iPhone-inspired floating Dynamic Island pill.
- **Multi-Monitor Awareness**: Automatically detects hardware cutouts on built-in Retina screens while rendering centered, symmetrical designs on external monitors.
- **Fluid Spring Physics**: Every transition is driven by custom interactive springs tuned for Apple ProMotion 120Hz displays.

### Lock Screen Media & Synced Lyrics
- **Live Karaoke Lyrics**: Real-time synchronized lyric stream with active line tracking, smooth autoscroll, and expanded full-screen reading mode.
- **Adaptive Lock Screen Widget**: Dedicated glassmorphic player accessible during playback from Spotify, Apple Music, and web browsers.
- **Smart Queue Retention**: The media card remains accessible while paused and automatically tucks away when audio sessions conclude.

### Media Hub & Audio Visualizer
- Integrated transport controls, track scrubbing, volume adjustments, and responsive audio visualizers directly inside the notch.
- Intelligent graphics throttling pauses all GPU animation passes when playback is paused or hidden.

### Notch Shelf & Quick Share
- Drag and drop files, images, and text onto the notch to temporarily stash them.
- Quick AirDrop forwarding, clipboard copying, and shelf pinning for multitasking.

### Multi-Display Hardware HUD
- Fine-grained brightness and audio control across both built-in Apple Silicon panels and third-party external monitors via DDC.

### Smart Battery Health Management
- Direct communication with the Apple Silicon SMC to enforce custom charging limits (e.g., stopping at 80% to preserve battery lifespan).
- Supports instant full-charge bypass and power adapter disconnection without physical unplugging.

### Resource-Efficient Engineering
- **Zero-Idle Overhead**: On-demand CoreML model loading saves memory at launch; background timers and sensors are strictly gated by visibility and active state.
- **Lightweight Footprint**: Native AppKit and SwiftUI implementation with no web-engine or Electron overhead.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer (including macOS 15 Sequoia)
- **Hardware**: Apple Silicon Mac (M1/M2/M3/M4) or Intel-based Mac
- **Camera Access**: Required for live camera previews and Face ID recognition

---

## Installation

1. Download the latest `NotchPulse.dmg` package from [Releases](https://github.com/HieuKunn/NotchPulse/releases/latest).
2. Open `NotchPulse.dmg` and drag `NotchPulse.app` into your `/Applications` directory.
3. Launch **NotchPulse** from Spotlight or `/Applications`.

> **First Launch Note (Gatekeeper)**  
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
