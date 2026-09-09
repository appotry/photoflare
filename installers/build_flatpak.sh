#!/usr/bin/env bash
# build_flatpak.sh
# Builds and optionally installs the PhotoFlare Flatpak locally.
#
# Usage:
#   bash installers/build_flatpak.sh [--install] [--run]
#
# Options:
#   --install   Install the built Flatpak for the current user
#   --run       Run io.photoflare.photoflare after install (implies --install)
#
# Requirements:
#   sudo apt-get install -y flatpak flatpak-builder
#   flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
#   flatpak install flathub org.kde.Platform//6.7 org.kde.Sdk//6.7

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
for cmd in flatpak flatpak-builder; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' not found."
        echo "Install with: sudo apt-get install -y flatpak flatpak-builder"
        exit 1
    fi
done

# Add Flathub remote if missing
if ! flatpak remote-list --user | grep -q flathub; then
    echo "Adding Flathub remote..."
    flatpak remote-add --user --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo
fi

# Install KDE runtime/SDK if missing
echo "=== Checking KDE Platform/SDK 6.7 ==="
for ref in org.kde.Platform//6.7 org.kde.Sdk//6.7; do
    if ! flatpak info --user "$ref" &>/dev/null && ! flatpak info "$ref" &>/dev/null; then
        echo "Installing $ref ..."
        flatpak install --user -y flathub "$ref"
    else
        echo "  $ref already installed."
    fi
done
echo ""

BUILD_DIR="$REPO_ROOT/build-flatpak"

if [[ $DO_INSTALL -eq 1 ]]; then
    echo "=== Building and installing Flatpak (user) ==="
    flatpak-builder --force-clean --install --user \
        "$BUILD_DIR" flatpak/flatpak_build.json
else
    echo "=== Building Flatpak (build only, no install) ==="
    flatpak-builder --force-clean \
        "$BUILD_DIR" flatpak/flatpak_build.json
    echo ""
    echo "To install and run:"
    echo "  flatpak-builder --force-clean --install --user $BUILD_DIR flatpak/flatpak_build.json"
    echo "  flatpak run io.photoflare.photoflare"
fi

if [[ $DO_RUN -eq 1 ]]; then
    echo ""
    echo "=== Launching io.photoflare.photoflare ==="
    flatpak run io.photoflare.photoflare
fi
