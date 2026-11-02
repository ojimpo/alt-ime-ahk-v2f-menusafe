#Requires AutoHotkey v2.0
#Include ../alt-ime-ahk-v2f-menusafe.ahk

Checks := 0
Observed := []
try {
    TestTap()
    TestChords()
    TestLifecycle()
    TestNativeHooks()
    FileAppend("PASS: " Checks " assertions (state machine + Windows hook integration)`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL: " e.Message " at " e.File ":" e.Line "`n" e.Stack "`n", "**")
    ExitApp(1)
}

Assert(ok, description) {
    global Checks
    Checks += 1
    if !ok
        throw Error(description)
}

Event(c, vk, up := false, time := 0, bypass := false) {
    sc := vk = 0xA4 || vk = 0xA5 ? 0x38 : 0
    return c.Key(vk, sc, (vk = 0xA5 ? 1 : 0) | (up ? 2 : 0), time, bypass)
}

TestTap() {
    for vk in [0xA4, 0xA5] {
        c := DeferredAltCore()
        r := Event(c, vk)
        Assert(r.block && !r.keys.Length && r.ime = -1, "Alt-down is invisible")
        r := Event(c, vk, true, 80)
        Assert(r.block && !r.keys.Length && r.ime = (vk = 0xA5), "tap only sets IME")
        Assert(!c.Alt.Count, "tap resets state")
        Event(c, vk, false, 100)
        r := Event(c, vk, true, 1200)
        Assert(!r.keys.Length && r.ime = -1, "long alone neither toggles IME nor opens menu")
        Event(c, vk, false, 1300)
        r := Event(c, vk, false, 1400)
        Assert(r.block && !r.keys.Length, "autorepeat remains invisible")
        r := Event(c, vk, true, 1500)
        Assert(r.ime = (vk = 0xA5), "autorepeat does not cancel a tap")
    }
    c := DeferredAltCore(0)
    Event(c, 0xA4)
    Assert(Event(c, 0xA4, true, 60000).ime = 0, "timeout can be disabled")
}

TestChords() {
    ; Tab, F4, Space, letters, Shift and Ctrl all use the same path.
    for alt in [0xA4, 0xA5] {
        for key in [9, 0x73, 0x20, 0x46, 0xA0, 0xA2] {
            c := DeferredAltCore()
            Event(c, alt)
            r := Event(c, key)
            Assert(r.block && r.keys.Length = 2, "first chord key is replayed")
            Assert(r.keys[1].vk = alt && r.keys[1].flags = (alt = 0xA5), "correct Alt precedes key")
            Assert(r.keys[2].vk = key && r.keys[2].flags = 0, "trigger key follows Alt")
            Assert(!Event(c, key, true).block, "key-up passes through")
            r := Event(c, key)
            Assert(!r.block && !r.keys.Length, "repeated Tab leaves Alt held")
            Event(c, key, true)
            r := Event(c, alt, true)
            Assert(r.keys.Length = 1 && r.keys[1].flags & 2, "Alt-up releases switcher")
            Assert(r.ime = -1, "chord never changes IME")
        }
        c := DeferredAltCore()
        Event(c, alt)
        Event(c, 9)
        r := Event(c, alt, true)
        Assert(r.keys.Length = 1 && r.ime = -1, "Alt may be released before Tab")
        Assert(!Event(c, 9, true).block, "late Tab-up is preserved")
    }
    c := DeferredAltCore()
    Event(c, 0xA4)
    keys := c.Mouse()
    Assert(keys.Length = 1 && keys[1].vk = 0xA4, "mouse promotes pending Alt")
    Assert(Event(c, 0xA4, true).ime = -1, "mouse cancels IME tap")
    c := DeferredAltCore()
    Event(c, 0xA4)
    r := c.Key(0x25, 0x4B, 1, 0)
    Assert(r.keys[2].sc = 0x4B && r.keys[2].flags = 1, "extended key is preserved")
}

