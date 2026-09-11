---
title: Configuration Reference
description: Every field in config.json, which component reads it, and how to change it safely.
document_type: reference
audience: users
applies_to: BATCRelayBot 1.6.0
updated: 2026-09-11
---

# Configuration Reference

`config.json` lives in `%LOCALAPPDATA%\BATCRelayBot` and is written by
`Install-BATCRelayBot`. It is restricted to your user account because it holds
the bot token in plaintext.

## Fields

### Required by `bot.py`

The bot exits at startup if any of these is missing or empty.

| Field | Type | Notes |
|---|---|---|
| `bot_token` | string | Treat like a password |
| `guild_id` | **number** | Discord server ID, unquoted |
| `audio_device_name` | string | Exactly as ffmpeg names it |

`guild_id` must be a JSON number. A quoted ID leaves discord.py unable to
resolve the server, and the only symptom is a "not found" line in the log.

There is no voice channel here. The bot joins the channel you are in when you
say `!BATCjoin`, or the one you name — `!BATCjoin Tower` or `!BATCjoin <id>`.
A `voice_channel_id` left over from an earlier version is ignored.

`audio_device_name` must be a VoiceMeeter **B** bus — those are virtual and
can be captured. The **A** buses feed your speakers and cannot. List what
ffmpeg sees:

```powershell
ffmpeg -list_devices true -f dshow -i dummy
```

### Detected during setup

| Field | Read by | Notes |
|---|---|---|
| `python_path` | `Start-BATCRelayBot` | Required to start the bot |
| `ffmpeg_path` | `bot.py` | Falls back to `ffmpeg` on PATH if unset |
| `voicemeeter_path` | `Start-BATCRelayBot` | Executable, not the directory |
| `voicemeeter_process_name` | `Start-BATCRelayBot` | No `.exe` suffix |
| `batc_path` | `Start-BATCRelayBot` | Leave empty if unused |
| `batc_process_name` | `Start-BATCRelayBot` | Leave empty if unused |
| `voicemeeter_wait_seconds` | `Start-BATCRelayBot` | Default 6 |
| `batc_wait_seconds` | `Start-BATCRelayBot` | Default 8 |

Empty `batc_*` fields mean "skip"; the bot works without BeyondATC.

### Optional, by hand only

| Field | Read by | Notes |
|---|---|---|
| `batc_log_path` | `bot.py` | Where BeyondATC writes `Player.log`. Absent means the default below |

`!BATCtext` reads what the controller says out of BeyondATC's own log, which
Unity places at

```
%USERPROFILE%\AppData\LocalLow\Skirmish Mode Games, Inc\BeyondATC\Player.log
```

That location is fixed by BeyondATC, so setup neither asks for it nor writes
the field. Set `batc_log_path` only if your copy writes elsewhere — a
relocated profile, say — and use the full path to the file, not the
directory. The editor does not offer this field; add it by hand and restart
the bot.

## Changing a setting

### With the editor

```powershell
Edit-BATCRelayBotConfig
```

Covers the bot token, server ID and audio device. The audio
device comes from the same filtered ffmpeg list the installer uses, so you
cannot pick a bus the bot is unable to capture, and a new token is checked
against the Discord API before it is saved.

Each change is backed up, written atomically, then read back and verified. If
verification fails the file is rolled back. The last 10 backups are kept
beside `config.json` and carry the same access restriction.

Restart the bot afterwards for the change to take effect:

```powershell
Stop-BATCRelayBot; Start-BATCRelayBot
```

### By hand

The paths above are not covered by the editor. Edit them directly:

```powershell
Stop-BATCRelayBot
notepad $env:LOCALAPPDATA\BATCRelayBot\config.json
Start-BATCRelayBot
```

Keep the file valid JSON, and keep `guild_id` unquoted. Re-running
`Install-BATCRelayBot` regenerates the whole file if you would rather start
over.

## Upgrading from 1.3.x

The field names changed in 1.4.0:

| Before | Now |
|---|---|
| `server_id` | `guild_id` |
| `channel_id` | gone - the channel is chosen per `!BATCjoin` |
| — | `audio_device_name` (new) |

`Install-BATCRelayBot` migrates the names and converts the IDs to numbers
automatically. `audio_device_name` cannot be guessed, so it is asked for.

Before 1.4.0 no installed configuration satisfied `bot.py`, so a 1.3.x
installation that never started is expected rather than broken.
