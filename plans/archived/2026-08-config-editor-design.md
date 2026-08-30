# Config Editor Design Document

**Version**: 1.0  
**Date**: 2026-08-30  
**Status**: DONE (Approved 2026-08-30)
**Owner**: Michel Brosche  
**Archived**: 2026-08-30

---

## Executive Summary

Interactive configuration editor for BATCRelayBot allowing users to modify specific settings (Discord token, channel ID, output format) without re-running the installer. Targeted at users who need quick updates without full installation workflow.

---

## Problem Statement

**Current Flow**: User must re-run entire `Install-BATCRelayBot` to change a single config value.

**Desired Flow**: `Edit-BATCRelayBotConfig` → Select field → Enter new value → Validate → Save

**Scope**: Token, ChannelID, OutputFormat, BotActivity (optional fields)

---

## Architecture Overview

### Design Principles
1. **Non-destructive**: Never delete/corrupt config.json if operation fails
2. **Validated Input**: Each field has format validation before save
3. **Backup**: Automatic backup before any write
4. **Secure Token Handling**: Never echo/log token to console
5. **Selective Editing**: User chooses what to edit (not full reconfig)

### Component Structure

```
Edit-BATCRelayBotConfig (Public Main Function)
├── Confirm-ConfigEditorPrerequisites (Validate installation + file access)
├── Show-ConfigEditorMenu (Display interactive menu)
├── Get-ConfigFieldValue (Prompt for specific field)
│   ├── Get-DiscordToken (Secure token input)
│   ├── Get-DiscordChannel (Validate channel ID format)
│   ├── Get-OutputFormat (Menu selection)
│   └── Get-BotActivity (Optional text input)
├── Test-ConfigValue (Validate before saving)
├── Backup-ConfigFile (Atomic safe write)
└── Write-ConfigFile (JSON serialization)
```

### Configuration Fields (Editable)

| Field | Type | Validation | Example | Required |
|-------|------|-----------|---------|----------|
| token | string | Non-empty, alphanumeric | "MTk4NjIyNDgzNTgxODI4OA..." | Yes |
| channel_id | string | Numeric, 17-21 digits | "123456789012345678" | Yes |
| output_format | enum | [standard, compact, verbose] | "standard" | No |
| bot_activity | string | Max 128 chars | "Flying sim streaming" | No |

**Not Editable** (locked):
- install_path (move requires uninstall/reinstall)
- install_date (immutable)
- bot_name (module name)

---

## Implementation Plan (3 Phases)

### Phase 1: Pre-flight Checks
**Function**: `Confirm-ConfigEditorPrerequisites`

Steps:
1. Check installation directory exists
2. Verify config.json is readable/writable
3. Check for running bot (warn user)
4. Return validation result + file paths

**Output**: `@{ Valid, InstallPath, ConfigPath, BotRunning, Errors }`

**Tests**: 12 scenarios
- Installation found/not found
- File permissions (readable, writable, none)
- Bot running/not running
- config.json corrupted/missing

---

### Phase 2: Interactive Menu & Input Validation
**Functions**: 
- `Show-ConfigEditorMenu` - Display options with current values
- `Get-DiscordToken` - Secure token input (no echo)
- `Get-DiscordChannel` - Format validation
- `Get-OutputFormat` - Menu selection
- `Get-BotActivity` - Text input with length check
- `Test-ConfigValue` - Validate before save

**Menu Display**:
```
Current Configuration:
1. Discord Token:       [***REDACTED***] (xxxxxxxxx last 4 visible)
2. Channel ID:          123456789012345678
3. Output Format:       standard
4. Bot Activity:        Flying sim streaming

Select field to edit (1-4) or 'q' to quit:
```

**Input Validation**:
- Token: Regex for base64/alphanumeric pattern
- Channel: Numeric 17-21 digits
- Format: Enum check (standard/compact/verbose)
- Activity: Max 128 chars, no invalid JSON chars

**Output**: `@{ Field, Value, Valid, Message }`

**Tests**: 28 scenarios
- Each field valid/invalid input (4 fields × 2)
- Token edge cases (empty, too short, special chars)
- Channel format validation
- Format enum validation
- Activity length limits
- Menu navigation (quit, invalid selection)

---

### Phase 3: Safe Save & Verification
**Functions**:
- `Backup-ConfigFile` - Create timestamped backup
- `Update-ConfigJson` - Merge new value into JSON
- `Verify-ConfigChange` - Confirm written value matches

**Save Process**:
1. Read existing config.json
2. Create backup: `config.json.backup-20260830-143022`
3. Parse JSON safely (error handling)
4. Update single field
5. Serialize back to JSON (preserve formatting)
6. Write atomically (temp file + move)
7. Verify written value by re-reading

**Output**: `@{ Success, BackupPath, UpdatedFields, Errors }`