TestLifecycle() {
    c := DeferredAltCore()
    Assert(!Event(c, 0xA4, true).block, "startup orphan release passes")
    Event(c, 0xA4)
    Event(c, 0xA5)
    Assert(Event(c, 0xA4, true).ime = -1 && Event(c, 0xA5, true).ime = -1, "two Alts cancel both taps")
    for modifier in [0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C] {
        c := DeferredAltCore()
        Event(c, modifier)
        Assert(!Event(c, 0xA4).block, "pre-held modifier keeps Alt native")
        Assert(!Event(c, 0xA4, true).block, "native Alt-up passes")
    }
    c := DeferredAltCore()
    Assert(!Event(c, 0xA4, false, 0, true).block, "RDP Alt-down passes")
    Assert(!Event(c, 0xA4, true).block, "RDP Alt-up passes even after focus changes")
    Event(c, 0xA4)
    Event(c, 9)
    keys := c.ReleaseAll()
    Assert(keys.Length = 1 && keys[1].flags = 2 && !c.Alt.Count, "exit releases forwarded Alt")
    Event(c, 0xA5)
    Assert(!c.ReleaseAll().Length, "exit never sends a pending Alt")
    Event(c, 0xA4)
    Event(c, 0x41, true)
    Assert(Event(c, 0xA4, true).ime = -1, "pre-existing key release cancels alone")
}

; A test-only adapter accepts uniquely tagged synthetic input as source input.
; The production adapter always ignores injected input. F23 is used instead
; of Tab/F4 so this integration test does not switch or close user windows.
class TestApp extends DeferredAltApp {
    __New() {
        super.__New(1000)
        this.IMEs := []
        this.Core.Held.Clear()
    }
    Keyboard(code, msg, p) {
        if (code >= 0 && NumGet(p, 16, "UPtr") = 0x54455354) {
            copy := Buffer(A_PtrSize = 8 ? 24 : 20)
            DllCall("RtlMoveMemory", "Ptr", copy, "Ptr", p, "UPtr", copy.Size)
            NumPut("UInt", NumGet(copy, 8, "UInt") & ~0x12, copy, 8)
            return super.Keyboard(code, msg, copy.Ptr)
        }
        return super.Keyboard(code, msg, p)
    }
    SetIME(enabled) {
        this.IMEs.Push(enabled)
    }
    ; Synthetic input never updates the real key state, so trust the Core.
    IsDown(vk) {
        return true
    }
}

Observe(code, msg, p) {
    global Observed
    if (code >= 0 && NumGet(p, 16, "UPtr") = 0x41494D45)
        Observed.Push({vk: NumGet(p, 0, "UInt"), flags: NumGet(p, 8, "UInt")})
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "UPtr", msg, "Ptr", p, "Ptr")
}

