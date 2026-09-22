# NotchPulse v4.7.1

## 🐛 Bug Fixes
- **Reliable notch hover behavior**: Fixed the notch sometimes staying open or closed when moving the pointer in or out.
- **HUD layout stability**: Fixed inline and normal HUDs hiding their progress bars, percentages, and mute status.
- **More dependable HUD interaction**: HUD content now stays within the notch hit area, so hover interactions continue to work correctly.

## 🖱️ Smooth Notch Animation
- Regular notch opening and closing now interpolate continuously between closed and open sizes.
- Opening and closing use the same spring timing as Face ID.

## 🚪 Quit Reliability
- Removed the delayed Exit action.
- Prevented the MediaRemote helper cleanup from blocking app termination.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.7.1, build 110.

---

# NotchPulse v4.7.0

## 🖱️ Smooth Notch Animation
- Regular notch opening and closing now interpolate continuously between closed and open sizes.
- Opening and closing use the same spring timing as Face ID.

## 🚪 Quit Reliability
- Removed the delayed Exit action.
- Prevented the MediaRemote helper cleanup from blocking app termination.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.7.0, build 109.

---

# NotchPulse v4.6.10

## 🖱️ Notch Animation
- Fixed the regular notch so it expands and contracts continuously instead of jumping between closed and open states.
- Matched the opening and closing spring behavior used by Face ID.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.6.10, build 108.

---

# NotchPulse v4.6.9

## 🖱️ Notch Animation
- Regular notch opening and closing now use the same spring timing as Face ID.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.6.9, build 107.

---

# NotchPulse v4.6.8

## 🖱️ Notch Animation
- Restored the smooth Boring Notch-style opening and closing behavior.

## 🧩 Maintenance
- Updated the app and helper build metadata to version 4.6.8, build 106.

---

# NotchPulse v4.6.6

## ⚙️ Shelf Settings

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
