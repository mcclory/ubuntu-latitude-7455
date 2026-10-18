# Touchscreen at the wrong address

On this unit the touchscreen works in Windows and in BIOS setup but registers nothing in Linux. The upstream device tree for the Latitude 7455 (`x1e80100-dell-latitude-7455.dts`) declares it on the I2C controller at `a80000`, address `0x09`, HID descriptor register `0x0001`. This unit's controller answers at `0x34` with its descriptor at register `0x0000`.

| | Device tree | This unit |
|---|---|---|
| I2C address | `0x09` | `0x34` |
| HID descriptor register | `0x0001` | `0x0000` |
| Vendor:Product | not stated | `1FD2:B011` |
| Report descriptor | never reached | 755 bytes, Digitizer / Touch Screen |

Same bus, same interrupt and pins. Likely a panel or controller variant the upstream tree does not describe. It is not known how many 7455s ship with it.

## Symptoms

- No touch entry in `/proc/bus/input/devices`.
- An I2C client exists for the DT node (bus number varies, e.g. `2-0009`) with no driver bound. A client in sysfs only means the DT described it; it is not discovery.
- `i2c_hid_of ...: supply vdd not found, using dummy regulator` is **not** the cause. The keyboard and touchpad log the same and work.
- A targeted reprobe fails with `nothing at this address: -6` (ENXIO).

Find the client by device-tree path, not bus number:

```bash
for d in /sys/bus/i2c/devices/*-00*; do echo "$d $(readlink -f $d/of_node)"; done | grep touchscreen
```

`scripts/collect-touchscreen.sh` gathers bindings, deferred probes, pin state and the relevant kernel log, read-only.

## Identifying the controller (active bus operations)

These two steps send I2C transactions on one bus. Reads can have device-side effects. Run them only if you accept that, and only on the touchscreen's controller.

1. `scripts/probe-touchscreen-addresses.py --approved-address-probe` does a one-byte read at each non-reserved address `0x03`–`0x77` on the `a80000` adapter. It aborts if any client on that adapter is bound or unexpected (it expects the stock `touchscreen@9` client only). Here only `0x34` answered.
2. `scripts/read-touchscreen-candidate.py` reads the HID-over-I2C descriptor at `0x34` from registers `1` and `0`, and if valid, the report descriptor. Here register `1` was invalid and register `0` gave a valid descriptor (VID `0x1FD2`, PID `0xB011`, report length 755, top-level collection Digitizer / Touch Screen).

An ACK is not an identity; the descriptor read is what establishes it.

## The correction

Three lines in one node; interrupts, pinctrl and supplies are unchanged:

```diff
-touchscreen@9 {
-    reg = <0x09>;
-    hid-descr-addr = <0x01>;
+touchscreen@34 {
+    reg = <0x34>;
+    hid-descr-addr = <0x00>;
```

`scripts/touchscreen-dt-fix.sh` builds this from the running kernel's own stock DTB, checks that exactly three lines changed, installs `/boot/latitude-touch-$KVER.dtb`, writes `/boot/grub/custom.cfg` with a separate menu entry and selects it for one boot only. It refuses to run if `custom.cfg` already exists.

With a separate `/boot` partition (LUKS installs), GRUB paths drop the `/boot` prefix and the `search` UUID is the `/boot` filesystem's; the script handles both layouts.

### Why a correct DTB still gets ignored: Stubble

Ubuntu's ARM64 kernel image on 26.10 is wrapped in the [Stubble](https://github.com/ubuntu/stubble) boot stub. `objdump -h` on the kernel shows dozens of `.dtbauto` sections: device trees embedded in the image. By default Stubble matches the machine's compatible string against them and replaces the DTB GRUB loaded. The symptom: GRUB's `devicetree` line points at the corrected file, and the live tree still says `touchscreen@9`.

Add this to the kernel command line of the corrected entry only:

```text
stubble.dtb_override=false
```

### Verify after boot

`scripts/touch-check.sh` (read-only) confirms the command line flag, `touchscreen@34` in the live tree, `hid-over-i2c 1FD2:B011` in `/proc/bus/input/devices` and the `i2c_hid_of` binding. Then touch the screen.

### Make it the default

Once it works:

```bash
echo "set default=latitude-touch" | sudo tee -a /boot/grub/custom.cfg
sudo grub-script-check /boot/grub/custom.cfg
```

On this unit the default entry survived plain reboots and a short deep suspend on `7.3.0-21-qcom-x1e`. Multitouch and edge mapping have not been tested systematically.

### Rollback

Pick the stock Ubuntu entry in the GRUB menu, then:

```bash
sudo rm /boot/grub/custom.cfg
```

### Kernel upgrades

The entry is pinned to one kernel version and its DTB. Each new kernel needs its own corrected DTB built from that kernel's stock DTB, a new entry, and a fresh check. Do not reuse an old DTB with a new kernel.

## Upstream

The right fix is a DT variant or detection upstream, not a local GRUB entry. Report: [LP #2171354](https://bugs.launchpad.net/ubuntu-concept/+bug/2171354).
