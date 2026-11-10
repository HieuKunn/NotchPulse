#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🔨 Building NotchPulse (Debug configuration with testability)..."
xcodebuild -scheme NotchPulse -configuration Debug -destination 'platform=macOS' build -quiet

BUILD_DIR=$(xcodebuild -scheme NotchPulse -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 " TARGET_BUILD_DIR =" | awk -F ' = ' '{print $2}')

echo "🧪 Compiling Test Harness..."
swiftc -parse-as-library \
  -I "$BUILD_DIR" \
  -F "$BUILD_DIR/PackageFrameworks" \
  -F "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -Xlinker -rpath -Xlinker "$BUILD_DIR/NotchPulse.app/Contents/MacOS" \
  -Xlinker -rpath -Xlinker "$BUILD_DIR/NotchPulse.app/Contents/Frameworks" \
  "$BUILD_DIR/NotchPulse.app/Contents/MacOS/NotchPulse.debug.dylib" \
  Tests/TestHarness.swift -o /tmp/NotchPulseTestHarness

echo "🚀 Executing Unit Tests..."
/tmp/NotchPulseTestHarness

