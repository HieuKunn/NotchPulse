## NotchPulse v5.5 (Build 439)

### 🔒 Reliable Lock Screen & Multi-Display Support
- **Lock Screen Player Visibility**: Fixed an issue where the Lock Screen media card failed to appear or was prematurely dismissed on screen wake.
- **External Monitor Support**: The Lock Screen player now dynamically anchors to your active screen (including external displays) with full elevated window shielding.
- **Smooth Unlock Transition**: Media controls and lyrics dissolve cleanly in tandem with native macOS unlock animations.

### 📥 Enhanced Shelf Drag & Drop
- **Proactive Drag Detection**: Shelf smoothly expands as soon as dragged files enter the footprint, eliminating the need to drag all the way to the top bezel.
- **Seamless Drop Target**: Resolved an issue where window level elevation prevented files and images (`.image`, `.png`, `.jpg`, `.url`, etc.) from being received into the Shelf.

### 🍏 Native macOS Settings Experience
- **Apple HIG Toggle Switch Parity**: Standardized all on/off toggle switches to uniform, 100% native macOS control size (`NSSwitch` / `.regular`) across all sections.
- **Enhanced Search Field Contrast**: Native sidebar search field with crisp rounded bezel and depth shadow cleanly separated from the translucent sidebar material.
- **Prominent Section Headers**: Restored large, bold title typography matching macOS System Settings.

### ⚡️ Proactive Updates & Stability
- **Immediate In-App Update Prompt**: Directly alerts you with release details and one-click updating upon launch or wake.
- **Startup Reliability**: Hardened audio and system service initialization to ensure smooth, zero-crash startup.
