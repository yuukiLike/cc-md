#!/bin/bash
# =========================================================================
# cc-md one-liner installer
# =========================================================================
# Usage:
#   bash <(curl -sL https://raw.githubusercontent.com/anthropics/cc-md/main/install-remote.sh)
#
# This script:
#   1. Clones cc-md to ~/.cc-md/cc-md (via HTTPS, no SSH needed)
#   2. Runs scripts/setup.sh (which handles everything else)
#   3. On re-run: pulls latest updates, then runs setup again
# =========================================================================

set -euo pipefail

CC_MD_HOME="$HOME/.cc-md"
CC_MD_REPO="$CC_MD_HOME/cc-md"
REPO_URL="https://github.com/anthropics/cc-md.git"

echo "cc-md installer"
echo ""

# Ensure git is available
if ! command -v git &>/dev/null; then
    echo "ERROR: git not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

mkdir -p "$CC_MD_HOME"

if [ -d "$CC_MD_REPO/.git" ]; then
    # Already cloned — pull latest
    echo "Updating cc-md..."
    git -C "$CC_MD_REPO" pull --quiet 2>/dev/null || true
else
    # Fresh clone via HTTPS (no SSH key needed for public repo)
    echo "Downloading cc-md..."
    git clone --quiet "$REPO_URL" "$CC_MD_REPO"
fi

echo ""
exec bash "$CC_MD_REPO/scripts/setup.sh" "$@"
