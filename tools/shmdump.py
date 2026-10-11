"""Print what both games last wrote to bridge.shm, decoded with the sheets.

    python tools/shmdump.py [runtime folder] [channel ...]

Default folder is %LOCALAPPDATA%\\PalCraft\\runtime; default channels are header, state, control, luastate, hunter.
"""
import json
import os
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FMT = {"u32": "I", "i32": "i", "u64": "Q", "f32": "f", "u8": "B"}


def sheet(name):
    data = json.loads((ROOT / "sheets" / f"{name}.json").read_text(encoding="utf-8"))
    return [dict(zip(data["columns"], row)) for row in data["rows"]]


def main():
    args = sys.argv[1:]
    folder = Path(os.environ["LOCALAPPDATA"]) / "PalCraft" / "runtime"
    if args and (os.sep in args[0] or "/" in args[0]):
        folder = Path(args.pop(0))
    want = args or ["header", "state", "control", "luastate", "hunter"]
    flags = {}
    for r in sheet("flags"):
        flags.setdefault(r["group"], []).append((r["name"], int(str(r["value"]), 0)))
    structs = {}
    for r in sheet("structs"):
        structs.setdefault(r["struct"], []).append(r)
    with open(folder / "bridge.shm", "rb") as f:
        for ch in sheet("channels"):
            if ch["id"] not in want or ch["file"] != "bridge.shm":
                continue
            base = int(ch["offset"], 0)
            print(f"[{ch['id']}] {ch['struct']} @ {ch['offset']}")
            for fld in structs.get(ch["struct"], []):
                code = FMT.get(fld["type"])
                if not code:
                    continue
                n = min(int(fld["count"]), 16)
                f.seek(base + int(fld["off"], 0))
                vals = struct.unpack("<" + code * n, f.read(struct.calcsize(code) * n))
                text = ", ".join(f"{v:.3f}" if isinstance(v, float) else str(v) for v in vals)
                if fld["field"] == "flags":
                    group = {"GameState": "state", "LuaState": "state", "Control": "ctrl"}.get(ch["struct"])
                    names = [n_ for n_, bit in flags.get(group, []) if vals[0] & bit]
                    text += "  " + "|".join(names)
                print(f"  {fld['field']:<18} {text}")


if __name__ == "__main__":
    main()
