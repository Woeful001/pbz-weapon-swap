import ctypes, sys, time
u = ctypes.windll.user32
KEY = {'return':0x0D, 'one':0x31, 'two':0x32, 'escape':0x1B, 'f3':0x72, 'f4':0x73, 'f9':0x78}
def find():
    found = []
    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def cb(h, l):
        n = u.GetWindowTextLengthW(h)
        if n and u.IsWindowVisible(h):
            b = ctypes.create_unicode_buffer(n + 1)
            u.GetWindowTextW(h, b, n + 1)
            if b.value.strip().startswith("Phantom Blade Zero"):
                found.append(h)
        return True
    u.EnumWindows(cb, 0)
    return found[0] if found else 0
def focus(h):
    u.ShowWindow(h, 9); u.SetForegroundWindow(h); time.sleep(0.4)
def tap(h, name, hold=0.06):
    vk = KEY[name]
    focus(h)
    u.keybd_event(vk, 0, 0, 0); time.sleep(hold)
    u.keybd_event(vk, 0, 2, 0); time.sleep(0.25)
if __name__ == '__main__':
    h = find()
    if not h:
        print("NO_WINDOW"); sys.exit(1)
    print("hwnd", h)
    for name in sys.argv[1:]:
        tap(h, name)
        print("sent", name)
