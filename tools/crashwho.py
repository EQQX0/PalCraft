"""Who crashed Palworld: reads an Unreal minidump and names the code on the faulting thread's stack.

    python tools/crashwho.py                 newest crash under %LOCALAPPDATA%/Pal/Saved/Crashes
    python tools/crashwho.py <UEMinidump.dmp> [how many stack entries]

The stack is scanned for values that point into a loaded module (no unwind data needed), and each one in a
DLL with exports is named after the nearest export below it. UE4SS exports its C++ interface, so its frames
get real names: enough to tell which Lua call touched a dead object.
"""
import os
import struct
import sys
from pathlib import Path


def exports(path):
    """[(rva, name)] of a PE file's export table, sorted."""
    d = Path(path).read_bytes()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    ddir = opt + (112 if magic == 0x20B else 96)
    exp_rva = struct.unpack_from("<I", d, ddir)[0]
    secs = []
    at = opt + struct.unpack_from("<H", d, pe + 20)[0]
    for i in range(nsec):
        vsize, va, rsize, raw = struct.unpack_from("<IIII", d, at + i * 40 + 8)
        secs.append((va, max(vsize, rsize), raw))

    def off(rva):
        for va, size, raw in secs:
            if va <= rva < va + size:
                return rva - va + raw
        return None

    if not exp_rva or off(exp_rva) is None:
        return []
    e = off(exp_rva)
    nfunc, nname, afunc, aname, aord = struct.unpack_from("<IIIII", d, e + 20)
    out = []
    for i in range(nname):
        name_rva = struct.unpack_from("<I", d, off(aname) + i * 4)[0]
        o = struct.unpack_from("<H", d, off(aord) + i * 2)[0]
        rva = struct.unpack_from("<I", d, off(afunc) + o * 4)[0]
        n = off(name_rva)
        out.append((rva, d[n:d.index(b"\0", n)].decode("ascii", "replace")))
    return sorted(out)


def main():
    args = sys.argv[1:]
    if args and args[0].lower().endswith(".dmp"):
        dmp = Path(args.pop(0))
    else:
        root = Path(os.environ["LOCALAPPDATA"]) / "Pal/Saved/Crashes"
        dmp = max(root.glob("*/UEMinidump.dmp"), key=lambda p: p.stat().st_mtime)
    depth = int(args[0]) if args else 40
    d = dmp.read_bytes()
    assert d[:4] == b"MDMP", "not a minidump"
    nstreams, dir_rva = struct.unpack_from("<II", d, 8)
    streams = {}
    for i in range(nstreams):
        kind, size, rva = struct.unpack_from("<III", d, dir_rva + i * 12)
        streams[kind] = (size, rva)

    def text(rva):
        n = struct.unpack_from("<I", d, rva)[0]
        return d[rva + 4:rva + 4 + n].decode("utf-16-le", "replace")

    mods = []
    _, rva = streams[4]
    for i in range(struct.unpack_from("<I", d, rva)[0]):
        base, size = struct.unpack_from("<QI", d, rva + 4 + i * 108)
        name_rva = struct.unpack_from("<I", d, rva + 4 + i * 108 + 20)[0]
        mods.append((base, size, text(name_rva)))
    cache = {}

    def name(addr):
        for base, size, path in mods:
            if base <= addr < base + size:
                short = path.replace("\\", "/").rsplit("/", 1)[-1]
                rva = addr - base
                if path not in cache:
                    try:
                        cache[path] = exports(path) if "UE4SS" in short or "palcraft" in short.lower() else []
                    except Exception:
                        cache[path] = []
                best = None
                for r, n in cache[path]:
                    if r > rva:
                        break
                    best = (r, n)
                near = f"  {best[1][:150]}+{rva - best[0]:#x}" if best and rva - best[0] < 0x4000 else ""
                return f"{short}+{rva:#x}{near}"
        return None

    _, rva = streams[6]
    tid = struct.unpack_from("<I", d, rva)[0]
    code, flags, _, addr, nparam = struct.unpack_from("<IIQQI", d, rva + 8)
    params = struct.unpack_from("<4Q", d, rva + 8 + 32)
    print(dmp.parent.name)
    print(f"exception {code:#x} at {name(addr) or hex(addr)}; {'write' if params[0] else 'read'} of {params[1]:#x}")
    ctx_size, ctx_rva = struct.unpack_from("<II", d, rva + 8 + 152)
    rsp = struct.unpack_from("<Q", d, ctx_rva + 0x98)[0]
    _, trva = streams[3]
    for i in range(struct.unpack_from("<I", d, trva)[0]):
        t = trva + 4 + i * 48
        if struct.unpack_from("<I", d, t)[0] != tid:
            continue
        start, size, mem = struct.unpack_from("<QII", d, t + 24)
        shown = 0
        for a in range(max(rsp, start) - start, size - 7, 8):
            v = struct.unpack_from("<Q", d, mem + a)[0]
            who = name(v)
            if who:
                print("  " + who)
                shown += 1
                if shown >= depth:
                    break


if __name__ == "__main__":
    main()
