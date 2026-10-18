# Latitude 7455 on 26.10: built it twice, used it for a week, here's what's left

I've been running a Dell Latitude 7455 (X1E-80-100, 32 GB) on Ubuntu 26.10 with the Concept kernel as my only laptop for the past week: on the couch, at my desk and out of the house. It's been solid, and I'm happy with performance and battery. That isn't the sentence I expected to write when I ordered an ARM laptop to run Linux on.

I built it twice. The first time was from the Snapdragon Concept image, figuring things out as I went over most of a week. The second was a clean LUKS reinstall on 2026-10-11 from the generic 26.10 daily plus `ppa:ubuntu-concept/x1e`, working from my own notes, to see whether any of it was repeatable. It was. The second build took about six hours of wall-clock time from wipe to a finished dev machine, breaks included. Every issue below showed up on both builds.

This post is for the people building this stack. It's a list of what still doesn't work on this model, the evidence I have, what I did about it, and what I'm asking for. The thing I actually care about is first. Everything is from one unit, so treat it as a single data point, not a census.

## The stack

* Dell Latitude 7455, X1E-80-100, 32 GB, 512 GB Kioxia NVMe, 14" 2560x1600 touch. BIOS 2.16.0.
* Ubuntu 26.10 desktop arm64 daily (20261011), LUKS with a passphrase from the installer.
* `linux-qcom-x1e` `7.3.0-21-qcom-x1e` from the Concept PPA, with `7.3.0-9-generic` kept as the fallback.
* Firmware from `qcom-firmware-extract` 20, run against a DriverStore copy I took before wiping Windows.
* COSMIC as the only desktop. GNOME was removed after COSMIC was verified.
* Chrome, VS Code, Docker, Python and Node toolchains, k8s CLIs. It's a working machine, not a demo.

## What just worked

Most of it, which says a lot about the work you've all put in. Display, keyboard, touchpad, NVMe, Wi-Fi and LUKS worked from the first boot of the generic image. Once firmware was in place, the Adreno came up with Freedreno GL 4.6 and Turnip Vulkan, and audio went from Dummy Output to a real HiFi profile with speakers, internal mic, headphone auto-switching and Bluetooth A2DP plus headset mic. Deep suspend on `-21` comes back with Wi-Fi, which `-15` didn't do on my first build (`ath12k ... failed to resume core: -110`). A Google Meet call in Chrome worked with camera, mic and screen share after turning on `chrome://flags/#enable-webrtc-pipewire-camera`. USB-C charges at 29 to 32 W on both ports. The fingerprint reader works at the COSMIC greeter and lock screen. I turned it off anyway, because a fingerprint login still leaves the GNOME keyring locked and asking for my password. That's a general fingerprint and keyring problem, not something specific to this build.

So the list below is short. It's also specific enough that each item should be fixable.

## 1. Brightness doesn't work, and it's the one I really want

Brightness keys and the slider do nothing. The backlight device exists and is useless:

```text
/sys/class/backlight/dp_aux_backlight
  type            raw
  max_brightness  0
  brightness      0
```

Every boot, on both builds, both kernels, also logs:

```text
panel-simple-dp-aux aux-aea0000.displayport-controller: Unknown panel LGD 0x0754, using conservative timings
WARNING: drivers/gpu/drm/panel/panel-edp.c:829 at generic_edp_panel_probe
```

For a while I assumed the unknown panel was the cause. I don't think it is anymore. [LP #2159387](https://bugs.launchpad.net/ubuntu-concept/+bug/2159387) on the Dell Inspiron 14 Plus 7441 shows exactly the same `dp_aux_backlight` with `max_brightness 0`, and that panel is recognized (`AUO B140QAX01.H`). The panel ID belongs in `panel-edp`'s table either way. It just doesn't seem to be what breaks the backlight.

The lead I'd like to chase is the one @glathe gave the 7441 reporter in July ([post 1976](https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800/1976)): part of the fix for backlight control on the Ideapad Slim 5x was making `vreg_edp_3p3` always-on. On this unit, the panel's `power-supply` points at `VREG_EDP_3P3`, which has `regulator-boot-on` and no `regulator-always-on`. Mainline `x1-dell-thena.dtsi` is the same. The 7455 and the 7441 both use the Thena DTSI, so if that's the fix for one, it's worth trying on the other.

I haven't tried it yet. Adding `regulator-always-on` to that node in my corrected DTB is a one-property change, and I already have a DT test path that survives reboots (see the touchscreen section). If you'd rather I run a debug kernel first, like the `-jg` build with the DP AUX backlight flag prints, I can do that too. EDID and DPCD backlight capability dumps are available on request.

