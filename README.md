# NotchPulse 🚀

> **A dynamic, fluid Dynamic Island & Productivity Center for macOS.**  
> *Crafted with Swift & SwiftUI by [HieuKunn](https://github.com/HieuKunn)*

[![Release](https://img.shields.io/github/v/release/HieuKunn/NotchPulse?color=007AFF&logo=apple)](https://github.com/HieuKunn/NotchPulse/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)](https://github.com/HieuKunn/NotchPulse)
[![Swift](https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## ✨ Key Features & What's New in v2.9.3.5

- 🚀 **Seamless Auto-Update (Sparkle 2 & GitHub Releases)**:
  - Built-in automatic update engine with cryptographic EdDSA verification. Download and upgrade directly within the app without manually fetching `.dmg` files.
- 📅 **Fluid Calendar & Extended Date Glance**: 
  - Comprehensive click target covering the entire date cell for foolproof date switching.
  - Smooth multi-day mouse wheel and trackpad navigation across a 90-day interactive calendar strip.
- 👤 **Face ID with Lightweight Neural Network (CoreML FaceNet)**: 
  - Real-time facial embedding extraction (512-dimensional vectors) using **CoreML MobileFaceNet** accelerated by Apple Neural Engine (ANE) and Metal GPU.
  - Ultra-fast recognition (0.2s – 0.4s) on screen wake with Cosine Distance verification and consecutive multi-frame anti-spoofing.
  - Native pop-down Face ID glyph animation extending naturally below the MacBook notch / Dynamic Island.
  - Secure automatic unlock powered by credentials stored inside macOS Keychain.
- 📱 **Lock Screen Media & Fullscreen Karaoke Lyrics**: 
  - Adaptive 2-column glassmorphism widget hovering seamlessly over the macOS lock screen with smooth rounded borders.
  - Real-time **Synced Karaoke Lyrics** with fullscreen immersive mode and dedicated media transport controls (Play/Pause, Next/Previous, Shuffle, Repeat).
- 🏝️ **MacBook Notch ⇋ Dynamic Island Seamless Switcher**: 
  - Switch instantly between the classic MacBook Notch and a floating iPhone-style Dynamic Island pill with live interactive width slider preview.
- 🎵 **Adaptive Media Hub**: 
  - Seamless playback controls, audio visualizer wave, scrubber, and volume integration for Spotify, Apple Music, YouTube, and web browsers.
- 📁 **Notch Shelf & Quick Share**: 
  - Drag, drop, stash, and share files directly through the top notch with instant AirDrop and clipboard support.
- ☀️ **Intelligent Multi-Display Brightness & Volume HUD**: 
  - Automatically detects built-in MacBook Retina displays vs. external monitors, controlling hardware and software brightness independently.
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
