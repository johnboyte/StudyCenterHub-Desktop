#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Gateway Deployment Package Generator
# Generates identical, non-drifting gateway bundles for Production and Development
# Authoritative Source: /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/gateway/index.php
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"

PROD_DEPLOY_DIR="$BUILDS_DIR/gateway_production"
DEV_DEPLOY_DIR="$BUILDS_DIR/gateway_development"
BACKUP_DIR="$BUILDS_DIR/backups"

echo "=============================================================================="
echo "GENERATING GATEWAY DEPLOYMENT PACKAGES FROM AUTHORITATIVE SOURCE"
echo "=============================================================================="

# Ensure target deployment and backup directories exist
mkdir -p "$PROD_DEPLOY_DIR"
mkdir -p "$DEV_DEPLOY_DIR"
mkdir -p "$BACKUP_DIR"

# 0. Safety Conflict Guard: If a generated file has unmerged modifications, preserve it before refreshing
if [ -f "$PROD_DEPLOY_DIR/index.php" ] && [ -f "$PROJECT_DIR/gateway/index.php" ]; then
    if ! cmp -s "$PROJECT_DIR/gateway/index.php" "$PROD_DEPLOY_DIR/index.php"; then
        BACKUP_TS=$(date +"%Y%m%d_%H%M%S")
        BACKUP_FILE="$BACKUP_DIR/gateway_production_index_conflict_backup_${BACKUP_TS}.php"
        cp -f "$PROD_DEPLOY_DIR/index.php" "$BACKUP_FILE"
        echo "⚠️  WARNING: Detected unsynced edits in builds/gateway_production/index.php!"
        echo "   Safely preserved backup to: $BACKUP_FILE"
    fi
fi

# Unlock write permissions on previous generated files before refreshing
chmod -R u+w "$PROD_DEPLOY_DIR" "$DEV_DEPLOY_DIR" 2>/dev/null || true
rm -rf "$PROD_DEPLOY_DIR"/* "$DEV_DEPLOY_DIR"/*

# 1. Copy authoritative index.php controller to both deployment targets
cp -f "$PROJECT_DIR/gateway/index.php" "$PROD_DEPLOY_DIR/index.php"
cp -f "$PROJECT_DIR/gateway/index.php" "$DEV_DEPLOY_DIR/index.php"

# 2. Copy .htaccess security & routing file to both deployment targets
cp -f "$PROJECT_DIR/gateway/.htaccess" "$PROD_DEPLOY_DIR/.htaccess"
cp -f "$PROJECT_DIR/gateway/.htaccess" "$DEV_DEPLOY_DIR/.htaccess"

# 3. Copy config.php template to both deployment targets
cp -f "$PROJECT_DIR/gateway/config.php" "$PROD_DEPLOY_DIR/config.php"
cp -f "$PROJECT_DIR/gateway/config.php" "$DEV_DEPLOY_DIR/config.php"

# 4. Copy mail.php relay controller to both deployment targets
cp -f "$PROJECT_DIR/gateway/mail.php" "$PROD_DEPLOY_DIR/mail.php"
cp -f "$PROJECT_DIR/gateway/mail.php" "$DEV_DEPLOY_DIR/mail.php"

# 5. Copy upload_pass.php PassKit relay to both deployment targets
cp -f "$PROJECT_DIR/gateway/upload_pass.php" "$PROD_DEPLOY_DIR/upload_pass.php"
cp -f "$PROJECT_DIR/gateway/upload_pass.php" "$DEV_DEPLOY_DIR/upload_pass.php"

# 6. Copy upload_media.php media relay to both deployment targets
cp -f "$PROJECT_DIR/gateway/upload_media.php" "$PROD_DEPLOY_DIR/upload_media.php"
cp -f "$PROJECT_DIR/gateway/upload_media.php" "$DEV_DEPLOY_DIR/upload_media.php"

# 7. Add explicit DO NOT EDIT documentation in generated deployment directories
cat << 'EOF' > "$PROD_DEPLOY_DIR/README_DO_NOT_EDIT.md"
# ⚠️ GENERATED GATEWAY DEPLOYMENT BUNDLE (PRODUCTION)

DO NOT EDIT ANY FILES IN THIS DIRECTORY!

All files in this directory are generated automatically by:
`scripts/prepare_gateway_deployments.sh`

The ONLY authoritative editable source is:
`study-center-hub---desktop/gateway/index.php`

Any direct edits made in this directory will be overwritten upon rebuild.
EOF

cat << 'EOF' > "$DEV_DEPLOY_DIR/README_DO_NOT_EDIT.md"
# ⚠️ GENERATED GATEWAY DEPLOYMENT BUNDLE (DEVELOPMENT)

DO NOT EDIT ANY FILES IN THIS DIRECTORY!

All files in this directory are generated automatically by:
`scripts/prepare_gateway_deployments.sh`

The ONLY authoritative editable source is:
`study-center-hub---desktop/gateway/index.php`

Any direct edits made in this directory will be overwritten upon rebuild.
EOF

# 8. Mark all generated deployment files as READ-ONLY on disk (chmod 444)
# This prevents stale editor buffers or accidental typing from modifying or saving over them.
find "$PROD_DEPLOY_DIR" "$DEV_DEPLOY_DIR" -type f -exec chmod 444 {} +

# 9. Package authoritative gateway_production.zip archive (excluding README_DO_NOT_EDIT.md)
(cd "$PROD_DEPLOY_DIR" && zip -r -q "$BUILDS_DIR/gateway_production.zip" . -x "README_DO_NOT_EDIT.md")

echo "✅ Production Gateway Bundle Created at: $PROD_DEPLOY_DIR (Read-Only)"
echo "✅ Production Gateway Archive Created at: $BUILDS_DIR/gateway_production.zip"
echo "✅ Development Gateway Bundle Created at: $DEV_DEPLOY_DIR (Read-Only)"
echo "=============================================================================="
echo "DEPLOYMENT INSTRUCTIONS:"
echo "1. Upload contents of $PROD_DEPLOY_DIR to SiteGround app.reallife-studycenter.org/public_html"
echo "2. Upload contents of $DEV_DEPLOY_DIR to SiteGround dev-gateway.reallife-studycenter.org/public_html"
echo "=============================================================================="
