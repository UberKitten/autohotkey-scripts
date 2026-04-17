; Jump Desktop + Bitwarden autofill.
; When Jump Desktop's "Mac Credentials" password prompt appears, this
; looks the entry up in Bitwarden and types the password into the dialog.
;
; Security design — ephemeral, session-only:
;   - Uses the Bitwarden CLI (`bw`); requires prior `bw login`.
;   - Master password is piped via stdin — never placed on a command line,
;     never written to disk.
;   - Session key lives in memory only; vault is locked on script exit
;     and via the tray menu's "Lock Vault" option.
;   - Password is sent via SendInput then its variable is cleared.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetTitleMatchMode 2

; --- State ---
bwSessionKey := ""
handledWindows := Map()

; --- Tray menu ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Lock Vault", LockVault)
A_TrayMenu.Add("Exit", ExitScript)
TraySetIcon("shell32.dll", 48)

; --- Start polling ---
SetTimer(CheckForCredPrompt, 500)

CheckForCredPrompt() {
    global bwSessionKey, handledWindows

    ; Find the credential popup
    hwnd := WinExist("Mac Credentials ahk_exe JumpClient.exe")
    if !hwnd
        return

    ; Skip if already handled
    if handledWindows.Has(hwnd)
        return

    ; Mark as handled
    handledWindows[hwnd] := true

    ; Qt gives us no WinGetText, so get user@host from sibling window title
    ; The parent/connection window has title like "astra@nyan" or "nyan@nyan"
    credential := ""
    wins := WinGetList("ahk_exe JumpClient.exe")
    for w in wins {
        t := WinGetTitle(w)
        ; Match "user@host" pattern but skip "Mac Credentials" and "Jump Desktop"
        if (t != "" && t != "Mac Credentials" && t != "Jump Desktop" && InStr(t, "@"))  {
            credential := t
            break
        }
    }

    if (credential = "") {
        handledWindows.Delete(hwnd)
        return
    }

    parts := StrSplit(credential, "@")
    username := parts[1]
    hostname := parts[2]

    ; Unlock BW vault if needed (retry up to 3 attempts)
    if (bwSessionKey = "") {
        attempts := 0
        while (bwSessionKey = "" && attempts < 3) {
            attempts++
            if !UnlockVault() {
                if (attempts >= 3) {
                    MsgBox("Failed to unlock vault after 3 attempts.", "JD-BW AutoFill", "Icon!")
                    handledWindows.Delete(hwnd)
                    return
                }
                result := MsgBox("Wrong password. Try again? (" (3 - attempts) " attempts left)", "JD-BW AutoFill", "YesNo Icon!")
                if (result = "No") {
                    handledWindows.Delete(hwnd)
                    return
                }
            }
        }
    }

    ; Fetch password from Bitwarden
    password := GetBWPassword(hostname, username)
    if (password = "") {
        MsgBox("No Bitwarden entry found for: " credential, "JD-BW AutoFill", "Icon!")
        handledWindows.Delete(hwnd)
        return
    }

    ; Fill password into the Qt credential dialog
    FillCredentials(hwnd, password)
    password := ""
}

UnlockVault() {
    global bwSessionKey

    ; Check if logged in
    statusResult := RunBWCommand("status")
    if InStr(statusResult, '"status":"unauthenticated"') {
        MsgBox("Bitwarden CLI is not logged in.`nRun 'bw login' in a terminal first.", "JD-BW AutoFill", "Icon!")
        return false
    }

    ; Prompt for master password
    ib := InputBox("Enter Bitwarden master password:", "JD-BW AutoFill", "Password w300 h130")
    if (ib.Result != "OK" || ib.Value = "")
        return false

    masterPass := ib.Value

    ; Unlock via stdin pipe — password never on command line
    sessionKey := ""
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('bw unlock --raw')
        exec.StdIn.Write(masterPass)
        exec.StdIn.Close()

        startTime := A_TickCount
        while !exec.Status {
            if (A_TickCount - startTime > 30000) {
                masterPass := ""
                MsgBox("Bitwarden unlock timed out.", "JD-BW AutoFill", "Icon!")
                return false
            }
            Sleep(100)
        }

        sessionKey := exec.StdOut.ReadAll()
        errOutput := exec.StdErr.ReadAll()
    }

    masterPass := ""  ; clear immediately

    if (sessionKey = "" || InStr(sessionKey, "Invalid") || InStr(sessionKey, "error")) {
        MsgBox("Failed to unlock Bitwarden vault.`nCheck your master password.", "JD-BW AutoFill", "Icon!")
        return false
    }

    sessionKey := Trim(sessionKey, " `t`r`n")
    bwSessionKey := sessionKey
    sessionKey := ""

    TrayTip("Vault unlocked", "JD-BW AutoFill")
    return true
}

