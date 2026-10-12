"""During a Melty test: wait until test TESTID's run RUN has a Palworld of its own running.

    python tools/test_wait.py <testId> <run> [timeout seconds]

Prints "up" once Palworld was started after Melty wrote that run's file, "timeout" otherwise.
"""
import json
import os
import subprocess
import sys
import time

test, run = sys.argv[1], int(sys.argv[2])
limit = time.time() + (int(sys.argv[3]) if len(sys.argv) > 3 else 500)
path = os.path.expandvars(r"%LOCALAPPDATA%\Melty\test\palcraft-6.json")
PS = ("$p = Get-Process Palworld-Win64-Shipping -ErrorAction SilentlyContinue | Select-Object -First 1; "
      "if ($p) { [DateTimeOffset]::new($p.StartTime).ToUnixTimeSeconds() } else { 0 }")

while time.time() < limit:
    try:
        with open(path, encoding="utf-8") as f:
            now = json.load(f)
        wrote = os.path.getmtime(path)
    except (OSError, ValueError):
        now = {}
    if now.get("testId") == test and now.get("run") == run:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", PS], capture_output=True, text=True).stdout
        started = int(out.strip() or 0)
        if started >= wrote - 2:
            print("up")
            sys.exit(0)
    time.sleep(4)
print("timeout")
sys.exit(1)
