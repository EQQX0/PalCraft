#!/usr/bin/env bash
# From Palworld's title screen: dismiss notices, open the first world, wait until the player exists.
cd /c/Users/Admin/PalCraft
inworld() { python tools/repl.py "local pc=FindFirstOf('PlayerController'); P(pc:GetFullName():find('PL_MainWorld') and pc.Pawn:IsValid() and 'inworld' or 'no')" | grep -q inworld; }
if inworld; then echo inworld; exit 0; fi
# notices (two possible OK positions), then Start Game, world row, Start Game
tools/pal.sh "sleep 2000" "click 1280 943" "sleep 1200" "click 1280 980" "sleep 1500" "click 1280 825" "sleep 2500" "click 1100 340" "sleep 1500" "click 1942 1308" "sleep 3000"
for i in $(seq 1 40); do if inworld; then echo inworld; exit 0; fi; sleep 3; done
echo "not in world"; exit 1
