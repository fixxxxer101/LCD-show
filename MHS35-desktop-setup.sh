#!/bin/bash
# MHS35-desktop-setup.sh — user-side desktop setup for an
# MHS35-DRM-show install. Run as your normal user (NO sudo), from
# the repo directory, after the installer has run and rebooted:
#   ./MHS35-desktop-setup.sh
#
# It installs the verified-on-hardware arrangement:
#   * kanshi layout profile: HDMI = main display at 0,0, panel
#     rotated (transform 90) as secondary at 1024,0
#   * taskbar/panel pinned to the HDMI output (wf-panel-pi
#     "monitor=" setting), so menus open on the big screen and
#     stay inside it
#   * Super+V keybind in labwc rc.xml creating the "BothScreens"
#     virtual output
#   * mhs35-bothscreens.sh in ~/.local/bin + a labwc autostart
#     line, so every login recreates the virtual output and
#     points Raspberry Pi Connect at it (Connect then shows both
#     screens side by side; the part of the virtual frame below
#     the small panel is extra space only visible via Connect)
# Existing files are backed up next to the originals
# (config.bak-<timestamp>). Safe to re-run.

set -u
cd "$(dirname "$0")"
STAMP=$(date +%Y%m%d-%H%M%S)

backup() {
  if [ -f "$1" ]; then
    cp -a "$1" "$1.bak-$STAMP"
    echo "backed up $1 -> $1.bak-$STAMP"
  fi
}

# --- kanshi layout profile ---
KDIR="$HOME/.config/kanshi"
mkdir -p "$KDIR"
backup "$KDIR/config"
cp -f ./usr/mhs35-kanshi-layout.conf "$KDIR/config"
echo "installed kanshi layout profile -> $KDIR/config"
pkill -HUP kanshi 2>/dev/null || true

# --- taskbar on the big screen ---
PANEL_INI="$HOME/.config/wf-panel-pi/wf-panel-pi.ini"
[ -f "$PANEL_INI" ] || PANEL_INI="$HOME/.config/wf-panel-pi.ini"
if [ -f "$PANEL_INI" ]; then
  backup "$PANEL_INI"
  if grep -q '^monitor=' "$PANEL_INI"; then
    sed -i 's/^monitor=.*/monitor=HDMI-A-1/' "$PANEL_INI"
  else
    sed -i 's/^\[panel\]/[panel]\nmonitor=HDMI-A-1/' "$PANEL_INI"
  fi
else
  mkdir -p "$(dirname "$PANEL_INI")"
  printf '[panel]\nmonitor=HDMI-A-1\n' > "$PANEL_INI"
fi
echo "taskbar pinned to HDMI-A-1 in $PANEL_INI"
# Restart the panel so the change takes effect now. The session
# supervisor respawns wf-panel-pi when it exits (verified on
# hardware) — do NOT launch a copy by hand, that gives two panels.
pkill wf-panel-pi 2>/dev/null || true

# --- Super+V creates the virtual output ---
RC="$HOME/.config/labwc/rc.xml"
mkdir -p "$(dirname "$RC")"
if [ -f "$RC" ] && grep -q 'BothScreens' "$RC"; then
  echo "rc.xml already has the BothScreens keybind"
elif [ -f "$RC" ]; then
  backup "$RC"
  sed -i 's|</openbox_config>|  <keyboard>\n    <keybind key="W-v">\n      <action name="VirtualOutputAdd" output_name="BothScreens"/>\n    </keybind>\n  </keyboard>\n</openbox_config>|' "$RC"
  echo "added Super+V keybind to $RC"
else
  printf '<?xml version="1.0"?>\n<openbox_config xmlns="http://openbox.org/3.4/rc">\n  <keyboard>\n    <keybind key="W-v">\n      <action name="VirtualOutputAdd" output_name="BothScreens"/>\n    </keybind>\n  </keyboard>\n</openbox_config>\n' > "$RC"
  echo "created $RC with the Super+V keybind"
fi
killall -SIGHUP labwc 2>/dev/null || true

# --- login script + autostart ---
mkdir -p "$HOME/.local/bin"
cp -f ./usr/mhs35-bothscreens.sh "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/mhs35-bothscreens.sh"
AUTOSTART="$HOME/.config/labwc/autostart"
touch "$AUTOSTART"
if grep -q 'mhs35-bothscreens' "$AUTOSTART"; then
  echo "autostart already runs mhs35-bothscreens.sh"
else
  backup "$AUTOSTART"
  echo '$HOME/.local/bin/mhs35-bothscreens.sh &' >> "$AUTOSTART"
  echo "added mhs35-bothscreens.sh to labwc autostart"
fi

# --- apply now, not just at next login ---
"$HOME/.local/bin/mhs35-bothscreens.sh"
echo "done. Reboot once to verify everything comes back on its own:"
echo "layout, taskbar on the big screen, and Connect showing both."
