# Fork fixes: MHS-3.5 kills HDMI + Raspberry Pi Connect

Fork of goodtft/LCD-show (upstream HEAD `a36c00a`). One problem, three
causes, all in the installer — the panel hardware and driver are fine.

## Symptoms

After `sudo ./MHS35-show` the panel works, but:

1. HDMI output is gone / unusable.
2. Raspberry Pi Connect offers only the remote shell — screen sharing
   (remote desktop) is disabled.

## Root cause

1. **`system_config.sh` replaces `config.txt` wholesale** with
   `boot/config-nomal-*.txt`, in which `dtoverlay=vc4-kms-v3d` is
   commented out (and `disable_fw_kms_setup=1` is set). No KMS means
   no DRM device at all: `kmsprint` reports "failed to find DRM
   cards". HDMI has no driver and Wayland has nothing to run on.

2. **`system_config.sh` reconfigures the session:**
   `do_boot_behaviour B2` (console autologin, no desktop) and
   `do_wayland W1` (X11). Pi Connect screen sharing requires a
   Wayland desktop session with desktop autologin — it does not work
   on X11 or from a console boot. On Debian 13 the install also drops
   a `~/.bash_profile` that runs `startx` on `/dev/fb1`, bypassing
   Wayland entirely.

3. **`MHS35-show` forces the HDMI output to the panel's resolution:**
   `hdmi_force_hotplug=1`, `hdmi_group=2`, `hdmi_mode=87`,
   `hdmi_cvt 480 320 …`. That is the legacy design, not a bug in
   isolation: render the desktop on HDMI (fb0) at 480×320, then copy
   fb0 → fb1 (the SPI panel) with `fbcp`. HDMI was never an
   independent output in that design — it was the panel's source.
   (On Pi 5 / Debian 13 the design is doubly dead: DispmanX, which
   `fbcp` uses, no longer exists.)

## The fix

**New installer: `MHS35-DRM-show`** — use this one on Bookworm/Trixie.

- Edits the real `/boot/firmware/config.txt` **in place** (timestamped
  backup first). Never replaces it, never touches unrelated settings.
- Keeps `dtoverlay=vc4-kms-v3d` enabled; removes only the lines a
  previous LCD-show install added (`dtoverlay=mhs35…`, `hdmi_cvt`,
  `hdmi_mode=87`, fbcp hooks, fbturbo config, the `startx`
  `.bash_profile`, the X11 calibration file — moved aside, not deleted).
- Sets desktop autologin (B4) + labwc Wayland (W3 on Debian 12,
  W2 on Debian 13 — the codes differ by release).
- Loads the panel via a new **`drm` parameter on the mhs35 overlay**:
  `dtoverlay=mhs35,drm,rotate=90,speed=24000000`.

**Overlay: source + `drm` override.** Upstream shipped only a binary
`usr/mhs35-overlay.dtb` with no source. This fork adds
`usr/mhs35-overlay.dts` (reconstructed from the shipped binary —
init sequence, SPI frequency, rotation and fps verified identical
after rebuild) plus `usr/build-mhs35-overlay.sh`, and one functional
addition, modelled on the stock Raspberry Pi `piscreen` overlay
(same wiring: ILI9486, reset GPIO25, DC GPIO24, ADS7846 touch on
GPIO17): the `drm` override switches the panel's compatible to
`waveshare,rpi-lcd-35` and flips the reset GPIO polarity, binding
the kernel's ILI9486 **DRM** driver instead of fbtft. Without `drm`
the overlay behaves exactly as before.

Result: HDMI is DRM output 1, the panel is DRM output 2 (SPI) at
480×320, labwc presents both, and Pi Connect screen sharing works.
Plug HDMI in at any time.

**Desktop arrangement** (installed by `MHS35-desktop-setup.sh`,
run as the desktop user — it is session state, so the root
installer does not touch it):

- **Layout — `usr/mhs35-kanshi-layout.conf`:** kanshi profile with
  HDMI as the main display (1024×768 at 0,0) and the panel as a
  rotated secondary (its only mode is 320×480 portrait; compositor
  `transform 90` makes it 480×320 landscape) at 1024,0. kanshi
  matches the first profile whose output count equals the number
  of connected displays, hence one profile per case.
- **Taskbar on the big screen:** `monitor=HDMI-A-1` in
  `~/.config/wf-panel-pi/wf-panel-pi.ini`. Without it the panel
  process puts the taskbar — and its menus, which are taller than
  320px — on the small screen, where they overflow unreadably.
