# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-09-07

Minor rather than patch: the config file schema changed. Existing
`config.json` files are migrated automatically on the next install.

### Fixed (CRITICAL) - the installed bot could never start

- **config.json did not match what bot.py reads.** The installer wrote
  `server_id` and `channel_id`; bot.py requires `guild_id` and
  `voice_channel_id`. `audio_device_name` - the recording device the bot
  streams from - was never written or even asked for. Every installation
  since v1.0.0 produced a config that bot.py rejected at startup. The
  installer now writes the schema its consumers actually read.
- **Discord IDs were written as JSON strings.** discord.py matches guilds and
  channels on int, so a quoted ID resolved to nothing and the bot logged
  "not found" and idled. They are now written as numbers.
- **`Start-BATCRelayBot` never received the fields it requires.**
  `voicemeeter_process_name`, `batc_path` and `batc_process_name` were absent
  from every generated config, and `voicemeeter_path` pointed at a directory
  where an executable was expected.
- **Auto-install could never satisfy the readiness check.** The Phase 4b
  handler ran winget and returned without re-detecting anything, so the check
  that followed still saw the tool as missing and refused to install - after
  the user had already entered their token, server ID and channel ID. There
  was a second, working copy of the same logic sitting unreachable inside
  `Start-Installation`. There is now one implementation, and success is
  decided by detection rather than by winget's exit code.
- **`exit` inside module functions terminated the whole PowerShell session,**
  closing the window before any error could be read. v1.3.16 pauses before
  the exit; the exits themselves are now `return`.
- **No log existed for the most common failures.** The log directory was
  created in installation step 1, so anything that failed during detection,
  credential entry or the readiness check left no trace. Logging now starts
  before the first thing that can fail.

### Fixed - prerequisite detection

- Python installed for all users (HKLM only) was never found: only HKCU was
  searched. HKLM, WOW6432Node and the `py` launcher are now included.
- The Microsoft Store alias at `WindowsApps\python.exe` - a zero-byte stub
  that opens the Store - could be reported as a working interpreter. Every
  candidate is now verified by running it, and interpreters older than 3.10
  are reported with the version that was found.
- BeyondATC was only looked for under `Program Files` and LocalLow, missing
  any install on another drive. The uninstall registry entries are now read.
- VoiceMeeter detection returns the executable and process name, not just the
  directory, so the launcher can actually start it.
- `Write-ConfigFile` wrote a UTF-8 BOM despite documenting that it did not.

### Changed

- **Phase order.** Prerequisites are resolved before any credentials are
  requested, so a missing tool can no longer discard what was just typed.
- **VoiceMeeter no longer blocks the installation.** It has to come from
  VB-Audio's own installer, so the installer explains what to do and lets the
  user decide whether to continue. BeyondATC is informational only: it is
  optional, commercial software, and `Start-BATCRelayBot` no longer refuses
  to run without it.
- **The audio device is chosen from a list** produced by the same ffmpeg the
  bot will use, instead of being typed by hand.
- `Show-PrerequisitesInfo` takes the detection results instead of running a
  second, independent detection pass.
- Discord User-Agent follows the documented `DiscordBot ($url, $version)`
  format.
- `Start-BATCRelayBot` no longer changes the caller's working directory.
- bot.py passes `ffmpeg_path` to discord.py instead of relying on ffmpeg
  being on PATH.

### Fixed - a stopped bot could not be stopped

- **`Stop-BATCRelayBot` could orphan a running bot permanently.** It treated
  `bot.pid` as the only source of truth: a stale PID made it delete the file
  and report "not running", after which every later call said the same while
  the process kept rejoining the voice channel. Closing PowerShell or
  uninstalling the module changes nothing - the Python process is independent
  of both. The PID file is now a hint, with the actual process as fallback.
- **`!BATCleave` was undone by the watchdog within ten seconds,** so there was
  no chat command that could get the bot out of a channel. It now pauses the
  relay until `!BATCjoin`.
- **New `!BATCshutdown` command** stops the bot process from chat, for exactly
  the case where the PowerShell side can no longer reach it. Requires the
  Administrator permission.
- `!BATCstatus` reports whether the relay is paused.

### Changed - chat commands and startup behaviour

