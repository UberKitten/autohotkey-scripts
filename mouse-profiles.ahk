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
; ticksPerLevel sets how many wheel ticks it takes to advance one level
; (deliberate ramp-up vs. one tick = liftoff). No max — gotta go fast.
; The level persists for restoreWindowMs after release, so quick re-presses
; pick up where you left off, even if you switch directions.
global scrollBumpLevel := 0
global scrollBumpTicks := 0
global scrollBumpTicksPerLevel := 3
global scrollBumpLastRelease := 0
global scrollBumpRestoreWindowMs := 3000

; Most-recently-pressed scroll button still held — drives which direction
; ScrollTick is sending. Lets the user chord XB1/XB2: press XB1, then
; XB2 (still holding XB1) → switches to up; release XB2 (XB1 still held)
; → falls back to down. Empty string when idle.
global activeScrollButton := ""

; Foreground window snapshot at the start of a fresh hold. Loop bails if
; the focused window changes (alt-tab, click into another app), which is
; both the user's expectation AND the recovery path if AHK's mouse hook
; ever misses a release event.
global scrollInitialHwnd := 0

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

; Side buttons: tap scrolls once, hold scrolls fast. Press-and-up are bound
; separately so chord/swap behavior works (see ScrollPress / ScrollRelease).
$XButton1::ScrollPress("XButton1")
$XButton2::ScrollPress("XButton2")
XButton1 up::ScrollRelease("XButton1")
XButton2 up::ScrollRelease("XButton2")

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

; Press / release / tick design notes:
;   ScrollPress and ScrollRelease are *non-blocking* — they only mutate
;   global state. The actual scrolling is driven by ScrollTick, a SetTimer
;   one-shot that re-schedules itself based on the current bumpLevel. This
;   avoids long-lived hotkey threads (one per active hold) which under
;   heavy chording could exceed AHK's #MaxThreads or get into states where
;   a missed up-event left the loop stuck with no way to recover (AHK's
;   own hook tracks "still pressed", so subsequent presses aren't seen as
;   transitions and don't fire $XButton1::, leaving the user wedged).
;
;   ScrollTick has a defensive IsHeld + WinGetID check on every tick, so
;   it self-terminates if the hook ever loses sync.

ScrollPress(button) {
    global activeScrollButton, scrollBumpLevel, scrollBumpTicks
    global scrollBumpLastRelease, scrollBumpRestoreWindowMs, scrollInitialHwnd

    ; Mid-session swap (other button still held) keeps the level. Only fresh
    ; presses do the restore-window check; outside the window, reset to L0.
    wasIdle := (activeScrollButton = "")
    activeScrollButton := button

    if wasIdle && (A_TickCount - scrollBumpLastRelease) >= scrollBumpRestoreWindowMs {
        scrollBumpLevel := 0
        scrollBumpTicks := 0
    }

    if wasIdle {
        try scrollInitialHwnd := WinGetID("A")
        SetTimer(ScrollTick, -1)  ; one-shot, fires asap
    }
    ; Otherwise the timer is already running — it'll pick up the new
    ; activeScrollButton (and direction) on the next tick.
}

ScrollRelease(button) {
    global activeScrollButton, scrollBumpLastRelease

    ; Only the active button's release matters. If a non-active scroll button
    ; is released (e.g., letting go of XB1 while XB2 is driving), the timer
    ; keeps running on the active. Otherwise, fall back to the other if it's
    ; still held; if neither is held, go idle.
    if activeScrollButton != button
        return

    otherButton := (button = "XButton1") ? "XButton2" : "XButton1"
    if IsHeld(otherButton) {
        activeScrollButton := otherButton
    } else {
        activeScrollButton := ""
        scrollBumpLastRelease := A_TickCount
        ; Don't bother stopping the timer — ScrollTick sees active="" and
        ; returns without rescheduling.
    }
}

ScrollTick() {
    ; Two modes — pick one in source, save+rerun.
    ;   "smooth": L0..L2 halve interval (60→30→15ms) at chunk 1; L3+ stays
    ;             at the 15ms Sleep floor and doubles chunk (2, 4, 8, ...).
    ;             Unbounded — Astra wants to go fast.
    ;   "step":   2 notches per 150ms (~13/sec), chunk doubles per level.
    ;
    ; Fractional-delta smooth scrolling (mouse_event with delta < 120) was
    ; tried; works in Chromium-family apps but Windows Terminal, Firefox,
    ; and Notepad++ silently drop sub-notch events. Whole notches it is.
    static mode := "smooth"

    global activeScrollButton, scrollBumpLevel, scrollInitialHwnd
    global scrollBumpLastRelease

    if activeScrollButton = ""
        return  ; idle: don't reschedule

    ; try/catch: AHK can throw during secure-desktop / lockscreen, when
    ; input or window queries are blocked. Bail cleanly.
    try {
        ; Defensive: window changed (alt-tab) OR hook drifted (button no
        ; longer physically held but ScrollRelease never fired).
        if !IsHeld(activeScrollButton) || WinGetID("A") != scrollInitialHwnd {
            activeScrollButton := ""
            scrollBumpLastRelease := A_TickCount
            return
        }

        if mode = "smooth" {
            if scrollBumpLevel < 3 {
                intervalMs := 60 // (2 ** scrollBumpLevel)
                chunkSize := 1
            } else {
                intervalMs := 15
                chunkSize := 2 ** (scrollBumpLevel - 2)
            }
        } else {
            intervalMs := 150
            chunkSize := 2 * (2 ** scrollBumpLevel)
        }

        direction := (activeScrollButton = "XButton1") ? "WheelDown" : "WheelUp"
        Send("{" direction " " chunkSize "}")
        SetTimer(ScrollTick, -intervalMs)
    } catch {
        activeScrollButton := ""
        scrollBumpLastRelease := A_TickCount
    }
}

ScrollBumpOrPassthrough(heldButton, wheelKey) {
    global scrollBumpLevel, scrollBumpTicks, scrollBumpTicksPerLevel
    if IsHeld(heldButton) {
        scrollBumpTicks++
        if scrollBumpTicks >= scrollBumpTicksPerLevel {
            scrollBumpLevel++
            scrollBumpTicks := 0
        }
        return
    }
    Send("{" wheelKey "}")
}
