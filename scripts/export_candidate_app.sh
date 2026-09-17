#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Candidate Standalone App Export Script
# Target: /Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Candidate.app
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"
TARGET_APP="$BUILDS_DIR/StudyCenterHub-Desktop-Candidate.app"
TARGET_PCK="$BUILDS_DIR/StudyCenterHub-Desktop-Candidate.pck"
RESOURCE_PCK="$TARGET_APP/Contents/Resources/StudyCenterHub-Desktop-Candidate.pck"
RESOURCE_ICNS="$TARGET_APP/Contents/Resources/icon.icns"
EXEC_BIN="$TARGET_APP/Contents/MacOS/StudyCenterHub-Desktop-Candidate"
GODOT_BIN="/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot"
INFO_PLIST="$TARGET_APP/Contents/Info.plist"

echo "=============================================================================="
echo "1. VERIFYING GIT REPOSITORY STATE"
echo "=============================================================================="
cd "$PROJECT_DIR"
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current Commit: $CURRENT_COMMIT"

echo "=============================================================================="
echo "2. EXPORTING CANDIDATE PCK PACKAGE"
echo "=============================================================================="
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-pack "macOS" "$TARGET_PCK"

echo "=============================================================================="
echo "3. CONSTRUCTING STANDALONE MAC OS APP BUNDLE"
echo "=============================================================================="
mkdir -p "$TARGET_APP/Contents/MacOS"
mkdir -p "$TARGET_APP/Contents/Resources"

# Copy Godot runner binary directly into candidate app bundle
cp -f "$GODOT_BIN" "$EXEC_BIN"
chmod +x "$EXEC_BIN"

# Copy PCK resource package
cp -f "$TARGET_PCK" "$RESOURCE_PCK"

# Copy app icon if present
if [ -f "$PROJECT_DIR/icon.icns" ]; then
    cp -f "$PROJECT_DIR/icon.icns" "$RESOURCE_ICNS"
elif [ -f "/Applications/StudyCenterHub.app/Contents/Resources/icon.icns" ]; then
    cp -f "/Applications/StudyCenterHub.app/Contents/Resources/icon.icns" "$RESOURCE_ICNS"
fi

# Create Info.plist for self-contained Candidate app
cat <<EOF > "$INFO_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>StudyCenterHub-Desktop-Candidate</string>
	<key>CFBundleIconFile</key>
	<string>icon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>org.godotengine.studycenterhub.candidate</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>StudyCenterHub Candidate</string>
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

# Strip quarantine attributes & apply ad-hoc code signature for native macOS launch
xattr -cr "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"

touch "$TARGET_APP"

echo "=============================================================================="
echo "4. VERIFYING CANDIDATE STANDALONE APP BUNDLE"
echo "=============================================================================="
ls -ld "$TARGET_APP"
ls -lh "$EXEC_BIN"
ls -lh "$RESOURCE_PCK"

echo "=============================================================================="
echo "SUCCESS: CANDIDATE STANDALONE APP BUNDLE CREATED CLEANLY!"
echo "=============================================================================="
