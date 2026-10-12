#!/usr/bin/env bash
# Start Palworld through Steam and wait until the mod's dev console answers. Clears a lingering crash reporter first.
export PYTHONPATH="C:/Users/Admin/PalCraft/ref/universal-modder"
cd /c/Users/Admin/PalCraft
LOG="/c/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/UE4SS.log"
for pid in $(python -m um win ps 2>/dev/null | grep -i "CrashReportClient" | awk '{print $1}'); do python -m um win kill "$pid" >/dev/null 2>&1; done
if ! python -m um win ps 2>/dev/null | grep -qi "Palworld-Win64-Shipping"; then
  # Melty switches the loader off when Palworld exits: a dev start switches it back on.
  W="/c/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64"
  [ -f "$W/dwmapi.dll" ] || cp "$W/dwmapi.dll.melty-off" "$W/dwmapi.dll"
  rm -f "$LOG"
  python -m um win launch --steam 1623730
fi
for i in $(seq 1 60); do
  if [ -f "$LOG" ] && grep -q "dev console on" "$LOG"; then
    if python tools/repl.py "P('alive')" | grep -q alive; then echo up; exit 0; fi
  fi
  sleep 3
done
echo "not up"; exit 1
