; NumLock Guard: keeps NumLock on by default, but gracefully lets you turn
; it off for a bit. If you disable NumLock, you get 30 minutes of idle
; numpad time before it's automatically re-enabled. Any numpad keypress
; resets that idle timer, so you can use arrow-keys-on-numpad as long as
; you want — NumLock only comes back when you stop using the numpad.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Ensure NumLock is on at startup
if !GetKeyState("NumLock", "T")
    SetNumLockState("On")

global numpadLastPress := A_TickCount

; Poll NumLock state every second
SetTimer(CheckNumLock, 1000)

CheckNumLock() {
    static wasOn := true
    isOn := GetKeyState("NumLock", "T")

    if wasOn && !isOn {
        ; NumLock just turned off — start the 30m re-enable countdown
        global numpadLastPress := A_TickCount
        SetTimer(ReEnableNumLock, 1000)
    } else if !wasOn && isOn {
        ; Back on (manually or by us) — stop monitoring
        SetTimer(ReEnableNumLock, 0)
    }

    wasOn := isOn
}

ReEnableNumLock() {
    if GetKeyState("NumLock", "T") {
        SetTimer(ReEnableNumLock, 0)
        return
    }
    if (A_TickCount - numpadLastPress) >= 1800000 {
        SetNumLockState("On")
        SetTimer(ReEnableNumLock, 0)
    }
}

; Any numpad key resets the idle timer (~ passes the key through normally)
ResetNumpadTimer(ThisHotkey) {
    global numpadLastPress := A_TickCount
}

for key in [
    "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
    "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
    "NumpadDot", "NumpadDiv", "NumpadMult", "NumpadAdd",
    "NumpadSub", "NumpadEnter", "NumpadDel", "NumpadIns",
    "NumpadClear", "NumpadUp", "NumpadDown", "NumpadLeft",
    "NumpadRight", "NumpadHome", "NumpadEnd", "NumpadPgUp", "NumpadPgDn"
]
    Hotkey("~" key, ResetNumpadTimer)
