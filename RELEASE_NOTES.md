# NotchPulse v4.6.8

## 🖱️ Notch Animation
- Restored the smooth Boring Notch-style opening and closing behavior.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.6.8, build 106.

---

# NotchPulse v4.6.6

## ⚙️ Shelf Settings
- **Independent hover controls**: Pointer hover distance and file-drag distance can now be adjusted separately from Shelf Settings.

## 🖱️ Notch Hover & Shelf Dragging
- **Smooth open and close animation**: Restored continuous notch sizing while hovering, including Inline HUD content.
- **Closed-notch hover distance**: Shelf activation is measured from the closed notch edge plus the configured padding.
- **Safer drag detection**: Global Shelf activation requires a changed drag pasteboard and a real file type, avoiding accidental activation from app or web drags.
- **Close on drag exit**: A Shelf opened by dragging closes when the held file leaves the notch area.

## 📁 Shelf — Safer File Dragging
- **Shelf takes priority at the notch center**: Dragging a file toward the center of the top edge opens the Shelf without requiring the pointer to land exactly on the closed notch.
- **Reduced Mission Control confusion**: The detection zone is limited to the notch area and its configurable nearby padding, leaving macOS corner gestures untouched.
- **Reliable Finder drags**: File drags are recognized even when Finder populates the drag pasteboard before the global mouse-down event.
- **Configurable detection distance**: Shelf Settings now lets you adjust the nearby detection distance from 0 to 160 px.

## 📊 HUD Display
- **Inline HUD progress restored**: Fixed the progress bar and percentage being clipped when the inline HUD is wider than the closed notch.

## 🔐 Face Unlock — Session Authentication Fix
- **Automatic re-authentication after lock**: Fixed a critical issue where Face Unlock would silently fail after your Mac woke from sleep or the screen was locked. Previously, the session key was cleared from memory on lock but the app never properly prompted for Touch ID or your password to restore it — meaning Face Unlock was stuck in a broken state until you manually went to Settings → Password and authenticated there. Now, when Face Unlock detects the session is locked, it immediately presents a Touch ID / password prompt and then automatically begins scanning your face once authenticated. No more manual workaround required.

## 📁 Shelf — Drag & Drop Fixes
- **No more Mission Control when dragging files**: Fixed a bug where dragging a file toward the notch area would trigger macOS Mission Control instead of opening the Shelf. The drag detector now always runs regardless of the "Expanded drag detection" setting — that setting only controls how far the detection zone extends beyond the notch edge.
- **Faster multi-file drops**: Fixed a lag where dropping multiple files into the Shelf processed them one by one. All files are now resolved in parallel so the entire drop completes as fast as the slowest single file.

## 🖱️ Notch Hover Stability
- **No More Accidental Closings**: Fixed an issue where the open notch could unexpectedly close while your cursor was still inside it, especially when moving between buttons or content within the notch area.
