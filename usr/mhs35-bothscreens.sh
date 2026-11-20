#!/bin/sh
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

# Give the compositor, kanshi and Connect's wayvnc time to start.
sleep 5

# Create the virtual output via the Super+V keybind (installed in
# ~/.config/labwc/rc.xml) if it is not there yet.
if ! wlr-randr 2>/dev/null | grep -q '^BothScreens'; then
  if command -v wtype >/dev/null 2>&1; then
    wtype -M logo -P v -m logo 2>/dev/null
    sleep 2
  fi
fi

# Still not there: leave the session as-is (physical screens only).
wlr-randr 2>/dev/null | grep -q '^BothScreens' || exit 0

# Span the whole layout, from the top-left corner.
wlr-randr --output BothScreens --custom-mode "$VIRTUAL_SIZE" \
  --pos 0,0 2>/dev/null

# Point Pi Connect's wayvnc at the virtual output. Its control
# socket can take a while to appear, so retry for ~30 seconds.
n=0
while [ $n -lt 10 ]; do
  if [ -S "$CTL" ] && wayvncctl --socket="$CTL" \
       output-set BothScreens 2>/dev/null; then
    break
  fi
  n=$((n + 1))
  sleep 3
done

exit 0
