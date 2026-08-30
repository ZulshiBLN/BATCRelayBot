# Config Editor Critical Bug Analysis

**Status**: BLOCKED - Requires Major Refactor  
**Date**: 2026-08-30  
**Priority**: HIGH  
**Version Target**: v1.3.11 or later

---

## Summary

The Edit-BATCRelayBotConfig feature (v1.3.10) has **critical architectural flaws** that make it unsafe for production use. The config schema mismatch between installer and editor causes data corruption and silent failures. Multiple additional bugs prevent basic functionality.

**Recommendation**: Disable editor for v1.3.10 release. Schedule comprehensive refactor for v1.3.11+.

---

## Critical Bugs Found

### 1. Config Schema Mismatch (CRITICAL)
**Severity**: 🔴 CRITICAL - Silent data corruption  
**Impact**: Any token edit creates new field instead of updating existing one

**Details**:
- Installer creates: `bot_token`, `server_id`, `channel_id`, `voicemeeter_path`, `ffmpeg_path`, `python_path`
- Editor expects: `token`, `channel_id`, `output_format`, `bot_activity`
- When editing token: creates NEW `token` field while bot still reads `bot_token`
- User thinks change worked, but bot uses old credentials

**Files involved**:
- Start-Installation.ps1 (line 61 - creates "bot_token")
- Update-ConfigJson.ps1 (line 46 - maps "Token" to "token")
- Verify-ConfigChange.ps1 (line 29 - maps "Token" to "token")
- Show-ConfigEditorMenu.ps1 (line 31 - reads "config.token")

**Fix Required**: Choose one approach:
- Option A: Change installer to create "token" instead of "bot_token"
- Option B: Change editor to read/write "bot_token"
- Option C: Create migration path for existing configs

---

### 2. Token Masking Display Bug (MEDIUM)
**Severity**: 🟡 MEDIUM - UX issue  
**Screenshot**: Last 4 characters show as "****" instead of actual alphanumeric

**Details**:
```powershell
# Current (broken):
$tokenDisplay = if ($token -and $token.Length -gt 4) { 
    $token.Substring($token.Length - 4) 
} else { 
    "****" 
}
# Shows: ****
# Should show: last 4 chars of token
```

**Files**:
- Show-ConfigEditorMenu.ps1 (line 36)

**Fix**: Remove the conditional masking for display (should show actual last 4 chars)

---

### 3. Exception During Token Save (CRITICAL)
**Severity**: 🔴 CRITICAL - Complete failure to edit  
**Error Message**: `"The property 'token' cannot be found on this object"`

**Details**:
- User enters new token → clicks confirm
- Backup created successfully
- Update-ConfigJson.ps1 tries to set $config.token
- Property doesn't exist (config has "bot_token" not "token")
- Exception thrown
- Rollback to backup triggered
- **Result**: Token change fails silently, user thinks it worked

**Root Cause**: Fallout from bug #1 (schema mismatch)

---

### 4. Missing Server ID Editor (MEDIUM)
**Severity**: 🟡 MEDIUM - Inconsistent data model  
**Impact**: Server ID shown but not editable

**Details**:
- Installer collects and stores `server_id`
- Editor displays it but has no edit option
- User can't change server after initial setup without manual JSON edit

**Files**:
- Show-ConfigEditorMenu.ps1 (displays field but no option to edit)
- Need: Get-DiscordServer function or similar

---

### 5. Non-existent Fields in Editor (LOW)
**Severity**: 🟡 LOW - Creates unexpected config structure  
**Impact**: Config bloat, possible bot confusion

**Details**:
- Editor tries to edit `output_format` and `bot_activity`
- Installer never creates these fields
- Bot code likely doesn't use them
- Editing these creates new (unused) config entries

**Solution**: Determine if these are real features:
- If YES: Installer must create them, bot must use them
- If NO: Remove from editor

---

## Test Coverage Issue

**Problem**: Integration tests pass but real-world fails

**Evidence**:
- Edit-BATCRelayBotConfig.Integration.Tests.ps1 creates test configs with "token" field (matches editor expectations)
- Tests do NOT test against actual installer-generated configs
- All tests pass ✅
- **But**: Real user runs installer → gets config with "bot_token" → editor fails ❌

**Impact**: False sense of security. Tests give green light but feature is broken in production.

---

## Recommended Fix Strategy

### Phase 1: Immediate (v1.3.10 - this release)
- [ ] **Disable** the config editor from being called by users
  - Remove from Install-BATCRelayBot menu options
  - Add deprecation notice if user somehow calls it
- [ ] Document as "Coming in v1.3.11"
- [ ] Update README to note feature is not yet available

### Phase 2: Architecture (v1.3.11)
- [ ] **Decide on config schema**: `bot_token` or `token`?
- [ ] **Redesign** editor to match actual installer output
- [ ] **Add schema validation** before attempting edits
- [ ] **Create migration** for any v1.3.10 configs

### Phase 3: Implementation (v1.3.11)
- [ ] Rewrite all field mappings
- [ ] Add comprehensive config validation
- [ ] Add server_id editing capability
- [ ] Remove non-existent field handlers
- [ ] Fix display/masking bugs

### Phase 4: Testing (v1.3.11)
- [ ] Update integration tests to use actual installer-generated configs
- [ ] Add schema validation tests
- [ ] Test token change end-to-end with bot.py reading it
- [ ] Test all 6 configuration fields (if all are real)

---

## Files Requiring Changes

| File | Lines | Issue | Action |
|------|-------|-------|--------|
| Install-BATCRelayBot.ps1 | 3, 38+ | Menu option | Remove/disable |
| Show-ConfigEditorMenu.ps1 | 31-34, 36, 54-120 | Schema mismatch, display bug | Rewrite |
| Update-ConfigJson.ps1 | 46-50 | Field mapping | Fix |
| Verify-ConfigChange.ps1 | 28-33 | Field mapping | Fix |
| Confirm-ConfigEditorPrerequisites.ps1 | All | Schema validation | Add validation |
| bot.py | All | Config reading | Verify it reads correct fields |
| Edit-BATCRelayBotConfig.Integration.Tests.ps1 | All | Uses wrong schema | Update to use actual schema |

---

## Owner & Timeline

**Owner**: To be assigned (v1.3.11 development)  
**Effort Estimate**: 6-8 hours (architecture + implementation + testing)  
**Target**: Next release cycle

---

## Notes

- This analysis was conducted via independent agent audit (agent ID: a985f295edc1608c6)
- All findings verified against actual code
- Config Editor feature was released in v1.3.10 but is NOT recommended for production use
- Disabling now prevents user data corruption in the field
