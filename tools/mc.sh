#!/usr/bin/env bash
# Send dev commands to the Minecraft dev client (one argument per command), then print what it logged.
cd /c/Users/Admin/PalCraft
n=$(grep -ac "" build/mc_run.log)
printf '%s\n' "$@" > runtime/mc_cmd.tmp && mv runtime/mc_cmd.tmp runtime/mc_cmd.txt
python -c "import time; time.sleep(${WAIT:-1.2})"
tail -n +$((n+1)) build/mc_run.log | grep -a "devcmd" | cut -c1-900
