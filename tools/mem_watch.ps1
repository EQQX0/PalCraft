# Dev: writes the private memory of Palworld and of the Minecraft dev client (the largest java) to
# build\mem.log every -Every seconds for -Minutes minutes. A leak shows as a line that keeps climbing.
param([int]$Minutes = 30, [int]$Every = 15)
$log = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\mem.log'
$end = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $end) {
    $pal = Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
    $mc = Get-Process -Name 'java' -ErrorAction SilentlyContinue | Sort-Object PrivateMemorySize64 -Descending | Select-Object -First 1
    $p = if ($pal) { '{0,6:N0} MB (pid {1}, up {2,4:N0} s)' -f ($pal.PrivateMemorySize64 / 1MB), $pal.Id, ((Get-Date) - $pal.StartTime).TotalSeconds } else { '     - ' }
    $m = if ($mc) { '{0,6:N0} MB' -f ($mc.PrivateMemorySize64 / 1MB) } else { '     - ' }
    Add-Content -Path $log -Value ('{0:HH:mm:ss}  Palworld {1}   Minecraft {2}' -f (Get-Date), $p, $m) -Encoding utf8
    Start-Sleep -Seconds $Every
}
