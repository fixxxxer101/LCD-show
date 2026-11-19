#!/bin/bash
# MHS35-mirror.sh — switch an MHS35-DRM-show install to a mirrored
# desktop: panel, HDMI and Pi Connect all show the same 480x320
# landscape desktop instead of an extended left/right layout.
#
# Run as your normal user (NO sudo), from the repo directory:
#   ./MHS35-mirror.sh
# It only writes your own ~/.config/kanshi/config (any existing
# config is backed up next to it as config.bak-<timestamp>) and
# asks kanshi to reload. Nothing else is touched; no reboot needed.

set -u

SRC="$(dirname "$0")/usr/mhs35-kanshi-mirror.conf"
if [ ! -f "$SRC" ]; then
  echo "cannot find $SRC — run this from the LCD-show repo directory"
  exit 1
fi

DEST_DIR="$HOME/.config/kanshi"
DEST="$DEST_DIR/config"
mkdir -p "$DEST_DIR"
if [ -f "$DEST" ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  cp -a "$DEST" "$DEST.bak-$STAMP"
  echo "backed up existing kanshi config -> $DEST.bak-$STAMP"
fi
cp -f "$SRC" "$DEST"
echo "installed mirror profile -> $DEST"

# kanshi reloads its config on SIGHUP; if it is not running in this
# session, the profile applies at next login instead.
if pkill -HUP kanshi 2>/dev/null; then
  echo "kanshi reloaded — the screens should switch to mirrored now."
else
  echo "kanshi not running in this session — log out/in (or reboot)"
  echo "and the mirror profile will be active."
fi
echo "To undo: restore the config.bak-* file (or delete $DEST) and"
echo "log out/in."
