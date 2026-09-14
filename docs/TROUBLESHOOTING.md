---
title: Troubleshooting
description: Symptoms, their usual causes, and how to fix them.
document_type: reference
audience: users
applies_to: BATCRelayBot 1.6.2
updated: 2026-09-14
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
leaves a trace even if the window closed. Since 1.7.0 it also records every
start and every end of the bot — how long it ran and with what exit code —
because it is the one file a restart does not touch.

`bot_error.log` is the bot's own log: a session header, gateway and voice
events, and a heartbeat every five minutes. It starts fresh with every start;
the previous one is kept beside it as `bot_error.<date>-<time>.log`, five
sessions in all.

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

**Setup says a newer version is installed than the one running**
You ran `Update-Module` and then `Install-BATCRelayBot` in the same window.
PowerShell keeps the version it loaded first, so that setup would install
the old bot under a new banner — it did exactly that before 1.6.2 noticed.
Close the window, open a new one, run `Install-BATCRelayBot` again. If setup
only *warns* that it could not compare versions, it carries on; that happens
when a module path is out of reach or the module runs from a checkout.

**Setup asks for the token again although it is in config.json**
Since 1.6.2 it should not, unless one of these: you answered `n` to *Keep
this configuration?*; Discord rejected the stored token — it was reset in
the developer portal, so a new one is needed; or the file was missing that
value. The audio device is asked again on its own when ffmpeg no longer
lists it — usually VoiceMeeter is not running.

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

**`!BATCtext` is on but no text appears**
The bot posts only what it finds in BeyondATC's `Player.log`, so work along
that chain:

1. Is BeyondATC running, with a flight loaded? Nothing is written until the
   controller speaks to *you* — traffic talking to other aircraft is not
   posted, and neither is your own side of the exchange.
2. Did you switch it on *after* `!BATCjoin`? Every join starts with text off,
   and `!BATCleave` clears it; the reply to `!BATCtext` says which state it
   switched to.
3. Does the bot have **Send Messages** in the channel you typed `!BATCjoin`
   in? A refused post switches the feed off and writes one line to
   `bot_error.log` saying so. Grant the permission, then `!BATCtext` again.
4. Is the log where the bot looks? By default
   `%USERPROFILE%\AppData\LocalLow\Skirmish Mode Games, Inc\BeyondATC\Player.log`.
   If BeyondATC writes elsewhere, set `batc_log_path` — see
   [CONFIGURATION.md](CONFIGURATION.md).
5. Still nothing, with all of the above in order: a BeyondATC update may have
   changed the log's format. The feed reads an undocumented file and goes
   quiet, rather than wrong, when its shape moves. Report it with a copy of
   `Player.log` from the flight.

**Text appears before the audio**
Expected. BeyondATC writes the line when its synthetic voice starts speaking,
so the text leads the audio by the length of the transmission.

**New lines do not show up as new messages**
Expected since 1.6.1. The lines are added to one message by editing it, and
a new message starts only when that one is full. Look at the bottom of the
bot's last message, not for a new one — and expect no notification: an edit
does not mark the channel unread.

**The old flight's text is still there**
The pages are deleted when the bot leaves — `!BATCleave`, `!BATCshutdown`,
`Stop-BATCRelayBot` — and, for a bot that was killed instead, the next time
it starts. If they are still there, one of these:

1. The bot was killed and has not been started since. Start it; it cleans
   up on login.
2. Discord could not be reached when the bot left. The pages are still
   listed in `%LOCALAPPDATA%\BATCRelayBot\transcript-session.json` (a hidden
   file) and go on the next `!BATCjoin`, leave or start.
3. That file was deleted before the bot came back, or the pages are from a
   version before 1.6.1. The bot no longer knows them; remove them by hand.
   Deleting the file is otherwise harmless — the bot starts normally.

The replies to `!BATC` commands are never deleted. That is on purpose: they
are the record of who asked for what, and when.

**"Timed out connecting to voice"**
Almost always channel permissions rather than the network. The bot's role
needs explicit **View Channel**, **Connect** and **Speak** on that specific
channel — server-wide permissions are not enough.

**Bot starts and immediately disconnects**
Check `bot_error.log`. Usual causes: wrong channel ID, missing permissions,
or Discord rate limiting.

**The bot went quiet — is it dead, or is nothing happening?**
Quiet is normal: at cruise a sector can pass with no ATC line for half an
hour. Two things tell a dead bot from a quiet one.

1. **The heartbeat.** `bot_error.log` gets a `Heartbeat:` line every five
   minutes whether or not the bot is in a channel, naming its state. If the
   last one is more than ten minutes old, the process is gone or stuck.
2. **The exit line.** When the bot ends, `install.log` gets a line like
   `Bot (PID 1234) ended after 2h 14m 3s with exit code -1: ...`. The code
   says how:

| Exit code | What happened |
|---|---|
| `0` | Clean exit — `Stop-BATCRelayBot`, `!BATCshutdown` or `stop.signal` |
| `1` | A Python error. The traceback is at the end of `bot_error.log` |
| `-1` | Terminated from outside, with no chance to write anything: Task Manager, `taskkill`, a Windows shutdown — or `Stop-BATCRelayBot` after the bot did not answer within fifteen seconds, which writes its own line saying so just before |
| `-1073741510` | Console closed or CTRL+C (`0xC000013A`) |
| `-1073741819` | A native crash, access violation (`0xC0000005`). Look for the `faulthandler` dump at the end of `bot_error.log` |
| other negative | A native crash; the line gives the NTSTATUS in hex |

If there is no exit line at all, the bot was started without the watcher
(`python bot.py` by hand) or the watcher itself was killed; the process may
still be running — `Get-BATCRelayBotStatus` knows.

Before the exit, read `bot_error.log` backwards from the last heartbeat:
`Disconnected from the Discord gateway` marks a network gap, `Left voice
channel ... not by this bot` a moderator's disconnect.

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
