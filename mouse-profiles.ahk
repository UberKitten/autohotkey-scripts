; Mouse profiles: replaces Razer Synapse for the Basilisk Ultimate.
; One script, many profiles — the active profile switches based on the
; foreground window (e.g. Deep Rock Galactic gets its own remaps) so the
; profiles never fight each other.
;
; Expects the mouse's on-board/hardware Synapse profile to be at factory
; defaults: side buttons send XButton1/XButton2, tilt wheel sends
; WheelLeft/WheelRight, DPI up/down + sensitivity clutch stay in firmware.
; This script only remaps in software — uninstalling Synapse is fine.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Wheel-bump intercept ($WheelDown/$WheelUp) fires once per detent — a fast
; wheel spin can trip AHK's default flood guard. Bump the ceiling.
A_MaxHotkeysPerInterval := 500
A_HotkeyInterval := 1000

global currentProfile := "desktop"

; Scroll-bump level — bumped by wheel ticks while a scroll button is held.
; Each level doubles chunkSize. ticksPerLevel sets how many wheel ticks it
; takes to advance one level (deliberate ramp-up vs. one tick = liftoff).
global scrollBumpLevel := 0
global scrollBumpMax := 3
global scrollBumpTicks := 0
global scrollBumpTicksPerLevel := 3

; Re-evaluate the active profile periodically. 500ms is fast enough that
; alt-tabbing into a game picks up the new remaps before the first click.
SetTimer(UpdateProfile, 500)
UpdateProfile()

UpdateProfile() {
    global currentProfile
    exe := ""
    try exe := WinGetProcessName("A")
    newProfile := ProfileForExe(exe)
    if newProfile != currentProfile {
        currentProfile := newProfile
        A_IconTip := "Mouse profile: " newProfile " (" exe ")"
    }
}

ProfileForExe(exe) {
    switch exe {
        case "FSD-Win64-Shipping.exe":  ; Deep Rock Galactic
            return "drg"
    }
    return "desktop"
}

; ── desktop profile ────────────────────────────────────────────────

#HotIf currentProfile = "desktop"

; Side buttons: tap scrolls once, hold scrolls fast.
$XButton1::HoldToScroll("XButton1", "WheelDown")
$XButton2::HoldToScroll("XButton2", "WheelUp")

; While a scroll button is held, ticking the wheel in the SAME direction
; bumps the speed level (RSI-friendly turbo). Opposite direction falls
; through to normal scroll behavior — no special handling.
$WheelDown::ScrollBumpOrPassthrough("XButton1", "WheelDown")
$WheelUp::ScrollBumpOrPassthrough("XButton2", "WheelUp")

; Tilt wheel → forward/back. Set tilt L/R to F20/F21 in the Synapse
; hardware profile; F20–F24 are unused function keys so nothing else
; clobbers them. We remap to XButton1/2 here since many apps only
; honor mouse buttons, not horizontal scroll.
F20::Send("{XButton1}")
F21::Send("{XButton2}")

#HotIf

; ── deep rock galactic profile ─────────────────────────────────────

#HotIf currentProfile = "drg"

; Hold XB1: bunny-hop turbo (~33 jumps/sec ≈ 66 up/down events/sec).
$XButton1::TurboKey("XButton1", "Space", 30)

; XB2: hypershift modifier. Has no standalone action — only enables the
; turbo-fire overlays below. While XB2 is held, LMB/RMB auto-fire ~33/sec.
XButton2 & LButton::TurboKey("LButton", "LButton", 30, "XButton2")
XButton2 & RButton::TurboKey("RButton", "RButton", 30, "XButton2")

; Hold MButton: DRG fast-deposit animation cancel. Custom keybinds:
; R = deposit, LCtrl = pickaxe (cancel). Timings (60/20/20ms) come from
; Measurity's AHK DRG script — more forgiving than tighter loops.
MButton::DepositLoop()

; Hypershift + MButton: driller rapid axe throw. Cancel animation with
; LCtrl (laser pointer), then throw (B = grenade/axe keybind). Only works
; when the axe throw has committed, so keep the post-throw gap generous.
XButton2 & MButton::AxeThrowLoop()

; Hypershift + XB1: spam E (~33/sec). No animation cancel — raw key spam.
XButton2 & XButton1::TurboKey("XButton1", "e", 30, "XButton2")

