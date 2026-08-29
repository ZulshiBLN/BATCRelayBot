# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
