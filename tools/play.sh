#!/usr/bin/env bash
# Play the installed game with real input, then screenshot Palworld's window (where the picture is).
# Usage: tools/play.sh "key 0x74" "sleep 500" ...   Keys go to whichever game holds the keyboard.
# W 0x57 A 0x41 S 0x53 D 0x44 space 0x20 shift 0xA0 ctrl 0xA2 E 0x45 esc 0x1B enter 0x0D T 0x54 slash 0xBF
# F5 0x74 F8 0x77   look: "rel dx dy"   attack: "mdown 960 540" ... "mup"   use: "click 960 540 right"
export PYTHONPATH="C:/Users/Admin/Desktop/repos/PalCraft/ref/universal-modder"
cd /c/Users/Admin/Desktop/repos/PalCraft
if [ $# -gt 0 ]; then python -m um win drive --proc javaw --no-retry "$@" 2>&1 | grep -v -E "ok$|ready" ; fi
python -m um win shot --exe Palworld-Win64-Shipping.exe build/shots/${SHOT:-play}.png --scale ${SCALE:-0.5} >/dev/null 2>&1
