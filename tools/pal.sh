#!/usr/bin/env bash
# Drive Palworld's window, then save a scaled screenshot. Usage: tools/pal.sh "click 1280 980" "sleep 800"
export PYTHONPATH="C:/Users/Admin/Desktop/repos/PalCraft/ref/universal-modder"
cd /c/Users/Admin/Desktop/repos/PalCraft
if [ $# -gt 0 ]; then python -m um win drive --proc Palworld-Win64-Shipping "focus" "sleep 250" "$@" 2>&1 | grep -v -E "ok$|ready" ; fi
python -m um win shot --exe Palworld-Win64-Shipping.exe build/shots/pal.png --scale ${SCALE:-0.4} >/dev/null 2>&1
