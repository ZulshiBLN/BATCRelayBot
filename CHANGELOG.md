# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
