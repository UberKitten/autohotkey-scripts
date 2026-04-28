; Vivaldi PWA startup bug workaround.
; When launching a PWA while Vivaldi itself is still starting up, Vivaldi
; pops a dialog: "Please wait for Vivaldi to close." — but Vivaldi is
; *starting*, not closing. The dialog has a button to force-launch anyway.
; This script waits for that dialog and auto-clicks it so the PWA opens
; without manual intervention.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; checkWindow() {
;     if winexist("Please wait for Vivaldi to close.", , "vivaldi.exe") {
;         controlclick "Button1", "Please wait for Vivaldi to close."
;     }
; }

; settimer checkWindow, 1000

Loop {
	HWND := WinWait("ahk_class #32770 ahk_exe vivaldi.exe", "Please wait for Vivaldi to close.")
    ControlClick "Button1", "ahk_id " HWND
}