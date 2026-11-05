"""Watch the mod log and press the switch key in the game window automatically.

Flow: the mod writes "staged ... into slot N — 再按一次切换键完成切换" when the
player picks a weapon in the pick panel. We then send a real "1"/"2" key to the
PBZ window so the game performs its own native switch (weapon ends up in hand).
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import sys
import time

LOG = r"D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PBZWeaponSwap\log.txt"
TITLE = "Phantom Blade Zero"
PATTERN = re.compile(r"staged \S+ into slot \d+ .*再按一次")
WM_KEYDOWN, WM_KEYUP = 0x0100, 0x0101
MAPVK_VK_TO_VSC = 0
user32 = ctypes.WinDLL("user32", use_last_error=True)


def find_window():
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        n = user32.GetWindowTextLengthW(hwnd)
        if n:
            buf = ctypes.create_unicode_buffer(n + 1)
            user32.GetWindowTextW(hwnd, buf, n + 1)
            if TITLE.lower() in buf.value.lower():
                found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    return found[0] if found else None


def press(hwnd, vk=0x31):
    """Real input injection: PostMessage is ignored by UE5 raw input, so use SendInput."""
    scan = user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)
    KEYEVENTF_SCANCODE = 0x0008
    KEYEVENTF_KEYUP = 0x0002

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                    ("time", wt.DWORD), ("dwExtraInfo", ctypes.POINTER(wt.ULONG))]

    class _INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 24)]
        _anonymous_ = ("u",)
        _fields_ = [("type", wt.DWORD), ("u", _U)]

    inputs = (_INPUT * 2)()
    inputs[0].type = 1
    inputs[0].ki.wVk = 0
    inputs[0].ki.wScan = scan
    inputs[0].ki.dwFlags = KEYEVENTF_SCANCODE
    inputs[1].type = 1
    inputs[1].ki.wVk = 0
    inputs[1].ki.wScan = scan
    inputs[1].ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP
    sent = user32.SendInput(2, inputs, ctypes.sizeof(_INPUT))
    return sent == 2


def main():
    hwnd = None
    while not hwnd:
        hwnd = find_window()
        if not hwnd:
            time.sleep(1.0)
    print(f"watching {LOG} for hwnd {hwnd}", flush=True)
    pos = os.path.getsize(LOG) if os.path.exists(LOG) else 0
    while True:
        if not user32.IsWindow(hwnd):
            hwnd = None
            while not hwnd:
                hwnd = find_window()
                if not hwnd:
                    time.sleep(1.0)
            print(f"window re-acquired: {hwnd}", flush=True)
        try:
            size = os.path.getsize(LOG)
        except OSError:
            time.sleep(0.2)
            continue
        if size < pos:  # log truncated / new session
            pos = 0
        if size > pos:
            with open(LOG, "r", encoding="utf-8", errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
            for line in chunk.splitlines():
                if PATTERN.search(line):
                    time.sleep(0.25)
                    vk = 0x32 if "shaqi" in line else 0x31
                    user32.SetForegroundWindow(hwnd)
                    time.sleep(0.05)
                    ok = press(hwnd, vk)
                    print(f"{time.strftime('%H:%M:%S')} matched -> sent vk=0x{vk:02x} ok={ok}", flush=True)
        time.sleep(0.15)


if __name__ == "__main__":
    sys.exit(main())
