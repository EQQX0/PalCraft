#!/usr/bin/env bash
# Dev: start Palworld if needed and enter the world named "PalCraft Test", with no clicks and no keys: the
# title screens are worked through their own handlers (tools/pal_enter.lua). The other worlds on this PC are
# the owner's own: never enter those.
cd /c/Users/Admin/Desktop/repos/PalCraft
inworld() { python tools/repl.py "local pc=FindFirstOf('PlayerController'); P(pc:GetFullName():find('PL_MainWorld') and pc.Pawn:IsValid() and 'inworld' or 'no')" | grep -q inworld; }
bash tools/pal_up.sh || exit 1
if inworld; then echo inworld; exit 0; fi
for i in $(seq 1 8); do
  r=$(python tools/repl.py -f tools/pal_enter.lua)
  echo "$r"
  case "$r" in *started*) break;; esac
  sleep 2
done
for i in $(seq 1 20); do if inworld; then echo inworld; exit 0; fi; sleep 3; done
echo "not in world"; exit 1
