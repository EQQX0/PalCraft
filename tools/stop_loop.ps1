# Dev: stops every tools/load_loop.sh still running (stopping its task leaves the shells behind), then
# says what is left: loop shells, Palworld, a crash reporter, the owner's own Minecraft (javaw).
$pat = 'tools/load_' + 'loop\.sh \d'
foreach ($x in @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $pat })) {
    & taskkill /PID $x.ProcessId /T /F 2>$null | Out-Null
}
Start-Sleep -Seconds 2
"loops left: " + @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $pat }).Count
foreach ($p in @(Get-Process -Name 'Palworld-Win64-Shipping', 'CrashReportClient', 'javaw' -ErrorAction SilentlyContinue)) {
    "{0} {1} since {2:HH:mm:ss}" -f $p.Id, $p.ProcessName, $p.StartTime
}
exit 0
