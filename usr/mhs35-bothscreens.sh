#!/bin/sh
# SUPERSEDED by usr/mhs35-layout.sh (autodetect layout), which
# also sizes the virtual output — to the real layout instead of
# this script's hardcoded 1504x768 — and re-asserts positions
# from measured sizes instead of fixed ones. Kept for history;
# the desktop setup no longer installs this file.
#
# mhs35-bothscreens.sh — make Raspberry Pi Connect show BOTH screens.
#
# Pi Connect's screen sharing is wayvnc, and wayvnc captures exactly
# one output. This script works around that with a labwc virtual
# output ("BothScreens") that spans the whole desktop layout, and
# points Connect's wayvnc at it. Connect then shows the screens side
# by side, as arranged, and the mouse can cross between them.
#
# Installed to ~/.local/bin/ and run from ~/.config/labwc/autostart
# at every login (virtual outputs do not survive logout/reboot).
# Safe to run again by hand; it does nothing if already set up.
#
# Layout assumption (see usr/mhs35-kanshi-layout.conf): HDMI at
# 1024x768, panel 480x320 landscape to its right -> the layout is
# 1504x768. If you change the HDMI mode, change VIRTUAL_SIZE to
# (hdmi_width + 480) x hdmi_height.

VIRTUAL_SIZE=1504x768
CTL="$XDG_RUNTIME_DIR/rpi-connect-wayvnc-ctl.sock"

# Log every run: a silent failure here cost a debugging round on
# 2026-11-19 (wtype missing, script exited 0 without a word).
mkdir -p "$HOME/.local/state"
exec >> "$HOME/.local/state/mhs35-bothscreens.log" 2>&1
echo "--- run at $(date) ---"

# Give the compositor, kanshi and Connect's wayvnc time to start.
sleep 5

# Create the virtual output via the Super+V keybind (installed in
# ~/.config/labwc/rc.xml) if it is not there yet.
if ! wlr-randr 2>/dev/null | grep -q '^BothScreens'; then
  if command -v wtype >/dev/null 2>&1; then
    wtype -M logo -P v -m logo 2>/dev/null
    sleep 2
  else
    echo "FAIL: wtype is not installed — cannot trigger Super+V."
    echo "      install it with: sudo apt install -y wtype"
  fi
fi

# Still not there: leave the session as-is (physical screens only).
if ! wlr-randr 2>/dev/null | grep -q '^BothScreens'; then
  echo "FAIL: BothScreens virtual output was not created."
  exit 0
fi
echo "virtual output present"

# Span the whole layout, from the top-left corner.
wlr-randr --output BothScreens --custom-mode "$VIRTUAL_SIZE" \
  --pos 0,0 2>/dev/null

# Creating/resizing the virtual output makes the compositor
# re-flow the row of outputs: on hardware the panel ended up at
# 1504,0 — outside the virtual frame, so Connect "lost" the small
# screen. Re-assert the physical layout after sizing, and verify.
wlr-randr --output HDMI-A-1 --pos 0,0 2>/dev/null
wlr-randr --output SPI-1 --pos 1024,0 2>/dev/null
sleep 1
if wlr-randr 2>/dev/null | grep -A99 '^SPI-1' \
     | grep -q 'Position: 1024,0'; then
  echo "panel placed at 1024,0 inside the virtual frame"
else
  echo "FAIL: panel is not at 1024,0 — see wlr-randr output"
fi

# Point Pi Connect's wayvnc at the virtual output. Its control
# socket can take a while to appear, so retry for ~30 seconds.
n=0
while [ $n -lt 10 ]; do
  if [ -S "$CTL" ] && wayvncctl --socket="$CTL" \
       output-set BothScreens 2>/dev/null; then
    echo "Pi Connect capture set to BothScreens"
    exit 0
  fi
  n=$((n + 1))
  sleep 3
done
echo "FAIL: could not set Pi Connect capture (socket: $CTL)"

exit 0
