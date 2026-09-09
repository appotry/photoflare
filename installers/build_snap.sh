#!/usr/bin/env bash
# build_snap.sh
# Builds the PhotoFlare Snap package locally.
#
# Usage:
#   bash installers/build_snap.sh [--install] [--run]
#
# Options:
#   --install   Install the built .snap after building (requires sudo)
#   --run       Run photoflare after install (implies --install)
#
# Requirements:
#   sudo snap install snapcraft --classic
#   sudo snap install lxd && sudo lxd init --minimal
#   # Add yourself to the lxd group (then log out/in):
#   sudo usermod -aG lxd $USER

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DO_INSTALL=0
DO_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) DO_INSTALL=1; shift ;;
        --run)     DO_INSTALL=1; DO_RUN=1; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Check prerequisites
if ! command -v snapcraft &>/dev/null; then
    echo "ERROR: snapcraft not found."
    echo "Install with: sudo snap install snapcraft --classic"
    exit 1
fi

if ! command -v lxd &>/dev/null; then
    echo "ERROR: lxd not found."
    echo "Install with: sudo snap install lxd && sudo lxd init --minimal"
    exit 1
fi

echo "=== Building Snap ==="
snapcraft --use-lxd
echo ""

SNAP_FILE=$(ls -1t "$REPO_ROOT"/*.snap 2>/dev/null | head -1 || true)
if [[ -z "$SNAP_FILE" ]]; then
    echo "ERROR: No .snap file found after build."
    exit 1
fi
echo "Built: $SNAP_FILE"

if [[ $DO_INSTALL -eq 1 ]]; then
    echo ""
    echo "=== Installing $SNAP_FILE ==="
    # classic confinement requires --dangerous for local installs
    sudo snap install --dangerous --classic "$SNAP_FILE"

    if [[ $DO_RUN -eq 1 ]]; then
        echo ""
        echo "=== Launching photoflare ==="
        snap run photoflare
    fi
else
    echo ""
    echo "To install and run:"
    echo "  sudo snap install --dangerous --classic $SNAP_FILE"
    echo "  snap run photoflare"
fi
