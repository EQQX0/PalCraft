"""Send keys and mouse to the installed Minecraft input window (the see-through window above Palworld).

    python tools/mcdrive.py "key 0x31" "hold 0x57 1500" "rel 300 0" "lclick" "rclick" "sleep 500"

Dev builds have tools/mc.sh; an installed build has no dev console, so this drives it the way a player would.
"""
import ctypes
import sys
import time
from ctypes import wintypes

u = ctypes.windll.user32
k = ctypes.windll.kernel32
u.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
u.IsWindowVisible.argtypes = [wintypes.HWND]
u.SetForegroundWindow.argtypes = [wintypes.HWND]
u.GetForegroundWindow.restype = wintypes.HWND
u.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]


class KI(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_void_p)]


class MI(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_void_p)]


class U(ctypes.Union):
    _fields_ = [("ki", KI), ("mi", MI)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", U)]


def send(inp):
    u.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def key(vk, up):
    i = INPUT(type=1)
    i.u.ki = KI(vk, u.MapVirtualKeyW(vk, 0), 2 if up else 0, 0, None)
    send(i)


def mouse(flags, dx=0, dy=0):
    i = INPUT(type=0)
    i.u.mi = MI(dx, dy, 0, flags, 0, None)
    send(i)


def find():
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(h, _):
        buf = ctypes.create_unicode_buffer(200)
        u.GetWindowTextW(h, buf, 200)
        if u.IsWindowVisible(h) and (buf.value.startswith("Minecraft") or buf.value == "PalCraft"):
            found.append(h)
        return True

    u.EnumWindows(cb, 0)
    return found[0] if found else None


def focus(h):
    if u.GetForegroundWindow() == h:
        return True
    key(0x12, False)  # an Alt press lets this process set the foreground window
    u.SetForegroundWindow(h)
    key(0x12, True)
    time.sleep(0.3)
    return u.GetForegroundWindow() == h


def title(h):
    buf = ctypes.create_unicode_buffer(200)
    u.GetWindowTextW(h, buf, 200)
    return buf.value


def main():
    args = sys.argv[1:]
    raw = bool(args) and args[0] == "--raw"  # --raw: send to whatever has the keyboard, change no focus
    if raw:
        args = args[1:]
    else:
        h = find()
        if not h:
            print("no Minecraft window")
            return 1
        if not focus(h):
            print("could not focus Minecraft")
            return 1
    for c in args:
        p = c.split()
        if p[0] == "fg":
            print("foreground:", repr(title(u.GetForegroundWindow())))
        elif p[0] == "sleep":
            time.sleep(int(p[1]) / 1000)
        elif p[0] == "key":
            key(int(p[1], 0), False); time.sleep(0.06); key(int(p[1], 0), True)
        elif p[0] == "hold":
            key(int(p[1], 0), False); time.sleep(int(p[2]) / 1000); key(int(p[1], 0), True)
        elif p[0] == "rel":
            mouse(0x0001, int(p[1]), int(p[2]))
        elif p[0] == "lclick":
            mouse(0x0002); time.sleep(0.08); mouse(0x0004)
        elif p[0] == "lhold":
            mouse(0x0002); time.sleep(int(p[1]) / 1000); mouse(0x0004)
        elif p[0] == "rclick":
            mouse(0x0008); time.sleep(0.08); mouse(0x0010)
        else:
            print("unknown", c)
            return 1
        time.sleep(0.05)
    return 0


sys.exit(main())