#HotIf

; ── helpers ────────────────────────────────────────────────────────

TurboKey(trigger, sendKey, cycleMs, alsoRequire := "") {
    try {
        while IsHeld(trigger) && (alsoRequire = "" || IsHeld(alsoRequire)) {
            Send("{" sendKey "}")
            Sleep(cycleMs)
        }
    } catch {
        ; See HoldToScroll's catch — same secure-desktop/lockscreen hardening.
    }
}

IsHeld(button) {
    ; Tried GetAsyncKeyState here for resilience against alt-tab-to-elevated
    ; missing the release event — but $-prefix hotkeys suppress the press
    ; from the OS, so GetAsyncKeyState returns 0 even when the button is
    ; held. Fell back to GetKeyState; HoldToScroll adds a foreground-window
    ; change check as a separate alt-tab safety.
    return GetKeyState(button, "P")
}

DepositLoop() {
    try {
        while IsHeld("MButton") {
            Send("{r down}")
            Sleep(60)
            Send("{r up}")
            Send("{LCtrl down}")
            Sleep(20)
            Send("{LCtrl up}")
            Sleep(20)
        }
    } catch {
        ; See HoldToScroll's catch.
    }
}

AxeThrowLoop() {
    try {
        while IsHeld("MButton") && IsHeld("XButton2") {
            Send("{b}")      ; throw
            Sleep(150)       ; let the throw commit
            Send("{LCtrl}")  ; cancel the recovery animation
            Sleep(200)
        }
    } catch {
        ; See HoldToScroll's catch.
    }
}

HoldToScroll(button, direction) {
    ; Two modes — pick one in source, save+rerun. #SingleInstance Force
    ; means re-launching the .ahk just hot-swaps the running copy.
    ;   "smooth": per-level table below. Tight cadence with chunk=1 at low
    ;             levels feels much smoother than chunky bursts at chunk>1.
    ;             At L3 we hit Sleep's ~15ms floor, so chunk doubles instead.
    ;   "step":   2 notches per 150ms (~13/sec) — page-style chunks.
    ;
    ; Fractional-delta smooth scrolling (mouse_event with delta < 120) was
    ; tried; works in Chromium-family apps but Windows Terminal, Firefox, and
    ; Notepad++ silently drop sub-notch events. Whole notches it is.
    static mode := "smooth"
    ; smooth-mode level table: L0..L3 → [intervalMs, chunkSize]
    static smoothIntervals := [60, 30, 15, 15]
    static smoothChunks    := [ 1,  1,  1,  2]

    global scrollBumpLevel, scrollBumpTicks
    scrollBumpLevel := 0
    scrollBumpTicks := 0

    ; Wrapped in try/catch: AHK can throw during secure-desktop transitions
    ; (UAC consent prompt), lock screen, or other states where input/window
    ; queries are blocked. Without this, an error dialog pops up minutes
    ; later when the user is no longer holding anything. Better to bail.
    try {
        ; Snapshot the foreground window — if it changes mid-loop (alt-tab,
        ; etc.), exit. Also catches the case where AHK's hook missed the
        ; release event during a focus change to an elevated window.
        initialHwnd := WinGetID("A")

        if mode = "smooth" {
            while IsHeld(button) && WinGetID("A") = initialHwnd {
                idx := scrollBumpLevel + 1
                Send("{" direction " " smoothChunks[idx] "}")
                Sleep(smoothIntervals[idx])
            }
        } else {
            while IsHeld(button) && WinGetID("A") = initialHwnd {
                Send("{" direction " " (2 * (2 ** scrollBumpLevel)) "}")
                Sleep(150)
            }
        }
    } catch {
    }

    scrollBumpLevel := 0
    scrollBumpTicks := 0
}

ScrollBumpOrPassthrough(heldButton, wheelKey) {
    global scrollBumpLevel, scrollBumpMax, scrollBumpTicks, scrollBumpTicksPerLevel
    if IsHeld(heldButton) {
        if scrollBumpLevel < scrollBumpMax {
            scrollBumpTicks++
            if scrollBumpTicks >= scrollBumpTicksPerLevel {
                scrollBumpLevel++
                scrollBumpTicks := 0
            }
        }
        return
    }
    Send("{" wheelKey "}")
}
