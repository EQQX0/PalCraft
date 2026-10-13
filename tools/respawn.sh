#!/usr/bin/env bash
# Dev: respawn the defeated test character through Palworld's own request, no clicks.
cd /c/Users/Admin/Desktop/repos/PalCraft
python tools/repl.py "FindFirstOf('PlayerController').PlayerState:RequestRespawn() P('asked')" | tail -1
