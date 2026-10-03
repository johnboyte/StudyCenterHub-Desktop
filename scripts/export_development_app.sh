#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Development Export Script
# Target: /Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Development.app
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"
TARGET_APP="$BUILDS_DIR/StudyCenterHub-Desktop-Development.app"
TARGET_PCK="$BUILDS_DIR/StudyCenterHub-Desktop-Development.pck"
RESOURCE_PCK="$TARGET_APP/Contents/Resources/StudyCenterHub-Desktop-Development.pck"
MACOS_DIR="$TARGET_APP/Contents/MacOS"
EXECUTABLE_BIN="$MACOS_DIR/StudyCenterHub-Desktop-Development"
INFO_PLIST="$TARGET_APP/Contents/Info.plist"

GODOT_BIN="/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot"
DEV_DB="/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"

echo "=============================================================================="
echo "1. VERIFYING GIT REPOSITORY STATE"
echo "=============================================================================="
cd "$PROJECT_DIR"
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current Commit: $CURRENT_COMMIT"

echo "=============================================================================="
echo "2. PRESERVING EXISTING DEVELOPMENT DATABASE STATE"
echo "=============================================================================="
echo "NOTE: App export is strictly non-destructive. Database seeding skipped during build."

echo "=============================================================================="
echo "3. EXPORTING DEVELOPMENT APP PCK PACKAGE"
echo "=============================================================================="
mkdir -p "$BUILDS_DIR"
mkdir -p "$TARGET_APP/Contents/Resources"
mkdir -p "$TARGET_APP/Contents/Frameworks"
mkdir -p "$TARGET_APP/Contents/MacOS/bin"
mkdir -p "$TARGET_APP/Contents/Resources/bin"
mkdir -p "$MACOS_DIR"

if [ -f "$PROJECT_DIR/bin/libmac_wkwebview.dylib" ]; then
    cp -f "$PROJECT_DIR/bin/libmac_wkwebview.dylib" "$TARGET_APP/Contents/Frameworks/libmac_wkwebview.dylib"
    rm -f "$TARGET_APP/Contents/MacOS/libmac_wkwebview.dylib"
    rm -f "$TARGET_APP/Contents/MacOS/bin/libmac_wkwebview.dylib"
    rm -f "$TARGET_APP/Contents/Resources/bin/libmac_wkwebview.dylib"
    echo "✅ Authoritative Native Dylib (Single Copy) Packaged at Contents/Frameworks/libmac_wkwebview.dylib"
fi

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-pack "macOS" "$TARGET_PCK"

if [ -f "$TARGET_PCK" ]; then
    echo "✅ PCK File Created: $TARGET_PCK"
    cp -f "$TARGET_PCK" "$RESOURCE_PCK"
    cp -f "$TARGET_PCK" "$MACOS_DIR/StudyCenterHub-Desktop-Development.pck"
    
    if [ -f "$PROJECT_DIR/icon.icns" ]; then
        cp -f "$PROJECT_DIR/icon.icns" "$TARGET_APP/Contents/Resources/icon.icns"
    fi
    
    # Install native runner binary directly into bundle MacOS directory
    cp -f "$GODOT_BIN" "$EXECUTABLE_BIN"
    chmod +x "$EXECUTABLE_BIN"
    
    # Write Info.plist for self-contained Standalone Development App
    cat << 'EOF' > "$INFO_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>StudyCenterHub-Desktop-Development</string>
	<key>CFBundleIconFile</key>
	<string>icon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>org.godotengine.studycenterhub.development</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>StudyCenterHub Development</string>
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

    # Strip quarantine attributes & apply ad-hoc code signature
    xattr -cr "$TARGET_APP"
    codesign --force --deep --sign - "$TARGET_APP"

    touch "$TARGET_APP"
    echo "✅ Development App Bundle Package Updated: $TARGET_APP"
else
    echo "❌ ERROR: Exported PCK missing at $TARGET_PCK"
    exit 1
fi

echo "=============================================================================="
echo "4. VERIFYING DEVELOPMENT DATABASE PRESERVATION"
echo "=============================================================================="
if [ -f "$DEV_DB" ]; then
    echo "✅ Development Database Intact: $DEV_DB"
    ls -lh "$DEV_DB"
fi

echo "=============================================================================="
echo "SUCCESS: DEVELOPMENT APP EXPORTED CLEANLY!"
echo "=============================================================================="
