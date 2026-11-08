#Requires AutoHotkey v2.0
#Include ../../alt-ime-ahk-v2f-menusafe.ahk

app := DeferredAltApp(1000)
app.LogFile := A_Args[1]
app.RegisterDiagnostics()
app.KbCount := 17
app.MouseCount := 23
app.Core.Held.Clear()
app.Core.Key(0xA4, 0x38, 0, A_TickCount, false)
app.Core.Held[0xA2] := true
app.Log("buffered before exit")
switch A_Args[2] {
    case "exit":
        ExitApp(7)
    case "error":
        ; Keep the child alive long enough to exercise the real OnError path,
        ; then exit without a dialog (/ErrorStdOut is supplied by the parent).
        SetTimer(() => ExitApp(9), -150)
        throw Error("exit logging test failure")
    case "wait":
        app.Log("ready for replacement")
        app.FlushLog()
        SetTimer(() => ExitApp(11), -5000)
}
