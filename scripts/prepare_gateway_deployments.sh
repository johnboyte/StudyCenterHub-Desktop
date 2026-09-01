#!/bin/bash
set -e

# ==============================================================================
# StudyCenterHub Gateway Deployment Package Generator
# Generates identical, non-drifting gateway bundles for Production and Development
# Source: /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/gateway/index.php
# ==============================================================================

PROJECT_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"
BUILDS_DIR="/Users/johnboyte/Development/StudyCenterHub-Desktop/builds"

PROD_DEPLOY_DIR="$BUILDS_DIR/gateway_production"
DEV_DEPLOY_DIR="$BUILDS_DIR/gateway_development"

echo "=============================================================================="
echo "GENERATING GATEWAY DEPLOYMENT PACKAGES FROM AUTHORITATIVE SOURCE"
echo "=============================================================================="

# Ensure target deployment directories exist
mkdir -p "$PROD_DEPLOY_DIR"
mkdir -p "$DEV_DEPLOY_DIR"

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

echo "✅ Production Gateway Bundle Created at: $PROD_DEPLOY_DIR"
echo "✅ Development Gateway Bundle Created at: $DEV_DEPLOY_DIR"
echo "=============================================================================="
echo "DEPLOYMENT INSTRUCTIONS:"
echo "1. Upload contents of $PROD_DEPLOY_DIR to SiteGround app.reallife-studycenter.org/public_html"
echo "2. Upload contents of $DEV_DEPLOY_DIR to SiteGround dev-gateway.reallife-studycenter.org/public_html"
echo "=============================================================================="