- **Pi Connect showing both screens:** Connect's wayvnc captures
  exactly one output, and position changes do not affect its
  choice. The setup adds a labwc keybind (Super+V) that creates a
  virtual output `BothScreens`, and installs
  `usr/mhs35-bothscreens.sh` to `~/.local/bin/` + labwc autostart:
  every login it recreates the virtual output, sizes it to span
  the whole layout (1504×768), and points Connect's wayvnc at it
  via its control socket (`wayvncctl … output-set BothScreens`).
  Connect then shows both screens side by side and the mouse
  crosses between them. Bonus: the part of the virtual frame not
  covered by a physical screen (below the small panel) is extra
  desktop space visible only through Connect.

An earlier revision mirrored the outputs instead (one 480×320
desktop everywhere, like the legacy fbcp design). It was built and
tested, then superseded by the arrangement above at the owner's
direction; `MHS35-mirror.sh` and `usr/mhs35-kanshi-mirror.conf`
remain in the repo marked SUPERSEDED for history.

**`system_config.sh`:** the forced `B2` / `W1` lines are removed
(see the comment there). A display installer should not silently
change the user's boot behaviour or display backend.

## Repairing a Pi that already ran the old installer

Run the new installer on it — it cleans up the legacy leftovers
listed above as part of installing:

```
git clone https://github.com/fixxxxer101/LCD-show.git
cd LCD-show
sudo ./MHS35-DRM-show
# after the reboot, as your normal user:
./MHS35-desktop-setup.sh
```

## Verify after reboot

```
kmsprint                 # should list HDMI + SPI outputs, no error
ls /sys/class/drm        # card*-HDMI-* and card*-SPI-*
echo $XDG_SESSION_TYPE   # in the desktop terminal: wayland
rpi-connect status       # screen sharing available
```

## Hardware test log

Hardware: Pi 5, user `pi5`, ViewSonic NX2232w on HDMI-A-1
(preferred mode 1024×768). All entries 2026-11-19, Clint's Pi.

- DRM installer verified working — panel + HDMI live, Pi Connect
  screen sharing back. Default layout was extended (panel left,
  HDMI right) and Connect captured only the panel's slice.
- Panel facts learned from `wlr-randr`: output name `SPI-1`, single
  mode 320×480 (portrait) — the landscape picture comes from the
  compositor transform, and any config asking the panel itself for
  480x320 silently fails. Touch already maps to SPI-1 in labwc
  rc.xml (`mapToOutput="SPI-1"`, set by the OS).
- Mirror attempt: kanshi profile asking SPI-1 for mode 480x320
  never matched/applied (see above). A live overlap at matching
  logical size (HDMI 720x480 @ scale 1.5) did mirror, but the owner
  rejected panel-resolution on the big monitor; custom HDMI modes
  1440x960 / 960x640 were rejected by the monitor ("out of range")
  or unwanted. Mirroring abandoned by owner decision.
- Final arrangement verified live, in order: panel rotated
  (transform 90); HDMI made main (position 0,0, panel at 1024,0);
  Connect capture switched with `wayvncctl output-set` (its
  control socket is `$XDG_RUNTIME_DIR/rpi-connect-wayvnc-ctl.sock`;
  `output-list` shows the captured output with `*`); taskbar moved
  to the big screen via wf-panel-pi `monitor=HDMI-A-1` (menus had
  been opening on the 320px-tall panel and overflowing);
  `BothScreens` virtual output created by labwc keybind, sized
  1504x768 at 0,0, Connect pointed at it — owner confirms Connect
  shows both screens side by side, mouse crosses, and the
  virtual-only area below the panel works as extra space.
- Persistence packaged in `MHS35-desktop-setup.sh` + `update.sh`.
  First reboot test found two bugs, both fixed and re-verified:
  wtype missing from the default install (setup now installs it;
  login script logs every run to
  `~/.local/state/mhs35-bothscreens.log`), and the compositor
  re-flowing the panel to 1504,0 when the virtual output is
  resized (login script now re-asserts positions and verifies).
- Final cold-boot verification PASSED 2026-11-19: after reboot,
  with no manual steps, the layout, taskbar, virtual output and
  Pi Connect showing both screens all came back on their own.
  Owner's verdict: "perfect".

## Still to confirm on real hardware

- Panel colours/orientation under the DRM driver with this init
  sequence (rotation default 90 matches the legacy installer's).
- Touch axes under Wayland/libinput; if swapped, add `swapxy` to
  the `dtoverlay=mhs35,…` line and reboot.
- Max stable SPI speed for the DRM driver on this panel
  (conservative 24 MHz default; the fbtft number does not carry over).
