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
    OnExit(ObjBindMethod(app, "Stop"))
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
        for vk in [0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C]
            if (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000)
                this.Core.Held[vk] := true
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
    }

    Next(code, msg, p) {
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", code,
            "UPtr", msg, "Ptr", p, "Ptr")
    }

    Keyboard(code, msg, p) {
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
        } catch {
            ; Never display a blocking error dialog inside the hook.
            this.Fail()
        }
        return this.Next(code, msg, p)
    }

    Mouse(code, msg, p) {
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
        } catch {
            this.Fail()
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
            throw Error("SendInput failed; remapping stopped (possible privilege mismatch).")
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

    Fail() {
        if this.Failed
            return
        this.Failed := true
        try this.SendKeys(this.Core.ReleaseAll())
        SetTimer(ObjBindMethod(this, "ReportFailure"), -1)
    }

    ReportFailure() {
        this.Stop()
        TrayTip("入力の送出に失敗したため停止しました。管理者権限のアプリでは同じ権限またはUIAccess版で実行してください。", "Alt IME 停止")
        A_IconTip := "Alt IME — stopped (送出失敗)"
    }

    Stop(*) {
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

