# Launchpad bug reports

The text of the bugs as filed on 2026-10-18. Launchpad is the live version; check there for status and replies.

| Bug | Launchpad |
|---|---|
| 1. `qcom-firmware-extract -d` fails when Windows is gone | [LP #2171350](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171350) |
| 2. `qcvss8380.mbn` not extracted | [LP #2171351](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171351) |
| 3. Touchscreen at `0x34` / descriptor register 0 | [LP #2171354](https://bugs.launchpad.net/ubuntu-concept/+bug/2171354), also [LP #2171352](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2171352) |
| 4. Camera privacy LED not linked to the sensor | [LP #2171357](https://bugs.launchpad.net/ubuntu-concept/+bug/2171357) |

The "Attachments" notes under each bug are the filing checklist. The two files in [attachments/](attachments/) are redacted evidence attachments.

Common environment (paste into each bug, adjust per bug):

* Hardware: Dell Latitude 7455, Snapdragon X Elite X1E-80-100, 32 GB. BIOS 2.16.0. DT model string `Dell Latitude 7455`.
* OS: Ubuntu 26.10 ARM64, installed 2026-10-11 from the `stonking-desktop-arm64.iso` daily-live (generic kernel `7.3.0-9-generic`, `7.3.0-9.9`), then `ppa:ubuntu-concept/x1e` kernel `7.3.0-21-qcom-x1e` (`7.3.0-21.21`, `#21-Ubuntu SMP PREEMPT_DYNAMIC Thu Oct 8 00:17:42 UTC 2026`).
* Secure Boot disabled (observed 2026-10-10 on the previous install; not re-checked after the reinstall).

---

## Bug 1: qcom-firmware-extract: `-d` still fails with "Failed to find windows partition" when Windows is gone

**Package:** `qcom-firmware-extract` 20 (stonking/universe; Debian changelog top entry `qcom-firmware-extract (20) unstable`, 27 Jun 2026). File it against `qcom-firmware-extract` in Ubuntu; the fix probably also belongs in Debian.

**Summary**

`-d <search_path>` exists so firmware can be extracted from a DriverStore copy. When no NTFS partition is present (Windows already removed, which is when `-d` is most useful), the script exits at the partition guard before it ever reaches the `search_path` branch.

**Steps to reproduce**

1. Install Ubuntu over the whole disk, so no NTFS partition remains.
2. Mount a copy of `C:\Windows\System32\DriverStore\FileRepository` at `<backup>`.
3. Run `sudo qcom-firmware-extract -d <backup>`.

**Expected:** the script skips partition discovery and extracts from `<backup>`.

**Actual:**

```text
error: Failed to find windows partition
```

Exit status 1. Reproduced twice: on the first install (early October 2026, Concept image, version 20; exact date not re-checked) and on a clean reinstall on 2026-10-11 (generic daily image, kernel 7.3.0-9-generic, version 20).

**Cause**

`/usr/sbin/qcom-firmware-extract`, lines 108 to 111 in version 20:

```bash
if [ -z "$part" ]; then
	printf "error: Failed to find windows partition" >&2
	exit 1
fi
```

This runs unconditionally. The mount block that needs `$part` starts at line 113 and is already guarded by `if [ -z "$search_path" ]`.

**Proposed fix**

```diff
--- a/qcom-firmware-extract
+++ b/qcom-firmware-extract
@@ -108 +108 @@
-if [ -z "$part" ]; then
+if [ -z "$part" ] && [ -z "$search_path" ]; then
```

Tested on a local copy (`bash -n` OK). With the change, extraction from the backup succeeded: 11 files, package `qcom-x1e-firmware-extracted-x1e80100-dell-latitude7455` version `20261011` built and installed, firmware loaded after reboot (Adreno X1-85 direct rendering, ADSP and CDSP running).

Minor, same area: the error string has no trailing newline.

**Attachments**

* The one-line diff above (no attachment needed).
* Optional: terminal log of the failing and patched runs, from `media/capture` (cast `20261011T113432-p3-firmware.cast`). **Redact:** hostname in the prompt, username in paths, backup mount path.

---

## Bug 2: qcom-firmware-extract: `qcvss8380.mbn` (IRIS video firmware) is not extracted

**Package:** `qcom-firmware-extract` 20.

**Summary**

The extractor's `fw_files` list (lines 148 to 158 in version 20) is the same for every X1E model and does not include `qcvss8380.mbn`. On the Latitude 7455 the `qcom-iris` driver requests that file from the model firmware directory, so with an otherwise complete extraction the video codec fails to initialise. The file is present in the Windows DriverStore.

**Steps to reproduce**

1. Run `qcom-firmware-extract` (with the Bug 1 fix, or from a Windows partition) on a Latitude 7455.
2. Reboot.
3. `journalctl -k -b | grep -i iris`

**Expected:** IRIS firmware loads from `qcom/x1e80100/dell/latitude-7455/`.

**Actual** (stock first boot after the 2026-10-11 reinstall, kernel 7.3.0-9-generic; same message on 7.3.0-21-qcom-x1e on the first install):

```text
qcom-iris aa00000.video-codec: Direct firmware load for qcom/x1e80100/dell/latitude-7455/qcvss8380.mbn failed with error -2
qcom-iris aa00000.video-codec: firmware download failed -2
qcom-iris aa00000.video-codec: video hw is power on
qcom-iris aa00000.video-codec: core init failed
```

The failure repeats each time a video node is opened.

**Workaround and result**

Copied `qcvss8380.mbn` from the DriverStore directory `qcdx8380.inf_arm64_<hash>` into `/usr/lib/firmware/updates/qcom/x1e80100/dell/latitude-7455/` by hand (2,323,048 bytes, SHA-256 `d52c28872ebbaf8087a30bf196d15ee24839fd62a2d91b605edfa73c09bbd8d4`), rebuilt the initramfs with dracut, rebooted. After that, `qcom-iris` binds, `/dev/video16` (decoder) and `/dev/video17` (encoder) exist, and opening the decoder logs no firmware error. **Not verified:** actual decode or encode of a stream. The hand-copied file is not owned by the generated package.

**Proposed fix**

Add `qcvss8380.mbn` to `fw_files`. It is safe to add globally, since missing files are skipped by the `[ -e "${fw_path}" ]` check. Other X1E models probably need it too, but that has only been checked on this one.

**Attachments**

* `attachments/bug2-qcvss8380-kernel-log.txt` (built 2026-10-18, hostname replaced with `host`): the stock first-boot iris failures, then the current state. That covers the firmware directory listing, `dpkg -S` showing the hand-copied file is unowned, its SHA-256, the decoder/encoder node names, and a clean boot log on 7.3.0-21.
* No firmware. The hash above is enough to identify the file.

---

## Bug 3: Latitude 7455 device tree: touchscreen at 0x34 / HID descriptor register 0 on this unit, DT says 0x09 / 1

**Package:** `linux` / `linux-qcom-x1e` DTB `qcom/x1e80100-dell-latitude-7455.dtb` (and `-el2`). The node matches mainline `arch/arm64/boot/dts/qcom/x1e80100-dell-latitude-7455.dts`, so this may be better as a linux-arm-msm discussion. File here first and ask.

**Summary**

On this unit the touchscreen works in Windows and in BIOS setup, but never appears in Linux. The DT declares the controller at I2C address 0x09 with the HID descriptor at register 0x0001. The controller on this unit answers at 0x34 with its HID descriptor at register 0x0000. Changing only those values makes touch work. This is one unit. The controller's marketing name is unknown, and so is how many 7455s ship with it. It may be a panel or controller variant that the DT doesn't describe.

**Shipped DT (checked 2026-10-11)**

Identical in `7.3.0-9-generic` (`x1e80100-dell-latitude-7455.dtb`) and `7.3.0-21-qcom-x1e` (`x1e80100-dell-latitude-7455.dtb` and `-el2.dtb`):

```dts
i2c@a80000 {
	touchscreen@9 {
		reg = <0x09>;
		hid-descr-addr = <0x01>;
```

**Observed**

* No touchscreen in `/proc/bus/input/devices`. Client `2-0009` (OF path `/soc@0/geniqup@ac0000/i2c@a80000/touchscreen@9`) exists but is unbound. The `i2c_hid_of ... supply vdd not found, using dummy regulator` message also appears for the working keyboard and touchpad, so it is not the cause.
* One sysfs bind of `2-0009` with dynamic debug on: `nothing at this address: -6` (ENXIO) before any descriptor fetch.
* A direct 30-byte descriptor read at 0x09, register 0x0001, via I2C_RDWR also fails with ENXIO.
* One-byte read at each non-reserved address 0x03 to 0x77, on this adapter only, after checking it had no bound or unexpected clients. Only 0x34 responds. All 116 others, including 0x09, return ENXIO.
* Bounded HID-over-I2C reads at 0x34 (no reset, set-power or feature commands):
  * Register 0x0001: invalid descriptor (length and version 0).
  * Register 0x0000: valid descriptor `1e 00 00 01 f3 02 21 00 24 00 42 00 25 00 44 00 22 00 23 00 d2 1f 11 b0 02 01 00 00 00 00`. VID:PID `1FD2:B011`, version `0x0102`, report descriptor length 755 at register 0x0021.
  * The report descriptor read cleanly: top-level collection Digitizer (0x0D) / Touch Screen (0x04), plus a vendor collection 0xFF00/0x01.

**Workaround (tested)**

Stock DTB with only these lines changed. Interrupts, pinctrl and supplies are unchanged:

```diff
-touchscreen@9 {
-	reg = <0x09>;
-	hid-descr-addr = <0x01>;
+touchscreen@34 {
+	reg = <0x34>;
+	hid-descr-addr = <0x00>;
```

The corrected DTB is loaded through a GRUB `devicetree` entry, with `stubble.dtb_override=false` on the command line (see the note below). Result:
* Live tree shows `touchscreen@34`.
* `i2c_hid_of` binds `2-0034`, and `hid-multitouch` registers `hid-over-i2c 1FD2:B011`.
* The owner confirms finger input works.
* Survived short deep suspends (2026-10-10).
* Survived plain reboots as the default entry on 2026-10-11, after a clean reinstall, on 7.3.0-21-qcom-x1e, under GNOME and then COSMIC.

**Not verified:** multitouch, edge and corner mapping, behaviour on other 7455 units, IRQ trace. The `LXST2021` description and the `29BD:1103` ID seen in upstream discussions come from other machines. Neither was observed here.

**Request**

A DT variant for this controller, or a detection approach that handles both addresses. Happy to test kernels or DTBs.

**Related usability note: Stubble replaces a GRUB-supplied DT by default**

The first test of the corrected DTB failed silently. GRUB had the `devicetree` line and the entry was confirmed selected, yet the live tree still showed `touchscreen@9`. `objdump -h /boot/vmlinuz-7.3.0-21-qcom-x1e` shows a PE image with 41 `.dtbauto` sections, and its strings include `stubble.dtb_override=`. The upstream Stubble docs (https://github.com/ubuntu/stubble) say Stubble replaces a supplied DT with an embedded match by compatible string, by default. Adding `stubble.dtb_override=false` let the corrected DT reach the kernel. That replacement happened on the failed boot is inferred from this, not traced. Suggest documenting the option wherever DT testing or `devicetree` in GRUB is described. This could be split into its own low-priority bug against the kernel packaging if preferred.

**Attachments** (all private files; redact before attaching)

* `touchscreen-address-probe.txt`: the address sweep. **Redact:** hostname, username in paths.
* `touchscreen-candidate-descriptor.txt` and `touchscreen-candidate-report.txt`: descriptor bytes and the 755-byte report descriptor. **Redact:** hostname.
* The three-line DTS diff above (no attachment needed).
* `/proc/bus/input/devices` excerpt for `1FD2:B011` (safe as is).
* Do **not** attach `grub.cfg` or `/proc/cmdline` unedited: they contain the root and LUKS UUIDs.

---

## Bug 4: Latitude 7455 device tree: camera privacy LED stays off while the camera is streaming

**Where:** project `ubuntu-concept`, https://bugs.launchpad.net/ubuntu-concept/+filebug

**Title:** `[X1E][Latitude 7455] Camera privacy LED stays off while the camera is streaming (sensor node has no led-names = "privacy")`

**Summary**

On a Dell Latitude 7455 the white camera indicator LED stays off while the OV02E10 camera is streaming. The LED and its GPIO work. The sensor's DT node doesn't link to the LED, so the V4L2 privacy-LED support never drives it. The camera can be active with no indicator.

**Environment**

Dell Latitude 7455, X1E-80-100, BIOS 2.16.0. Ubuntu 26.10 arm64, `7.3.0-21-qcom-x1e` from `ppa:ubuntu-concept/x1e`, shipped `x1e80100-dell-latitude-7455.dtb`.

**Steps to reproduce**

1. Boot the shipped DTB.
2. Start the camera (Chrome, Snapshot, or `cam -c 1 --capture`).
3. Look at the LED next to the camera, or `cat /sys/class/leds/white:camera-indicator/brightness`.

**Expected:** LED on while streaming, off after.

**Actual:** the LED stays off, and `brightness` stays `0`.

**Evidence**

* In the shipped DTB, `/soc@0/cci@ac16000/i2c-bus@1/camera@10` (`ovti,ov02e10`) has no `leds` or `led-names` property, and `/leds/led-camera-indicator` has no phandle (only `panic-indicator`).
* The hardware works: `echo 1 > /sys/class/leds/white:camera-indicator/brightness` turns the LED on, and `echo 0` turns it off.
* `ov02e10` registers through `v4l2_async_register_subdev_sensor`, which looks up a privacy LED. `CONFIG_LEDS_CLASS=y`.

**Fix (tested)**

```dts
camera_indicator: led-camera-indicator { /* unchanged */ };

camera@10 {
	/* existing properties unchanged */
	leds = <&camera_indicator>;
	led-names = "privacy";
};
```

Applied to a local DTB with `fdtput`. The decompiled diff is exactly those three lines. After a reboot the LED turns on when a stream starts and off when it stops (verified 2026-10-11, and still in place on 2026-10-18).

**Notes**

Mainline `x1-dell-thena.dtsi` defines the LED with the comment "Reuse as a panic indicator until we get a 'camera on' trigger". As far as I can tell the `camera@10` node exists only in the Concept DT, so the fix belongs there. Other Thena-based machines with this sensor probably need it too. Not checked.

**Attachments**

* `attachments/bug4-camera-privacy-led-dt.txt` (built 2026-10-18, no hostname or user data). It contains the shipped DTB's node property lists and sha256, the LED hardware check, the before/after diff, and the live `led-names` on the current boot.
