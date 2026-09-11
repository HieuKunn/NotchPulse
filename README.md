# NotchPulse 🚀

> **A dynamic, fluid Dynamic Island & Productivity Center for macOS.**  
> *Crafted with Swift & SwiftUI by [HieuKunn](https://github.com/HieuKunn)*

[![Release](https://img.shields.io/github/v/release/HieuKunn/NotchPulse?color=007AFF&logo=apple)](https://github.com/HieuKunn/NotchPulse/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)](https://github.com/HieuKunn/NotchPulse)
[![Swift](https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## ✨ Key Features & What's New (v3.5+)

- 🔒 **Face ID Lock Screen Unlock & Dynamic Dropdown**:
  - Seamless Face ID unlocking for macOS upon screen wake or returning to the Lock Screen.
  - Native animated Face ID scanning glyph & fluid drop-notch animation morphing instantly into a green checkmark on success.
  - On-device real-time facial recognition using **CoreML MobileFaceNet** (512-dimensional embeddings) with secure Keychain credential injection.
  - Precise hover detection matching physical notch bounds to prevent unwanted triggering.
- 📱 **Lock Screen Media & Synced Live Lyrics**:
  - Adaptive glassmorphic Lock Screen widget for active media playback (Spotify, Apple Music, YouTube, Web Browsers).
  - Real-time **Synced Karaoke Lyrics** with automatic active line highlighting, synchronized autoscroll, and expanded full-screen lyrics mode.
  - Media transport controls (Play/Pause, Next/Previous).
- 🏝️ **MacBook Notch ⇋ Dynamic Island Seamless Switcher**: 
  - Switch instantly between the classic MacBook Notch and a floating iPhone-style Dynamic Island pill with customizable width and preview.
- 🚀 **Seamless Auto-Update (Sparkle 2 & GitHub Releases)**:
  - Built-in automatic update engine with cryptographic EdDSA verification. Download and upgrade directly within the app.
- 📅 **Fluid Calendar & Extended Date Glance**: 
  - Comprehensive date switching with multi-day navigation across an interactive calendar strip.
- 🎵 **Adaptive Media Hub**: 
  - Playback controls, audio visualizer wave, scrubber, and volume integration directly in the notch.
- 📁 **Notch Shelf & Quick Share**: 
  - Drag, drop, stash, and share files directly through the top notch with instant AirDrop and clipboard support.
- ☀️ **Intelligent Multi-Display Brightness & Volume HUD**: 
  - Hardware and software brightness & volume control for built-in Retina displays and external monitors.
- ⚡ **Zero-Overhead & Battery Efficient**: 
  - Built with pure native AppKit and SwiftUI for smooth 120Hz ProMotion performance without background battery drain.

---

## 💻 System Requirements

- **macOS Sonoma (14.0)** or **macOS Sequoia (15.0+)**
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

---

## 📥 Installation

1. Download the latest **`NotchPulse.dmg`** from [Releases](https://github.com/HieuKunn/NotchPulse/releases/latest).
2. Open the `.dmg` installer and drag **`NotchPulse.app`** into your **`/Applications`** folder.
3. Launch the app from `/Applications` or Spotlight.

> [!TIP]
> **First Launch Notice (Gatekeeper)**:  
> Since NotchPulse is self-signed (ad-hoc), macOS may show an unidentified developer prompt on the first launch.  
> Simply right-click (or Control-click) `NotchPulse.app` in `/Applications` and choose **Open**, or run this command once in Terminal:
> ```bash
> xattr -cr /Applications/NotchPulse.app
> ```

---

## 🛠️ Built With

- **Swift & SwiftUI** — Declarative UI and fluid 120Hz animations
- **CoreML & Apple Vision** — On-device face detection and FaceNet 512D embeddings
- **AppKit & SkyLight** — Window level management for macOS lock screen overlays
- **AVFoundation & CoreAudio** — Camera capture and low-latency audio processing

---

## 📄 License

This project is licensed under the MIT License.
