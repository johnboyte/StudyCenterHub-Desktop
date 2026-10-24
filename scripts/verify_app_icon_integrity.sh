#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub App Icon Integrity Verification Script
# Enforces that every build and bundle uses the approved StudyCenterHub icon
# Expected ICNS SHA-256: 94fa84a8f882351baca17dc66352d7d5bc3ec598bee5e4dab359ad69e5fcd19b
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
EXPECTED_ICNS_HASH="94fa84a8f882351baca17dc66352d7d5bc3ec598bee5e4dab359ad69e5fcd19b"
TARGET_APP="${1:-/Applications/StudyCenterHub.app}"

echo "=============================================================================="
echo "VERIFYING STUDYCENTERHUB ICON INTEGRITY"
echo "Target App Bundle: $TARGET_APP"
echo "=============================================================================="

# 1. Authoritative tracked asset check
AUTH_ICNS="$PROJECT_DIR/assets/branding/StudyCenterHub.icns"
if [ ! -f "$AUTH_ICNS" ]; then
    echo "❌ ERROR: Authoritative icon missing at $AUTH_ICNS"
    exit 1
fi

AUTH_HASH=$(shasum -a 256 "$AUTH_ICNS" | awk '{print $1}')
if [ "$AUTH_HASH" != "$EXPECTED_ICNS_HASH" ]; then
    echo "❌ ERROR: Authoritative icon hash mismatch!"
    echo "   Expected: $EXPECTED_ICNS_HASH"
    echo "   Actual:   $AUTH_HASH"
    exit 1
fi
echo "✅ Authoritative icon asset verified: $AUTH_ICNS ($AUTH_HASH)"

# 2. Project root icon.icns check
ROOT_ICNS="$PROJECT_DIR/icon.icns"
if [ ! -f "$ROOT_ICNS" ]; then
    echo "❌ ERROR: Root icon missing at $ROOT_ICNS"
    exit 1
fi

ROOT_HASH=$(shasum -a 256 "$ROOT_ICNS" | awk '{print $1}')
if [ "$ROOT_HASH" != "$EXPECTED_ICNS_HASH" ]; then
    echo "❌ ERROR: Root icon hash mismatch!"
    echo "   Expected: $EXPECTED_ICNS_HASH"
    echo "   Actual:   $ROOT_HASH"
    exit 1
fi
echo "✅ Project root icon verified: $ROOT_ICNS ($ROOT_HASH)"

# 3. Project root icon.png check
ROOT_PNG="$PROJECT_DIR/icon.png"
if [ ! -f "$ROOT_PNG" ]; then
    echo "❌ ERROR: Root icon.png missing at $ROOT_PNG"
    exit 1
fi
echo "✅ Project root icon.png verified"

# 4. Godot robot icon regression safeguard
ROOT_SVG="$PROJECT_DIR/icon.svg"
if [ -f "$ROOT_SVG" ]; then
    if grep -iq "478cbf" "$ROOT_SVG"; then
        echo "❌ ERROR: Default Godot robot logo detected in $ROOT_SVG!"
        exit 1
    fi
    echo "✅ Project root icon.svg verified (free of default Godot robot logo)"
fi

# 5. project.godot configuration check
PROJECT_GODOT="$PROJECT_DIR/project.godot"
if ! grep -q 'config/icon="res://icon.png"' "$PROJECT_GODOT"; then
    echo "❌ ERROR: project.godot does not configure config/icon to res://icon.png"
    exit 1
fi
if ! grep -q 'config/macos_native_icon="res://icon.icns"' "$PROJECT_GODOT"; then
    echo "❌ ERROR: project.godot does not configure config/macos_native_icon to res://icon.icns"
    exit 1
fi
echo "✅ project.godot icon configuration verified"

# 6. Bundle icon check (if bundle exists)
if [ -d "$TARGET_APP" ]; then
    BUNDLE_ICNS="$TARGET_APP/Contents/Resources/icon.icns"
    if [ ! -f "$BUNDLE_ICNS" ]; then
        echo "❌ ERROR: Target bundle icon missing at $BUNDLE_ICNS"
        exit 1
    fi

    BUNDLE_HASH=$(shasum -a 256 "$BUNDLE_ICNS" | awk '{print $1}')
    if [ "$BUNDLE_HASH" != "$EXPECTED_ICNS_HASH" ]; then
        echo "❌ ERROR: Bundle icon hash mismatch in $TARGET_APP!"
        echo "   Expected: $EXPECTED_ICNS_HASH"
        echo "   Actual:   $BUNDLE_HASH"
        exit 1
    fi
    echo "✅ Installed bundle icon verified: $BUNDLE_ICNS ($BUNDLE_HASH)"

    BUNDLE_PLIST="$TARGET_APP/Contents/Info.plist"
    if [ ! -f "$BUNDLE_PLIST" ]; then
        echo "❌ ERROR: Info.plist missing at $BUNDLE_PLIST"
        exit 1
    fi

    if ! grep -q "<key>CFBundleIconFile</key>" "$BUNDLE_PLIST" || ! grep -q "<string>icon.icns</string>" "$BUNDLE_PLIST"; then
        echo "❌ ERROR: Info.plist does not reference icon.icns in $TARGET_APP"
        exit 1
    fi
    echo "✅ Installed bundle Info.plist verified (CFBundleIconFile -> icon.icns)"
fi

echo "=============================================================================="
echo "✅ ALL ICON INTEGRITY CHECKS PASSED (100%)"
echo "=============================================================================="
