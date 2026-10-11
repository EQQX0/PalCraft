"""Dev aid: where the Pals are relative to Steve, read from bridge.shm.

    python tools/nav.py [runtime folder]

Prints each entity's distance and the mouse turn (um "rel" pixels, 600 per quarter turn) that faces it.
"""
import math
import os
import struct
import sys
from pathlib import Path

folder = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(os.environ["LOCALAPPDATA"]) / "PalCraft" / "runtime"
STATE, ENTITIES, FIRST, STRIDE = 0x100, 0x200000, 0x10, 0x80
with open(folder / "bridge.shm", "rb") as f:
    f.seek(STATE + 0x10)
    blob = f.read(0x100)
    f.seek(ENTITIES)
    table = f.read(FIRST + STRIDE * 64)
cam = struct.unpack_from("<3f", blob, 0)
tgt = struct.unpack_from("<3f", blob, 12)
fx, fy, fz = tgt[0] - cam[0], tgt[1] - cam[1], tgt[2] - cam[2]
heading = math.degrees(math.atan2(fx, fz))
pitch = math.degrees(math.atan2(fy, math.hypot(fx, fz)))
print(f"cam {cam[0]:.1f} {cam[1]:.1f} {cam[2]:.1f} heading {heading:.0f} pitch {pitch:.0f}")
count = struct.unpack_from("<I", table, 4)[0]
for i in range(min(count, 64)):
    at = FIRST + i * STRIDE
    x, y, z = struct.unpack_from("<3f", table, at + 0x10)
    hp, top = struct.unpack_from("<2f", table, at + 0x44)
    name = table[at + 0x50:at + 0x80].split(b"\0")[0].decode("ascii", "replace")
    dx, dy, dz = x - cam[0], y - cam[1], z - cam[2]
    turn = (math.degrees(math.atan2(dx, dz)) - heading + 180) % 360 - 180
    print(f"{name:<22} hp {hp:.0f}/{top:.0f} dist {math.hypot(dx, dz):5.1f} m, {dy:+.1f} m up, turn {turn:+.0f} deg")
