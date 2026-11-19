#!/usr/bin/env bash
# Removes Stronghold Assault installed by install.sh. Settings and saves in
# ~/.local/share/godot/app_userdata/Stronghold Assault are kept.
set -euo pipefail
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -f "$HOME/.local/bin/stronghold-assault" \
      "$DATA_HOME/applications/stronghold-assault.desktop" \
      "$DATA_HOME/icons/hicolor/256x256/apps/stronghold-assault.png"
rm -rf "$DATA_HOME/stronghold-assault"
echo "Stronghold Assault uninstalled."
