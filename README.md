# BATC Relay Bot

A PowerShell module + Python bot that joins a Discord voice channel and live-streams audio from a Windows recording device (typically a [VoiceMeeter](https://vb-audio.com/Voicemeeter/) virtual output) into that channel. It was built as an automated replacement for manually running a second Discord client to relay [BeyondATC](https://www.beyondatc.net/) radio traffic into a group flight's voice channel.

## How it works

```
BeyondATC  --(Windows app audio output)-->  VoiceMeeter  --(virtual bus B1)-->  ffmpeg  -->  Discord voice channel
```

BeyondATC's audio output is routed into VoiceMeeter's virtual input, mixed onto VoiceMeeter's B1 bus, and then this bot captures that bus with ffmpeg and streams it into your Discord voice channel — so everyone in the channel hears the ATC radio traffic without anyone needing a second Discord account or browser window.

## Prerequisites

Before you start, you need:

| Software | Official site | Notes |
|---|---|---|
| Windows 10/11 | — | Windows only (due to VoiceMeeter, ffmpeg, and BATC) |
| Discord account | https://discord.com | Need server management permissions |
| winget (Windows Package Manager) | Built-in on Win11; on Win10: [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) | Automated tool installation |
| BeyondATC | https://www.beyondatc.net/download | (Optional) Only needed to stream ATC radio traffic |
| Microsoft Flight Simulator 2024 | https://flightsimulator.xbox.com | (Optional) Only needed if using BeyondATC |

**Python, ffmpeg, and VoiceMeeter are installed automatically by the setup function.**

---

## Setup, step by step

### 1. Create a Discord bot application

1. Go to https://discord.com/developers/applications and create a **New Application**.
2. Under **Bot**, generate a token and copy it somewhere safe. Treat this like a password.
3. Under **OAuth2 → URL Generator**, check **bot** scope and **Connect** + **Speak** permissions (add **Send Messages** if you want to use text commands). Open the generated URL and invite the bot to your server.
4. In your server, right-click your target voice channel → **Edit Channel → Permissions**. Select the bot's role and explicitly **Allow** View Channel, Connect, and Speak.
5. In Discord, enable **Developer Mode** (Settings → Advanced) so you can right-click to copy server and channel IDs.

**Reference:** [Discord developer docs](https://discord.com/developers/docs/intro) and [discord.py intents guide](https://discordpy.readthedocs.io/en/stable/intents.html)

### 2. Install the PowerShell module and run automated setup

Open PowerShell **in this folder** (no admin needed) and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Import-Module .\BATCRelayBot -Force
Install-BATCRelayBot
```

This will automatically:
- Install Python 3.10+ (via winget)
- Install ffmpeg (via winget)
- Install VoiceMeeter (via winget)
- Install required Python packages
- Auto-detect your VoiceMeeter output device
- Prompt you for:
  - Discord bot token
  - Discord server ID (guild_id)
  - Discord voice channel ID
  - Path to BeyondATC.exe (if using BeyondATC)
- Write configuration to `config.json`

**Note:** VoiceMeeter installation may require a **system restart** to fully activate. If the setup completes but VoiceMeeter isn't working, restart Windows.

### 3. Configure VoiceMeeter audio routing (manual step)

This is required to route audio from applications into the bot.

1. **Open Windows Volume Mixer:**
   - Settings → System → Sound → Volume mixer
   - Find any applications that output audio (e.g., BeyondATC)
   - Set their output device to **"Voicemeeter Input (VB-Audio Voicemeeter VAIO)"** (not "Default")

2. **Configure VoiceMeeter:**
   - Open VoiceMeeter
   - On the **Virtual Input** strip (the one that receives audio from your apps), make sure:
     - **B1** routing button is enabled (highlighted) — this sends audio to the virtual output bus
     - **Solo (S)** button is OFF — if on, it mutes everything else
   - You should see levels move on the **"VIRTUAL OUT (B)"** meter when audio plays

3. **Test the routing:**
   - Play audio from your application (e.g., trigger a BeyondATC radio call)
   - Watch the Virtual Input meter — levels should move
   - If they don't, check step 1: is the app really sending audio to Voicemeeter Input?

**Reference:** [VoiceMeeter manual](https://vb-audio.com/Voicemeeter/)

### 4. Start the bot

```powershell
Start-BATCRelayBot
```

This will:
- Start VoiceMeeter (if not running)
- Start BeyondATC (if not running and configured)
- Start the bot in the background
- Log output to `logs\bot_output.log` and errors to `logs\bot_error.log`

To stop it cleanly:

```powershell
Stop-BATCRelayBot
```

---

## PowerShell commands

Once the module is imported, these commands are available:

| Command | Effect |
|---|---|
| `Install-BATCRelayBot` | Installs prerequisites and generates config.json |
| `Start-BATCRelayBot` | Starts the bot in the background |
| `Stop-BATCRelayBot` | Stops the bot cleanly |
| `Get-BATCRelayBotStatus` | Shows whether the bot is running and its uptime |
| `Uninstall-BATCRelayBot` | Removes config and generated files, optionally uninstalls Python/ffmpeg |

---

## Discord bot commands

Once the bot is in your server, these text commands are available in any channel it can see:

| Command | Effect |
|---|---|
| `!status` | Shows whether the bot is connected and streaming |
| `!restart_stream` | Restarts the audio stream without leaving the channel |
| `!leave` | Manually disconnects the bot from voice |

---

## Troubleshooting

- **"file cannot be loaded... not digitally signed"** - PowerShell's execution policy is blocking the script. Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` first, or permanently with `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force`.

- **Voice connection times out ("Timed out connecting to voice")** - This is usually a Discord **channel permission** issue, not network/firewall. Re-check Setup step 1.4 above: the bot's role needs explicit "View Channel" + "Connect" + "Speak" on the target channel.

- **VoiceMeeter installed but not activating** - VoiceMeeter may require a system restart. Restart Windows and try again.

- **No audio reaches Discord (bot is connected but silent)** - Debug VoiceMeeter routing first:
  1. Check step 3 above: is the app really sending audio to Voicemeeter Input? Check the Virtual Input meter.
  2. Test ffmpeg directly: `ffmpeg -f dshow -i audio="<your device name>" -t 8 test.wav`, then play `test.wav`. If silent, the problem is VoiceMeeter/app routing, not the bot.

- **Bot starts but immediately disconnects** - Check `logs\bot_error.log` for details. Common causes: wrong channel ID, missing bot permissions, or Discord rate limiting.

- **`json.decoder.JSONDecodeError: Unexpected UTF-8 BOM`** - `config.json` was saved with a BOM (e.g., by Notepad). `bot.py` handles this automatically with `utf-8-sig`, so this should only happen with very old copies.

---

## Uninstalling

```powershell
Uninstall-BATCRelayBot
```

This will:
- Stop the bot (if running)
- Securely delete `config.json` (which contains your Discord token)
- Remove generated files (logs, bot.pid, stop.signal)
- Optionally uninstall Python and/or ffmpeg (will ask for confirmation separately in case you use them for other projects)

Your project files remain in place.

---

## Files

| File/Folder | Purpose |
|---|---|
| `BATCRelayBot/` | PowerShell module (install, start, stop, uninstall commands) |
| `bot.py` | The Discord bot itself (Python) |
| `config.example.json` | Template for `config.json` |
| `requirements.txt` | Python dependencies (auto-installed by setup) |
| `LICENSE` | MIT License |
| `README.md` | This file |

---

## License

MIT License - see LICENSE file for details.
