#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Production Export Script (Standalone Native macOS Bundle)
# Target: /Applications/StudyCenterHub.app
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"
TARGET_APP="/Applications/StudyCenterHub.app"
BUILD_APP="$BUILDS_DIR/StudyCenterHub-Desktop-Production.app"
TARGET_PCK="$BUILDS_DIR/StudyCenterHub.pck"
GODOT_BIN="/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot"
PROD_DB="/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"

echo "=============================================================================="
echo "1. VERIFYING GIT REPOSITORY STATE"
echo "=============================================================================="
cd "$PROJECT_DIR"
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current Commit: $CURRENT_COMMIT"

echo "=============================================================================="
echo "2. RUNNING AUTOMATED REGRESSION TEST SUITES"
echo "=============================================================================="
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_database_environment_resolution.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_launcher_environment_routing.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_center_open_hours_persistence.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_session_staff_assignment_dialog.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_uncovered_center_hours_calculation.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_center_hours_staffing_and_capabilities.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_spelling_context_menu_actions.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_spelling_assistance_and_sync.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_sms_reply_composer.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_email_digital_member_pass.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_sms_digital_member_pass.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_sms_schedule_send.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/verify_production_deployment.gd"
echo "✅ All regression test suites passed 100% cleanly."

echo "=============================================================================="
echo "3. EXPORTING PRODUCTION RESOURCE PACK"
echo "=============================================================================="
pkill -f "StudyCenterHub" || true
sleep 1

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-pack "macOS" "$TARGET_PCK"

if [ ! -f "$TARGET_PCK" ]; then
    echo "❌ ERROR: Exported PCK missing at $TARGET_PCK"
    exit 1
fi

echo "=============================================================================="
echo "4. CONSTRUCTING STANDALONE MAC OS APP BUNDLE IN /Applications"
echo "=============================================================================="
mkdir -p "$TARGET_APP/Contents/MacOS"
mkdir -p "$TARGET_APP/Contents/Resources"
mkdir -p "$BUILD_APP/Contents/MacOS"
mkdir -p "$BUILD_APP/Contents/Resources"

# Install native runner binary directly into bundle MacOS directory
cp -f "$GODOT_BIN" "$TARGET_APP/Contents/MacOS/StudyCenterHub"
chmod +x "$TARGET_APP/Contents/MacOS/StudyCenterHub"
cp -f "$GODOT_BIN" "$BUILD_APP/Contents/MacOS/StudyCenterHub-Desktop-Production"
cp -f "$GODOT_BIN" "$BUILD_APP/Contents/MacOS/StudyCenterHub"
chmod +x "$BUILD_APP/Contents/MacOS/StudyCenterHub-Desktop-Production"
chmod +x "$BUILD_APP/Contents/MacOS/StudyCenterHub"

# Copy PCK resource package to both main app pack paths (Resources & MacOS)
cp -f "$TARGET_PCK" "$TARGET_APP/Contents/Resources/StudyCenterHub.pck"
cp -f "$TARGET_PCK" "$TARGET_APP/Contents/Resources/StudyCenterHub-Desktop-Production.pck"
cp -f "$TARGET_PCK" "$TARGET_APP/Contents/MacOS/StudyCenterHub.pck"
cp -f "$TARGET_PCK" "$BUILD_APP/Contents/Resources/StudyCenterHub-Desktop-Production.pck"
cp -f "$TARGET_PCK" "$BUILD_APP/Contents/Resources/StudyCenterHub.pck"
cp -f "$TARGET_PCK" "$BUILD_APP/Contents/MacOS/StudyCenterHub-Desktop-Production.pck"
cp -f "$TARGET_PCK" "$BUILD_APP/Contents/MacOS/StudyCenterHub.pck"

# Copy icon
if [ -f "$PROJECT_DIR/icon.icns" ]; then
    cp -f "$PROJECT_DIR/icon.icns" "$TARGET_APP/Contents/Resources/icon.icns"
    cp -f "$PROJECT_DIR/icon.icns" "$BUILD_APP/Contents/Resources/icon.icns"
fi

# Write Info.plist for self-contained Production bundle
cat <<EOF > "$TARGET_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>StudyCenterHub</string>
	<key>CFBundleIconFile</key>
	<string>icon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>org.godotengine.studycenterhub</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>StudyCenterHub</string>
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

cp -f "$TARGET_APP/Contents/Info.plist" "$BUILD_APP/Contents/Info.plist"

# Strip quarantine attributes & apply ad-hoc code signature for native macOS launch
xattr -cr "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"
xattr -cr "$BUILD_APP"
codesign --force --deep --sign - "$BUILD_APP"

touch "$TARGET_APP"
touch "$BUILD_APP"

echo "=============================================================================="
echo "5. VERIFYING PRODUCTION DATABASE PRESERVATION"
echo "=============================================================================="
if [ -f "$PROD_DB" ]; then
    echo "✅ Production Database Intact: $PROD_DB"
    ls -lh "$PROD_DB"
else
    echo "⚠️ Warning: Production database path not found at $PROD_DB"
fi

echo "=============================================================================="
echo "SUCCESS: PRODUCTION APP EXPORTED & INSTALLED CLEANLY!"
echo "=============================================================================="
