# ADR-001: VoiceMeeter as Audio Routing Solution

**Date:** 2026-08-30  
**Status:** ACCEPTED  
**Author:** Claude (Project AI)

## Context

The BATC Relay Bot needs to capture audio from Windows applications (primarily BeyondATC) and stream it into Discord. Multiple audio routing solutions exist:

1. **VoiceMeeter** - Virtual audio device software with bus routing capabilities
2. **Windows WASAPI** - Direct Windows audio API
3. **Stereo Mix / Loopback** - Built-in Windows audio loopback
4. **Third-party routing software** (e.g., VB-Audio Voicemeeter Alternative)

## Decision

We selected **VoiceMeeter** as the audio routing solution.

## Rationale

### Why VoiceMeeter?

1. **Reliability** - VoiceMeeter is mature, stable, and widely used for audio routing
2. **Flexibility** - Multiple virtual buses (A1, A2, A3, B1-B2) allow complex routing scenarios
3. **User-friendly** - GUI makes configuration accessible to non-technical users
4. **Cross-application** - Works with any Windows application that supports audio output device selection
5. **Installation** - Available via winget for automated deployment
6. **No admin rights** - Can be installed per-user without administrator privileges
7. **Free/Freeware** - No licensing costs

### Why NOT other options?

- **Windows WASAPI** - Lower-level API, harder to integrate, not user-configurable
- **Stereo Mix/Loopback** - Not available on all systems, requires specific hardware support
- **Third-party alternatives** - Less mature, less community support, potentially less stable

## Consequences

### Positive
- Audio routing is transparent to BeyondATC application
- Users can configure routing without code changes
- Supports multiple simultaneous audio sources
- Portable across different Windows configurations
- Easy to test and debug with VoiceMeeter's GUI

### Negative
- Adds external dependency (VoiceMeeter must be installed)
- May require system restart after installation
- Users must manually configure audio routing (not fully automated)
- Windows-only solution (limits cross-platform future development)

## Related Decisions

- ADR-003: Installation path (AppData\Local) - chosen to keep VoiceMeeter separate from bot
- ADR-004: Manual audio routing config - required because VoiceMeeter needs user-specific setup

## Alternatives Considered

1. **WASAPI Direct** - Rejected for complexity
2. **Stereo Mix** - Rejected for unreliable hardware support
3. **Virtual Cable/Dante** - Rejected for cost and complexity
4. **Adobe Audition routing** - Rejected for license cost and complexity

## Implementation Notes

- VoiceMeeter installed via `winget install VB-Audio.VoiceMeeter`
- User configures routing via VoiceMeeter GUI (Section 3 of README)
- Bot captures from virtual output bus B1 using ffmpeg
- Graceful fallback: Installation continues if VoiceMeeter install fails (with warning)
