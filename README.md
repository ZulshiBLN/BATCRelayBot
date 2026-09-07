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

Open PowerShell (no admin needed) and run:

```powershell
Install-Module BATCRelayBot -Repository PSGallery
Install-BATCRelayBot
```

The installer runs in six phases and resolves every prerequisite *before*
asking for anything, so a missing tool can never discard credentials you have
already typed:

1. **Detect** Python, ffmpeg, VoiceMeeter and BeyondATC (silent)
2. **Report** what was found and what is missing
3. **Resolve** what is missing:
   - Python and ffmpeg can be installed for you via winget, per-user, without
     admin rights
   - VoiceMeeter and BeyondATC are only checked. Both must be installed with
     their vendor's own installer - VoiceMeeter because it ships audio
     drivers, BeyondATC because it is commercial software with no winget
     package. You get a link and a short guide instead.
4. **Configure** — you are prompted for:
   - Discord bot token (validated against the Discord API before it is accepted)
   - Discord server ID (`guild_id`)
   - Discord voice channel ID
   - The recording device to stream, **chosen from a list** that ffmpeg
     reports, so the name always matches exactly
5. **Confirm** the summary
6. **Install** — Python packages, `bot.py` and `config.json` into
   `$env:LOCALAPPDATA\BATCRelayBot`, then verify that the generated config
   satisfies everything `bot.py` requires

Everything is logged to `install.log` in the installation directory from the
first step onwards, including any failure.

**Note:** VoiceMeeter requires a **system restart** after installation before
its virtual audio devices appear. Start VoiceMeeter before running the
installer, otherwise its outputs will be missing from the device list.

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
| `Edit-BATCRelayBotConfig` | (Coming in v1.3.11) — Interactive editor for config changes. For now, manually edit config.json |
| `Uninstall-BATCRelayBot` | Stops the bot, removes the installation, and optionally uninstalls Python/ffmpeg after separate confirmation |

---

## Editing Configuration

**Note:** Interactive configuration editing is coming in v1.3.11. For now, edit configuration manually.

### Manual JSON Editing (v1.3.10)

To update settings, edit `config.json` directly:

```powershell
# Stop the bot first
Stop-BATCRelayBot

# Edit the configuration file
notepad $env:USERPROFILE\AppData\Local\BATCRelayBot\config.json

# Restart the bot to apply changes
Start-BATCRelayBot
```

### Configuration Fields

The `config.json` file contains these fields (you can edit all of them):

Required by `bot.py` — the bot exits at startup if any is missing or empty:

- **`bot_token`**: Discord bot authentication token (secret — treat like a password)
- **`guild_id`**: Discord server ID, as a **number, not a string**
- **`voice_channel_id`**: Discord voice channel ID, likewise a number
- **`audio_device_name`**: The recording device to stream, spelled exactly as
  ffmpeg reports it, e.g. `VoiceMeeter Output (VB-Audio Voicemeeter VAIO)`.
  List the available names with:
  ```powershell
  ffmpeg -list_devices true -f dshow -i dummy
  ```

Used by `Start-BATCRelayBot` and `bot.py`, all auto-detected during setup:

- **`python_path`**: Path to python.exe (required to start the bot)
- **`ffmpeg_path`**: Path to ffmpeg.exe
- **`voicemeeter_path`** / **`voicemeeter_process_name`**: Executable and
  process name, used to start VoiceMeeter if it is not already running
- **`batc_path`** / **`batc_process_name`**: The same for BeyondATC. Leave
  empty if you do not use it — the bot works without it.
- **`voicemeeter_wait_seconds`** / **`batc_wait_seconds`**: How long to wait
  after starting each one (defaults: 6 and 8)

> **Upgrading from 1.3.x:** the fields were previously named `server_id` and
> `channel_id`, and `audio_device_name` was never written. Running
> `Install-BATCRelayBot` migrates the names automatically; the audio device
> cannot be guessed and is asked for.

### Important Notes

- **Stop the bot before editing**: `Stop-BATCRelayBot`
- **Restart required after editing**: `Start-BATCRelayBot` applies your changes
- **Backup your config**: Before major edits, manually copy config.json to config.json.backup
- **JSON syntax matters**: Make sure your JSON is valid after editing (use a JSON validator if unsure)

### Interactive editing

`Edit-BATCRelayBotConfig` is still disabled: it returns a notice without
changing anything. Its underlying helpers were repaired in 1.4.0, but the
command itself has not been re-audited, so use the manual route above.
Re-running `Install-BATCRelayBot` also regenerates the configuration.

---

## Discord bot commands

Once the bot is in your server, these text commands are available in any channel it can see:

| Command | Effect |
|---|---|
| `!BATCjoin` | Joins the configured voice channel and starts relaying |
| `!BATCleave` | Disconnects and **stays out** until `!BATCjoin` |
| `!BATCstatus` | Shows whether the bot is connected and streaming |
| `!BATCrestart` | Restarts the audio stream without leaving the channel |
| `!BATCshutdown` | Stops the bot process entirely (requires Administrator permission) |
| `!BATChelp` | Lists the commands |

Command names are case-insensitive, so `!batcjoin` works too. Everything is
`BATC`-prefixed so this bot cannot collide with other bots in the same server.

### Starting the bot does not join a channel

`Start-BATCRelayBot` only brings the bot **online** in Discord — it stands by
without entering a voice channel. Relaying starts when someone types
`!BATCjoin`. That way the bot can run permanently (or start with Windows)
without sitting in the channel when nobody is flying.

`!BATCleave` pauses the relay as well as disconnecting. Without that the
watchdog reconnects within ten seconds, which is why `!leave` appeared to do
nothing before 1.4.0.

Use `!BATCshutdown` if the bot runs in the background and `Stop-BATCRelayBot`
cannot reach it — for example after `bot.pid` was lost. The Python process is
independent of the PowerShell module, so closing the terminal or uninstalling
the module does **not** stop it.

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
- **Stop the bot** if it is running — cleanly, so it leaves the voice channel
  before exiting
- Overwrite and delete `config.json`, then remove the whole installation
  directory including logs, `bot.pid` and `stop.signal`
- Ask **separately** about Python and FFmpeg, showing the exact package and
  version. Neither is removed unless you confirm it — you may well be using
  them for something else. Answer `y` or `yes`; anything else keeps them.

Add `-Force` to skip the final confirmation for unattended cleanup. Optional
components still require an explicit yes.

**VoiceMeeter is never removed.** It installs audio drivers, so it has to go
through VB-Audio's own uninstaller (Settings → Apps), followed by a reboot.

### Reset your bot token

`config.json` is overwritten three times before deletion, but on an SSD that
is **not** a guarantee: wear levelling can leave the original bytes readable.
The only reliable step is to invalidate the token itself:

> https://discord.com/developers/applications → your app → Bot → **Reset Token**

Do this whenever you uninstall, and certainly before handing the machine on.

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