- **Starting the bot no longer joins a voice channel.** The process comes
  online and stands by; relaying begins on an explicit `!BATCjoin`. This lets
  the bot run permanently, or start with Windows, without occupying the
  channel when nobody is flying. Previously the watchdog joined within ten
  seconds of startup with no way to prevent it.
- **All commands are now `BATC`-prefixed** so they cannot collide with other
  bots in the same server: `!BATCjoin`, `!BATCleave`, `!BATCstatus`,
  `!BATCrestart`, `!BATCshutdown`, `!BATChelp`. Names are case-insensitive,
  and `!BATCrestart_stream` remains as an alias.
- Command replies read the configured guild's voice state rather than
  whichever server the command was typed in, so running a command from a
  second server no longer reports the wrong state.

### Security

- The bot token is redacted from all log output and never partially printed.
- `!shutdown` is restricted to administrators so any server member cannot stop
  the relay.
- `SecureString` conversion frees its unmanaged buffer, which previously left
  the token in memory for the life of the session.

### Tests

- New `ConfigContract.Tests.ps1` verifies the installer's output against the
  keys bot.py and `Start-BATCRelayBot` actually declare, reading both lists
  from their source so the two cannot drift apart again. The previous
  `Start-Installation` test asserted the broken schema, which is why the
  mismatch survived sixteen releases.
- `Start-Installation` tests no longer run pip for real or write into the
  developer's own installation directory.
- Suite goes from 270 passing / 9 failing to 298 passing / 0 failing.

## [1.3.16] - 2026-08-31 (HOTFIX)

### Fixed (CRITICAL)
- **Installer crash on error:** PowerShell now pauses before exit, allowing users to see error messages
- **Phase 4b unreachable:** Auto-install prompt now displays when prerequisites missing (moved before summary check)
- **Error visibility:** Installation failures now show pause prompt instead of instant window close

### Impact
Users can now see what went wrong during installation and access the auto-install functionality for missing tools.

## [1.3.15] - 2026-08-31

### Security (CRITICAL)
- **S1:** Bot token fully redacted in installation summary (no partial display in logs/console)
- **S2:** config.json restricted to current user only via NTFS ACLs (prevents unauthorized access)
- **S3:** Sanitized sensitive data from logs (winget output, Discord API errors no longer exposed)

### Design & Robustness (HIGH)
- **D1:** Phase 4b auto-install confirmation for missing tools (ADR-005 compliant 6-phase structure)
  - Users can choose: auto-install, manual install, or skip
  - Prompt only appears when tools are actually missing
- **R3:** Installation now fails if critical prerequisites still missing after auto-install attempt
- **R6/R7:** Multi-level path resolution for requirements.txt and bot.py (works from any directory)

### Enhancement & Maintenance (MEDIUM/LOW)
- **D2-Paths:** Replaced all hardcoded `C:\Program Files` paths with environment variables (fixes non-English Windows)
- **D3:** Token validation retry messages now show attempt counter (e.g., "attempt 2/3")
- **R5:** Log directory guaranteed to exist before writing (prevents silent log failures)
- **S3b:** Error messages sanitized (no raw exception details exposed to users)
- **Migration:** Phase 0b auto-applies ACL security to existing v1.3.14 configurations

### Technical Details
- Prompt count reduced to ADR-005 compliance (3 mandatory + 1 conditional)
- ACL migration handles permission failures gracefully (non-blocking)
- Environment variable paths support non-English Windows installations
- All fixes backward-compatible with v1.3.14 installations

## [1.3.14] - 2026-08-31

### Fixed
- Fixed Discord API token validation failure in installer (User-Agent header compliance)
- Improved error messages for Discord API connection failures (contextual guidance)
- Removed debug output that exposed exception details (security fix)