GetBWPassword(hostname, username) {
    global bwSessionKey

    credential := username "@" hostname  ; e.g. "nyan@nyan"

    ; Search by full credential string (matches entry name "nyan@nyan")
    jsonResult := RunBWCommand('list items --search "' credential '" --session ' bwSessionKey)
    if (jsonResult != "" && jsonResult != "[]") {
        password := ParseBWItems(jsonResult, credential)
        jsonResult := ""
        if (password != "")
            return password
    }

    ; Fall back: search by hostname only
    jsonResult := RunBWCommand('list items --search "' hostname '" --session ' bwSessionKey)
    if (jsonResult = "" || jsonResult = "[]")
        return ""

    password := ParseBWItems(jsonResult, credential)
    jsonResult := ""
    return password
}

ParseBWItems(json, credential) {
    ; Find login items (type:1) matching the credential as name or username
    ; Walk through each item object looking for:
    ;   "type":1 (login item, not SSH key etc.)
    ;   "name":"credential" or "username":"credential"
    ;   then grab "password":"..."

    pos := 1
    while (pos := InStr(json, '"type":1', , pos)) {
        ; Find the boundaries of this item (look for next item or end)
        itemStart := Max(1, pos - 500)
        nextItem := InStr(json, '"type":', , pos + 8)
        itemEnd := nextItem ? nextItem : StrLen(json)
        chunk := SubStr(json, itemStart, itemEnd - itemStart)

        ; Check if name or username matches
        hasName := InStr(chunk, '"name":"' credential '"')
        hasUser := InStr(chunk, '"username":"' credential '"')

        if (hasName || hasUser) {
            if RegExMatch(chunk, '"password":"(.*?)"', &pm)
                return pm[1]
        }
        pos += 8
    }
    return ""
}

RunBWCommand(args) {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec("bw " args)

        startTime := A_TickCount
        while !exec.Status {
            if (A_TickCount - startTime > 15000)
                return ""
            Sleep(100)
        }

        return exec.StdOut.ReadAll()
    } catch {
        return ""
    }
}

FillCredentials(hwnd, password) {
    ; Qt exposes no controls to AHK, so we use keyboard navigation:
    ; 1. Activate the credential window
    ; 2. Tab to the password field (username is first, password is second)
    ; 3. Type the password via SendInput
    ; 4. Press Enter to submit (clicks OK)

    WinActivate(hwnd)
    WinWaitActive(hwnd, , 2)
    Sleep(200)

    ; Password field is already focused by default
    ; Type the password (raw mode to handle special chars)
    SendInput("{Raw}" password)
    Sleep(100)

    ; Press Enter to click OK
    SendInput("{Enter}")
}

LockVault(*) {
    global bwSessionKey
    if (bwSessionKey != "") {
        RunBWCommand("lock")
        bwSessionKey := ""
        TrayTip("Vault locked", "JD-BW AutoFill")
    }
}

ExitScript(*) {
    global bwSessionKey
    if (bwSessionKey != "") {
        RunBWCommand("lock")
        bwSessionKey := ""
    }
    ExitApp()
}

; Clean up handled windows that no longer exist
SetTimer(CleanupHandled, 5000)
CleanupHandled() {
    global handledWindows
    for hwnd, _ in handledWindows {
        if !WinExist(hwnd)
            handledWindows.Delete(hwnd)
    }
}
