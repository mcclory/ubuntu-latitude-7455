#!/usr/bin/env python3
"""Approval-required active address test, limited to the DT touchscreen adapter.

One plain one-byte read per nonreserved address; no register writes, resets,
force access, driver changes or GPIO operations. Reads can have device side
effects. An ACK establishes a responder, not touchscreen identity. Failure
does not exclude an unpowered controller or another physical bus.
Run only after explicit approval, on the host with existing i2c-dev access.
"""
import argparse
import errno
import fcntl
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--approved-address-probe', action='store_true')
    args = parser.parse_args()
    if not args.approved_address_probe:
        parser.error('explicit approval required; pass --approved-address-probe afterward')
    target = '/soc@0/geniqup@ac0000/i2c@a80000'
    root = Path('/sys/bus/i2c/devices')
    adapters = [p for p in root.glob('i2c-*')
                if (p / 'of_node').exists()
                and str((p / 'of_node').resolve()).endswith(target)]
    if len(adapters) != 1:
        raise SystemExit('Abort: touchscreen adapter mapping is not unique')
    adapter = adapters[0]
    bus = adapter.name.removeprefix('i2c-')
    clients = list(root.glob(bus + '-*'))
    for client in clients:
        if (client / 'driver').exists():
            raise SystemExit('Abort: adapter has a bound client: ' + client.name)
        if not ((client / 'of_node').exists()
                and str((client / 'of_node').resolve()).endswith(target + '/touchscreen@9')):
            raise SystemExit('Abort: unexpected client: ' + client.name)
    device = '/dev/' + adapter.name
    print('Kernel:', os.uname().release, 'adapter:', device, 'OF:', target, flush=True)
    with open(device, 'rb', buffering=0) as stream:
        for address in range(0x03, 0x78):
            fcntl.ioctl(stream.fileno(), 0x0703, address)  # I2C_SLAVE, never FORCE
            try:
                value = os.read(stream.fileno(), 1)
            except OSError as exc:
                print(f'0x{address:02x}: errno={exc.errno}', flush=True)
                if exc.errno not in (errno.ENXIO, errno.EREMOTEIO):
                    raise SystemExit('Abort: unexpected bus error; no further reads')
            else:
                print(f'0x{address:02x}: responded, bytes={value.hex()}', flush=True)


if __name__ == '__main__':
    main()
