#!/usr/bin/env bash
# Builds the installable versions of Stronghold Assault into dist/:
#   dist/StrongholdAssault-<ver>-Windows-Setup.exe    Windows installer (shortcuts, uninstaller)
#   dist/StrongholdAssault-<ver>-Windows-Portable.zip  Windows, unzip and run
#   dist/StrongholdAssault-<ver>-Linux.tar.gz          Linux, unpack and ./install.sh (or just run)
#
# Needs: Godot 4.5.x with its export templates installed, makensis (NSIS 3), zip, tar.
# Assets must be real files, not LFS pointers (git lfs pull).
#
# Usage:  installer/build_release.sh [version]          (default 1.0.0)
#         GODOT=/path/to/godot installer/build_release.sh 1.2.0
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || command -v godot4 || true)}"
[ -n "$GODOT" ] || { echo "Set GODOT=/path/to/Godot_v4.5.x binary" >&2; exit 1; }
command -v makensis >/dev/null || { echo "makensis (NSIS) not found" >&2; exit 1; }

# Refuse to ship LFS pointer files instead of models.
if head -c 40 "$ROOT/game/assets/stronghold/stronghold.glb" | grep -q "git-lfs"; then
  echo "Assets are Git LFS pointers - run 'git lfs pull' first." >&2; exit 1
fi

BUILD="$ROOT/builds"
DIST="$ROOT/dist"
rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD/windows" "$BUILD/linux" "$DIST"

echo "== Importing assets"
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true

echo "== Exporting Windows"
"$GODOT" --headless --path "$ROOT/game" --export-release "Windows" "$BUILD/windows/StrongholdAssault.exe"
echo "== Exporting Linux"
"$GODOT" --headless --path "$ROOT/game" --export-release "Linux" "$BUILD/linux/StrongholdAssault.x86_64"
for f in windows/StrongholdAssault.exe windows/StrongholdAssault.pck linux/StrongholdAssault.x86_64 linux/StrongholdAssault.pck; do
  [ -s "$BUILD/$f" ] || { echo "Export failed: $f missing" >&2; exit 1; }
done

echo "== Smoke test (Linux build loads the match and quits)"
if "$BUILD/linux/StrongholdAssault.x86_64" --headless res://scenes/match.tscn --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|Failed loading resource"; then
  echo "Smoke test found errors" >&2; exit 1
fi

echo "== Windows installer"
makensis -V2 -DVERSION="$VERSION" -DSRC_DIR="$BUILD/windows" \
  -DOUT_FILE="$DIST/StrongholdAssault-$VERSION-Windows-Setup.exe" \
  "$ROOT/installer/windows/StrongholdAssault.nsi"

echo "== Windows portable zip"
PORT="$BUILD/StrongholdAssault-Windows"
mkdir -p "$PORT"
cp "$BUILD/windows/"StrongholdAssault.{exe,pck} "$PORT/"
cp "$ROOT/installer/HOW_TO_PLAY.txt" "$PORT/How to play.txt"
(cd "$BUILD" && zip -q -r "$DIST/StrongholdAssault-$VERSION-Windows-Portable.zip" "StrongholdAssault-Windows")

echo "== Linux package"
LIN="$BUILD/StrongholdAssault-Linux"
mkdir -p "$LIN"
cp "$BUILD/linux/"StrongholdAssault.{x86_64,pck} "$LIN/"
cp "$ROOT/installer/icon.png" "$ROOT/installer/HOW_TO_PLAY.txt" "$ROOT/installer/linux/install.sh" "$ROOT/installer/linux/uninstall.sh" "$LIN/"
chmod +x "$LIN/StrongholdAssault.x86_64" "$LIN/install.sh" "$LIN/uninstall.sh"
tar -C "$BUILD" -czf "$DIST/StrongholdAssault-$VERSION-Linux.tar.gz" "StrongholdAssault-Linux"

(cd "$DIST" && sha256sum * > SHA256SUMS.txt)
echo
echo "Built:"
ls -lh "$DIST"
