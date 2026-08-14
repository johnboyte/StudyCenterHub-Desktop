#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Production Export Script
# Target: /Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Production.app
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"
TARGET_APP="$BUILDS_DIR/StudyCenterHub-Desktop-Production.app"
TARGET_PCK="$BUILDS_DIR/StudyCenterHub-Desktop-Production.pck"
RESOURCE_PCK="$TARGET_APP/Contents/Resources/StudyCenterHub-Desktop-Production.pck"
GODOT_BIN="/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot"
PROD_DB="/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"

echo "=============================================================================="
echo "1. VERIFYING GIT REPOSITORY STATE"
echo "=============================================================================="
cd "$PROJECT_DIR"
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current Commit: $CURRENT_COMMIT"
git status --short

echo "=============================================================================="
echo "2. RUNNING AUTOMATED TEST SUITES"
echo "=============================================================================="
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_center_open_hours_persistence.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_session_staff_assignment_dialog.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_uncovered_center_hours_calculation.gd"
"$GODOT_BIN" --headless --script "$PROJECT_DIR/tests/test_center_hours_staffing_and_capabilities.gd"
echo "✅ All test suites passed cleanly."

echo "=============================================================================="
echo "3. EXPORTING PRODUCTION APP PCK PACKAGE"
echo "=============================================================================="
echo "Export Target: $TARGET_PCK"

# Close running app if open to prevent file locking
pkill -f "StudyCenterHub" || true
sleep 1

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-pack "macOS" "$TARGET_PCK"

if [ -f "$TARGET_PCK" ]; then
    echo "✅ PCK File Created: $TARGET_PCK"
    mkdir -p "$TARGET_APP/Contents/Resources"
    cp -f "$TARGET_PCK" "$RESOURCE_PCK"
    touch "$TARGET_APP"
    echo "✅ App Bundle Package Updated: $RESOURCE_PCK"
else
    echo "❌ ERROR: Exported PCK missing at $TARGET_PCK"
    exit 1
fi

echo "=============================================================================="
echo "4. VERIFYING EXPORT ARTIFACT TIMESTAMPS"
echo "=============================================================================="
ls -ld "$TARGET_APP"
ls -lh "$TARGET_PCK"
ls -lh "$RESOURCE_PCK"

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
echo "SUCCESS: PRODUCTION APP EXPORTED CLEANLY!"
echo "=============================================================================="
