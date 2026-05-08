#Requires AutoHotkey v2.0
SetTitleMatchMode 2

; ============================================================
; Spot3 Tester v0.5 — Per-application Spotify volume ducking
; ============================================================

; --- Tunables ---
DUCK_VOLUME      := 0.1    ; 0.0–1.0 float; Spotify session level during ads
LOOP_INTERVAL    := 600     ; ms between main loop iterations
MANUAL_TIMEOUT   := 10000   ; ms backoff after detecting manual change
MANUAL_THRESHOLD := 0.02    ; minimum delta to count as manual change (~2%)
SELF_TOLERANCE   := 0.02    ; tolerance for matching expected vs. actual after a script-driven change

; --- COM IIDs ---
IID_AudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
IID_AudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
IID_SimpleAudioVolume    := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

; --- State ---
originalVolume       := -1.0   ; user's baseline; -1 = not yet captured
lastKnownVolume      := -1.0   ; last value observed on Spotify's session
expectedVolume       := -1.0   ; -1 = no script change pending; else value we just commanded
manualChangeDetected := false
manualChangeTime     := 0
spotifyInitialized   := false

; --- GUI ---
Spotgui := Gui()
Spotgui.Caption := "Spot3 Tester v0.5"
Spotgui.Add("Text", "vWindowTitles w400 h115 ReadOnly")
Spotgui.Add("Text", "vAdStatus w400 h13", "Advertisement status:")
Spotgui.Add("Text", "vVolumeStatus w400 h13", "Spotify session: (not yet detected)")
Spotgui.Add("Text", "vWindowCount w400 h13", "Window Count: N/A")
Spotgui.Add("Text", "vLoopStatus w400 h13", "Loop Status: Waiting...")
Spotgui.Add("CheckBox", "vDashMode w400 h20", "Dash mode (ad = Spotify title lacks ' - ')")
Spotgui.OnEvent("Close", (*) => Spotgui.Hide())
Spotgui.Show("w420 h300")

; ============================================================
; Audio session helper
; Enumerates all active audio sessions on the default render device,
; finds the one belonging to a Spotify.exe process, and returns its
; ISimpleAudioVolume interface (auto-released ComValue). Returns 0
; if Spotify isn't running or has no active session.
; ============================================================
GetSpotifySession() {
    global IID_AudioSessionManager2, IID_AudioSessionControl2, IID_SimpleAudioVolume
    try {
        ; CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator
        deviceEnum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
                                "{A95664D2-9614-4F35-A746-DE8DB63617E6}")

        ; IMMDeviceEnumerator::GetDefaultAudioEndpoint(eRender=0, eMultimedia=1) → IMMDevice*
        devPtr := 0
        ComCall(4, deviceEnum, "Int", 0, "Int", 1, "Ptr*", &devPtr)
        if (!devPtr)
            return 0
        device := ComValue(0xD, devPtr)

        ; IMMDevice::Activate(REFIID, dwClsCtx=CLSCTX_ALL=23, NULL, **ppInterface)
        iidBuf := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", IID_AudioSessionManager2, "Ptr", iidBuf)
        smPtr := 0
        ComCall(3, device, "Ptr", iidBuf, "UInt", 23, "Ptr", 0, "Ptr*", &smPtr)
        if (!smPtr)
            return 0
        sessionManager := ComValue(0xD, smPtr)

        ; IAudioSessionManager2::GetSessionEnumerator (vtable 5)
        sePtr := 0
        ComCall(5, sessionManager, "Ptr*", &sePtr)
        if (!sePtr)
            return 0
        sessionEnum := ComValue(0xD, sePtr)

        ; IAudioSessionEnumerator::GetCount (3) / GetSession (4)
        count := 0
        ComCall(3, sessionEnum, "Int*", &count)

        Loop count {
            scPtr := 0
            ComCall(4, sessionEnum, "Int", A_Index - 1, "Ptr*", &scPtr)
            if (!scPtr)
                continue
            sessionControl := ComValue(0xD, scPtr)

            sessionControl2 := ComObjQuery(sessionControl, IID_AudioSessionControl2)
            if (!sessionControl2)
                continue

            ; IAudioSessionControl2::GetProcessId (vtable 14)
            pid := 0
            ComCall(14, sessionControl2, "UInt*", &pid)

            if (pid > 0) {
                try {
                    if (ProcessGetName(pid) = "Spotify.exe") {
                        return ComObjQuery(sessionControl, IID_SimpleAudioVolume)
                    }
                }
            }
        }
    } catch {
        return 0
    }
    return 0
}