### Technical Details
- User-Agent header now includes "DiscordBot" prefix as required by Discord API (Issue #4908, #6473)
- Token validation failures now provide specific guidance (401 vs 403 vs network errors)
- Cloudflare blocking issue resolved through proper User-Agent formatting
- Installer token validation now succeeds for valid bot tokens

## [1.3.13] - 2026-08-30 (HOTFIX)

### Fixed (CRITICAL)
- Correct winget installation path detection for Python and FFmpeg (AppData, not Program Files)
  - Fixes auto-install detection when using `winget install`
  - Handles nested version directories (e.g., ffmpeg-9.0.1-full_build\bin\)
- Fix PowerShell environment variable syntax in VoiceMeeter detection
  - Changed from `$env:PROGRAMFILES(x86)` to `${env:ProgramFiles(x86)}` (braces required for parentheses)
  - Corrected path casing (ProgramFiles, not PROGRAMFILES)
- Add AppData LocalLow path for BeyondATC detection (official config location)
  - Improved detection of optional BeyondATC installations
- Replace UTF8NoBOM with UTF8 encoding for PowerShell 5.1 compatibility
  - UTF8NoBOM only supported in PowerShell 6.0+ (Core)
  - Fix enables install.log creation on Windows PowerShell 5.1 systems
  - Affects both installation and removal logging
- Add defensive parameters to Discord token validation (suppress prompts)

### Technical Details
- Verified against PowerShell 5.1 and user-tested installation paths
- All logging now functional on PowerShell 5.1+
- Path detection priority: AppData (winget) → Program Files → Registry → PATH

## [1.3.12] - 2026-08-30 (HOTFIX)

### Fixed (CRITICAL)
- VoiceMeeter detection now finds installations with correct paths (C:\Program Files\VB\... not VB-Audio)
- VoiceMeeter detection searches registry (HKLM, HKCU, WOW6432) + filesystem + wildcard for 100% coverage
- FFmpeg auto-install now works: PowerShell PATH refreshed after winget install
- FFmpeg detection checks common path first before Get-Command fallback

### Important Note
**v1.3.11 should not be used.** If you installed v1.3.11, update to v1.3.12 immediately:
```powershell
Update-Module BATCRelayBot
```

Both critical bugs (VoiceMeeter detection + FFmpeg auto-install) are now fixed in v1.3.12.

## [1.3.11] - 2026-08-30 (WITHDRAWN)

### Added
- Auto-detect VoiceMeeter installation path (flexible registry search for multiple installation variants)
- Auto-install Python and FFmpeg via winget (interactive setup with re-detection)
- Improved prerequisite validation with better path detection

### Fixed
- VoiceMeeter detection: Now finds installations with variant DisplayNames (e.g., "VB\Voicemeeter")
- PowerShell security warning in bot token input (added -UseBasicParsing flag)
- Config editor field name mappings (token → bot_token, channel_id → voice_channel_id)
- Uninstaller return value causing "aborted" message on valid installations
- Box-drawing character encoding corruption in uninstaller screens
- GitHub Actions workflow: Fixed missing pytest and pytest-asyncio in test pipeline

### Known Issues
- Edit-BATCRelayBotConfig disabled for v1.3.10 (coming in v1.3.11) — use manual JSON editing for now
  - See plans/todo/CONFIG-EDITOR-BUGS-ANALYSIS.md for details

## [1.3.9] - 2026-08-30

### Fixed
- Download bot files from GitHub if not in module directory (PSGallery limitation)
- Fallback mechanism: try local copy first, then GitHub Raw URL
- Proper error handling for download failures
- Works reliably with PSGallery-installed modules

## [1.3.8] - 2026-08-30

### Fixed
- Correct path calculation for PSGallery module installation (use 1 parent, not 2)
- Files are now correctly found in Modules\BATCRelayBot directory when installed via Install-Module

## [1.3.7] - 2026-08-30

### Fixed
- Add .nuspec file to include bot.py, requirements.txt, config.example.json in PSGallery package
- These files were not being included in PSGallery publish, causing installation failures

## [1.3.6] - 2026-08-30

### Fixed
- Fix path calculation for copying bot files (requirements.txt, bot.py, config.example.json)
- Was using 3 parents instead of 2, causing files to not be found
- Add logging for file copy operations

## [1.3.5] - 2026-08-30

### Added
- Install logging to file (install.log in bot directory)
- Better pip install error detection and reporting
- Log file path shown in error messages

### Improved
- More detailed pip install progress messages
- Check if requirements.txt exists before trying to install
- Improved error messages with actionable information

## [1.3.4] - 2026-08-30

### Improved
- Add pause on error in Install-BATCRelayBot (window stays open for troubleshooting)
- Better error messages with full exception details
- Visual separator for error output

## [1.3.3] - 2026-08-30

### Improved
- Better VoiceMeeter installation error handling
- Try multiple package versions (base + Potato) if first fails
- Detailed error messages explaining common failure reasons
- Allow continuing setup without VoiceMeeter (with warning)

## [1.3.2] - 2026-08-30

### Fixed
- Correct VoiceMeeter winget package ID casing (VB-Audio.Voicemeeter)
- Fixed installation failures due to incorrect package ID lookup

## [1.3.1] - 2026-08-30

### Added
- Automatic VoiceMeeter installation path detection during setup
- Skip user prompt for VoiceMeeter path if auto-detection succeeds

### Changed
- Simplified setup process: fewer interactive prompts
- Updated README to document VoiceMeeter auto-detection

### Fixed
- Correct VoiceMeeter winget package ID casing (VB-Audio.Voicemeeter)
- Fixed installation failures due to incorrect package ID

### Technical
- Auto-detect VoiceMeeter from standard winget path
- Graceful fallback to manual entry if auto-detection fails

## [1.3.0] - 2026-08-30

### Added
- Automatic VoiceMeeter installation path detection during setup
- Skip user prompt for VoiceMeeter path if auto-detection succeeds

### Changed
- Simplified setup process: fewer interactive prompts
- Updated README to document VoiceMeeter auto-detection

### Technical
- Auto-detect from standard winget installation path: `C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe`
- Graceful fallback to manual path entry if auto-detection fails

## [1.2.0] - 2026-08-30

### Added
- Comprehensive Architecture Decision Records (ADRs) for design documentation
  - ADR-001: VoiceMeeter selection rationale
  - ADR-002: PowerShell module vs standalone script decision
  - ADR-003: AppData\Local installation path justification
  - ADR-004: Task-based polling vs event-driven architecture
- Enhanced async function test coverage for bot lifecycle

### Fixed
- Improved test coverage for async functions (connect_and_stream, watchdog, shutdown_watcher)
- Added comprehensive command registration tests
- Cleaned up .gitignore duplicate entries (reduced from 81 to 60 lines)

### Changed
- Test suite now includes mock-based async testing patterns

## [1.1.0] - 2026-08-30

### Added
- Bot installation now automatic in `$env:USERPROFILE\AppData\Local\BATCRelayBot`
- `Install-BATCRelayBot` automatically copies bot.py and requirements.txt from module
- VoiceMeeter uninstall support in `Uninstall-BATCRelayBot` (with user confirmation)

### Changed
- All functions now use `BotPath` parameter instead of `ProjectPath`
- Default bot path changed from current directory to AppData\Local
- Installation simplified: no need to navigate to project directory
- Updated help documentation for all functions

### Fixed
- Installation now properly copies bot files to installation directory
- Uninstall now handles all three prerequisites (Python, ffmpeg, VoiceMeeter)

## [1.0.0] - 2026-08-30

### Added
- PowerShell module for BATC Relay Bot with full automation
- `Install-BATCRelayBot` - Installs prerequisites (Python, ffmpeg, VoiceMeeter) and generates config
- `Start-BATCRelayBot` - Starts the bot and associated services in the background
- `Stop-BATCRelayBot` - Cleanly stops the bot and services
- `Get-BATCRelayBotStatus` - Reports bot status and uptime
- `Uninstall-BATCRelayBot` - Removes configuration and optionally uninstalls prerequisites
- Automated VoiceMeeter detection and installation via winget
- Python Discord bot with voice channel streaming
- Discord commands: `!status`, `!restart_stream`, `!leave`
- Comprehensive README with setup steps and troubleshooting
- MIT License
- Pester tests for PowerShell module
- pytest tests for Python bot with 80% coverage requirement
- GitHub Actions CI/CD pipeline for testing and publishing
- Architecture Decision Records (ADRs) for major design decisions

### Technical Details
- Windows 10/11 only (VoiceMeeter, ffmpeg, BATC compatibility)
- PowerShell 5.1+ support
- Python 3.10+ support
- Automatic audio routing from BeyondATC/other apps to Discord via VoiceMeeter virtual bus
