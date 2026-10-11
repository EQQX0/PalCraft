#!/usr/bin/env bash
# During a Melty test: wait for run $1 to start Palworld, click through the title screen into the first world,
# then print the self-test checks. Click positions are for a 1920x1080 window.
cd /c/Users/Admin/PalCraft
run=$1
for i in $(seq 1 90); do
  r=$(python -c "
import json,os
try: print(json.load(open(os.path.expandvars(r'%LOCALAPPDATA%\Melty\test\palcraft-6.json')))['run'])
except Exception: print(0)")
  if [ "$r" = "$run" ] && tasklist //FI "IMAGENAME eq Palworld-Win64-Shipping.exe" 2>/dev/null | grep -q Palworld; then break; fi
  python -c "import time; time.sleep(4)"
done
echo "run $r, Palworld up"
python -c "import time; time.sleep(32)"
SCALE=0.5 bash tools/pal.sh "sleep 500" "click 960 707" "sleep 1200" "click 960 735" "sleep 1500" "click 960 619" "sleep 2500" "click 825 255" "sleep 1500" "click 1456 981" "sleep 4000"
python -c "import time; time.sleep(50)"
SCALE=0.5 bash tools/pal.sh
cat "$LOCALAPPDATA/Melty/test/palcraft-6-checks.txt" 2>/dev/null
grep -a "WARN\|ERROR" "$LOCALAPPDATA/PalCraft/Prism/instances/PalCraft/.minecraft/logs/latest.log" | cut -c1-160 | head -8
