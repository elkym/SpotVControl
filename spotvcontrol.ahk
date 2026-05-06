#Requires AutoHotkey v2.0
SetTitleMatchMode 2  ; "contains" mode

Spotgui := Gui()
Spotgui.Caption := "Spot3 Tester"
Spotgui.Add("Text", "vWindowTitles w400 h115 ReadOnly")
Spotgui.Add("Text", "vAdStatus w400 h13", "Advertisement status:")
Spotgui.Add("Text", "vVolumeStatus w400 h13", "Volume status:")
Spotgui.Add("Text", "vWindowCount w400 h13", "Window Count: N/A")
Spotgui.Add("Text", "vLoopStatus w400 h13", "Loop Status: Waiting...")
Spotgui.Add("CheckBox", "vDashMode w400 h20", "Dash mode (ad = Spotify title lacks ' - ')")
Spotgui.OnEvent("Close", (*) => Spotgui.Hide())
Spotgui.Show("w420 h300")

; Initialize Variables
originalVolume := SoundGetVolume()
currentVolume := originalVolume
expectedVolume := -1                ; -1 = no script-commanded change pending
volumeCheckInterval := 300
manualChangeDetected := false
manualChangeTime := A_TickCount
DUCK_VOLUME := 15

CheckVolumeChange() {
    global currentVolume, manualChangeDetected, manualChangeTime, originalVolume, expectedVolume
    newVolume := SoundGetVolume() + 0

    ; If the script just commanded a change and the system now reflects it,
    ; accept it silently — don't treat it as a manual user adjustment.
    if (expectedVolume != -1 && Abs(newVolume - expectedVolume) <= 1) {
        currentVolume := newVolume
        expectedVolume := -1
        return
    }

    ; Otherwise, large jumps are real manual changes.
    if (Abs(newVolume - currentVolume) > 5) {
        manualChangeDetected := true
        manualChangeTime := A_TickCount
        originalVolume := newVolume
    }
    currentVolume := newVolume

    if (manualChangeDetected && (A_TickCount - manualChangeTime >= 10000)) {
        manualChangeDetected := false
    }
}

SetTimer(CheckVolumeChange, volumeCheckInterval)

MainLoop() {
    global manualChangeDetected, originalVolume, currentVolume, expectedVolume, DUCK_VOLUME
    while true {
        windowList := WinGetList()
        allTitles := ""
        adDetected := false
        useDashMode := Spotgui["DashMode"].Value
        spotifyTitle := ""
        spotifyFound := false

        for id in windowList {
            title := WinGetTitle(id)
            allTitles .= title " "

            try {
                if (WinGetProcessName(id) = "Spotify.exe") {
                    spotifyTitle := title
                    spotifyFound := true
                }
            }

            if (!useDashMode && (InStr(title, "Advertisement") || InStr(title, "__"))) {
                adDetected := true
            }
        }

        if (useDashMode && spotifyFound && !InStr(spotifyTitle, " - ")) {
            adDetected := true
        }

        Spotgui["WindowCount"].Text := "Window Count: " windowList.Length
        Spotgui["WindowTitles"].Text := allTitles

        modeLabel := useDashMode ? "dash mode" : "keyword mode"
        Spotgui["AdStatus"].Text := "Advertisement status: "
            . (adDetected ? "Detected" : "Not detected") " (" modeLabel ")"

        ; Adjust volume only if no manual change is detected.
        ; Only call SoundSetVolume when the desired state actually differs
        ; from the current state — and announce what we're about to do via
        ; expectedVolume so CheckVolumeChange doesn't misread it as manual.
        if (!manualChangeDetected) {
            if adDetected {
                if (currentVolume != DUCK_VOLUME) {
                    expectedVolume := DUCK_VOLUME
                    SoundSetVolume(DUCK_VOLUME)
                }
                Spotgui["VolumeStatus"].Text := "Volume status: Reduced to " DUCK_VOLUME
            } else {
                if (Abs(currentVolume - originalVolume) > 1) {
                    expectedVolume := originalVolume
                    SoundSetVolume(originalVolume)
                }
                Spotgui["VolumeStatus"].Text := "Volume status: Restored to " originalVolume
            }
        }
        Sleep(600)
    }
}
MainLoop()
