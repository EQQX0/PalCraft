"""Dev aid: post a key to Palworld's window without giving it the keyboard (the owner may be using the PC).

    python tools/pal_key.py 0x09        Tab
"""
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
found = []


def name_of(pid):
    h = kernel32.OpenProcess(0x1000, False, pid)
    if not h:
        return ""
    buf = ctypes.create_unicode_buffer(520)
    size = wintypes.DWORD(520)
    ok = kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
    kernel32.CloseHandle(h)
    return buf.value if ok else ""


@ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
def each(hwnd, _):
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if user32.IsWindowVisible(hwnd) and name_of(pid.value).endswith("Palworld-Win64-Shipping.exe"):
        cls = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(hwnd, cls, 64)
        if cls.value == "UnrealWindow":
            found.append(hwnd)
    return True


user32.EnumWindows(each, 0)
if not found:
    sys.exit("no Palworld window")
vk = int(sys.argv[1], 0)
scan = user32.MapVirtualKeyW(vk, 0)
user32.PostMessageW(found[0], 0x0100, vk, 1 | scan << 16)
time.sleep(0.08)
user32.PostMessageW(found[0], 0x0101, vk, 1 | scan << 16 | 0xC0000000)
print("posted", hex(vk), "to", hex(found[0]))
