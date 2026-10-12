#!/usr/bin/env bash
# Dev: Palworld's private bytes now and after N seconds (default 20), with the growth rate.
N=${1:-20}
powershell -NoProfile -Command "\$a=(Get-Process Palworld-Win64-Shipping).PrivateMemorySize64; Start-Sleep $N; \$b=(Get-Process Palworld-Win64-Shipping).PrivateMemorySize64; '{0:N0} MB -> {1:N0} MB, {2:N1} MB/s' -f (\$a/1MB),(\$b/1MB),((\$b-\$a)/1MB/$N)"