My details and test offer are on [LP #2159387](https://bugs.launchpad.net/ubuntu-concept/+bug/2159387).

## 2. The touchscreen is at a different address than the DT says

This one took the longest, and it's the one most likely to bite somebody else.

Touch worked in Windows and in BIOS setup. In Linux, nothing. The Latitude 7455 DT declares the controller on `i2c@a80000` at `0x09`, with the HID descriptor at register `0x0001`. Mainline has the same node, commented `/* LXST2021 */`. Linux creates the `2-0009` client from that declaration whether anything is there or not, so the client showing up in sysfs proved nothing. A targeted bind failed with `nothing at this address: -6`. ENXIO, before the descriptor fetch ever happened.

So I asked the bus a smaller question. On that one adapter only, after confirming there were no bound or unexpected clients on it, I did a one-byte read at each address from `0x03` to `0x77`. Exactly one address answered: `0x34`. A bounded HID-over-I2C descriptor read there gave:

| | DT says | This unit has |
|---|---|---|
| I2C address | `0x09` | `0x34` |
| HID descriptor register | `0x0001` | `0x0000` (register 1 returns garbage) |
| VID:PID | `LXST2021` per the mainline comment | `1FD2:B011`, version `0x0102` |
| Report descriptor | never reached | 755 bytes, Digitizer / Touch Screen |

Same bus, same interrupt line, different address and descriptor register. My guess is a second controller or panel assembly that the DT doesn't describe. I don't know the controller's marketing name, and I don't know how many 7455s ship with it.

The fix is three lines in one node:

```diff
-touchscreen@9 {
-	reg = <0x09>;
-	hid-descr-addr = <0x01>;
+touchscreen@34 {
+	reg = <0x34>;
+	hid-descr-addr = <0x00>;
```

Getting it to load was its own lesson. I compiled the corrected DTB, put it in `/boot` under a new name, added a separate GRUB entry with a `devicetree` line, picked that entry by hand, and the live tree still said `touchscreen@9`. The DTB on disk was right. GRUB was configured. The entry was selected. The kernel got the wrong tree anyway.

The kernel image is a Stubble PE binary with 41 `.dtbauto` sections, and Stubble's documented default is to swap a supplied DT for its own embedded match. Adding `stubble.dtb_override=false` to that one entry fixed it. On the next boot the tree said `touchscreen@34`, `i2c_hid_of` bound `2-0034`, `hid-multitouch` picked up `1FD2:B011`, and touch worked. That entry has been my default for a week, across reboots, suspends and both desktops. I haven't tested edge mapping or gestures in detail.

Two asks. First, a DT variant for this controller, or some way of probing that handles both. I'll happily test either. If it belongs upstream on linux-arm-msm instead, tell me and I'll send it there. Second, please document `stubble.dtb_override` wherever DT testing comes up. I lost an evening to a DTB that was correct and never loaded, and the next person will too.

[LP #2171354](https://bugs.launchpad.net/ubuntu-concept/+bug/2171354) (also filed against the kernel package as [LP #2171352](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2171352))

## 3. The camera privacy LED doesn't light

This one's small in code and big in principle: on the stock DT, the camera can stream and the white indicator LED next to it stays off.

The LED itself is fine. Writing `1` to `/sys/class/leds/white:camera-indicator/brightness` turns it on. The problem is that the sensor node (`camera@10`, `ovti,ov02e10`, on the CCI bus) has no `leds` / `led-names = "privacy"` link, so V4L2 never drives it. Mainline's Thena DTSI defines the LED with the comment "Reuse as a panic indicator until we get a 'camera on' trigger", and as far as I can tell the camera node itself is Concept-kernel DT, not mainline.

I added a phandle to `/leds/led-camera-indicator` and `leds = <&...>; led-names = "privacy";` on `camera@10`, in the same corrected DTB as the touchscreen fix. Camera on, LED on. Camera off, LED off. Verified after a reboot. I'd like this in the shipped DT for every Thena machine with that sensor, because "the camera is on and nothing tells you" isn't a state a laptop should ship in.

[LP #2171357](https://bugs.launchpad.net/ubuntu-concept/+bug/2171357)

## 4. Firmware extraction: one guard and one missing file

Two small ones against `qcom-firmware-extract` 20, both reproduced on both builds.

`-d <path>` exists for the case where Windows is already gone, and that's exactly when it fails: `error: Failed to find windows partition`. The partition guard runs before the script checks for a search path. The fix is one condition:

```diff
-if [ -z "$part" ]; then
+if [ -z "$part" ] && [ -z "$search_path" ]; then
```

With that patched locally, the package built and installed cleanly (11 files).

The extractor's file list also doesn't include `qcvss8380.mbn`, which `qcom-iris` requests from the Latitude 7455 firmware directory. I copied it from the DriverStore by hand and checked the hash, and the decoder and encoder nodes now come up. It's safe to add to the shared list, because files that don't exist are skipped.

[LP #2171350](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171350) · [LP #2171351](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171351)

## Smaller things worth knowing on 26.10 ARM64

None of these are Concept bugs, but they all cost me time:

* VS Code's `vsce-sign` fails with only OpenSSL 4 present. Installing `libssl3t64` fixes it with signature checks left on.
* `newgrp` lives in `util-linux-extra` now, and `sg` isn't packaged at all. Old Docker instructions that say `sg docker -c ...` just fail.
* Chrome plays YouTube AV1 with software dav1d. Iris shows up as a V4L2 decoder, not VA-API, so Chrome doesn't use it. That's expected, but it costs some battery during video.
* COSMIC from Pop's noble repo needs an apt crypto-policy exception on 26.10, because Pop's signing key still uses SHA-1 self-signatures, which apt's sqv rejects after 2026-02-01. That's Pop's problem to fix. I'm noting it for anyone else trying COSMIC here.

## What I'm asking for

In order:

1. Help getting brightness working. I'll test the `vreg_edp_3p3` always-on change or a debug kernel, whichever you'd rather.
2. A DT variant for the `0x34` / `1FD2:B011` touchscreen.
3. The camera privacy LED link in the shipped DT.
4. The extractor guard fix and `qcvss8380.mbn` in the file list.
5. A line of documentation about `stubble.dtb_override`.

The unit is on my desk and I'm happy to keep testing. Logs, descriptor dumps, the address sweep, DT diffs and firmware hashes (never the binaries) are all available, and the full device matrix is below. Scripts and notes are in [ubuntu-latitude-7455](https://github.com/mcclory/ubuntu-latitude-7455).

A year ago, getting a used Dell X Elite to this point would have meant a custom kernel and a weekend of bisecting. This time it took a generic daily image, one PPA, my own Windows firmware and a short list of fixes. If brightness gets sorted, I'd tell people to buy one.

---

## Appendix: device matrix (clean install, 2026-10-11, `7.3.0-21-qcom-x1e`)

| Component | Status | Notes |
|---|---|---|
| Display | Works | Native 2560x1600. No brightness control, see section 1 |
| Keyboard | Works | F1-F4 media keys with Fn lock on and off (needs `playerctl` on COSMIC); F5 keyboard backlight works |
| Brightness keys (F6/F7) | No | See section 1 |
| Touchpad | Works | Two-finger click right-click via COSMIC click behavior |
| Touchscreen | Works with DT fix | See section 2 |
| NVMe + LUKS | Works | Passphrase from the installer |
| Wi-Fi (WCN7850, ath12k) | Works | Back about 17 s after resume |
| Bluetooth | Works | A2DP playback and headset mic (HFP) tested |
| GPU (Adreno X1-85) | Works | Needs extracted firmware. Freedreno GL 4.6, Turnip Vulkan |
| Speakers / internal mic | Works | No WSA `-61` after resume on this install so far (seen on the first build) |
| Headphone jack | Works | Output and auto-switch. Jack mic untested (no TRRS headset) |
| Camera (OV02E10) | Works, quality caveat | libcamera 0.7.0 has no OV02E10 tuning or helper, so the image is grainy and desaturated. Chrome Meet works with the PipeWire camera flag |
| Camera privacy LED | Works with DT fix | See section 3 |
| Fingerprint (Goodix 27c6:631c) | Works | Greeter and lock screen. Keyring stays locked after a fingerprint login, as usual |
| IRIS video | Enumerates | Needs `qcvss8380.mbn` by hand. No hardware decode workload tested |
| Suspend (deep) | Works | Lid and power button, daily for a week. `qcom-pcie ... Timeout waiting for L2 entry` logged on resume, no visible effect |
| USB-C charging | Works | Both ports, 29-32 W after a ~30 s ramp. upower lags right after plug-in; `power_now` doesn't |
| USB-C display / USB4 | Untested | No USB-C monitor here |
| Battery reporting | Works, oddity | 46.43 of 54 Wh design (86%) at 5 cycles, same on both builds. Not claiming a defect |
