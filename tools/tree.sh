#!/usr/bin/env bash
# Dev: stand in front of the nearest standing tree whose foliage type contains $1 (default tree_), skipping those within $2 cm.
cd /c/Users/Admin/Desktop/repos/PalCraft
python tools/repl.py "LIST=nil WANT='${1:-tree_}' SKIP=${2:-0} DIST=${3:-220} dofile([[C:\Users\Admin\Desktop\repos\PalCraft\build\probe\tree.lua]])" | tail -1
