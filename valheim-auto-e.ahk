; Valheim auto-E: hold E to repeatedly press E.
; Reduces RSI from the constant E-mashing the game needs for collecting,
; mining, chopping, etc. Tap E normally for a single press; hold it and
; it auto-repeats until you let go. Only active while Valheim is focused.

#Requires AutoHotkey v2.0
#SingleInstance Force

#HotIf WinActive("Valheim")
$e:: {
    ; If E is still held 100ms later, they're holding — spam E until release.
    ; Otherwise they tapped it — send a single E.
    if KeyWait("e", "T0.1") {
        while GetKeyState("e", "P") {
            Send("e")
            Sleep(1)
        }
    } else {
        Send("e")
    }
}
#HotIf