TestNativeHooks() {
    global Observed
    callback := CallbackCreate(Observe, , 3)
    hook := DllCall("SetWindowsHookEx", "Int", 13, "Ptr", callback,
        "Ptr", DllCall("GetModuleHandle", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    Assert(!!hook, "observer hook installs")
    app := TestApp()
    source := DeferredAltApp(1000)
    source.Tag := 0x54455354
    try {
        app.Start()
        Assert(app.KeyboardHook && app.MouseHook, "production hooks install")
        source.SendKeys([{vk: 0xA4, sc: 0x38, flags: 0}])
        Sleep(20)
        source.SendKeys([{vk: 0xA4, sc: 0x38, flags: 2}])
        Sleep(20)
        Assert(!Observed.Length && app.IMEs.Length = 1 && app.IMEs[1] = 0, "native hook hides left Alt tap")
        source.SendKeys([{vk: 0xA5, sc: 0x38, flags: 1}])
        Sleep(20)
        source.SendKeys([{vk: 0xA5, sc: 0x38, flags: 3}])
        Sleep(20)
        Assert(!Observed.Length && app.IMEs.Length = 2 && app.IMEs[2] = 1, "native hook hides right Alt tap")
        source.SendKeys([{vk: 0xA4, sc: 0x38, flags: 0}])
        Sleep(20)
        source.SendKeys([{vk: 0x86, sc: 0, flags: 0}])
        Sleep(20)
        source.SendKeys([{vk: 0x86, sc: 0, flags: 2}])
        source.SendKeys([{vk: 0xA4, sc: 0x38, flags: 2}])
        Sleep(20)
        Assert(Observed.Length = 3, "native hook replay has Alt-down, key-down, Alt-up")
        Assert(Observed[1].vk = 0xA4 && !(Observed[1].flags & 0x80), "Alt-down delivered first")
        Assert(Observed[2].vk = 0x86, "chord key delivered second")
        Assert(Observed[3].vk = 0xA4 && (Observed[3].flags & 0x80), "Alt-up delivered last")
        Assert(app.IMEs.Length = 2 && !app.Failed, "native chord does not set IME or fail")
        if (A_Args.Length && A_Args[1] = "--desktop")
            TestDesktop(app, source)
    } finally {
        app.Stop()
        DllCall("UnhookWindowsHookEx", "Ptr", hook)
        CallbackFree(callback)
    }
}

TestDesktop(app, source) {
    windows := []
    saved := DllCall("GetForegroundWindow", "Ptr")
    try {
        Loop 3 {
            w := Gui(, "Alt IME shortcut test " A_Index)
            w.AddText(, "Temporary shortcut test window. No user documents.")
            w.Show("w370 h100 NoActivate")
            windows.Push(w)
        }
        for alt in [0xA4, 0xA5] {
            for w in windows {
                WinActivate("ahk_id " w.Hwnd)
                WinWaitActive("ahk_id " w.Hwnd, , 2)
                Sleep(80)
            }
            SourceKey(source, alt)
            SourceKey(source, 9)
            SourceKey(source, 9, true)
            SourceKey(source, 9)
            SourceKey(source, 9, true)
            SourceKey(source, alt, true)
            Assert(!!WinWaitActive("ahk_id " windows[1].Hwnd, , 2), "real repeated Alt+Tab selects first test window")
            Assert(!(DllCall("GetAsyncKeyState", "Int", alt, "Short") & 0x8000), "real switcher releases Alt")
        }
        for w in windows {
            WinActivate("ahk_id " w.Hwnd)
            WinWaitActive("ahk_id " w.Hwnd, , 2)
            Sleep(80)
        }
        SourceKey(source, 0xA4)
        SourceKey(source, 9)
        SourceKey(source, 9, true)
        SourceKey(source, 0xA0)
        SourceKey(source, 9)
        SourceKey(source, 9, true)
        SourceKey(source, 0xA0, true)
        SourceKey(source, 0xA4, true)
        Assert(!!WinWaitActive("ahk_id " windows[3].Hwnd, , 2), "real Alt+Shift+Tab reverses switcher")
        Assert(!app.Failed && !app.Core.Alt.Count, "desktop shortcuts leave no pending Alt")
    } finally {
        ; Release only test keys and close only our disposable windows.
        source.SendKeys([{vk: 0xA0, sc: 0x2A, flags: 2},
            {vk: 0xA4, sc: 0x38, flags: 2}, {vk: 0xA5, sc: 0x38, flags: 3}])
        for w in windows
            w.Destroy()
        if saved && WinExist("ahk_id " saved)
            WinActivate("ahk_id " saved)
    }
}

SourceKey(source, vk, up := false) {
    sc := (vk = 0xA4 || vk = 0xA5) ? 0x38 : vk = 9 ? 0x0F : vk = 0xA0 ? 0x2A : 0
    source.SendKeys([{vk: vk, sc: sc, flags: (vk = 0xA5 ? 1 : 0) | (up ? 2 : 0)}])
    Sleep(80)
}
