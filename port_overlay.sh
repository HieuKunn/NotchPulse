#!/bin/bash
GLANCE="glance-main/glance/NotchOverlay"
TARGET="NotchPulse/managers/FaceIDCore/Overlay"

mkdir -p "$TARGET"

apply_renames() {
    local file="$1"
    # Rename classes/structs/variables
    sed -i '' 's/NotchOverlayController/FaceIDOverlayController/g' "$file"
    sed -i '' 's/NotchOverlayView/FaceIDOverlayView/g' "$file"
    sed -i '' 's/NotchGeometry/FaceIDOverlayGeometry/g' "$file"
    sed -i '' 's/NotchShape/FaceIDOverlayShape/g' "$file"
    sed -i '' 's/NotchWindow/FaceIDOverlayWindow/g' "$file"
    sed -i '' 's/NotchWindowController/FaceIDOverlayWindowController/g' "$file"
    sed -i '' 's/ScanAnimationView/FaceIDScanAnimationView/g' "$file"
    sed -i '' 's/NotchSkyLight/FaceIDOverlaySkyLight/g' "$file"
    sed -i '' 's/MinimalUnlockView/FaceIDMinimalUnlockView/g' "$file"
    sed -i '' 's/NotchPanelStyle/FaceIDOverlayPanelStyle/g' "$file"
    sed -i '' 's/glance/NotchPulse/g' "$file"
    
    # Specific internal properties or methods renaming if needed
    sed -i '' 's/GlanceSettings/NotchPulseFaceIDSettings/g' "$file"
    sed -i '' 's/NotchPulseTheme/FaceIDTheme/g' "$file"
    sed -i '' 's/GlanceTheme/FaceIDTheme/g' "$file"
}

# Copy and rename files
cp "$GLANCE/NotchOverlayController.swift" "$TARGET/FaceIDOverlayController.swift"
cp "$GLANCE/NotchOverlayView.swift" "$TARGET/FaceIDOverlayView.swift"
cp "$GLANCE/NotchGeometry.swift" "$TARGET/FaceIDOverlayGeometry.swift"
cp "$GLANCE/NotchShape.swift" "$TARGET/FaceIDOverlayShape.swift"
cp "$GLANCE/NotchWindow.swift" "$TARGET/FaceIDOverlayWindow.swift"
cp "$GLANCE/NotchWindowController.swift" "$TARGET/FaceIDOverlayWindowController.swift"
cp "$GLANCE/ScanAnimationView.swift" "$TARGET/FaceIDScanAnimationView.swift"
cp "$GLANCE/NotchSkyLight.swift" "$TARGET/FaceIDOverlaySkyLight.swift"
cp "$GLANCE/MinimalUnlockView.swift" "$TARGET/FaceIDMinimalUnlockView.swift"
cp "$GLANCE/NotchPanelStyle.swift" "$TARGET/FaceIDOverlayPanelStyle.swift"

for file in "$TARGET"/*.swift; do
    echo "Processing $file..."
    apply_renames "$file"
done

echo "Done porting overlay files."
