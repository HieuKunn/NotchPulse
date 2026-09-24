# NotchPulse v4.8.3

## 🔒 Face ID Accuracy & Multi-Face Candidate Detection
- **Restored Source Alignment**: Restored full Face ID scan timing and streak threshold logic identically to reference source, resolving immediate false rejection issues.
- **Smart Multi-Face Identification**: Enhanced recognition logic to automatically detect and select the registered owner's face first when multiple people are present in front of the Mac.
- **Optimized Memory Recovery**: Core ML models and alignment pixel buffer pools are immediately released upon unlocking to maintain minimal RAM usage.
