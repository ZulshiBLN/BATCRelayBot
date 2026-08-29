# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
