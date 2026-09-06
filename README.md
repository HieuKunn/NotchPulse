# NotchPulse 🚀

> **A dynamic, fluid Dynamic Island & Productivity Center for macOS.**
> *Crafted with Swift & SwiftUI by [HieuKunn](https://github.com/HieuKunn)*

THANK YOU SO MUCH FOR SUPPORTING NOTCHPULSE!

---

## ✨ What's New in NotchPulse v2.0 🚀

- 👤 **Zero-Overhead Face ID Unlock**: Fast face recognition (0.2s - 0.4s) accelerated by Apple Neural Engine (NPU) upon screen wake. Automatically stops after 1.5s (0% idle CPU/RAM usage). Supports **Multi-Face ID** and Alternative Appearances.
- 📱 **iPhone-Style Lock Screen Media Player**: 2-column glassmorphism widget displayed over the macOS lock screen via `SkyLightWindow`. Includes large album art, live sound waves, and real-time **Synced Karaoke Lyrics**.
- 🏝️ **MacBook Notch ⇋ Dynamic Island Selector**: Switch instantly between the classic MacBook Notch and a floating iPhone-style Dynamic Island pill with customizable top spacing.
- 🎵 **Adaptive Media Hub**: Seamless playback controls, scrubber, shuffle, repeat, and volume integration for Spotify, Apple Music, YouTube, and web browsers.
- 📅 **Integrated Calendar Widget**: Glance at your schedule with an instant-response day wheel, fixed ergonomic widget layout, and smooth date switching.
- ☀️ **Intelligent Multi-Display Brightness HUD**: Automatically detects built-in MacBook Retina displays vs. external monitors, controlling hardware and software brightness independently.
- 📁 **Notch Shelf & Quick Share**: Drag, drop, stash, and share files directly through the top notch with instant AirDrop support.
- ⚡ **Lightweight & Battery Efficient**: Built with pure native AppKit and SwiftUI for smooth 120Hz ProMotion performance without draining your battery.

---

## 💻 System Requirements

- **macOS Sonoma (14.0)** or **macOS Sequoia (15.0+)**
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

---

## 📥 Installation

1. Go to the [Releases](https://github.com/HieuKunn/NotchPulse/releases) section.
2. Download **`NotchPulse.dmg`**.
3. Open the `.dmg` and drag **`NotchPulse.app`** into your **`/Applications`** folder.
4. Launch the app from `/Applications` or Spotlight.

> [!TIP]
> **First Launch Notice (Gatekeeper)**:
> Since NotchPulse is self-signed (ad-hoc), macOS may prompt an alert on first open.
> Simply right-click (or Control-click) `NotchPulse.app` in `/Applications` and select **Open**, or run the following command once in Terminal:
> ```bash
> xattr -cr /Applications/NotchPulse.app
> ```

---

## 🛠️ Built With

- **Swift 6 & SwiftUI**
- **AppKit & CoreAudio**
- **Combine & CoreGraphics**

---

## 📄 License

This project is licensed under the MIT License.


