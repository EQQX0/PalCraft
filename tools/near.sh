#!/usr/bin/env bash
# Dev: stand $2 cm (default 300) from the nearest actor whose class name contains $1, facing it. $3 = height above it in cm.
cd /c/Users/Admin/Desktop/repos/PalCraft
python tools/repl.py "WANT='$1' DIST=${2:-300} UP=${3:-100} PITCH=${4:--8} BASE=${BASE:-nil} ALIVE=${ALIVE:-nil} dofile([[C:\\Users\\Admin\\Desktop\\repos\\PalCraft\\build\\probe\\near.lua]])" | tail -1
