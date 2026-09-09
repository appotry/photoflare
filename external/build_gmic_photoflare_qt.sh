#!/usr/bin/env bash
# build_gmic_photoflare_qt.sh
# Builds the gmic_photoflare_qt binary from the gmic-qt and gmic submodules.
#
# Usage:
#   ./external/build_gmic_photoflare_qt.sh [--prefix /path/to/qt6]
#
# Options:
#   --prefix PATH   Path to a Qt6 installation (sets CMAKE_PREFIX_PATH).
#                   Defaults to whatever cmake/qmake6 can find on the system.
#
# Output: external/gmic-qt-build-linux/gmic_photoflare_qt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GMIC_QT_SRC="$SCRIPT_DIR/gmic-qt"
GMIC_SRC="$SCRIPT_DIR/gmic/src"
BUILD_DIR="$SCRIPT_DIR/gmic-qt-build-linux"
OUTPUT_BIN="$BUILD_DIR/gmic_photoflare_qt"

QT_PREFIX=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            QT_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Verify submodules are present
if [[ ! -f "$GMIC_QT_SRC/CMakeLists.txt" ]]; then
    echo "ERROR: gmic-qt submodule not found at $GMIC_QT_SRC"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [[ ! -f "$GMIC_SRC/gmic.h" ]]; then
    echo "ERROR: gmic submodule not found at $GMIC_SRC"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Install build dependencies via apt if available
APT_PACKAGES=(
    cmake
    ninja-build
    make
    wget
    qt6-base-dev
    qt6-tools-dev
    qt6-tools-dev-tools
    libfftw3-dev
    libcurl4-openssl-dev
    libomp-dev
    zlib1g-dev
    libpng-dev
)

if command -v apt-get &>/dev/null; then
    echo "=== Installing build dependencies ==="
    if [[ $EUID -eq 0 ]]; then
        apt-get install -y "${APT_PACKAGES[@]}"
    elif command -v sudo &>/dev/null; then
        sudo apt-get install -y "${APT_PACKAGES[@]}"
    else
        echo "WARNING: Not root and sudo not available — skipping apt install."
        echo "Please ensure the following packages are installed:"
        printf '  %s\n' "${APT_PACKAGES[@]}"
    fi
    echo ""
else
    echo "NOTE: apt-get not found — skipping dependency install."
    echo "Please ensure the equivalent packages are installed for your distro."
    echo ""
fi

# Check for required tools
for cmd in cmake make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' not found. Dependency install may have failed."
        exit 1
    fi
done

# CImg.h and gmic_stdlib_community.h are not committed to the gmic submodule —
# they must be downloaded before cmake runs.
#
# IMPORTANT: the gmic Makefile's CImg.h target always downloads from master (latest),
# which may not match the pinned gmic version. Download from the matching CImg tag instead.
echo "=== Fetching gmic generated headers ==="

# Extract gmic version number (e.g. 375) and build the matching CImg tag (e.g. v.3.7.5)
GMIC_VER=$(grep -oP '(?<=gmic_version )\d+' "$GMIC_SRC/gmic.h")
CIMG_TAG="v.${GMIC_VER:0:1}.${GMIC_VER:1:1}.${GMIC_VER:2:1}"

# Download CImg.h directly from the versioned tag — do NOT use "make CImg.h" which downloads master
if [[ ! -f "$GMIC_SRC/CImg.h" ]]; then
    echo "  Downloading CImg.h at tag $CIMG_TAG ..."
    wget --no-check-certificate --quiet -O "$GMIC_SRC/CImg.h" \
        "https://github.com/GreycLab/CImg/raw/${CIMG_TAG}/CImg.h"
else
    echo "  CImg.h already present, skipping."
fi

# gmic_stdlib_community.h: the gmic Makefile uses a version-specific URL (safe to use make)
if [[ ! -f "$GMIC_SRC/gmic_stdlib_community.h" ]]; then
    echo "  Generating gmic_stdlib_community.h ..."
    make -C "$GMIC_SRC" gmic_stdlib_community.h
else
    echo "  gmic_stdlib_community.h already present, skipping."
fi
echo ""

# Ensure lrelease (Qt6) is on PATH — on Ubuntu it lives in /usr/lib/qt6/bin/
# but is not symlinked to /usr/bin. The gmic-qt translations Makefile needs it.
if ! command -v lrelease &>/dev/null && ! command -v lrelease-qt5 &>/dev/null; then
    QT6_LRELEASE=$(find /usr/lib/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/bin \
                        /opt/qt6/bin /usr/local/lib/qt6/bin \
                        -name "lrelease" 2>/dev/null | head -1 || true)
    if [[ -n "$QT6_LRELEASE" ]]; then
        echo "  Adding $(dirname "$QT6_LRELEASE") to PATH for lrelease"
        export PATH="$(dirname "$QT6_LRELEASE"):$PATH"
    else
        echo "WARNING: lrelease not found — gmic-qt translation files may fail to build."
    fi
fi

CMAKE_EXTRA_ARGS=()
if [[ -n "$QT_PREFIX" ]]; then
    CMAKE_EXTRA_ARGS+=("-DCMAKE_PREFIX_PATH=$QT_PREFIX")
fi

echo "=== Configuring gmic-qt ==="
cmake "$GMIC_QT_SRC" \
    -B "$BUILD_DIR" \
    -DBUILD_WITH_QT6=ON \
    -DGMIC_QT_HOST=none \
    -DENABLE_SYSTEM_GMIC=OFF \
    -DGMIC_PATH="$GMIC_SRC" \
    -DENABLE_FFTW3=ON \
    -DENABLE_CURL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS="-no-pie" \
    "${CMAKE_EXTRA_ARGS[@]}"

echo ""
echo "=== Building gmic-qt ==="
cmake --build "$BUILD_DIR" --parallel 1

echo ""
echo "=== Renaming to gmic_photoflare_qt ==="
mv "$BUILD_DIR/gmic_qt" "$OUTPUT_BIN"

echo ""
echo "=== Done. Output: $OUTPUT_BIN ==="
