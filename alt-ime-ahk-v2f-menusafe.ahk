#Requires AutoHotkey v2.0
#SingleInstance Force
#Include DeferredAltCore.ahk

; Karabiner-style lazy modifier + to_if_alone.
; 0 disables the tap timeout. Holding Alt alone NEVER sends Alt.
AloneTimeoutMs := 1000

if (A_LineFile = A_ScriptFullPath) {
    if (A_Args.Length && A_Args[1] = "--check")
        ExitApp(0)
    Persistent()
    app := DeferredAltApp(AloneTimeoutMs)
    app.RegisterDiagnostics()
    A_IconTip := "Alt IME — deferred Alt"
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Deferred Alt (左右Alt単押しでIME切替)", (*) => 0)
    A_TrayMenu.Disable("Deferred Alt (左右Alt単押しでIME切替)")
    A_TrayMenu.Add("終了（元のAlt動作に戻す）", (*) => ExitApp())
    app.Start()
}

class DeferredAltApp {
    __New(timeout) {
        this.Core := DeferredAltCore(timeout)
        this.KeyboardHook := 0
        this.MouseHook := 0
        this.KeyboardCallback := 0
        this.MouseCallback := 0
        this.Tag := 0x41494D45
        this.Failed := false
        this.KbCount := 0
        this.MouseCount := 0
        this.LastInput := 0
        this.LastTotal := 0
        this.Suspect := 0
        this.Ticks := 0
        this.Reinstalls := 0
        this.LogBuf := []
        this.LogFile := A_ScriptDir "\alt-ime.log"
        this.Watching := false
        this.StartedAt := A_TickCount
        for vk in [0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C]
            if (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000)
                this.Core.Held[vk] := true
    }

    RegisterDiagnostics() {
        OnExit(ObjBindMethod(this, "HandleExit"))
        OnError(ObjBindMethod(this, "HandleError"))
    }

    ; Log before cleanup resets the state. Flush synchronously: timers will
    ; not get another turn once the process exits.
    HandleExit(reason, code) {
        try this.Log("exiting pid=" ProcessExist() " reason=" reason " code=" code
            " uptimeMs=" (A_TickCount - this.StartedAt) " failed=" this.Failed
            " keyboardHook=" (!!this.KeyboardHook) " mouseHook=" (!!this.MouseHook)
            " kb=" this.KbCount " mouse=" this.MouseCount
            " reinstalls=" this.Reinstalls " altCount=" this.Core.Alt.Count
            " heldCount=" this.Core.Held.Count)
        try this.FlushLog()
        try {
            this.Stop()
        } catch as e {
            try this.Log("exit cleanup error: " this.ErrorDetails(e))
        }
        try this.FlushLog()
        return 0
    }

    ErrorDetails(e) {
        if !IsObject(e)
            return "non-object exception"
        return StrReplace(StrReplace(Type(e) ": " e.Message " file=" e.File
            " line=" e.Line " stack=" e.Stack, "`r", ""), "`n", " | ")
    }

    HandleError(e, mode) {
        try {
            this.Log("unhandled error pid=" ProcessExist() " mode=" mode " " this.ErrorDetails(e))
            this.FlushLog()
        }
        ; Preserve AutoHotkey's normal error reporting and exit behavior.
        return 0
    }

    ; Append-only diagnostics. Never records which keys were typed: only
    ; modifier state anomalies, hook restarts and session events.
    Log(msg) {
        this.LogBuf.Push(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg)
        SetTimer(ObjBindMethod(this, "FlushLog"), -50)
    }

    FlushLog() {
        if !this.LogBuf.Length
            return
        text := ""
        for line in this.LogBuf
            text .= line "`n"
        this.LogBuf := []
        try {
            if (FileExist(this.LogFile) && FileGetSize(this.LogFile) > 262144)
                FileMove(this.LogFile, this.LogFile ".1", true)
            FileAppend(text, this.LogFile, "UTF-8")
        }
    }

    ; Overridden by tests, whose synthetic input never updates the real state.
    IsDown(vk) {
        return !!(DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000)
    }

    ; Forget modifiers/keys whose release we never saw (lock screen, UAC,
    ; a hook timeout). A stale entry makes every later Alt look like a chord
    ; with a held modifier, so Alt+Tab works but a lone Alt never switches IME.
    ; Alt itself is not checked: this hook swallows it, so the OS reports it up.
    PruneHeld(why) {
        stale := []
        for vk in this.Core.Held
            if !this.IsDown(vk)
                stale.Push(vk)
        for vk in stale {
            this.Core.Held.Delete(vk)
            this.Log("stale Held vk=0x" Format("{:X}", vk) " dropped (" why ")")
        }
    }

