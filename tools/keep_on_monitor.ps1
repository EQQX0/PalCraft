# Dev aid: keeps the windows of both games (and Prism) on one monitor while a test session runs.
#   powershell -File tools/keep_on_monitor.ps1 -Device '\\.\DISPLAY2' -Minutes 60
# -Names limits it to those programs: the owner may have a Minecraft of their own open (javaw), which stays put.
param([string]$Device = '\\.\DISPLAY2', [int]$Minutes = 60,
    [string[]]$Names = @('java', 'javaw', 'prismlauncher', 'Palworld-Win64-Shipping', 'Palworld'))
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PcWin {
    public delegate bool Cb(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(Cb cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hgt, uint f);
}
'@
$target = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -eq $Device }
if (-not $target) { Write-Output "no monitor $Device"; exit 1 }
$b = $target.Bounds
$names = @($Names | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) # -File hands a,b,c over as one word
$until = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $until) {
    $pids = @{}
    Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { $pids[[uint32]$_.Id] = $_.Name }
    if ($pids.Count) {
        $cb = [PcWin+Cb] {
            param($h, $l)
            $procId = 0
            [void][PcWin]::GetWindowThreadProcessId($h, [ref]$procId)
            if ($pids.ContainsKey([uint32]$procId) -and [PcWin]::IsWindowVisible($h)) {
                $r = New-Object PcWin+RECT
                if ([PcWin]::GetWindowRect($h, [ref]$r) -and ($r.R - $r.L) -gt 60) {
                    $cx = ($r.L + $r.R) / 2; $cy = ($r.T + $r.B) / 2
                    if ($cx -lt $b.Left -or $cx -ge $b.Right -or $cy -lt $b.Top -or $cy -ge $b.Bottom) {
                        $w = [Math]::Min($r.R - $r.L, $b.Width); $hgt = [Math]::Min($r.B - $r.T, $b.Height)
                        $x = $b.Left + [int](($b.Width - $w) / 2); $y = $b.Top + [int](($b.Height - $hgt) / 2)
                        # SWP_NOZORDER | SWP_NOACTIVATE
                        [void][PcWin]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, $w, $hgt, 0x0014)
                        Write-Output ("moved {0} to {1},{2} {3}x{4}" -f $pids[[uint32]$procId], $x, $y, $w, $hgt)
                    }
                }
            }
            return $true
        }
        [void][PcWin]::EnumWindows($cb, [IntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 150
}
