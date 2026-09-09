# BATC Relay Bot

A PowerShell module and Python bot that joins a Discord voice channel and
live-streams audio from a Windows recording device into it. Built to replace
running a second Discord client by hand to relay
[BeyondATC](https://www.beyondatc.net/) radio traffic into a group flight's
voice channel.

```
BeyondATC --(app audio)--> VoiceMeeter --(bus B1)--> ffmpeg --> Discord voice channel
```

Everyone in the channel hears the ATC traffic; nobody needs a second Discord
account or a spare browser window.

## Requirements

| Software | Where | Notes |
|---|---|---|
| Windows 10/11 | — | Windows only: VoiceMeeter and DirectShow |
| Discord account | [discord.com](https://discord.com) | You need to manage a server |
| winget | Built into Win11; Win10: [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) | Used to install Python and ffmpeg |
| VoiceMeeter | [vb-audio.com](https://vb-audio.com/Voicemeeter/) | Install manually, then reboot |
| BeyondATC | [beyondatc.net](https://www.beyondatc.net/download) | Optional, only for ATC traffic |

**Python and ffmpeg are installed for you** by the setup command, per-user and
without admin rights. **VoiceMeeter and BeyondATC are not** — VoiceMeeter ships
audio drivers and BeyondATC is commercial software, so both come from their own
installers. Setup checks for them and tells you what to do.

## Setup

### 1. Create the Discord bot

1. At [discord.com/developers](https://discord.com/developers/applications),
   create a **New Application**.
2. Under **Bot**, generate a token. Treat it like a password.
3. Still under **Bot**, switch on the **Message Content Intent**. Without it
   the bot never sees the text of a message and no `!BATC…` command works.
4. Under **OAuth2 → URL Generator**, tick the **bot** scope and these
   permissions, then open the generated URL and invite the bot:

   | Where | Permission | Why |
   |---|---|---|
   | text channel | View Channel | a command in a channel it cannot see never reaches it |
   | text channel | Send Messages | every command answers in the channel |
   | voice channel | View Channel | a hidden channel cannot be joined, or even named |
   | voice channel | Connect | to enter the channel |
   | voice channel | Speak | to be heard once inside |

   **Read Message History is not needed.** Commands arrive as they are typed;
   nothing here reads older messages.

5. Right-click each voice channel the bot should be able to join →
   **Edit Channel → Permissions**, and explicitly **Allow** its role
   View Channel, Connect and Speak. Server-wide permissions are not enough
   when a channel overrides them.
6. Enable **Developer Mode** (Settings → Advanced) so you can copy IDs.

### 2. Install

Start VoiceMeeter first — its virtual buses only appear in the device list
while it is running. Then, in PowerShell without admin rights:

```powershell
Install-Module BATCRelayBot -Repository PSGallery
Install-BATCRelayBot
```

Setup detects what is present, offers to install what is missing, and only
then asks for your bot token, server ID, voice channel ID and audio device.
Nothing you type can be discarded by a missing tool.

For the audio device, pick **B1** unless you have a reason not to — that is
the bus step 3 routes audio to. Everything is logged to `install.log` in the
installation directory.

### 3. Route audio in VoiceMeeter

1. **Send your app's audio to VoiceMeeter.** Settings → System → Sound →
   Volume mixer, set the app's output device to
   **"Voicemeeter Input (VB-Audio Voicemeeter VAIO)"** — not "Default".
2. **Send it on to B1.** In VoiceMeeter, on the **Virtual Input** strip,
   enable the **B1** button and make sure **Solo** is off. The
   **VIRTUAL OUT (B)** meter should move when audio plays.
3. **Check it.** Trigger a radio call and watch the Virtual Input meter. If it
   stays flat, the app is not sending audio to Voicemeeter Input.

### 4. Run

```powershell
Start-BATCRelayBot
```

The bot comes **online but stays out of the channel**. In Discord, type
`!BATCjoin` to start relaying. Stop it with `Stop-BATCRelayBot`.

## Commands

### PowerShell

| Command | Effect |
|---|---|
| `Install-BATCRelayBot` | Detects prerequisites, collects settings, writes `config.json` |
| `Start-BATCRelayBot` | Brings the bot online in the background |
| `Stop-BATCRelayBot` | Stops it cleanly |
| `Get-BATCRelayBotStatus` | Shows whether it is running, and for how long |
| `Edit-BATCRelayBotConfig` | Changes one setting without reinstalling |
| `Uninstall-BATCRelayBot` | Stops the bot and removes the installation |

### Discord

| Command | Effect |
|---|---|
| `!BATCjoin` | Join the configured channel and start relaying |
| `!BATCleave` | Leave and **stay out** until `!BATCjoin` |
| `!BATCstatus` | Connection and stream state |
| `!BATCrestart` | Restart the stream without leaving |
| `!BATCshutdown` | Stop the bot process (Administrator only) |
| `!BATChelp` | List the commands |

Names are case-insensitive, so `!batcjoin` works. The `BATC` prefix keeps them
from colliding with other bots in the same server.

`!BATCshutdown` is the way out if the bot runs in the background and
`Stop-BATCRelayBot` cannot reach it: the Python process is independent of the
PowerShell module, so closing the terminal does not stop it.

## Uninstalling

```powershell
Uninstall-BATCRelayBot
```

Stops the bot, removes the installation directory, and asks **separately**
about Python and FFmpeg — neither is removed unless you confirm it. Add
`-Force` to skip the final confirmation; the optional components still need an
explicit yes.

**VoiceMeeter is never removed.** Use VB-Audio's own uninstaller
(Settings → Apps), then reboot.

**Reset your bot token afterwards.** `config.json` is overwritten before
deletion, but overwriting does not reliably erase a file on an SSD. Invalidating
the token is the only guarantee: developer portal → your app → Bot → **Reset
Token**.

## Documentation

| Document | Contents |
|---|---|
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Every `config.json` field, and how to change it |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptoms, causes, fixes |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Repository layout

| Path | Contents |
|---|---|
| `BATCRelayBot/` | The PowerShell module |
| `bot.py` | The Discord bot |
| `config.example.json` | Template for `config.json` |
| `requirements.txt` | Python dependencies, installed by setup |
| `tests/` | Pester and pytest suites |

## Licence

MIT — see [LICENSE](LICENSE).
