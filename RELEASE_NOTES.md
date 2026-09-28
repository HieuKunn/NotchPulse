# NotchPulse v5.0.0 (Build 196) Release Notes

## 🚀 What's New in v5.0.0

### ✨ Dynamic Real-Time Spotlight Highlight & Setup Flow
- **Fluid Proportional Framing**: The Spotlight Tour highlight ring now directly animates its shape and size in sync with the live open notch height and width, providing a seamless glow regardless of customized sizes or tab expansions.
- **Continuous Face ID Tour Flow**: Completing or canceling the Face ID enrollment popup from the tour automatically returns to the spotlight tour and advances cleanly to the next step without dismissing the entire guide.
- **Top Bezel Integration**: On standard Mac notches, the highlight cleanly merges into the top bezel without stray lines across the menu bar or camera housing.

### 🤝 Smart Shake-to-Shelf & Enhanced Dragging
- **Reliable Left-Right Shake Gesture**: Upgraded drag detection to capture both global and local mouse drag events, allowing natural left-right shaking to instantly reveal the temporary Notch Shelf drop zone.
- **Broad File & Content Support**: Recognized all native macOS Finder file types, image URLs, and text drag pasteboards.

### 🪶 Buttery-Smooth Notch Hover & Open Transitions
- **Continuous Spring Physics**: Removed conflicting transition animations on notch expansion and collapse to ensure 60/120Hz ProMotion smoothness without frame stuttering.
- **Conflict-Free Hover Tracking**: Cleaned up hover detection timers so mouse movements over the notch never stutter or snap shut abruptly.
