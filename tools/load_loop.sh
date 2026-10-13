#!/usr/bin/env bash
# Dev: start Palworld, enter the test world, stay a while, quit; N times. Counts the starts that died.
#   bash tools/load_loop.sh 10 [seconds in the world]     results in build/load_loop.log
# Each load takes the next of ARMS (default "on,lua"): the loader's object cache on or off
# (UE4SS-settings.ini, bUseUObjectArrayCache), and how the wait for the world asks: "lua" runs a search
# inside Palworld every few seconds, "shm" reads bridge.shm and runs nothing there, as for a player.
# "time" asks nothing and takes 42 s in the load for the world (for a mod that reports nothing).
# A third word "quiet" stops the dev console's timer once the world starts (ARMS="on,shm,quiet").
export PYTHONPATH="C:/Users/Admin/Desktop/repos/PalCraft/ref/universal-modder"
cd /c/Users/Admin/Desktop/repos/PalCraft
W="/c/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64"
N=${1:-10}; STAY=${2:-20}
read -r -a ARM <<< "${ARMS:-on,lua}"
running() { tasklist //FI "IMAGENAME eq Palworld-Win64-Shipping.exe" 2>/dev/null | grep -qi Palworld; }
nap() { python -c "import time; time.sleep($1)"; }
inworld_lua() { python tools/repl.py "local pc=FindFirstOf('PlayerController'); P(pc:GetFullName():find('PL_MainWorld') and pc.Pawn:IsValid() and 'inworld' or 'no')" | grep -q inworld; }
ok=0; bad=0
for i in $(seq 1 "$N"); do
  arm=${ARM[$(( (i - 1) % ${#ARM[@]} ))]}
  IFS=, read -r cache poll con <<< "$arm"
  if [ "$con" = quiet ]; then : > runtime/dev_quiet; else rm -f runtime/dev_quiet; fi
  [ "$cache" = off ] && v=false || v=true
  sed -i "s/^bUseUObjectArrayCache = .*/bUseUObjectArrayCache = $v/" "$W/UE4SS-settings.ini"
  res="DIED (never up)"
  if bash tools/pal_up.sh >/dev/null 2>&1; then
    res="DIED (title)"
    for t in $(seq 1 8); do
      r=$(python tools/repl.py -f tools/pal_enter.lua 2>&1 | tail -1)
      case "$r" in *started*) res="DIED (loading)"; break;; esac
      running || break
      nap 2
    done
    if [ "$res" = "DIED (loading)" ]; then
      for t in $(seq 1 40); do
        running || break
        if [ "$poll" = lua ]; then inworld_lua && { res=in; break; }
        elif [ "$poll" = time ]; then [ "$t" -ge 14 ] && { res=in; break; }
        else python tools/pal_inworld.py >/dev/null 2>&1 && { res=in; break; }; fi
        nap 3
      done
    fi
    if [ "$res" = in ]; then
      res=ok
      for s in $(seq 1 "$STAY"); do running || { res="DIED (in the world)"; break; }; nap 1; done
    fi
  fi
  if [ "$res" = ok ]; then
    ok=$((ok + 1))
    python tools/repl.py "local pc=FindFirstOf('PlayerController') StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):QuitGame(pc, pc, 0, false) P('quit')" >/dev/null 2>&1
  else
    bad=$((bad + 1))
    # The loader starts its log afresh with every Palworld: keep the one of a start that died.
    mkdir -p build/load_logs && cp "$W/UE4SS.log" "build/load_logs/$(date +%H%M%S)-$cache-$poll-${con:-on}.log" 2>/dev/null
  fi
  for s in $(seq 1 30); do running || break; nap 1; done
  running && python -m um win kill "$(python -m um win ps 2>/dev/null | grep -i 'Palworld-Win64-Shipping' | awk '{print $1}' | head -1)" >/dev/null 2>&1
  nap 2
  for pid in $(python -m um win ps 2>/dev/null | grep -i "CrashReportClient" | awk '{print $1}'); do python -m um win kill "$pid" >/dev/null 2>&1; done
  rm -f runtime/dev_in.lua
  echo "$(date +%T) load $i: $res   cache=$cache wait=$poll console=${con:-on}   [ok $ok, died $bad]" >> build/load_loop.log
done
echo "done: ok $ok, died $bad" >> build/load_loop.log
