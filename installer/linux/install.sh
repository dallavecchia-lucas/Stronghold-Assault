#!/usr/bin/env bash
# Stronghold Assault - Linux installer.
# Run from the unpacked folder:   ./install.sh
# Installs for your user only (no sudo): the game in ~/.local/share/stronghold-assault,
# a `stronghold-assault` command in ~/.local/bin and an entry in your applications menu.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/stronghold-assault"
BIN_DIR="$HOME/.local/bin"
DESKTOP_FILE="$DATA_HOME/applications/stronghold-assault.desktop"
ICON_FILE="$DATA_HOME/icons/hicolor/256x256/apps/stronghold-assault.png"

for f in StrongholdAssault.x86_64 StrongholdAssault.pck icon.png uninstall.sh; do
  [ -f "$HERE/$f" ] || { echo "Missing $f next to install.sh - unpack the whole archive first." >&2; exit 1; }
done

echo "Installing Stronghold Assault to $APP_DIR ..."
mkdir -p "$APP_DIR" "$BIN_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
cp "$HERE/StrongholdAssault.x86_64" "$HERE/StrongholdAssault.pck" "$HERE/icon.png" "$HERE/uninstall.sh" "$APP_DIR/"
[ -f "$HERE/HOW_TO_PLAY.txt" ] && cp "$HERE/HOW_TO_PLAY.txt" "$APP_DIR/"
chmod +x "$APP_DIR/StrongholdAssault.x86_64" "$APP_DIR/uninstall.sh"
cp "$HERE/icon.png" "$ICON_FILE"

ln -sf "$APP_DIR/StrongholdAssault.x86_64" "$BIN_DIR/stronghold-assault"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Stronghold Assault
Comment=Asymmetric RTS vs FPS siege game
Exec="$APP_DIR/StrongholdAssault.x86_64"
Path=$APP_DIR
Icon=stronghold-assault
Terminal=false
Categories=Game;ActionGame;StrategyGame;
EOF
chmod +x "$DESKTOP_FILE"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true

echo
echo "Done. Start it from your applications menu (Stronghold Assault),"
echo "or run:  stronghold-assault"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "(add $BIN_DIR to your PATH to use the command, or run $APP_DIR/StrongholdAssault.x86_64)";; esac
echo "To uninstall:  $APP_DIR/uninstall.sh"

if [ "${1:-}" != "--no-launch" ] && [ -t 0 ]; then
  read -r -p "Play now? [Y/n] " ans
  case "${ans:-y}" in [Yy]*) (cd "$APP_DIR" && nohup ./StrongholdAssault.x86_64 >/dev/null 2>&1 &) ;; esac
fi
