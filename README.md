# BATC Relay Bot

A PowerShell module + Python bot that joins a Discord voice channel and live-streams audio from a Windows recording device (typically a [VoiceMeeter](https://vb-audio.com/Voicemeeter/) virtual output) into that channel. It was built as an automated replacement for manually running a second Discord client to relay [BeyondATC](https://www.beyondatc.net/) radio traffic into a group flight's voice channel.

## How it works

```
BeyondATC  --(Windows app audio output)-->  VoiceMeeter  --(virtual bus B1)-->  ffmpeg  -->  Discord voice channel
```

BeyondATC's audio output is routed into VoiceMeeter's virtual input, mixed onto VoiceMeeter's B1 bus, and then this bot captures that bus with ffmpeg and streams it into your Discord voice channel — so everyone in the channel hears the ATC radio traffic without anyone needing a second Discord account or browser window.

## Prerequisites

Before running the installer, you need:

| Software | Official site | Notes |
|---|---|---|
| Microsoft Flight Simulator | — | Already assumed installed |
| BeyondATC | https://www.beyondatc.net/download | Paid add-on |
| VoiceMeeter (Standard is enough) | https://vb-audio.com/Voicemeeter/ | Free/donationware. Follow their "Step ZERO" first-use guide before anything else |
| A Discord account with a server you can manage | https://discord.com | You need permission to create channels and manage roles |
| Windows 10/11 with winget | https://apps.microsoft.com/detail/9nblggh4nns1 | Usually preinstalled via "App Installer" |

Python, ffmpeg, and pip dependencies are installed automatically by the setup function.

## Setup, step by step

### 1. Install and configure VoiceMeeter

1. Install VoiceMeeter and reboot as instructed.
2. Open Windows Settings → System → Sound → Volume mixer. Find **BeyondATC** and set its output to **"Voicemeeter Input (VB-Audio Voicemeeter VAIO)"** (not "Default").
3. Open VoiceMeeter. On the **Virtual Input** strip (fed by BeyondATC), make sure **B1** routing is enabled (highlighted) so audio reaches the virtual output bus. Make sure **Solo (S)** is off.
4. Test a BeyondATC radio call and verify levels move on the Virtual Input strip and "VIRTUAL OUT (B)" meter.

See VB-Audio's [Voicemeeter manual](https://vb-audio.com/Voicemeeter/) for full details.

### 2. Create a Discord bot application

1. Go to https://discord.com/developers/applications and create a **New Application**.
2. Under **Bot**, generate a token and copy it somewhere safe. Treat this like a password.
3. Under **OAuth2 → URL Generator**, check **bot** scope and **Connect** + **Speak** permissions (add **Send Messages** if you want text commands). Invite the bot to your server.
4. In your server, right-click your target voice channel → **Edit Channel → Permissions**. Select the bot's role and explicitly **Allow** View Channel, Connect, and Speak.
5. In Discord, enable **Developer Mode** (Settings → Advanced) so you can right-click to copy server and channel IDs.

Reference: [Discord developers docs](https://discord.com/developers/docs/intro) and [discord.py intents guide](https://discordpy.readthedocs.io/en/stable/intents.html).

### 3. Install the PowerShell module and run setup

Open PowerShell **in this folder** (no admin needed) and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Import-Module .\BATCRelayBot -Force
Install-BATCRelayBot
```

This will:
- Install Python and ffmpeg (via winget) for your user only
- Install required Python packages
- Auto-detect your VoiceMeeter device
- Prompt you for bot token, server ID, channel ID, and paths to VoiceMeeter/BeyondATC
- Write everything to `config.json`

### 4. Start the bot

```powershell
Start-BATCRelayBot
```

This starts VoiceMeeter and BeyondATC if they aren't running, waits for them to initialize, then starts the bot in the background. Logs go to `logs\bot_output.log` and `logs\bot_error.log`.

To stop it cleanly:

```powershell
Stop-BATCRelayBot
```

## PowerShell commands

Once the module is imported, these commands are available:

| Command | Effect |
|---|---|
| `Install-BATCRelayBot` | Installs prerequisites and generates config.json |
| `Start-BATCRelayBot` | Starts the bot in the background |
| `Stop-BATCRelayBot` | Stops the bot cleanly |
| `Get-BATCRelayBotStatus` | Shows whether the bot is running and its uptime |
| `Uninstall-BATCRelayBot` | Removes config and generated files, optionally uninstalls Python/ffmpeg |

## Discord bot commands

Once the bot is in your server, these text commands are available in any channel it can see:

| Command | Effect |
|---|---|
| `!status` | Shows whether the bot is connected and streaming |
| `!restart_stream` | Restarts the audio stream without leaving the channel |
| `!leave` | Manually disconnects the bot from voice |

## Troubleshooting

- **"file cannot be loaded... not digitally signed"** - PowerShell's execution policy is blocking the script. Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` first, or permanently with `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force`.

- **Voice connection times out** - This is usually a Discord **channel permission** issue, not network/firewall. Re-check step 2.4 above: the bot's role needs explicit "View Channel" + "Connect" + "Speak" on the target channel.

- **`json.decoder.JSONDecodeError: Unexpected UTF-8 BOM`** - `config.json` was saved with a BOM (e.g., by Notepad). `bot.py` handles this automatically with `utf-8-sig`, so this should only happen with very old copies.

- **No audio reaches Discord, but bot is connected** - Test VoiceMeeter isolation first: `ffmpeg -f dshow -i audio="<your device name>" -t 8 test.wav`, then play `test.wav`. If silent, the problem is VoiceMeeter/BeyondATC routing (step 1), not the bot.

## Uninstalling

```powershell
Uninstall-BATCRelayBot
```

Stops the bot, securely deletes `config.json` (which contains your token), and removes generated files (logs, bot.pid, stop.signal). It will ask separately for confirmation before uninstalling Python/ffmpeg, in case you use either for something else. Your project files are left in place.

To check for leftover Python/ffmpeg installs:

```powershell
# (Check manually in Settings → Apps → Installed apps, or via winget list)
winget list | findstr Python
winget list | findstr FFmpeg
```

## Files

| File/Folder | Purpose |
|---|---|
| `BATCRelayBot/` | PowerShell module (setup, start, stop, uninstall commands) |
| `bot.py` | The Discord bot itself (Python) |
| `config.example.json` | Template for `config.json` - copy and fill in, or let setup generate it |
| `requirements.txt` | Python dependencies (auto-installed by setup) |
| `LICENSE` | MIT License |
| `README.md` | This file |

## License

MIT License - see LICENSE file for details.
