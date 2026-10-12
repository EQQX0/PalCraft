#!/usr/bin/env bash
# Dev: start Palworld (if it is not running), click through its title screen into the first world and wait
# until the player exists. Click positions are for a 1920x1080 window.
cd /c/Users/Admin/PalCraft
inworld() { python tools/repl.py "local pc=FindFirstOf('PlayerController'); P(pc:GetFullName():find('PL_MainWorld') and pc.Pawn:IsValid() and 'inworld' or 'no')" | grep -q inworld; }
bash tools/pal_up.sh || exit 1
if inworld; then echo inworld; exit 0; fi
for try in 1 2 3; do
  SCALE=0.5 bash tools/pal.sh "sleep 2500" "click 960 707" "sleep 1500" "click 960 735" "sleep 1500" "click 960 619" "sleep 2500" "click 825 255" "sleep 1500" "click 1456 981" "sleep 4000"
  for i in $(seq 1 25); do if inworld; then echo inworld; exit 0; fi; sleep 3; done
done
echo "not in world"; exit 1
