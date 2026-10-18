#!/bin/bash
# Read-only post-boot check for the corrected touchscreen device tree (Latitude 7455, 0x34 variant).
who -b
uname -r
grep -o 'stubble.dtb_override=false' /proc/cmdline || echo "NOT the corrected entry (no stubble.dtb_override=false on the command line)"
for n in /proc/device-tree/soc@0/geniqup@ac0000/i2c@a80000/touchscreen@*; do basename "$n"; done
tr -d '\0' < /proc/device-tree/soc@0/geniqup@ac0000/i2c@a80000/touchscreen@34/compatible 2>/dev/null; echo
grep -A1 1FD2 /proc/bus/input/devices || echo "no 1FD2 input device"
for c in /sys/bus/i2c/drivers/i2c_hid_of/[0-9]*-*; do basename "$c"; done
journalctl -k -b --no-pager | grep -iE 'i2c_hid|0034' | tail -8
