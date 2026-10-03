#!/bin/bash
set -e

# ==============================================================================
# Standalone Native macOS AppKit Drag Probe Compiler
# Target: /Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-DragProbe.app
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"
PROBE_APP="$BUILDS_DIR/StudyCenterHub-DragProbe.app"
MACOS_DIR="$PROBE_APP/Contents/MacOS"
EXECUTABLE="$MACOS_DIR/StudyCenterHub-DragProbe"
INFO_PLIST="$PROBE_APP/Contents/Info.plist"

echo "=============================================================================="
echo "BUILDING STANDALONE APPKIT DRAG PROBE"
echo "=============================================================================="

mkdir -p "$MACOS_DIR"
mkdir -p "$PROBE_APP/Contents/Resources"

clang -framework AppKit -framework Foundation "$PROJECT_DIR/tools/drag_probe/drag_probe.m" -o "$EXECUTABLE"

cat << 'EOF' > "$INFO_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>StudyCenterHub-DragProbe</string>
	<key>CFBundleIdentifier</key>
	<string>org.studycenterhub.dragprobe</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>StudyCenterHub Drag Probe</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

xattr -cr "$PROBE_APP"
codesign --force --deep --sign - "$PROBE_APP"

echo "✅ Standalone Native AppKit Drag Probe Built & Signed: $PROBE_APP"
