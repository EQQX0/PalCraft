# Dev aid: mutes the test games in Windows' volume mixer, and nothing else. The owner may be playing
# something of their own while a test runs.
#   powershell -File tools/mute_games.ps1 -Minutes 90     keeps them muted (a game opens its sound late)
#   powershell -File tools/mute_games.ps1 -Unmute         gives the sound back: Windows remembers a mute
#                                                         per program, so run this when the test is over
param([string[]]$Names = @('java', 'Palworld-Win64-Shipping'), [int]$Minutes = 0, [switch]$Unmute)
Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace PcAudio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator { }
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int flow, int state, out IMMDeviceCollection devices);
    }
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        int GetCount(out int n);
        int Item(int i, out IMMDevice device);
    }
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        int GetAudioSessionControl(IntPtr a, int b, out IntPtr c);
        int GetSimpleAudioVolume(IntPtr a, int b, out IntPtr c);
        int GetSessionEnumerator(out IAudioSessionEnumerator e);
    }
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        int GetCount(out int n);
        int GetSession(int i, out IAudioSessionControl2 s);
    }
    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        int GetState(out int s);
        int GetDisplayName(out IntPtr s);
        int SetDisplayName(IntPtr s, IntPtr ctx);
        int GetIconPath(out IntPtr s);
        int SetIconPath(IntPtr s, IntPtr ctx);
        int GetGroupingParam(out Guid g);
        int SetGroupingParam(ref Guid g, IntPtr ctx);
        int RegisterAudioSessionNotification(IntPtr n);
        int UnregisterAudioSessionNotification(IntPtr n);
        int GetSessionIdentifier(out IntPtr s);
        int GetSessionInstanceIdentifier(out IntPtr s);
        int GetProcessId(out uint pid);
    }
    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        int SetMasterVolume(float v, ref Guid ctx);
        int GetMasterVolume(out float v);
        int SetMute(bool m, ref Guid ctx);
        int GetMute(out bool m);
    }
    public static class Mixer {
        // Sets the mute of every sound session of the given processes; returns how many it changed.
        public static int SetMute(uint[] pids, bool mute) {
            int changed = 0;
            var en = (IMMDeviceEnumerator)(new Enumerator());
            IMMDeviceCollection devices;
            if (en.EnumAudioEndpoints(0, 1, out devices) != 0) return 0; // eRender, DEVICE_STATE_ACTIVE
            int nd; devices.GetCount(out nd);
            for (int d = 0; d < nd; d++) {
                IMMDevice dev; if (devices.Item(d, out dev) != 0) continue;
                Guid iid = typeof(IAudioSessionManager2).GUID; object o;
                if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) continue;
                IAudioSessionEnumerator se;
                if (((IAudioSessionManager2)o).GetSessionEnumerator(out se) != 0) continue;
                int ns; se.GetCount(out ns);
                for (int i = 0; i < ns; i++) {
                    IAudioSessionControl2 s; if (se.GetSession(i, out s) != 0) continue;
                    uint pid; s.GetProcessId(out pid);
                    if (Array.IndexOf(pids, pid) < 0) continue;
                    var vol = (ISimpleAudioVolume)s;
                    bool was; vol.GetMute(out was);
                    if (was != mute) { Guid ctx = Guid.Empty; vol.SetMute(mute, ref ctx); changed++; }
                }
            }
            return changed;
        }
    }
}
'@
$names = @($Names | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$until = (Get-Date).AddMinutes($Minutes)
do {
    $pids = [uint32[]]@(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    if ($pids.Count) {
        $n = [PcAudio.Mixer]::SetMute($pids, -not $Unmute)
        if ($n) { Write-Output ("{0} {1} sound session(s)" -f $(if ($Unmute) { 'unmuted' } else { 'muted' }), $n) }
    }
    if ((Get-Date) -lt $until) { Start-Sleep -Seconds 2 }
} while ((Get-Date) -lt $until)
