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

**Mirrored by default.** Two DRM outputs with no layout config give
an *extended* desktop (panel left, HDMI right) — and Pi Connect then
captures only part of the layout. The legacy design was mirrored
(one desktop everywhere), so the installer also writes a **kanshi
profile** (`usr/mhs35-kanshi-mirror.conf` →
`~/.config/kanshi/config`, existing config backed up): every output
at position 0,0 in the same 480×320 landscape mode, so the panel,
HDMI and Pi Connect all show the same complete desktop. kanshi
matches the first profile whose output count equals the number of
connected displays, hence one profile per case (panel only, +HDMI-1,
+HDMI-2, +both). Trade-off: the shared desktop is 480×320, so an
HDMI monitor shows the panel-resolution image scaled up. Already
installed and just want the mirror? Run `./MHS35-mirror.sh` as your
user — no reinstall, no reboot. Delete the kanshi config (or
restore its `config.bak-*`) to go back to an extended desktop.

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
```

## Verify after reboot

```
kmsprint                 # should list HDMI + SPI outputs, no error
ls /sys/class/drm        # card*-HDMI-* and card*-SPI-*
echo $XDG_SESSION_TYPE   # in the desktop terminal: wayland
rpi-connect status       # screen sharing available
```

## Hardware test log

- 2026-11-19 (Clint's Pi): DRM installer verified working — panel +
  HDMI live, Pi Connect screen sharing back. Default layout was
  extended (left/right); mirrored profile added in response.

## Still to confirm on real hardware

- Panel colours/orientation under the DRM driver with this init
  sequence (rotation default 90 matches the legacy installer's).
- Touch axes under Wayland/libinput; if swapped, add `swapxy` to
  the `dtoverlay=mhs35,…` line and reboot.
- Max stable SPI speed for the DRM driver on this panel
  (conservative 24 MHz default; the fbtft number does not carry over).
