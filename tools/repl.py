"""Run Lua inside Palworld through the mod's dev console.

    python tools/repl.py "P(FindFirstOf('PlayerController'):GetFullName())"
    python tools/repl.py -f script.lua
"""
import os
import sys
import time
from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "runtime"


def run(src: str, timeout: float = 20.0) -> str:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    out = RUNTIME / "dev_out.txt"
    if out.exists():
        out.unlink()
    tmp = RUNTIME / "dev_in.tmp"
    tmp.write_text(src, encoding="utf-8", newline="\n")
    os.replace(tmp, RUNTIME / "dev_in.lua")
    end = time.time() + timeout
    while time.time() < end:
        if out.exists():
            time.sleep(0.02)
            try:
                return out.read_text(encoding="utf-8", errors="replace")
            except OSError:
                pass
        time.sleep(0.05)
    return "TIMEOUT (is the game running with the mod and dev_enabled?)\n"


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "-f":
        code = Path(args[1]).read_text(encoding="utf-8")
    else:
        code = " ".join(args)
    sys.stdout.write(run(code))