    OnSession(wParam, lParam, msg, hwnd) {
        names := Map(1, "console-connect", 2, "console-disconnect", 3, "remote-connect",
            4, "remote-disconnect", 5, "logon", 6, "logoff", 7, "lock", 8, "unlock")
        this.Log("session " (names.Has(wParam) ? names[wParam] : wParam))
        if (wParam = 7 || wParam = 8) {
            try this.SendKeys(this.Core.ReleaseAll())
            this.Core.Held.Clear()
            for vk in [0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C]
                if this.IsDown(vk)
                    this.Core.Held[vk] := true
        }
    }

    ; Windows silently removes a low-level hook that answers too slowly.
    ; Detect "input is arriving but neither hook is called" and reinstall.
    WatchHooks() {
        if this.Failed
            return
        this.Ticks++
        if (Mod(this.Ticks, 720) = 0)
            this.Log("alive kb=" this.KbCount " mouse=" this.MouseCount " reinstalls=" this.Reinstalls)
        if (!this.KeyboardHook || !this.MouseHook) {
            this.Reinstall("hook missing")
            return
        }
        li := Buffer(8, 0)
        NumPut("UInt", 8, li)
        DllCall("GetLastInputInfo", "Ptr", li)
        t := NumGet(li, 4, "UInt")
        total := this.KbCount + this.MouseCount
        if (this.LastInput && t != this.LastInput && total = this.LastTotal)
            this.Suspect++
        else
            this.Suspect := 0
        this.LastInput := t
        this.LastTotal := total
        ; Two consecutive samples: a hook call may merely be queued behind this timer.
        if (this.Suspect >= 2) {
            this.Suspect := 0
            this.Reinstall("input without hook calls")
        }
    }

    Reinstall(why) {
        this.Reinstalls++
        this.Log("hooks reinstalled #" this.Reinstalls " (" why ")")
        this.Stop()
        try {
            this.Start()
        } catch as e {
            this.Log("reinstall failed: " e.Message " lastError=" A_LastError)
        }
    }

    Start() {
        this.KeyboardCallback := CallbackCreate(ObjBindMethod(this, "Keyboard"), , 3)
        this.MouseCallback := CallbackCreate(ObjBindMethod(this, "Mouse"), , 3)
        module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        this.KeyboardHook := DllCall("SetWindowsHookEx", "Int", 13,
            "Ptr", this.KeyboardCallback, "Ptr", module, "UInt", 0, "Ptr")
        this.MouseHook := DllCall("SetWindowsHookEx", "Int", 14,
            "Ptr", this.MouseCallback, "Ptr", module, "UInt", 0, "Ptr")
        if (!this.KeyboardHook || !this.MouseHook) {
            lastError := A_LastError
            this.Stop()
            throw OSError(lastError, "SetWindowsHookEx")
        }
        this.LastTotal := this.KbCount + this.MouseCount
        this.Suspect := 0
        if !this.Watching {
            this.Watching := true
            this.Log("started pid=" ProcessExist() " ahk=" A_AhkVersion " timeout=" this.Core.Timeout)
            SetTimer(ObjBindMethod(this, "WatchHooks"), 5000)
            try {
                this.SessionGui := Gui()
                DllCall("wtsapi32\WTSRegisterSessionNotification", "Ptr", this.SessionGui.Hwnd, "UInt", 0)
                OnMessage(0x2B1, ObjBindMethod(this, "OnSession"))
            }
        }
    }

