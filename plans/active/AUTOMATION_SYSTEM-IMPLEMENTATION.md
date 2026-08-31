# IMPLEMENTATION ROADMAP: Phase 0-10 Detailed Steps
## BATCRelayBot Automation System — Complete Execution Guide

**Document Purpose:** Step-by-step implementation details for all 10 phases  
**Audience:** Michel Brosche (implementer)  
**Timeline:** 12 weeks, 38-39 hours total  
**Status:** Ready to execute (all pre-conditions clarified)

---

## PRE-PHASE-0: GATE PHASE (Week 1, Days 1-2, 4 hours)

**Purpose:** Verify all 5 pre-conditions before Phase 0 begins  
**Owner:** Michel  
**Gate Decision:** Cannot proceed to Phase 0 until ALL 5 complete

### Task 1: Verify Pester Tests Exist (30 min)
**Status:** ✅ VERIFIED (33+ test files found)
- Unit tests: ✅ Found in `develop\tests\unit\`
- Integration tests: ✅ Found in `develop\tests\integration\`
- PowerShell tests: ✅ Found in `develop\tests\powershell\`
- Effort: 0h (already done)
- **Action:** NONE - tests exist

### Task 2: Test Pre-Commit Hook Compatibility (45 min)
**Status:** ❌ TODO
- **Requirement:** Test on PowerShell 5.1 ONLY (no 7.x support)
- **Command to run:**
```powershell
# Test PowerShell 5.1 version check
pwsh -Version 5.1 -Command "Write-Host 'Testing PS 5.1 compatibility'"
# Expected: Success
```
- **Decision Rule:** If fails → document workaround in Phase 1 (not blocker)
- **Owner:** Michel
- **Deadline:** Week 1 Wednesday

### Task 3: Enable Branch Protection (30 min)
**Status:** ❌ TODO
- **Location:** GitHub Settings → Branches
- **Apply to:** main + develop
- **Rules to enable:**
  - ✅ Require 1 approval for PRs
  - ✅ Require all status checks pass
  - ✅ Require branch up to date before merge
  - ✅ Block force pushes
  - ✅ Dismiss stale reviews
- **CODEOWNERS file:**
```
# Protect workflow files
.github/workflows/ @michel
scripts/ @michel
.git/hooks/ @michel
```
- **Owner:** Michel (GitHub admin)
- **Deadline:** Week 1 Thursday

### Task 4: Document 45 Specification Gaps (90 min)
**Status:** ❌ TODO
- **Deliverable:** `docs/automation/SPECIFICATION_GAPS.md`
- **Content:**
  - Hotfix version format: v1.3.13-hotfix1 ✅ (decided)
  - Rollback procedure: automated (decided) ✅
  - Concurrent releases: Distributed Lock (decided) ✅
  - Pre-release version format (e.g., v1.3.14-rc1)
  - Tag deletion & recreation procedure
  - Emergency release bypass procedure
  - Automation failure recovery steps
- **Owner:** Michel (domain knowledge)
- **Deadline:** Week 1 Friday

### Task 5: Write Governance Rules X.1-X.4 (90 min)
**Status:** ❌ TODO
- **Deliverable:** Update `COMPLIANCE.md` Section 13
- **Rules to document:**

**Rule X.1: Version Canonical Source**
```
Source of Truth: BATCRelayBot/BATCRelayBot.psd1::ModuleVersion = 'X.Y.Z'
All other files must match exactly.
Enforcement: Pre-commit hook BLOCKS if mismatch
Responsibility: Developer uses sync-versions.ps1
```

**Rule X.2: Version Synchronization Process**
```
Step 1: Edit .psd1 ModuleVersion = 'X.Y.Z'
Step 2: Run: pwsh scripts/sync-versions.ps1 -NewVersion "X.Y.Z"
Step 3: Edit CHANGELOG.md with release notes
Step 4: Commit (hook validates)
Step 5: git tag -a vX.Y.Z
Step 6: git push origin main --follow-tags
```

**Rule X.3: Pre-Commit Hook Bypass**
```
Bypass: git commit --no-verify
When permitted: Only with explicit approval (logged)
Review: All bypasses reviewed before merge
```

**Rule X.4: Release Approval Gate**
```
Authority: Michel (solo project)
Process: pwsh scripts/validate-release.ps1 → Michel approval → git tag
Validates: version format, consistency, git state
Blocks: tag if ANY check fails
```

- **Owner:** Michel
- **Deadline:** Week 1 Friday

### Gate Sign-Off
```
□ Task 1: Pester tests verified
□ Task 2: PowerShell compatibility tested
□ Task 3: Branch protection enabled
□ Task 4: Spec gaps documented
□ Task 5: Governance rules written
```
**Decision:** Cannot proceed to Phase 0 until ALL checked

---

## PHASE 0: SECURITY HARDENING (Weeks 1-2, Days 3-7, 4.5 hours)

**Purpose:** Establish security baseline before automation deployment  
**Owner:** Michel  
**Success Criteria:** All security controls in place and verified

### Step 0.1: Fix .nuspec Version (15 min)
**File:** `BATCRelayBot/BATCRelayBot.nuspec`
**Current:** `<version>1.3.6</version>` (WRONG)
**Change to:** `<version>1.3.13</version>`
**Verify:** `grep -n "version" BATCRelayBot/BATCRelayBot.nuspec`

### Step 0.2: Fix User-Agent Version (10 min)
**File:** `BATCRelayBot/Private/Get-DiscordConfiguration.ps1`
**Current:** `"BATCRelayBot/1.3.12"` (WRONG)
**Change to:** `"BATCRelayBot/1.3.13"`
**Verify:** `grep -n "User-Agent" BATCRelayBot/Private/Get-DiscordConfiguration.ps1`

### Step 0.3: Implement Secret Masking (30 min)
**File:** `.github/workflows/publish.yml`
**Add step before PSGallery upload:**
```yaml
- name: Mask secrets
  run: |
    echo "::add-mask::${{ secrets.PSGALLERY_API_KEY }}"
