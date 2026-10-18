#!/usr/bin/env python3
"""Bounded HID descriptor reads of candidate 0x34; no reset or driver binding."""
import ctypes as C
import os
import struct
from pathlib import Path

class Message(C.Structure):
    _fields_ = [('addr', C.c_uint16), ('flags', C.c_uint16),
                ('length', C.c_uint16), ('buffer', C.POINTER(C.c_uint8))]

class Transfer(C.Structure):
    _fields_ = [('messages', C.POINTER(Message)), ('count', C.c_uint32)]

root = Path('/sys/bus/i2c/devices')
target = '/soc@0/geniqup@ac0000/i2c@a80000'
adapters = [p for p in root.glob('i2c-*') if (p/'of_node').exists()
            and str((p/'of_node').resolve()).endswith(target)]
if len(adapters) != 1:
    raise SystemExit('Abort: ambiguous adapter')
adapter = adapters[0]
bus = adapter.name.split('-')[1]
if any((p/'driver').exists() for p in root.glob(bus+'-*')):
    raise SystemExit('Abort: bound client on adapter')
libc = C.CDLL(None, use_errno=True)
libc.ioctl.argtypes = [C.c_int, C.c_ulong, C.c_void_p]
libc.ioctl.restype = C.c_int
fd = os.open('/dev/'+adapter.name, os.O_RDWR)
try:
    print('kernel', os.uname().release, 'adapter', adapter.name, 'address 0x34', flush=True)
    for register in [1, 0]:
        pointer = (C.c_uint8*2)(register, 0)
        data = (C.c_uint8*30)()
        messages = (Message*2)(Message(0x34, 0, 2, pointer), Message(0x34, 1, 30, data))
        transfer = Transfer(messages, 2)
        result = libc.ioctl(fd, 0x0707, C.byref(transfer))
        if result < 0:
            print(f'register 0x{register:04x}: errno={C.get_errno()}', flush=True)
            continue
        raw = bytes(data)
        print(f'register 0x{register:04x}: messages={result} raw={raw.hex(" ")}', flush=True)
        fields = struct.unpack('<13HI', raw)
        print('descriptor fields:', fields, flush=True)
        if result == 2 and fields[0] == 30 and fields[1] == 0x100 and 0 < fields[2] <= 4096:
            print(f'VALID HID candidate: report_length={fields[2]} report_register=0x{fields[3]:04x} VID=0x{fields[10]:04x} PID=0x{fields[11]:04x}', flush=True)
            pointer = (C.c_uint8*2)(fields[3] & 255, fields[3] >> 8)
            report = (C.c_uint8*fields[2])()
            messages = (Message*2)(Message(0x34, 0, 2, pointer), Message(0x34, 1, fields[2], report))
            transfer = Transfer(messages, 2)
            result = libc.ioctl(fd, 0x0707, C.byref(transfer))
            if result != 2:
                print('report read failed:', result, 'errno', C.get_errno(), flush=True)
                break
            raw = bytes(report)
            print('report descriptor:', raw.hex(' '), flush=True)
            offset = 0
            page = 0
            usage = None
            depth = 0
            stack = []
            while offset < len(raw):
                prefix = raw[offset]
                offset += 1
                if prefix == 0xfe:
                    size = raw[offset]
                    offset += 2 + size
                    continue
                size = [0, 1, 2, 4][prefix & 3]
                value = int.from_bytes(raw[offset:offset+size], 'little')
                offset += size
                kind, tag = (prefix >> 2) & 3, prefix >> 4
                if kind == 1 and tag == 0:
                    page = value
                elif kind == 1 and tag == 10:
                    stack.append(page)
                elif kind == 1 and tag == 11:
                    page = stack.pop()
                elif kind == 2 and tag == 0:
                    usage = value
                elif kind == 0:
                    if tag == 10:
                        if depth == 0:
                            print(f'TOP LEVEL COLLECTION: page=0x{page:04x} usage={usage} collection_type={value}', flush=True)
                        depth += 1
                    elif tag == 12:
                        depth -= 1
                    usage = None
            break
finally:
    os.close(fd)
