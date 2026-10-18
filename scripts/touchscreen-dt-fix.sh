#!/bin/bash
# Build a corrected DTB for the running kernel and add a one-shot GRUB test entry.
#
# For Latitude 7455 units whose touchscreen answers at I2C 0x34 with its HID descriptor at
# register 0x0000 (HID 1FD2:B011). The stock DT says 0x09 / 0x0001. Confirm your unit first
# (see docs/touchscreen.md); do not apply this blindly.
#
# Changes: writes /boot/latitude-touch-$KVER.dtb and /boot/grub/custom.cfg (refuses if it exists),
# and sets a one-time GRUB next entry. The stock entry stays the default.
# Rollback: pick the stock Ubuntu entry in the boot menu, then: sudo rm /boot/grub/custom.cfg
set -euo pipefail
set -x
KVER=$(uname -r)
grep -A1 1FD2 /proc/bus/input/devices || echo "no 1FD2 device (still broken)"
STOCK=/usr/lib/firmware/$KVER/device-tree/qcom/x1e80100-dell-latitude-7455.dtb
WORK=$(mktemp -d)
cd "$WORK"
dtc -I dtb -O dts -o stock.dts "$STOCK" 2>/dev/null
grep -n -A12 'touchscreen@9 {' stock.dts
cp stock.dts fixed.dts
sed -i '/touchscreen@9 {/,/};/{s/touchscreen@9 {/touchscreen@34 {/; s/reg = <0x09>;/reg = <0x34>;/; s/hid-descr-addr = <0x01>;/hid-descr-addr = <0x00>;/}' fixed.dts
diff stock.dts fixed.dts || true
test "$(diff stock.dts fixed.dts | grep -c '^>')" -eq 3   # exactly: node name, reg, hid-descr-addr
dtc -I dts -O dtb -o "latitude-touch-$KVER.dtb" fixed.dts 2>/dev/null
# Camera privacy LED: link the gpio LED to the OV02E10 sensor so V4L2 lights it while streaming.
# The stock DT defines the LED but nothing references it. Uses the next free phandle.
CAM=/soc@0/cci@ac16000/i2c-bus@1/camera@10; LED=/leds/led-camera-indicator
PH=$(( $(grep -oE 'phandle = <0x[0-9a-f]+>' fixed.dts | grep -oE '0x[0-9a-f]+' | sort -u | xargs -n1 printf '%d\n' | sort -n | tail -1) + 1 ))
fdtput -t x "latitude-touch-$KVER.dtb" "$LED" phandle "$(printf %x "$PH")"
fdtput -t x "latitude-touch-$KVER.dtb" "$CAM" leds "$(printf %x "$PH")"
fdtput -t s "latitude-touch-$KVER.dtb" "$CAM" led-names privacy
test "$(fdtget "latitude-touch-$KVER.dtb" "$CAM" led-names)" = privacy
sha256sum "latitude-touch-$KVER.dtb"
sudo install -m 0644 "latitude-touch-$KVER.dtb" /boot/
# With a separate /boot partition (e.g. LUKS installs) GRUB paths drop the /boot prefix.
if findmnt -n /boot >/dev/null; then BOOTUUID=$(findmnt -no UUID /boot); P=""; else BOOTUUID=$(findmnt -no UUID /); P="/boot"; fi
CMDLINE=$(sed 's/^BOOT_IMAGE=[^ ]* //' /proc/cmdline)
echo "boot uuid=$BOOTUUID prefix='$P'"; echo "cmdline=$CMDLINE"
test ! -e /boot/grub/custom.cfg
# stubble.dtb_override=false stops the kernel's Stubble boot stub from replacing this DTB
# with the stock one embedded in the kernel image (.dtbauto sections).
sudo tee /boot/grub/custom.cfg >/dev/null <<CFG
set timeout_style=menu
set timeout=10
menuentry 'Ubuntu (touchscreen fix, $KVER)' --class ubuntu --id 'latitude-touch' {
	recordfail
	load_video
	insmod gzio
	insmod part_gpt
	insmod ext2
	search --no-floppy --fs-uuid --set=root $BOOTUUID
	linux	$P/vmlinuz-$KVER $CMDLINE stubble.dtb_override=false
	devicetree $P/latitude-touch-$KVER.dtb
	initrd	$P/initrd.img-$KVER
}
CFG
cat /boot/grub/custom.cfg
sudo grub-script-check /boot/grub/custom.cfg && echo SYNTAX_OK
sudo grub-reboot latitude-touch
sudo grub-editenv list
