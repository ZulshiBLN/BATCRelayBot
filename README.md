# BATC Relay Bot

A PowerShell module and a Python bot that joins a Discord voice channel and
live-streams a Windows recording device into it. Built to replace running a
second Discord client by hand to relay [BeyondATC](https://www.beyondatc.net/)
radio traffic into a group flight's voice channel: everyone in the channel
hears the ATC traffic, and nobody needs a second account or a spare browser
window.

```
BeyondATC --(app audio)--> VoiceMeeter --(bus B1)--> ffmpeg --> Discord voice channel
```

## Requirements

- [ ] **Windows 10 or 11** — VoiceMeeter and DirectShow exist nowhere else
- [ ] **Windows PowerShell 5.1** — the one Windows ships with
- [ ] **A Discord account** that can manage the server the bot will join
- [ ] **winget** — built into Windows 11; on Windows 10, install
      [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1)
- [ ] **VoiceMeeter** from [vb-audio.com](https://vb-audio.com/Voicemeeter/),
      installed by hand, then a reboot
- [ ] **BeyondATC** from [beyondatc.net](https://www.beyondatc.net/download) — optional

**Python (3.10 or later) and ffmpeg are installed for you** by setup, per
user and without admin rights. **VoiceMeeter and BeyondATC are not** —
VoiceMeeter ships audio drivers and BeyondATC is commercial software. Setup
checks for them and tells you what to do.

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

5. A channel can override server-wide permissions, so check the channels
   themselves — **Edit Channel → Permissions**, and explicitly **Allow** the
   bot's role: View Channel, Connect and Speak on every **voice** channel it
   should join; View Channel and Send Messages on every **text** channel you
   type commands in. If you type `!BATCjoin` in a voice channel's own chat,
   that voice channel needs Send Messages as well.

6. Enable **Developer Mode** (Settings → Advanced) so you can copy IDs.

### 2. Install

Start VoiceMeeter first — its virtual buses only appear in the device list
while it is running. Then, in PowerShell without admin rights:

```powershell
Install-Module BATCRelayBot -Repository PSGallery
Install-BATCRelayBot
```

Setup detects what is present, offers to install what is missing, and only
then asks for your bot token, server ID and audio device — nothing you type
can be discarded by a missing tool. For the audio device, pick **B1** unless
you have a reason not to; that is the bus step 3 routes audio to. There is no
voice channel to configure: the bot joins whichever channel you are in when
you call it. Everything is logged to `install.log` in the installation folder.

### 3. Route audio in VoiceMeeter

1. **Send your app's audio to VoiceMeeter.** Settings → System → Sound →
   Volume mixer, set the app's output device to
   **"Voicemeeter Input (VB-Audio Voicemeeter VAIO)"** — not "Default".
2. **Send it on to B1.** In VoiceMeeter, on the **Virtual Input** strip,
   enable the **B1** button and make sure **Solo** is off. The
   **VIRTUAL OUT (B)** meter should move when audio plays.
3. **Check it.** Trigger a radio call and watch the Virtual Input meter. If it
   stays flat, the app is not sending audio to Voicemeeter Input.

## Daily use

```powershell
Start-BATCRelayBot
```

That starts VoiceMeeter and BeyondATC if they are not running, then the bot.
It comes **online but stays out of the channel** — starting it, also at boot,
never puts it in one. Join a voice channel yourself and type `!BATCjoin` in
Discord; it follows you in. Or name a channel: `!BATCjoin Tower`.

`!BATCleave` takes it out of the channel and keeps it out until the next
`!BATCjoin`. `Get-BATCRelayBotStatus` says whether it is running. When you
are done:

```powershell
Stop-BATCRelayBot
```

### ATC as text

With BeyondATC running, `!BATCtext` posts what the controller says, as it is
said, into the channel you typed `!BATCjoin` in:

> **19:10** · 121.755 · Swiss 874, taxi to holding point A1, runway 28, via N, F, INNER, A.

Only the controller's side — readbacks and requests stay out. It is off after
every `!BATCjoin`; `!BATCtext` switches it on, and again off. The line
appears a few seconds *before* you hear it, because BeyondATC writes it when
its voice starts speaking.

The lines go into **one message that grows**; a new one starts only when the
next line would not fit into Discord's 2000 characters, so a flight is one
page, a long one two or three, and nobody is notified per line. The pages
stay until the bot leaves: `!BATCleave`, `!BATCshutdown` and
`Stop-BATCRelayBot` delete them, a bot that was killed deletes them the next
time it starts, and the replies to `!BATC` commands stay. No extra permission
is needed — a bot may delete its own messages.

## Commands

### PowerShell

| Command | Effect |
|---|---|
| `Install-BATCRelayBot` | Checks prerequisites, collects settings, writes `config.json` |
| `Start-BATCRelayBot` | Brings the bot online in the background |
| `Stop-BATCRelayBot` | Stops it cleanly |
| `Get-BATCRelayBotStatus` | Shows whether it is running, and for how long |
| `Edit-BATCRelayBotConfig` | Changes the token, server ID or audio device without reinstalling |
| `Uninstall-BATCRelayBot` | Stops the bot and removes the installation |

### Discord

| Command | Effect |
|---|---|
| `!BATCjoin` | Join **your** voice channel and start relaying |
| `!BATCjoin <name or id>` | Join that channel instead |
| `!BATCleave` | Leave and **stay out** until `!BATCjoin` |
| `!BATCstatus` | Connection and stream state |
| `!BATCrestart` | Restart the stream without leaving |
| `!BATCtext` | Toggle ATC as text, posted where `!BATCjoin` was typed |
| `!BATCshutdown` | Stop the bot process (Administrator only) |
| `!BATChelp` | List the commands |

Names are case-insensitive, so `!batcjoin` works. The `BATC` prefix keeps them
from colliding with other bots in the same server.

`!BATCshutdown` is the way out if `Stop-BATCRelayBot` cannot reach the bot:
the Python process is independent of the PowerShell module, so closing the
terminal does not stop it.

## When something goes wrong

The bot runs under a watcher. A voice connection lost to a network blip is
rebuilt by the bot itself once the network is back, usually within a minute;
a bot that dies — a crash, a kill from Task Manager — is started again ten
seconds later and rejoins its channel, with ATC text off, up to three times
an hour. How it ended is
written to `install.log`, and a heartbeat every five minutes in
`logs\bot_error.log` says it is alive. `Stop-BATCRelayBot` and `!BATCshutdown`
stop it for good. Where to look and what the log lines mean is in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Upgrading

`Update-Module` fetches the new module, but the bot itself is a file setup
copies into the installation, and only setup replaces it. **1.6.3 changes the
bot file, so it needs both steps.**

```powershell
Stop-BATCRelayBot
Update-Module BATCRelayBot
```

Then **open a new PowerShell window** — the one that ran `Update-Module`
keeps the old version loaded, and setup from there would install the old bot;
setup notices and tells you so — and run:

```powershell
Install-BATCRelayBot
```

Setup finds your token, server ID and audio device in the existing
configuration, shows them and asks once whether to keep them. Enter keeps
everything; the whole upgrade is one keystroke. A token that Discord no
longer accepts, or a device ffmpeg no longer lists, is asked for on its own.
Skip setup and the old bot is still the one running.

## Uninstalling

```powershell
Uninstall-BATCRelayBot
```

Stops the bot, deletes everything it installed, and asks **separately** about
Python and FFmpeg — neither is removed unless you confirm it. Add `-Force` to
skip the final confirmation; the optional components still need an explicit
yes. The installation directory itself stays, holding `uninstall.log` and
nothing else.

**VoiceMeeter and BeyondATC are never removed.** Use each vendor's own
installer to uninstall them — for VoiceMeeter, Settings → Apps leaves its
audio drivers behind.

**Reset your bot token afterwards.** `config.json` is overwritten before
deletion, but overwriting does not reliably erase a file on an SSD.
Invalidating the token is the only guarantee: developer portal → your app →
Bot → **Reset Token**.

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
| `docs/` | The guides linked above |
| `tests/` | Pester and pytest suites |

## Licence

MIT — see [LICENSE](LICENSE).