    Next(code, msg, p) {
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code,
            "UPtr", msg, "Ptr", p, "Ptr")
    }

    Keyboard(code, msg, p) {
        this.KbCount++
        if (code < 0 || this.Failed)
            return this.Next(code, msg, p)
        llFlags := NumGet(p, 8, "UInt")
        ; Ignore our replay and other software-generated input.
        if (llFlags & 0x10)
            return this.Next(code, msg, p)
        vk := NumGet(p, 0, "UInt")
        sc := NumGet(p, 4, "UInt")
        if (vk = 0x12)
            vk := (llFlags & 1) ? 0xA5 : 0xA4
        flags := (llFlags & 1) | ((llFlags & 0x80) ? 2 : 0)
        try {
            bypass := false
            if ((vk = 0xA4 || vk = 0xA5) && !(flags & 2)) {
                if this.Core.Alt.Has(vk)
                    if (A_TickCount - this.Core.Alt[vk].start > 5000)
                        this.Log("Alt down while its entry is " (A_TickCount - this.Core.Alt[vk].start) "ms old (lost Alt-up?)")
                this.PruneHeld("Alt down")
            }
            if ((vk = 0xA4 || vk = 0xA5) && !(flags & 2) && !this.Core.Alt.Has(vk)) {
                bypass := !!WinActive("ahk_exe mstsc.exe")
                ; Preserve Alt pressed during an existing mouse drag.
                for button in [1, 2, 4, 5, 6]
                    if (DllCall("GetAsyncKeyState", "Int", button, "Short") & 0x8000)
                        bypass := true
            }
            r := this.Core.Key(vk, sc, flags, A_TickCount, bypass)
            if r.keys.Length
                this.SendKeys(r.keys)
            if (r.ime != -1)
                this.SetIME(r.ime)
            if r.block
                return 1
        } catch as e {
            ; Never display a blocking error dialog inside the hook.
            this.Fail(e)
        }
        return this.Next(code, msg, p)
    }

    Mouse(code, msg, p) {
        this.MouseCount++
        if (code < 0 || this.Failed || !this.Core.Alt.Count)
            return this.Next(code, msg, p)
        if (NumGet(p, 12, "UInt") & 1)
            return this.Next(code, msg, p)
        ; Movement alone does not cancel a tap; buttons and wheels do.
        static mouseFlags := Map(0x201, 2, 0x202, 4, 0x204, 8, 0x205, 16,
            0x207, 32, 0x208, 64, 0x20B, 128, 0x20C, 256,
            0x20A, 0x800, 0x20E, 0x1000)
        if !mouseFlags.Has(msg)
            return this.Next(code, msg, p)
        try {
            keys := this.Core.Mouse()
            if keys.Length {
                data := NumGet(p, 8, "UInt") >> 16
                if (msg = 0x20A || msg = 0x20E)
                    data := (data & 0x8000) ? data - 0x10000 : data
                else if (msg != 0x20B && msg != 0x20C)
                    data := 0
                ; Atomically order Alt-down before the triggering click/wheel.
                this.SendKeys(keys, {flags: mouseFlags[msg], data: data})
                return 1
            }
        } catch as e {
            this.Fail(e)
        }
        return this.Next(code, msg, p)
    }

    SendKeys(keys, mouse := 0) {
        count := keys.Length + (IsObject(mouse) ? 1 : 0)
        if !count
            return
        size := A_PtrSize = 8 ? 40 : 28
        offset := A_PtrSize = 8 ? 8 : 4
        packet := Buffer(size * count, 0)
        for i, k in keys {
            base := (i - 1) * size
            NumPut("UInt", 1, packet, base)
            NumPut("UShort", k.vk, "UShort", k.sc, packet, base + offset)
            NumPut("UInt", k.flags, packet, base + offset + 4)
            NumPut("UPtr", this.Tag, packet, base + offset + (A_PtrSize = 8 ? 16 : 12))
        }
        if IsObject(mouse) {
            base := keys.Length * size + offset
            NumPut("Int", mouse.data, "UInt", mouse.flags, packet, base + 8)
            NumPut("UPtr", this.Tag, packet, base + (A_PtrSize = 8 ? 24 : 20))
        }
        sent := DllCall("SendInput", "UInt", count, "Ptr", packet, "Int", size, "UInt")
        if (sent != count)
            throw Error("SendInput failed (sent " sent "/" count ", lastError " A_LastError "); remapping stopped (possible privilege mismatch).")
    }

    SetIME(enabled) {
        ; Same WM_IME_CONTROL mechanism as IMEv2.ahk, with pointer-sized HWNDs
        ; and a bounded timeout. No F24, Alt or toggle shortcut is sent.
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        info := Buffer(8 + 6 * A_PtrSize + 16, 0)
        NumPut("UInt", info.Size, info)
        if DllCall("GetGUIThreadInfo", "UInt", tid, "Ptr", info)
            if (focus := NumGet(info, 8 + A_PtrSize, "Ptr"))
                hwnd := focus
        ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if ime
            DllCall("SendMessageTimeout", "Ptr", ime, "UInt", 0x283,
                "UPtr", 6, "Ptr", enabled, "UInt", 2, "UInt", 50, "Ptr", 0, "Ptr")
    }

    Fail(e := "") {
        if this.Failed
            return
        this.Failed := true
        this.Log("FAILED: " (IsObject(e) ? e.Message : "unknown") " lastError=" A_LastError)
        try this.SendKeys(this.Core.ReleaseAll())
        SetTimer(ObjBindMethod(this, "ReportFailure"), -1)
    }

    ReportFailure() {
        this.Stop()
        TrayTip("入力の送出に失敗したため停止しました。管理者権限のアプリでは同じ権限またはUIAccess版で実行してください。", "Alt IME 停止")
        A_IconTip := "Alt IME — stopped (送出失敗)"
    }

    Stop(*) {
        this.FlushLog()
        if this.KeyboardHook {
            DllCall("UnhookWindowsHookEx", "Ptr", this.KeyboardHook)
            this.KeyboardHook := 0
        }
        if this.MouseHook {
            DllCall("UnhookWindowsHookEx", "Ptr", this.MouseHook)
            this.MouseHook := 0
        }
        try this.SendKeys(this.Core.ReleaseAll())
        if this.KeyboardCallback {
            CallbackFree(this.KeyboardCallback)
            this.KeyboardCallback := 0
        }
        if this.MouseCallback {
            CallbackFree(this.MouseCallback)
            this.MouseCallback := 0
        }
    }
}

