---
title: Changelog
description: Release history for the BATCRelayBot PowerShell module and Discord bot.
document_type: history
audience: users
applies_to: BATCRelayBot 1.4.0
updated: 2026-09-08
---

# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries describe what changed for users. For the reasoning behind a change,
see the commit that made it.

## [1.4.0] - 2026-09-08

Minor rather than patch: `config.json` changed shape. Existing files are
migrated automatically on the next `Install-BATCRelayBot`, except
`audio_device_name`, which cannot be guessed and is asked for.

### Added

- `Edit-BATCRelayBotConfig` works and is enabled again. It changes the bot
  token, server ID, voice channel ID or audio device without reinstalling,
  with a backup, verification and rollback around every write.
- Discord commands `!BATCjoin`, `!BATCleave`, `!BATCstatus`, `!BATCrestart`,
  `!BATCshutdown` and `!BATChelp`.
- `Uninstall-BATCRelayBot -Force` skips the final confirmation for unattended
  cleanup. Optional components still need an explicit yes.
- The installation log now starts with the first step and records every
  failure, including those before any file is written.

### Changed

- **`config.json` field names.** `server_id` is now `guild_id`, `channel_id`
  is now `voice_channel_id`, and `audio_device_name` was added. Both IDs are
  JSON numbers, not strings.
- **Starting the bot no longer joins a voice channel.** It comes online and
  stands by; relaying begins on `!BATCjoin`. The bot can run permanently
  without occupying the channel.
- **Chat commands are `BATC`-prefixed** so they cannot collide with other
  bots in the same server. Names are case-insensitive.
- **The installer resolves prerequisites before asking for anything**, so a
  missing tool can no longer discard credentials that were just typed.
- **VoiceMeeter and BeyondATC are never installed or removed automatically.**
  VoiceMeeter ships audio drivers and BeyondATC is commercial software, so
  both come from their vendors' installers. Missing VoiceMeeter warns and
  explains instead of blocking, and the bot runs without BeyondATC.
- **The audio device is chosen from a list** produced by the same ffmpeg the
  bot will use. Only VoiceMeeter's virtual buses are offered, with B1
  preselected; physical outputs and microphones are filtered out.
- **The uninstaller stops a running bot** before deleting anything, cleanly
  where possible. Python and FFmpeg are asked about separately, each showing
  the exact package and version, and removed only on explicit confirmation.
- **`discord.py` is pinned to an exact version** (`2.7.1`) rather than a
  minimum. An unpinned minor has broken a release here before.
- Deleting `config.json` is described accurately: it is overwritten and
  deleted, which is not secure erasure on an SSD, so every screen points at
  resetting the token instead.

### Removed

- Output format and bot activity from the configuration editor. `bot.py` read
  neither, so changing them had no effect.
- Five module files nothing called - `Find-FfmpegExe`, `Find-PerUserPython`,
  `Prompt-FilePath`, `Prompt-WithDefault`, `Write-Step` - and a winget check
  that ran twice for the same answer.

### Fixed

- **The installed bot could never start.** The installer wrote `server_id`
  and `channel_id` while `bot.py` requires `guild_id` and
  `voice_channel_id`, and `audio_device_name` was never written or asked
  for. Every installation since 1.0.0 produced a config `bot.py` rejected.
- **`Start-BATCRelayBot` never received the fields it needs**
  (`voicemeeter_process_name`, `batc_path`, `batc_process_name`), and
  `voicemeeter_path` pointed at a directory where an executable was expected.
- **Auto-installing a missing tool could not satisfy the readiness check.**
  It ran winget without re-detecting, so the check that followed still saw
  the tool as missing and refused to install.
- **A failed installation closed the window before the error could be read.**
  `exit` inside a module function terminates the whole PowerShell session; it
  is now a return.
- **Prerequisite detection missed real installations**: Python installed for
  all users, BeyondATC on a drive other than C:, and VoiceMeeter's executable
  and process name. The Microsoft Store stub could be reported as a working
  interpreter; every candidate is now verified by running it.