**Tests**: 18 scenarios
- Backup creation success/fail
- JSON parsing (valid/invalid config)
- Single field update
- Multiple field updates in sequence
- Write permission errors
- Verification after write
- Rollback on verification failure

---

## Success Criteria

### Functional
- [ ] User can edit token without losing other settings
- [ ] User can edit channel ID with format validation
- [ ] User can select output format from menu
- [ ] User can add/modify bot activity text
- [ ] Changes persist after bot restart

### Non-functional
- [ ] 58+ tests passing (100%)
- [ ] No config corruption on partial failure
- [ ] Secure token handling (never logged/echoed)
- [ ] Automatic backups for recovery
- [ ] Clear error messages on validation failure

### Security
- [ ] Token input masked from console
- [ ] No token logged to files
- [ ] Backup files secured (same perms as original)
- [ ] Atomic writes (no partial configs)

---

## Test Strategy

### Unit Tests (58 total)
- Phase 1: 12 tests (prerequisites)
- Phase 2: 28 tests (input validation)
- Phase 3: 18 tests (safe save/verify)

### Integration Tests
- Edit single field → verify persistence
- Edit multiple fields → sequence test
- Simulate bot running → warning message
- File permission errors → graceful handling

### Rollback Scenario
- Write fails → rollback to backup
- Verify backup integrity
- Confirm original config untouched

---

## Security Considerations

### Token Handling
```powershell
# WRONG: $token = Read-Host "Token"  # Echoes to console
# RIGHT: 
$PSDefaultParameterValues['Read-Host:AsSecureString'] = $true
$secureToken = Read-Host "Discord Token"
$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($secureToken)
)
```

### Backup Strategy
- Keep last 10 backups
- Name: `config.json.backup-YYYYMMDD-HHmmss`
- Auto-cleanup on edit (remove oldest if > 10)

### File Permissions
- Preserve original file permissions on backup
- Preserve original permissions on write

---

## Error Handling

### Validation Errors (Continue)
- "Token must be alphanumeric" → Reprompt
- "Channel must be 17-21 digits" → Reprompt
- "Activity max 128 chars" → Show count, reprompt

### Write Errors (Abort with Recovery)
- "Cannot write to config.json" → Rollback backup
- "JSON parsing failed" → Show syntax error
- "Verification failed" → Restore from backup

### User Errors (Graceful)
- Bot still running → Warn (don't block)
- Installation not found → Abort with path suggestion
- Config missing → Offer to restore from backup

---

## Future Enhancements (Out of Scope)

- [ ] Config validation against running bot
- [ ] Remote config management (API)
- [ ] Config versioning/history
- [ ] Advanced settings (logging level, timeouts)
- [ ] Config export/import

---

## Deployment Notes

### Installation
1. Add to PowerShell module (Public/ folder)
2. Update manifest to export function
3. Version bump (if included in release)

### User Experience
```
PS> Edit-BATCRelayBotConfig
BATCRelayBot Configuration Editor v1.0

Installation found: C:\Users\User\AppData\Local\BATCRelayBot
Bot status: Running (will pick up changes on restart)

Current Configuration:
1. Discord Token:       [***REDACTED***] (last 4: 8hA6)
2. Channel ID:          123456789012345678
3. Output Format:       standard
4. Bot Activity:        Flying sim streaming

Select field to edit (1-4) or 'q' to quit: 1

New Discord Token: [masked input]
Token updated successfully!
Backup created: config.json.backup-20260830-143022
```

---

## Timeline

- Phase 1 (Pre-checks): 1-2 hours
- Phase 2 (Menu + Input): 2-3 hours
- Phase 3 (Save + Verify): 1-2 hours
- Testing & QA: 2-3 hours
- **Total**: ~6-10 hours

---

## Files to Create

```
BATCRelayBot/
├── Public/
│   └── Edit-BATCRelayBotConfig.ps1
└── Private/
    ├── Confirm-ConfigEditorPrerequisites.ps1
    ├── Show-ConfigEditorMenu.ps1
    ├── Get-DiscordToken.ps1
    ├── Get-DiscordChannel.ps1
    ├── Get-OutputFormat.ps1
    ├── Get-BotActivity.ps1
    ├── Test-ConfigValue.ps1
    ├── Backup-ConfigFile.ps1
    └── Update-ConfigJson.ps1

tests/unit/
├── Confirm-ConfigEditorPrerequisites.Tests.ps1
├── Show-ConfigEditorMenu.Tests.ps1
├── Get-DiscordToken.Tests.ps1
├── Get-DiscordChannel.Tests.ps1
├── Get-OutputFormat.Tests.ps1
├── Get-BotActivity.Tests.ps1
├── Test-ConfigValue.Tests.ps1
├── Backup-ConfigFile.Tests.ps1
├── Update-ConfigJson.Tests.ps1
└── Edit-BATCRelayBotConfig.Tests.ps1
```

---

## Status

**Current**: PLANNING  
**Next**: Approval → Phase 1 Implementation  
**Approved By**: [Pending user review]

