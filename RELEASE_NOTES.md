# NotchPulse v4.6.1 (Build 101)

## 🏝️ Dynamic Island Complete Feature Parity
- **Music Live Activity in Dynamic Island**: When playing music, Dynamic Island now smoothly expands to display your album artwork on the left and an animated audio equalizer on the right, perfectly centered and beautifully styled like iOS.
- **Identical Open & Close Mechanics**: Moving your mouse cursor to the top edge of the screen or hovering directly over the island smoothly opens NotchPulse with tabs (Home, Shelf, Stats), and moving your mouse away gracefully closes it.
- **Click & Gesture Controls**: Click to open, tap the center header to close, swipe down with two fingers to expand, and swipe up to collapse.
- **Inline Volume & Brightness HUDs**: Volume and brightness sliders now expand the Dynamic Island with clear icons, draggable level bars, and percentage indicators without distortion or clipping.
- **Seamless File Shelf Dragging**: Dragging any file over the Dynamic Island instantly expands the shelf tab with dynamic detection padding.

## 📁 Enhanced File Shelf & Drag Detection
- **Dynamic Drag Hover Detection**: The shelf now accurately opens as soon as you drag a file into the expanded detection zone (10–120px) and smoothly remains open as you move anywhere across the shelf to drop your files.
- **Reliable Exit Handling**: Moving a file away from the notch gracefully debounces before closing, eliminating frustrating premature closures.
- **Window Move Protection**: Moving ordinary application windows near the top edge is safely ignored and will never accidentally open the file shelf.

## ⚡ Instant App Exit
- **Zero-Lag App Termination**: Cleaned up background observers and connection hooks so NotchPulse quits instantly and cleanly when clicking "Quit" without hanging or requiring Force Quit.

