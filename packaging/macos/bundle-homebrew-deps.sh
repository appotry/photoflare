#!/usr/bin/env bash
# Bundles the non-Qt (Homebrew) dependencies of one or more executables into
# Contents/Frameworks and rewrites their load commands to be
# @executable_path-relative, so the resulting .app doesn't depend on the
# build machine's Homebrew install (graphicsmagick/libomp/fftw and their own
# transitive deps such as lcms2/freetype/libpng/libltdl).
#
# This intentionally reimplements the small part of what dylibbundler does
# instead of using it: dylibbundler's own dependency-copy loop can abort with
# "cp: ... are identical (not copied)" on diamond-shaped dependency graphs
# where several bundled dylibs share the same transitive dependency (see
# auriamg/macdylibbundler#83, unresolved upstream). That happens because
# dylibbundler resolves a dependent's own @loader_path/@rpath references
# against its *already-copied* Contents/Frameworks copy while recursively
# walking dependencies-of-dependencies, and BSD realpath(3) happily resolves
# a path whose final component doesn't exist yet, making a not-yet-bundled
# sibling look like it already lives at its own destination path. To avoid
# that, this script fully discovers the dependency closure first (always
# resolving @loader_path/@rpath against original, on-disk Homebrew files —
# never against files already copied into Frameworks), and only then copies
# and fixes everything up as a separate step.
#
# Usage: bundle-homebrew-deps.sh <App.app> <executable-or-dylib>...
set -euo pipefail

APP="$1"
shift
EXECUTABLES=("$@")

FRAMEWORKS_DIR="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

DEP_NAMES=()
DEP_SRCS=()
VISITED=()
QUEUE=()

contains() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    [ "$x" = "$needle" ] && return 0
  done
  return 1
}

abspath() {
  local d b
  d=$(cd "$(dirname "$1")" && pwd) || return 1
  b=$(basename "$1")
  printf '%s/%s\n' "$d" "$b"
}

# Qt frameworks are already handled by macdeployqt; system libs are assumed
# present on every macOS install and shouldn't be bundled.
is_ignored() {
  case "$1" in
    /usr/lib/*|/System/*|*.framework/*|*.framework) return 0 ;;
  esac
  return 1
}

read_rpaths() {
  otool -l "$1" 2>/dev/null | awk '
    /cmd LC_RPATH/ { getline; getline; sub(/^ *path /,""); sub(/ \(offset.*$/,""); print }'
}

# Resolves an install-name string recorded in a Mach-O load command (as seen
# via `otool -L`) to a real, existing file on disk, given the absolute path
# of the file that recorded it.
resolve_dep() {
  local dep="$1" referrer_abs="$2" referrer_dir resolved rp
  referrer_dir=$(dirname "$referrer_abs")
  case "$dep" in
    @loader_path/*) resolved="$referrer_dir/${dep#@loader_path/}" ;;
    @executable_path/*) resolved="$referrer_dir/${dep#@executable_path/}" ;;
    @rpath/*)
      resolved=""
      while IFS= read -r rp; do
        [ -z "$rp" ] && continue
        case "$rp" in
          @loader_path/*) rp="$referrer_dir/${rp#@loader_path/}" ;;
          @executable_path/*) rp="$referrer_dir/${rp#@executable_path/}" ;;
        esac
        if [ -e "$rp/${dep#@rpath/}" ]; then
          resolved="$rp/${dep#@rpath/}"
          break
        fi
      done < <(read_rpaths "$referrer_abs")
      ;;
    /*) resolved="$dep" ;;
    *) resolved="" ;;
  esac
  [ -n "$resolved" ] && [ -e "$resolved" ] && abspath "$resolved"
}

# Discovers (never copies) the full dependency closure of $1, always
# resolving against the original on-disk file, not any Frameworks copy.
scan() {
  local file_abs="$1" line dep resolved base
  contains "$file_abs" "${VISITED[@]:-}" && return 0
  VISITED+=("$file_abs")

  while IFS= read -r line; do
    dep=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//')
    [ -z "$dep" ] && continue
    is_ignored "$dep" && continue
    resolved=$(resolve_dep "$dep" "$file_abs") || continue
    [ -z "$resolved" ] && continue
    base=$(basename "$resolved")
    if ! contains "$base" "${DEP_NAMES[@]:-}"; then
      DEP_NAMES+=("$base")
      DEP_SRCS+=("$resolved")
      QUEUE+=("$resolved")
    fi
  done < <(otool -L "$file_abs" | tail -n +2)
}

for exe in "${EXECUTABLES[@]}"; do
  QUEUE+=("$(abspath "$exe")")
done

while [ "${#QUEUE[@]}" -gt 0 ]; do
  next="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")
  scan "$next"
done

echo "Bundling ${#DEP_NAMES[@]} Homebrew dependencies into $FRAMEWORKS_DIR"
for i in "${!DEP_NAMES[@]}"; do
  base="${DEP_NAMES[$i]}"
  src="${DEP_SRCS[$i]}"
  dest="$FRAMEWORKS_DIR/$base"
  if [ ! -e "$dest" ]; then
    echo "  + $base  (from $src)"
    cp -L "$src" "$dest"
    chmod +w "$dest"
    install_name_tool -id "@executable_path/../Frameworks/$base" "$dest"
  fi
done

find_src_index() {
  local needle="$1" i
  for i in "${!DEP_NAMES[@]}"; do
    if [ "${DEP_NAMES[$i]}" = "$needle" ]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

# Rewrites $1's own load commands to point at the bundled copies. Sibling
# dylibs inside Frameworks that reference each other via @loader_path already
# resolve correctly once co-located, but rewriting them too keeps every
# reference consistently @executable_path-relative.
fix_refs() {
  local file="$1" line dep base
  while IFS= read -r line; do
    dep=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//')
    [ -z "$dep" ] && continue
    case "$dep" in
      @executable_path/../Frameworks/*) continue ;;
    esac
    base=$(basename "$dep")
    if find_src_index "$base" >/dev/null; then
      install_name_tool -change "$dep" "@executable_path/../Frameworks/$base" "$file"
    fi
  done < <(otool -L "$file" | tail -n +2)
}

for exe in "${EXECUTABLES[@]}"; do
  fix_refs "$exe"
done
for base in "${DEP_NAMES[@]}"; do
  fix_refs "$FRAMEWORKS_DIR/$base"
done

echo "Done bundling Homebrew dependencies."
