#!/usr/bin/env bash
# Dev: stand the Palworld character next to the nearest map object whose class name contains $1 (skip those within $2 cm).
cd /c/Users/Admin/Desktop/repos/PalCraft
python tools/repl.py "WANT='$1' SKIP=${2:-0} dofile([[C:\\Users\\Admin\\Desktop\\repos\\PalCraft\\build\\probe\\goto.lua]]) FindFirstOf('PlayerController'):SetControlRotation({Pitch=-15,Yaw=0,Roll=0})" | tail -1