```
**Verify:** No token appears in GitHub Actions logs

### Step 0.4: Remove SkipPublisherCheck (15 min)
**Files:** Any install scripts using `Install-Module Pester`
**Current:** `Install-Module Pester -Force -SkipPublisherCheck`
**Change to:** `Install-Module Pester -Force` (remove SkipPublisherCheck)
**Reason:** Allow signature verification

### Step 0.5: Pin Python Dependencies (20 min)
**File:** `requirements.txt` or `requirements-dev.txt`
**Current:** `requests>=2.28.1` (loose versioning)
**Change to:** `requests==2.28.1` (exact version)
**All lines:** Change `>=` or `~=` to `==`
**Verify:** `cat requirements.txt | grep "=="`

### Step 0.6: Document 90-Day Token Rotation (30 min)
**Deliverable:** `docs/automation/TOKEN_ROTATION.md`
**Content:**
```
## PSGallery API Token Rotation (Every 90 Days)

1. Go to PowerShell Gallery account settings
2. Generate new API key
3. Update GitHub Secret: PSGALLERY_API_KEY
4. Test with mock publish
5. Rotate out old token (delete from gallery)
6. Log rotation in ROTATION_LOG.txt (date, who, confirmation)
```

### Step 0.7: Create CODEOWNERS File (15 min)
**File:** `.github/CODEOWNERS`
**Content:**
```
# Protect workflow files (prevent unauthorized CI changes)
.github/workflows/ @michel

# Protect automation scripts
scripts/ @michel
.git/hooks/ @michel

