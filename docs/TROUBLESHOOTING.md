---
title: Troubleshooting
description: Symptoms, their usual causes, and how to fix them.
document_type: reference
audience: users
applies_to: BATCRelayBot 1.5.0
updated: 2026-09-09
---

# Troubleshooting

## Where to look first

| Log | Path |
|---|---|
| Installation | `%LOCALAPPDATA%\BATCRelayBot\install.log` |
| Bot output | `%LOCALAPPDATA%\BATCRelayBot\logs\bot_output.log` |
| Bot errors | `%LOCALAPPDATA%\BATCRelayBot\logs\bot_error.log` |
| Uninstall | `%APPDATA%\BATCRelayBot-Uninstall\` |

`install.log` records every step from the first one, so a failed setup always
leaves a trace even if the window closed.

## Setup

**"file cannot be loaded... not digitally signed"**
PowerShell's execution policy is blocking the module. For the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Permanently, for your account: `-Scope CurrentUser -ExecutionPolicy RemoteSigned`.

**The device list has no VoiceMeeter entries**
VoiceMeeter is not running. Its virtual buses only exist while it is. Start it
and run `Install-BATCRelayBot` again.

**VoiceMeeter is installed but its devices never appear**
VoiceMeeter needs a reboot after installation before Windows exposes the
virtual audio devices.

**Setup says Python or FFmpeg is missing although you installed it**
Setup verifies a candidate by running it, so a Microsoft Store stub or a
broken install is rejected on purpose. `install.log` names the reason. A
Python older than 3.10 is reported with the version that was found.

## Running

**Bot connects but the channel is silent**
Work outwards from the source:

1. Is the app sending audio to **Voicemeeter Input**? Watch the Virtual Input
   meter in VoiceMeeter while audio plays.
2. Is **B1** enabled on that strip, and **Solo** off?
3. Does ffmpeg hear it? Record eight seconds directly and play the result:

   ```powershell
   ffmpeg -f dshow -i audio="Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)" -t 8 test.wav
   ```

   If `test.wav` is silent the problem is the routing, not the bot.
4. Is `audio_device_name` a **B** bus? An A bus feeds your speakers and
   carries nothing for the bot to capture.

**No audio anywhere on the machine after stopping the bot**
Not a bot problem any more by the time you notice it: VoiceMeeter's audio
engine is stuck, and because your default playback device is one of its
virtual inputs, *everything* fails — a browser video will not start, a stream
reports a decoding error, the Media Player refuses a local file.

Right-click the VoiceMeeter tray icon → **Restart Audio Engine**. Killing the
VoiceMeeter process and starting it again does **not** help: a terminated
process never shuts its engine down, and the new one attaches to the same
stuck state. Shutting VoiceMeeter down from that tray menu works because it
stops the engine properly.

It happens when the bot is terminated rather than stopped, because ffmpeg then
loses its capture of the VoiceMeeter bus without closing it. Stopping the bot
with `Stop-BATCRelayBot` or `!BATCshutdown` closes the capture first; the
command tells you when it had to terminate instead.

**"Timed out connecting to voice"**
Almost always channel permissions rather than the network. The bot's role
needs explicit **View Channel**, **Connect** and **Speak** on that specific
channel — server-wide permissions are not enough.

**Bot starts and immediately disconnects**
Check `bot_error.log`. Usual causes: wrong channel ID, missing permissions,
or Discord rate limiting.

**"Field 'x' is missing or empty in config.json"**
The configuration predates 1.4.0 or was edited by hand. Run
`Install-BATCRelayBot` to migrate it, or see
[CONFIGURATION.md](CONFIGURATION.md).

**Guild or channel "not found" in the log**
Either the bot is not a member of that server, or the ID is written as a
string. Both IDs must be unquoted numbers.

**`JSONDecodeError: Unexpected UTF-8 BOM`**
`config.json` was saved with a byte-order mark. The bot tolerates one, so this
only appears with very old copies. Re-saving as UTF-8 without BOM fixes it.

## Stopping

**The bot keeps rejoining after `Stop-BATCRelayBot`**
The Python process is independent of the PowerShell module: closing the
terminal or uninstalling the module does not stop it. Use `!BATCshutdown` in
Discord, or:

```powershell
New-Item "$env:LOCALAPPDATA\BATCRelayBot\stop.signal" -ItemType File -Force
```

The bot checks for that file every second, leaves the channel and exits.

**`!BATCleave` and the bot comes back**
Fixed in 1.4.0. Before that the watchdog reconnected within ten seconds.
`!BATCleave` now keeps it out until `!BATCjoin`.

## Uninstalling

**Python or FFmpeg stayed installed**
Answer `y` or `yes` at each prompt — they are asked about separately, and
anything else keeps them. If a removal fails, the uninstaller prints the
`winget` command to run by hand.

**The uninstaller says there is nothing to remove**
It only removes the directory it is pointed at. Pass a custom location with
`-InstallPath` if you did not install to the default.
