# NotchPulse v4.8.3

## 🔒 Face ID Stability & Recognition Window
- **Full Recognition Window**: Fixed an issue where Face ID could prematurely trigger a "Face not recognized" error in under 1.5 seconds. The scan now patiently and resiliently uses your full configured scan time (e.g. 3–5 seconds), allowing proper camera auto-exposure and lighting adjustment.
- **Seamless Match Latching**: Restored momentary match latching to prevent brief lighting changes, blinks, or minor head turns from interrupting successful recognition.
- **Consistent Lock Screen Unlocking**: Ensured active face profiles are instantly synchronized upon wake for swift, reliable unlock attempts every time.
