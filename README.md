# LCD-show — MHS-3.5″ fix (fork)

A fork of [goodtft/LCD-show](https://github.com/goodtft/LCD-show) that
fixes the MHS-3.5″ touchscreen install so it no longer disables HDMI
output and Raspberry Pi Connect. For all other displays and the
original documentation, see the
[upstream repository](https://github.com/goodtft/LCD-show).

Full technical write-up: [FIXES.md](FIXES.md).

## The problem

Installing the stock MHS35 driver works — the little screen lights
up — but it quietly breaks two other things:

- **HDMI output dies.** The installer replaces the whole boot
  config with a template that comments out the KMS graphics driver
  (`dtoverlay=vc4-kms-v3d`), and forces HDMI into the panel's
  480×320 mode for the old framebuffer-copy design. On current
  Raspberry Pi OS there is no native HDMI desktop at all.
- **Raspberry Pi Connect screen sharing dies.** The installer
  switches the Pi to console boot + X11. Pi Connect screen sharing
  requires a Wayland desktop session, so it silently stops working
  (remote shell still works, which makes it confusing).

## What this fork does

- **`MHS35-DRM-show`** — a new installer that edits the boot config
  in place instead of replacing it: KMS stays on, HDMI is left
  alone, the session stays on Wayland with desktop autologin. The
  panel is driven by the kernel's ILI9486 DRM driver via a new
  `drm` override on the mhs35 overlay, so the panel and HDMI are
  independent outputs of one desktop.
- **`usr/mhs35-overlay.dts`** — the overlay as source (upstream
  ships only a binary), with the `drm` override added. The binary
  is rebuilt on the Pi at install time if needed.
- **`MHS35-desktop-setup.sh`** — one user-side setup that installs
  the autodetecting layout: every connected screen (either HDMI
  port, both, or none — any brand or resolution) at its own
  preferred mode, the panel rotated beside them, the taskbar on
  the first big screen (or on the panel when it's the only
  screen), and a virtual output spanning the real layout so Pi
  Connect shows **all** screens at once. Nothing assumes a
  specific monitor exists, so booting away from your usual desk
  — or with no monitor at all — is a normal, working desktop.
- **`update.sh`** — after the first install, updating the Pi is a
  single command: `bash update.sh` (pull + setup, nothing else to
  run by hand).
- **`system_config.sh`** — the forced console-boot / X11 lines are
  removed for all installers, not just this one.

Verified working on real hardware: panel + HDMI side by side,
menus on the big screen, Pi Connect showing both screens, and
everything coming back by itself after a cold reboot.

## Testing — Raspberry Pi 5 only

**All development and testing so far is on a Raspberry Pi 5**
(Debian 13 "Trixie", labwc/Wayland), with the MHS-3.5″ panel
(ILI9486 + XPT2046 touch) and one 1024×768 HDMI monitor.

Nothing here is tested yet on Pi 4 or earlier, on other OS
releases, or with other displays. It may work — the approach is
not Pi 5-specific — but that is unverified, and issues on other
hardware are best-effort until someone tests them.

## In progress

- **Dual-HDMI autodetection — built, in hardware testing.** The
  fixed one-monitor layout has been replaced by an autodetecting
  one (both HDMI ports, any monitor brand or resolution,
  positions computed from the actual screens, panel-only boots
  included), because this Pi is used as a portable PC with many
  different monitor combinations. It passes an 8-scenario
  simulation suite; live testing with a second monitor is the
  remaining step.
- After that, this work will be submitted upstream as a pull
  request to goodtft/LCD-show.

## Use

```sh
git clone -b fix/mhs35-drm-hdmi-pi-connect \
  https://github.com/fixxxxer101/LCD-show
cd LCD-show
sudo ./MHS35-DRM-show      # then reboot
./MHS35-desktop-setup.sh   # after the reboot, as your normal user
```

Later updates on the Pi: `bash update.sh` in the clone.