- **A running bot could become unstoppable.** `Stop-BATCRelayBot` and
  `Get-BATCRelayBotStatus` trusted `bot.pid` alone, so a missing or stale
  file made both report "not running" while the bot kept rejoining the
  channel. Both fall back to finding the process.
- **`!leave` was undone by the watchdog within ten seconds**, leaving no chat
  command that could get the bot out of a channel.
- **The uninstaller removed nothing it was asked to.** Only the literal word
  `yes` was accepted, the winget package id was wrong, and failures were
  reported as success. FFmpeg was offered for removal even when it was not
  installed.
- **A half-finished installation could not be uninstalled**, because a
  missing `config.json` aborted the whole operation.
- **The recommended audio device was arbitrary.** The first name containing
  "Voicemeeter" and "Out" won, and ffmpeg enumerates in no useful order.
- **The configuration editor wrote to fields nothing read**, so an edited
  token was saved while the bot kept using the old one.
- CI ran 26 module smoke tests; the unit and integration suites sat outside
  the configured path and never ran. The whole tree runs now.
- CI could fail before running anything, when installing Pester from the
  gallery failed. It uses the preinstalled copy where there is one and retries
  with TLS 1.2 otherwise.
- Four tests for token-validation errors existed as empty shells marked
  `-Skip`, describing cases nobody had written and expecting wordings the code
  does not use. They are written, and cover the rate-limit and server-error
  codes the shells had missed.

### Security

- The bot token is redacted everywhere and never partially displayed.
- Reading the token from a `SecureString` frees its unmanaged buffer, which
  previously kept the token in memory for the life of the session.
- Configuration backups are restricted to the current user. They hold the
  token in plaintext and previously inherited the directory's permissions.
- `!BATCshutdown` requires the Administrator permission.
- The build fails if a credential-shaped string enters the repository. Every
  tracked file is scanned for token, key and snowflake shapes; a fixture has to
  look obviously synthetic to pass.
- `.gitignore` closed gaps around `config.json` backups, local editor state and
  test output, any of which could have carried a real token into a commit.

### Known issues

- **Uninstalling while the bot is running leaves the installation directory
  behind.** The running process holds `bot_error.log`, the removal fails, and
  the step that follows reports "Nothing to clean up" over the failure. Stop the
  bot with `Stop-BATCRelayBot` before uninstalling, or delete
  `%LOCALAPPDATA%\BATCRelayBot` by hand afterwards. Fixed in the next release.

## [1.3.0] - [1.3.16] - 2026-08-30 to 2026-08-31

A rapid series of installer hotfixes. Every release in this range changed
only the PowerShell installer; `bot.py` was untouched throughout.

Recurring themes: PSGallery packaging and path resolution (1.3.6-1.3.9),
VoiceMeeter and winget detection (1.3.0-1.3.3, 1.3.12-1.3.13), Discord API
token validation (1.3.14), and security hardening of the installer (1.3.15).

Notable:

- **1.3.11 was withdrawn** and should not be used.
- **1.3.10** was tagged but never given a changelog entry.
- The configuration editor shipped in 1.3.10 and was disabled immediately
  afterwards; it returns in 1.4.0.

None of these releases fixed the underlying defect that made an installed bot
unable to start - see 1.4.0. For per-release detail, see the git tags.

## [1.2.0] - 2026-08-30

### Added

- Architecture Decision Records for VoiceMeeter selection, the module format,
  the installation path, and the polling design.
- Async test coverage for the bot lifecycle.

## [1.1.0] - 2026-08-30

### Changed

- The bot is installed into `%LOCALAPPDATA%\BATCRelayBot` and its files are
  copied there automatically, instead of running from the project directory.
- All commands take `BotPath` in place of `ProjectPath`.

## [1.0.0] - 2026-08-30

Initial release.

### Added

- PowerShell module with `Install-`, `Start-`, `Stop-`, `Get-…Status` and
  `Uninstall-BATCRelayBot`.
- Python bot streaming a Windows recording device into a Discord voice
  channel, with `!status`, `!restart_stream` and `!leave`.
- Pester and pytest suites, GitHub Actions for testing and PSGallery
  publishing, MIT licence.
- Windows 10/11, PowerShell 5.1+, Python 3.10+.
