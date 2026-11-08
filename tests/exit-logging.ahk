#Requires AutoHotkey v2.0

Checks := 0
Children := []
tempDir := A_Temp "\alt-ime-exit-test-" ProcessExist() "-" A_TickCount
DirCreate(tempDir)
try {
    logPath := tempDir "\exit.log"
    code := RunWait(Command(logPath, "exit"), , "Hide")
    text := FileRead(logPath, "UTF-8")
    Assert(code = 7, "exit code is preserved")
    Assert(InStr(text, "buffered before exit"), "pending log is flushed before exit")
    Assert(InStr(text, "reason=Exit code=7"), "real OnExit reason/code are logged")
    Assert(InStr(text, "pid=") && InStr(text, "uptimeMs="), "process and uptime are logged")
    Assert(InStr(text, "keyboardHook=0 mouseHook=0 kb=17 mouse=23"), "hook state and counters are logged")
    Assert(InStr(text, "altCount=1 heldCount=1"), "state is captured before cleanup")

    logPath := tempDir "\error.log"
    code := RunWait(Command(logPath, "error"), , "Hide")
    text := FileRead(logPath, "UTF-8")
    Assert(code = 9, "error callback leaves later execution unchanged")
    Assert(InStr(text, "unhandled error pid=") && InStr(text, "mode=Exit"), "real OnError callback is logged")
    Assert(InStr(text, "exit logging test failure") && InStr(text, "file=")
        && InStr(text, "line=") && InStr(text, "stack="), "error details include source and stack")
    Assert(InStr(text, "reason=Exit code=9"), "error child also flushes its exit record")

    logPath := tempDir "\single.log"
    Run(Command(logPath, "wait"), , "Hide", &childPid)
    Children.Push(childPid)
    deadline := A_TickCount + 3000
    while (!FileExist(logPath) || !InStr(FileRead(logPath, "UTF-8"), "ready for replacement")) {
        if A_TickCount > deadline
            throw Error("replacement child did not start")
        Sleep(20)
    }
    code := RunWait(Command(logPath, "exit"), , "Hide")
    ProcessWaitClose(childPid, 3)
    text := FileRead(logPath, "UTF-8")
    Assert(!ProcessExist(childPid), "old instance exits on replacement")
    Assert(InStr(text, "reason=Single"), "single-instance replacement reason is recorded")
    Assert(code = 7 && InStr(text, "reason=Exit code=7"), "replacement logs its own exit")
    FileAppend("PASS: " Checks " assertions (exit logging child processes)`n", "*")
} catch as e {
    FileAppend("FAIL: " e.Message " at " e.File ":" e.Line "`n", "**")
    ExitApp(1)
} finally {
    for childPid in Children
        if ProcessExist(childPid)
            ProcessClose(childPid)
    for name in ["exit.log", "error.log", "single.log"]
        if FileExist(tempDir "\" name)
            FileDelete(tempDir "\" name)
    DirDelete(tempDir)
}

Command(logPath, mode) {
    return '"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\fixtures\exit-child.ahk" "' logPath '" ' mode
}

Assert(ok, description) {
    global Checks
    Checks++
    if !ok
        throw Error(description)
}
