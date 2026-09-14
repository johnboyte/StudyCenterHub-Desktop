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
mkdir -p "$MACOS_DIR"

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-pack "macOS" "$TARGET_PCK"

if [ -f "$TARGET_PCK" ]; then
    echo "✅ PCK File Created: $TARGET_PCK"
    cp -f "$TARGET_PCK" "$RESOURCE_PCK"
    
    # Write Info.plist
    cat << 'EOF' > "$INFO_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StudyCenterHub-Desktop-Development</string>
    <key>CFBundleIdentifier</key>
    <string>org.reallife.studycenterhub.development</string>
    <key>CFBundleName</key>
    <string>StudyCenterHub Development</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF

    # Write Executable Launcher Script
    cat << 'EOF' > "$EXECUTABLE_BIN"
#!/bin/bash
GODOT_BIN="/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot"
PCK_FILE="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Development.app/Contents/Resources/StudyCenterHub-Desktop-Development.pck"
export STUDYCENTERHUB_ENV=development
if [ -x "$GODOT_BIN" ] && [ -f "$PCK_FILE" ]; then
    exec "$GODOT_BIN" --main-pack "$PCK_FILE" "$@"
else
    echo "Error: Required binary or frozen PCK package missing."
    exit 1
fi
EOF

    chmod +x "$EXECUTABLE_BIN"
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