; ============================================================
; Main loop
; ============================================================
MainLoop() {
    global originalVolume, lastKnownVolume, expectedVolume
    global manualChangeDetected, manualChangeTime, spotifyInitialized
    global DUCK_VOLUME, LOOP_INTERVAL, MANUAL_TIMEOUT, MANUAL_THRESHOLD, SELF_TOLERANCE

    while true {
        ; --- Window scan & ad detection ---
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

        ; --- GUI: window list + ad status ---
        Spotgui["WindowCount"].Text := "Window Count: " windowList.Length
        Spotgui["WindowTitles"].Text := allTitles
        modeLabel := useDashMode ? "dash mode" : "keyword mode"
        Spotgui["AdStatus"].Text := "Advertisement status: "
            . (adDetected ? "Detected" : "Not detected") " (" modeLabel ")"

        ; --- Spotify session ---
        sav := GetSpotifySession()
        if (!sav) {
            Spotgui["VolumeStatus"].Text := "Spotify session: not active"
            Spotgui["LoopStatus"].Text := "Loop Status: idle (Spotify silent or closed)"
            Sleep(LOOP_INTERVAL)
            continue
        }

        ; Read current Spotify session volume (ISimpleAudioVolume::GetMasterVolume, vtable 4)
        currentVol := 0.0
        try {
            ComCall(4, sav, "Float*", &currentVol)
        } catch {
            Spotgui["LoopStatus"].Text := "Loop Status: read error"
            Sleep(LOOP_INTERVAL)
            continue
        }

        ; First-time initialization: capture user's baseline
        if (!spotifyInitialized) {
            originalVolume := currentVol
            lastKnownVolume := currentVol
            spotifyInitialized := true
        }

        ; --- Manual change detection ---
        ; If a script-commanded change is pending and the value matches, accept silently.
        if (expectedVolume >= 0 && Abs(currentVol - expectedVolume) <= SELF_TOLERANCE) {
            lastKnownVolume := currentVol
            expectedVolume := -1.0
        }
        ; Otherwise, any meaningful delta from lastKnownVolume is a manual user adjustment.
        else if (Abs(currentVol - lastKnownVolume) >= MANUAL_THRESHOLD) {
            manualChangeDetected := true
            manualChangeTime := A_TickCount
            originalVolume := currentVol
            lastKnownVolume := currentVol
        }
        else {
            lastKnownVolume := currentVol
        }

        ; Clear backoff once timeout has elapsed
        if (manualChangeDetected && (A_TickCount - manualChangeTime >= MANUAL_TIMEOUT)) {
            manualChangeDetected := false
        }

        ; --- Adjust Spotify session volume ---
        if (!manualChangeDetected) {
            if (adDetected) {
                if (Abs(currentVol - DUCK_VOLUME) > SELF_TOLERANCE) {
                    expectedVolume := DUCK_VOLUME
                    try ComCall(3, sav, "Float", DUCK_VOLUME, "Ptr", 0)  ; SetMasterVolume
                }
                Spotgui["VolumeStatus"].Text := Format("Spotify session: ducked to {:d}%", Round(DUCK_VOLUME * 100))
            } else {
                if (Abs(currentVol - originalVolume) > SELF_TOLERANCE) {
                    expectedVolume := originalVolume
                    try ComCall(3, sav, "Float", originalVolume, "Ptr", 0)
                }
                Spotgui["VolumeStatus"].Text := Format("Spotify session: restored to {:d}%", Round(originalVolume * 100))
            }
        } else {
            Spotgui["VolumeStatus"].Text := Format("Spotify session: {:d}% (manual override active)", Round(currentVol * 100))
        }

        Spotgui["LoopStatus"].Text := "Loop Status: running"
        Sleep(LOOP_INTERVAL)
    }
}
MainLoop()
