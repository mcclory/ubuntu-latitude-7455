#!/usr/bin/env bash
# Read-only diagnostics. No bus scans, GPIO requests, driver binds or configuration writes.
# Run with sudo (debugfs). Output can include system-identifying details; review before sharing.
set -u
filter() {
    if command -v rg >/dev/null 2>&1; then
        rg "$@"
    else
        grep -E "$@"
    fi
}
printf 'Kernel: '; uname -r
printf '\nDeferred probes\n'
cat /sys/kernel/debug/devices_deferred 2>&1
printf '\nI2C bindings (bus numbers are not stable)\n'
for dev in /sys/bus/i2c/devices/*-00*; do
    printf '\n%s\n' "$dev"
    cat "$dev/name" "$dev/uevent" 2>/dev/null
    readlink "$dev/driver" || true
    readlink -f "$dev/of_node" || true
done
printf '\nTouch-related kernel log\n'
journalctl -b -k --no-pager | filter -i 'i2c_hid|hid.over|touchscreen|a80000|geni.*(error|timeout)|descriptor|ack reset'
printf '\nGPIO state\n'
cat /sys/kernel/debug/gpio 2>&1
printf '\nTLMM selected pins/configuration\n'
for controller in /sys/kernel/debug/pinctrl/*; do
    [[ "$controller" == *f100000* ]] || continue
    for file in pinmux-pins pinconf-pins pins; do
        printf '\n%s/%s\n' "$controller" "$file"
        filter 'pin (32|33|48|51|75)\b|gpio(32|33|48|51|75)\b' "$controller/$file" 2>&1 || true
    done
done
printf '\nInput devices\n'
cat /proc/bus/input/devices