# Protect security rules
COMPLIANCE.md @michel
CLAUDE.md @michel
```

### Step 0.8: Verify All Security Controls (30 min)
**Checklist:**
- [ ] .nuspec is 1.3.13
- [ ] User-Agent is 1.3.13
- [ ] Secret masking in workflows
- [ ] SkipPublisherCheck removed
- [ ] Python dependencies pinned
- [ ] Token rotation procedure documented
- [ ] CODEOWNERS file created
- [ ] Branch protection enabled (from Pre-Phase-0)

---

## PHASE 1: TIER 1 — VERSION GOVERNANCE (Weeks 2-3, 4.5 hours)

**Purpose:** Implement version automation (proof-of-concept)  
**Owner:** Michel  
**Success Criteria:** All 5 version files stay synchronized automatically

### Step 1.1: Create Shared Version Module (45 min)
**File:** `scripts/version-manager.ps1`
**Purpose:** Single source of version extraction logic (used by pre-commit, GitHub Actions, release validation)
**Implementation:**
- Create function `Extract-Version` (universal parser for all 5 file types)
- Create function `Validate-VersionConsistency` (compare all versions)
- Create function `Sync-Versions` (update dependent files)
- See IMPROVED_MASTER_AUTOMATION_PLAN.md Part 1 for complete code
**Test:**
```powershell
& (Join-Path $ProjectRoot "scripts/version-manager.ps1") -Operation Validate
# Expected: IsValid = $true
```

### Step 1.2: Implement Pre-Commit Hook (60 min)
**File:** `.git/hooks/pre-commit`
**Bash wrapper:**
```bash
#!/bin/bash
pwsh "$(git rev-parse --show-toplevel)/.git/hooks/pre-commit.ps1"
exit $?
```
**PowerShell script:** Call version-manager.ps1 with Validate operation
**Test:** 
```bash
git commit -m "test" # Should succeed if versions match
# Edit .psd1 version to wrong value
git commit -m "test" # Should BLOCK
```

### Step 1.3: Implement Sync-Versions Script (60 min)
**File:** `scripts/sync-versions.ps1`
**Usage:** `pwsh scripts/sync-versions.ps1 -NewVersion "1.3.14"`
**Implementation:**
- Validate version format (X.Y.Z)
- Update .nuspec
- Update User-Agent
- Update Install display
- Show git diff
- Instructions for user to commit
**Test:**
```powershell
# Edit .psd1 to 1.3.14
pwsh scripts/sync-versions.ps1 -NewVersion "1.3.14"
# Verify all 4 other files updated
git diff
```

### Step 1.4: Implement Release Validation Script (45 min)
**File:** `scripts/validate-release.ps1`
**Usage:** `pwsh scripts/validate-release.ps1` (before git tag)
**Checks:**
- On main branch? ✓
- Version is semver (X.Y.Z)? ✓
- All 5 versions match? ✓
- CHANGELOG has entry? ✓
- Git working tree clean? ✓
**Test:**
```powershell
# Make a change on main
pwsh scripts/validate-release.ps1
# Expected: PASS if all checks pass, WARN if issues
```

### Step 1.5: Create GitHub Actions Workflow (60 min)
**File:** `.github/workflows/version-check.yml`
**Trigger:** PR to main/develop
**Steps:**
- Extract version from .psd1
- Compare with .nuspec
- Compare with User-Agent
- Compare with Install display
- Compare with CHANGELOG
- Fail if ANY mismatch
**Test:** Create PR with version mismatch → workflow blocks ✓

### Step 1.6: Document Version Process (30 min)
**Deliverable:** Update `docs/automation/RELEASE.md` Section 1
**Content:**
- When to bump version
- Step-by-step version bump process
- sync-versions.ps1 usage
- validate-release.ps1 usage
- troubleshooting

### Step 1.7: Verify All Version Automation (30 min)
**Checklist:**
- [ ] version-manager.ps1 created + tested
- [ ] Pre-commit hook blocks mismatches
- [ ] sync-versions.ps1 updates all 4 files
- [ ] validate-release.ps1 passes with good versions
- [ ] GitHub Actions workflow catches mismatches
- [ ] RELEASE.md documents the process

---

## PHASE 2: TIER 2 — CODE QUALITY (Week 3, 4 hours)

**Purpose:** Automated code quality checking  
**Owner:** Michel  
**Success Criteria:** 100% of code violations caught before commit

### Step 2.1: Configure PSAnalyzer (60 min)
**Files:**
- Create `.github/linters/.editorconfig`
- Create `PSScriptAnalyzerSettings.psd1`
**Rules:** PowerShell best practices, no hardcoded credentials
**Test:** Run on existing code, fix violations

### Step 2.2: Implement Secret Detection Hook (45 min)
**Tool:** truffleHog
**File:** `.git/hooks/pre-commit` (add to existing)
**Check:** Scan for Discord tokens, API keys, credentials
**Block:** Commit if secrets detected

### Step 2.3: Add Python SAST (Bandit) (45 min)
**For:** discord.py bot code
**GitHub Actions:** Add step to publish.yml
**Check:** Security issues in Python code
**Fail:** If HIGH severity issues found

### Step 2.4: Windows Installer Testing (60 min)
**Test:** Run installer on clean Windows VM
**Verify:**
- Installation completes
- Version display shows correct version
- Bot starts successfully

### Step 2.5: Verify Code Quality Automation (30 min)
**Checklist:**
- [ ] PSAnalyzer config created
- [ ] Secret detection working
- [ ] Python SAST running
- [ ] Windows installer tested
- [ ] All 4 components verified

---

## PHASE 3: TIER 2 — TESTING & VALIDATION (Weeks 4-5, 3.5 hours)

**Purpose:** Automated testing on every PR and merge  
**Owner:** Michel  
**Success Criteria:** 100% of test failures caught before merge

### Step 3.1: Configure Pester in GitHub Actions (90 min)
**File:** `.github/workflows/test.yml`
**Trigger:** Every push, every PR
**Steps:**
- Run on ubuntu-latest
- Run on windows-latest (VoiceMeeter compatibility)
- Fail if tests fail
- Generate coverage report

### Step 3.2: Add Code Coverage Reporting (45 min)
**Tool:** Pester code coverage
**Report:** Coverage percentage in PR comments
**Gate:** Fail if coverage drops below 70%

### Step 3.3: Test on Multiple Environments (45 min)
**Environments:**
- Windows 10 (current)
- Windows 11 (new)
- PowerShell 5.1 (mandatory)
**Verify:** Tests pass on all

### Step 3.4: Verify Testing Automation (30 min)
**Checklist:**
- [ ] Pester runs on GitHub Actions
- [ ] Tests fail if code is broken
- [ ] Coverage report generates
- [ ] Multiple environments tested

---

## PHASE 4: TIER 2 — DEPENDENCIES & RELEASE (Weeks 5-6, 6 hours)

**Purpose:** Automated dependency management and release  
**Owner:** Michel  
**Success Criteria:** Dependencies updated within 48h, releases fully automated

### Step 4.1: Configure Dependency Scanning (90 min)
**Tool:** GitHub Dependabot
**Setup:**
- Weekly scan for outdated packages
- Auto-create PRs for updates
- Include: discord.py, psutil, etc.
**Test:** Create test PR with outdated package

### Step 4.2: Implement Release Workflow (120 min)
**File:** `.github/workflows/release.yml`
**Trigger:** git tag vX.Y.Z
**Steps:**
1. Validate tag format
2. Extract version from tag
3. Verify version matches .psd1
4. Run tests
5. Build module package
6. Create GitHub Release (from CHANGELOG)
7. Publish to PSGallery
8. Create post-release report
**Test:** Mock release with v1.3.14 tag

### Step 4.3: Implement Rollback Workflow (45 min)
**File:** `.github/workflows/rollback.yml`
**Trigger:** Manual (workflow_dispatch)
**Steps:**
1. Delete tag from GitHub
2. Create rollback release note
3. Undo PSGallery publish (if possible)
4. Create tracking issue
**Test:** Rollback mock v1.3.14

### Step 4.4: Add Token Masking to Release Workflow (30 min)
**In release.yml:** Mask PSGallery token before publish
**Verify:** Token never appears in logs

### Step 4.5: Verify Dependencies & Release Automation (30 min)
**Checklist:**
- [ ] Dependabot configured
- [ ] Release workflow executes end-to-end
- [ ] PSGallery publish succeeds
- [ ] Rollback procedure works
- [ ] Token never leaks

---

## PHASE 5: OBSERVABILITY & MONITORING (Weeks 6-7, 3.5 hours)

**Purpose:** Early detection of automation failures  
**Owner:** Michel (with Claude drafts)  
**Success Criteria:** Failures detected within 15 minutes, alerting works

### Step 5.1: Set Up Monitoring Dashboard (90 min)
**Type:** HTML dashboard (monitoring/)
**Metrics:**
- GitHub Actions job status (last 7 days)
- Release history (dates, versions, status)
- Test results (pass/fail trend)
- Dependency update status
**Access:** Local HTML file or web server
**Notification:** Dashboard refresh (Michel checks periodically)

### Step 5.2: Create Detection Workflows (60 min)
**Monitor:**
- Stuck GitHub Actions jobs (>30 min queued)
- Test failures
- Dependency scan failures
- Release pipeline failures
**Action:** Create issue if detected

### Step 5.3: Set Up Immutable Audit Logs (45 min)
**Logs:**
- releases.log (forever)
- tests.log (90 days)
- failures.log (forever)
- notifications.log (30 days)
**Format:** JSON (searchable, parseable)
**Retention:** Files stored in monitoring/logs/

### Step 5.4: Document Observability (30 min)
**Deliverable:** `docs/automation/MONITORING.md`
**Content:**
- How to read dashboard
- How to interpret metrics
- Where to find logs
- How to troubleshoot alerts

### Step 5.5: Verify Monitoring System (30 min)
**Checklist:**
- [ ] Dashboard displays all metrics
- [ ] Detection workflows trigger on failure
- [ ] Logs record all events
- [ ] Documentation complete

---

## PHASE 6: DOCUMENTATION & MAINTAINABILITY (Weeks 7-9, 7 hours)

**Purpose:** System is maintainable without Claude  
**Owner:** Michel (reviews) + Claude (drafts)  
**Success Criteria:** New developer can follow runbooks independently

### Step 6.1: Write Release Runbook (120 min)
**File:** `docs/automation/runbooks/RELEASE.md`
**Content:** 15-minute release procedure
- Step-by-step (from decision to published)
- Screenshots where helpful
- Troubleshooting section
- Edge cases (hotfixes, rollbacks)

### Step 6.2: Write Hotfix Runbook (60 min)
**File:** `docs/automation/runbooks/HOTFIX.md`
**Content:** 10-minute emergency release
- When to use hotfix
- Version format (v1.3.13-hotfix1)
- Abbreviated steps
- Recovery if broken

### Step 6.3: Write Rollback Runbook (45 min)
**File:** `docs/automation/runbooks/ROLLBACK.md`
**Content:** 5-minute recovery procedure
- When rollback needed
- Automated rollback steps
- Manual verification
- Post-rollback checklist

### Step 6.4: Write Troubleshooting Guide (90 min)
**File:** `docs/automation/runbooks/TROUBLESHOOT.md`
**Content:**
- Pre-commit hook broken → recovery
- GitHub Actions failed → diagnosis
- Release stuck → recovery
- Version mismatch → fix
- Token expired → update

### Step 6.5: Create Architecture Diagrams (90 min)
**File:** `docs/automation/ARCHITECTURE.md`
**Diagrams:**
- 4-layer automation stack (pre-commit → GitHub Actions → release → monitoring)
- Data flow (version changes → sync → validation → release)
- Decision tree (release vs hotfix vs rollback)

### Step 6.6: Write Onboarding Guide (60 min)
**File:** `docs/automation/onboarding/FIRST_DAY.md`
**Content:**
- Architecture overview (5 min)
- How to do first release (with RELEASE.md walkthrough)
- Where to find help
- Common questions answered

### Step 6.7: Verify Documentation (30 min)
**Test:** New developer (or Michel after delay) follows FIRST_DAY.md
- Can they understand architecture?
- Can they do a release from RELEASE.md?
- Can they troubleshoot from TROUBLESHOOT.md?

---

## PHASE 7: TESTING & VALIDATION (Weeks 8-9, 4 hours)

**Purpose:** All automation works end-to-end  
**Owner:** Michel (executor) + Claude (tests)  
**Success Criteria:** Full release flow succeeds v1.3.14-test → v1.3.14

### Step 7.1: Unit Test All Scripts (90 min)
**Test each:**
- version-manager.ps1 (all operations)
- sync-versions.ps1 (version formats)
- validate-release.ps1 (all checks)
- GitHub Actions workflows (syntax + logic)

### Step 7.2: Integration Test Version Automation (90 min)
**Test flow:**
1. Edit .psd1 to 1.3.14
2. Run sync-versions.ps1
3. Verify all 5 files updated
4. Pre-commit hook validates ✓
5. Create PR
6. GitHub Actions validates ✓
7. Merge
8. Run validate-release.ps1 ✓
9. Create tag ✓
10. Release workflow publishes ✓

### Step 7.3: Test Failure Scenarios (60 min)
**Scenarios:**
- Mismatch in .nuspec → pre-commit blocks ✓
- Forgot to run sync-versions.ps1 → GitHub Actions blocks ✓
- Manual tag with wrong version → release validation warns ✓
- Hotfix version (v1.3.13-hotfix1) → handled correctly ✓
- Rollback needed → procedure works ✓

### Step 7.4: Test on Real v1.3.14 Release (30 min)
**Execute full release:**
- Use actual v1.3.14 (not mock)
- Follow RELEASE.md
- Verify PSGallery publish
- Verify GitHub Release created
- Verify monitoring logs recorded

---

## PHASE 8: GO-LIVE & MONITORING (Weeks 9-10, 2 hours)

**Purpose:** System operational, monitoring active  
**Owner:** Michel  
**Success Criteria:** System healthy, logs recording, dashboards working

### Step 8.1: Verify All Components Live (60 min)
**Checklist:**
- [ ] Pre-commit hooks working locally
- [ ] GitHub Actions workflows running
- [ ] Release automation succeeds
- [ ] Monitoring dashboard active
- [ ] Audit logs recording

### Step 8.2: Monitor for First Week (60 min)
**Daily check:**
- Are there any automation failures?
- Are logs recording correctly?
- Is dashboard updating?
- Any false positives in alerts?

---

## PHASE 9: QUARTERLY REVIEW & ITERATION (Weeks 10-12, 2 hours)

**Purpose:** System review, identify improvements  
**Owner:** Michel  
**Cadence:** Quarterly (same as CLAUDE.md reviews)

### Step 9.1: Quarterly Audit (90 min)
**Review:**
- Automation effectiveness (failure rate, detection time)
- GitHub Actions quota usage
- PowerShell/Windows compatibility (new versions)
- Specification gap changes
- Documentation accuracy

### Step 9.2: Iteration Planning (30 min)
**Update:**
- COMPLIANCE.md (if rules changed)
- Runbooks (if procedures changed)
- ARCHITECTURE.md (if design changed)
- Phase 6 onboarding (if changed)

---

## SUCCESS CHECKLIST

**Timeline:** ✅ Week 1 (Pre-Conditions) → Week 12 (Complete)  
**Effort:** ✅ 38-39 hours (realistic)  
**Confidence:** ✅ 90%+ (all risks mitigated)

**Pre-Conditions (Must complete Week 1):**
- [ ] Pester tests verified (done)
- [ ] PowerShell compatibility tested
- [ ] Branch protection enabled
- [ ] 45 spec gaps documented
- [ ] Governance rules written

**Core Automation (Weeks 1-6):**
- [ ] Phase 0: Security hardening
- [ ] Phase 1: Version automation
- [ ] Phase 2: Code quality
- [ ] Phase 3: Testing
- [ ] Phase 4: Dependencies & release
- [ ] Phase 5: Observability

**Sustainability (Weeks 7-12):**
- [ ] Phase 6: Documentation (Claude drafts, Michel reviews)
- [ ] Phase 7: End-to-end testing
- [ ] Phase 8: Go-live
- [ ] Phase 9: Quarterly reviews

---

**Status:** READY TO EXECUTE  
**Next Step:** Complete Pre-Phase-0 tasks (Week 1)  
**Owner:** Michel Brosche
