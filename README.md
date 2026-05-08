

 # SpotV — Spotify Ad Volume Ducker

An AutoHotkey v2 script that automatically lowers system volume during Spotify advertisements and restores it when music resumes.

## Why this exists

Spotify's free-tier advertising includes a category of ads — ASMR spots, hyper-compressed promos, and similar — that are mastered louder than the music they interrupt. I believe this isn't supposed to be legal, but who's going to sue them over it? The bigger problem isn't even the volume, but the overcompression that makes the ad feel louder than it really is. For listeners with sensory sensitivities, this isn't just annoying; it's the kind of jolt that makes you tear your headphones off. This script is a small accommodation aimed at that problem: it watches for ad indicators and ducks the volume to a tolerable level until the ad ends, then puts things back where you had them.

If you're neurodivergent, have auditory processing differences, or just don't want sudden loudness shoved into your ears, this is for you.

In short, I developed this to deal with ASMR ads that would quite literally make me rip my headphones off in anger because of their volume and overcompression.

## What it does

The script runs a small status window and a background loop that:

- Enumerates open windows roughly twice a second.
- Decides whether an advertisement is currently playing using one of two detection modes (toggleable via checkbox).
- If an ad is detected, sets system volume to **15**. (This is alterable, but only by editing the script itself)
- If no ad is detected, restores volume to whatever the user had it at before.
- Watches for manual volume changes and backs off for 10 seconds when it sees one, so it doesn't fight the user over the volume slider. (Notably, if you change the volume too fast, it won't register-- but this might be improved in future fine tuning).

## Detection modes

**Keyword mode (default)** — flags an ad when any open window title contains `"Advertisement"` or `"__"` (double/triple underscore). These are markers Spotify itself has used to label ad windows at various times in the past.

**Dash mode** — flags an ad when the Spotify window's title does *not* contain `" - "` (space-dash-space). The reasoning: actual songs are titled `Artist - Track`, so a Spotify window without a dash is almost certainly playing something that isn't a song. This mode is more resilient to Spotify changing its ad labels but has a known quirk (see below).

Toggle between them at runtime with the **"Dash mode"** checkbox in the GUI.

## The status window

Shows, top to bottom:

- All current window titles (concatenated, for debugging what the script sees).
- Advertisement status, with the active detection mode in parentheses.
- Volume status (current ducking state).
- Window count.
- Loop status.
- The dash-mode toggle.

## Manual override

If you change the system volume by more than 5 points, the script treats that as a manual override and stops adjusting volume for 10 seconds. After 10 seconds it resumes normal behavior, using your new volume as the new "restore to" target.

## Known quirks

- **Paused Spotify in dash mode.** When Spotify is paused, its window title is usually just `"Spotify"` or `"Spotify Free"` — no dash present. Dash mode will read that as an ad and duck the volume. Harmless (nothing's playing) but it'll show "Detected" in the status box.
- **Other windows with dashes.** Dash mode specifically inspects the Spotify process window, not all windows, so unrelated windows (`file.py - VSCode`, browser tabs, etc.) don't interfere.
- **Detection lag.** The loop runs every ~600 ms, so there can be a fraction of a second between an ad starting and the volume dropping. I tested this at various amounts, and found that this seems to work well.
- **Resetting the volume.** This is buggy. I've had it work well, but it sometimes it has broken in the past.
- **Spotify changing how it displays information and what it displays in the window title will break this.**

## Requirements

- Windows.
- AutoHotkey v2.0 or later.
- Spotify desktop app (the script keys off window titles, not the web player).

## Running it
Save the script as `_INSERT_FILENAME_HERE.ahk`, double-click to launch. The status window appears immediately and the detection loop starts. Closing the window hides it rather than exiting; right-click the AutoHotkey tray icon to fully quit.

## Tuning

A few values near the top of the script are worth knowing about:

- `SoundSetVolume(15)` — the ducked volume level. Lower it if 15 is still too loud during ads, raise it if you want ads audible but quiet.
- `volumeCheckInterval := 300` — how often (ms) the script polls for manual volume changes.
- `Sleep(600)` — main loop interval. Shorter = faster ad volume reduction response, but more CPU usage.
- `Abs(newVolume - currentVolume) > 5` — sensitivity for detecting a manual change.
- `A_TickCount - manualChangeTime >= 10000` — how long (ms) to back off after a manual change.
