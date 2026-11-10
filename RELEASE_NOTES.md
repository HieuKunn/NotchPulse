## NotchPulse v5.6 (Build 465)

### 🧼 Seamless Invisible Scrollbars (Clipboard & Shelf Parity)
- **Zero Scrollbar Indicator Visibility**: Eliminated the vertical scrollbars from both the sidebar list and detail settings form while fully preserving smooth trackpad and mouse wheel scrolling.
- **Underlying ScrollView Scroller Suppression**: Applied underlying AppKit overlay scroller suppression to guarantee scrollbars never flash or render as grey bars, exactly like the Shelf and Clipboard views.
