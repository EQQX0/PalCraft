#!/usr/bin/env bash
# Dev: run Palworld console commands (its own cheat manager) in the test world, one per argument.
cd /c/Users/Admin/PalCraft
for c in "$@"; do
  python tools/repl.py "local pc=FindFirstOf('PlayerController'); StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):ExecuteConsoleCommand(pc,[[$c]],pc); P('sent: $c')" | tail -1
done
