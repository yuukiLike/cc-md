#!/bin/bash
# =========================================================================
# cc-md install — backward-compatible wrapper
# =========================================================================
# This script delegates to setup.sh. Kept for backward compatibility
# so existing docs and instructions continue to work.
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/setup.sh" "$@"
