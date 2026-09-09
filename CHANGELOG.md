---
title: Changelog
description: Release history for the BATCRelayBot PowerShell module and Discord bot.
document_type: history
audience: users
applies_to: BATCRelayBot 1.4.1
updated: 2026-09-08
---

# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries describe what changed for users. For the reasoning behind a change,
see the commit that made it.

## [Unreleased]

### Changed

- **The commands no longer print their result object.** `Install-BATCRelayBot`,
  `Uninstall-BATCRelayBot`, `Edit-BATCRelayBotConfig` and
  `Get-BATCRelayBotStatus` returned a result that nothing consumed, so
  PowerShell dumped it to the screen as a `Name / Value` table underneath the
  report the command had just written - install paths listed a second time,
  `Success` in the middle of the output, and quitting the config editor shown
  as a table saying "Cancelled by the user".

  Pass **`-PassThru`** to get the object back for scripting. This is a breaking
  change for anything that captured a return value:

  ```powershell
  $result = Install-BATCRelayBot -PassThru
  ```

- **The installer says each thing once.** Success was announced three times over
  - a banner, a heading and a sentence - and the closing message ran to 98 lines
  including four troubleshooting recipes that belong in the documentation. It
  now ends with one green line, the three paths, the commands the user has and
  where each is explained, and links to the guides.

- **Download links appear where they are needed, not everywhere.** The
  prerequisite status in phase 2 listed a link under each component, and phase 3
  printed them again beside whatever was actually missing. Phase 2 reports
  status only; the links are printed once, by whichever path stops the install.

- **VoiceMeeter now reports its version.** It was read from the registry alone,
  so an installation found through the filesystem showed a bare `FOUND` while
  BeyondATC beside it showed a version. The executable is asked when the
  registry has nothing.

### Fixed

- **An uninstall that could not delete a file no longer reports itself as
  tidy.** A file handle outlives the process that held it by a moment, so
  removing the installation directory immediately after stopping the bot failed
  on `bot_error.log` - and the next step, which only ever looked at a different
  folder, printed "Nothing to clean up" underneath it. The removal now retries
  while handles clear, and anything still on disk is listed by path with the
  reason it stayed.

### Changed

- **The uninstaller says each thing once.** Its "what will be removed" screen
  opened a second banner under the caller's heading, printed the installation
  path twice more, listed every log file a second time, and ended with a
  disk-space figure reading "Approximately: 0.01 MB". The confirmation warned
  that removing Python or FFmpeg can break other software whether or not either
  had been chosen; it now lists only what was approved, and says `None` when
  nothing was.

- **The confirmation word is `uninstall`, not `yes`.** Nine considered
  characters are a different act from three reflexive ones.

- **The config editor stays open.** It exited after a single change, so
  correcting two fields meant starting it again and reading the same warnings
  a second time. It now returns to its menu, which shows the value it just
  wrote, and `-PassThru` reports every field changed in the session.

- **The editor no longer prints its title twice** - "BATCRelayBot Configuration
  Editor" directly above "BATCRelayBot Configuration" - and no longer says
  "No changes made" on the way out when changes were made. The restart reminder
  for a running bot is given once, at the end, and only if something changed.

- **The manual steps afterwards are correct.** They told users to remove
  VoiceMeeter through Control Panel, which leaves its audio drivers behind;
  VB-Audio's own installer is what removes it. BeyondATC was never mentioned
  although it is not removed either. Both are now named, with their vendors'
  pages.

- **The removal log stays in the installation directory** as `uninstall.log`.
  It was written to a second folder under Roaming, so removing an installation
  created a directory elsewhere in the profile and left a timestamped file
  there on every run. The directory now survives holding that log and nothing
  else, and any older Roaming folders are cleaned up.

### Removed

- **"Continue without installing" is gone** from the missing-tool prompt. The
  bot cannot run without Python or FFmpeg, so continuing only moved the failure
  further from its cause. The choice is now a single question that defaults to
  installing; declining shows the links and stops.

- **The uninstaller no longer offers to remove the PowerShell module.**
  Uninstalling the module that is running the uninstaller is a separate
  decision; the summary prints the one command that does it.

## [1.4.1] - 2026-09-08

A hotfix for a release that could not be installed.

### Fixed

- **1.4.0 could not be installed from PSGallery.** The package was missing
  `bot.py`, `requirements.txt` and `config.example.json`, so
  `Install-BATCRelayBot` stopped with "requirements.txt not found in any known
  location" before writing anything. `Publish-Module` packages the module
  folder, and those three live above it. `BATCRelayBot.nuspec` declared them and
  looked like the safeguard against exactly this - `Publish-Module` never reads
  a nuspec. Nothing caught it because every test ran in a checkout, where the
  installer finds the files through its relative-path fallbacks.

### Security

- **The install log no longer records Discord server and channel IDs.** They
  were written in plain text beside the redacted token, while the same rule
  covers both. Every message written to the log is redacted, so a value added
  later is covered without anyone having to remember.

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
