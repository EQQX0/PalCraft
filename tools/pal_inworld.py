"""Dev: is the test character in a world? Read from bridge.shm, so nothing runs inside Palworld.

    python tools/pal_inworld.py [runtime folder]     prints "inworld" or "no"

The frame loop writes its state there every frame: the player flag is up and the frame number moves.
"""
import struct
import sys
import time
from pathlib import Path

folder = Path(sys.argv[1] if len(sys.argv) > 1 else "runtime")


def state():
    with open(folder / "bridge.shm", "rb") as f:
        f.seek(0xC00)
        return struct.unpack("<IIQ", f.read(16))


try:
    a = state()
    time.sleep(0.4)
    b = state()
except OSError:
    print("no")
    sys.exit(1)
moving = b[2] != a[2]
print("inworld" if moving and b[1] & 2 else "no")
sys.exit(0 if moving and b[1] & 2 else 1)
