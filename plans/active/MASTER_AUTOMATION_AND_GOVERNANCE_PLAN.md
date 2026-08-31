# Master Automation & Governance Plan
## BATCRelayBot: Systematic Automation of Recurring Processes

**Plan Owner:** Claude (working with Michel Brosche)  
**Status:** APPROVED (2-Agent validation complete, ready for pre-implementation review)  
**Date:** 2026-08-31  
**Objective:** Replace manual, error-prone recurring processes with external automation and systematic enforcement

---

## Executive Summary

**Problem:** 3 failed releases (v1.3.11-v1.3.13) with identical errors = **recurring manual processes are inherently error-prone** (33% failure rate). Version-bump process has 6+ steps over 20 minutes; under pressure, selective attention causes missed items.

**Root Cause:** Manual multi-step processes (15+ minutes, 6+ items) fail even with discipline because humans exceed working-memory capacity (~4 items). This is systemic, not specific to Claude.

**Solution:** Two-tier strategy:
1. **Tier 1 (Proof-of-Concept):** Version-Bump Governance — solve acute problem, validate automation approach
2. **Tier 2 (Strategic):** Comprehensive Automation — apply pattern to all recurring processes

**Target Effectiveness:** 75-85% (from 33% current) — realistic, not aspirational  
**Total Effort:** 27-29 hours (Phases 0-5 complete, amended) / 24-26 hours (core, Phases 0-4) / 11.25 hours (MVP, Phases 0-2)  
**Timeline:** Week 1-2 complete (with Phase 5 mandatory) / Week 1-2 core / Week 1 MVP  
**ROI:** Break-even within 2-3 releases (measurable: failure rate <10% = ~1-2 prevented failures/year × 500 tokens each)

---

## Two-Tier Architecture

### Tier 1: Version-Bump Governance (Proof-of-Concept)
**Why start here?** 3 identical failures = highest-confidence problem + fastest path to wins

**4 Critical Fixes (Pre-work: 25 min)**
- [ ] Fix .nuspec version (1.3.6 → 1.3.13)
- [ ] Fix GitHub Actions workflow (add User-Agent + Install-Display checks)
- [ ] Document --no-verify bypass risk (Rule X.4)
- [ ] Future enhancement: Git hook for tag prevention (Phase 6, optional)

**5 Implementation Phases (3.5h core)**
1. Canonical Version Registry (COMPLIANCE.md) — 0.5h
2. Governance Rules (CLAUDE.md) — 0.5h
3. Pre-Commit Hook (version check) — 1h
4. GitHub Actions (validation gate) — 1h
5. Documentation (automation explanation) — 0.5h

**Success Criteria:** Zero version mismatches in v1.3.14+

---

### Tier 2: Comprehensive Automation (Strategy)
**Why needed?** Version problems are SYMPTOM, not root cause. 6 other opportunities have same pattern.

**7 Automation Opportunities**
1. **Version Management** ← already detailed in Tier 1
2. **Pre-Release Checklist Automation** (2h) — 15 manual items → automated gates
3. **Code Quality Scanning** (4h with improvements) — PSAnalyzer + Python SAST + secret detection
4. **Automated Testing** (2h, conditional on Pester tests existing) — Pester on PR + Windows runner
5. **Dependency & Security Scanning** (2.5h) — weekly scheduled, auto-PRs
6. **Git Workflow Enforcement** (1h) — prevent wrong-worktree tags, force-push protection
7. **Automated Release Pipeline** (2.5h) — tag trigger → GitHub Release → PSGallery

**Success Criteria:** 
- 100% of code quality violations caught before commit
- 100% of test failures caught before merge
- Zero release failures due to version/checklist mismatches
- Failure rate: 33% (current: 3 of 9) → <10% (estimated)

---

## Implementation Roadmap

### Pre-Work (2h 45min) — Week 1 Day 1 **GATE PHASE + CRITICAL PRE-PHASE-0**

**Critical Pre-Phase-0 Items (do BEFORE Phase 0 security hardening starts):**
- [ ] **Add branch protection on main + develop** (prevent unapproved merges + require approval for .github/workflows/ changes)
- [ ] **Verify Pester test existence + audit coverage** (count tests, coverage %; critical blocker for Phase 3; if missing: +15-20h)
- [ ] **Test pre-commit hooks on PowerShell versions** (verify compatibility on PS 5.1, 7.4, 7.5+)

**Standard Pre-Work Items:**
- [ ] Sync .nuspec to 1.3.13
- [ ] Update GitHub Actions workflow (add User-Agent + Install-Display checks)
- [ ] Document --no-verify bypass rule (Rule X.4)

**Why This Order:** Security gates must be in place BEFORE Phase 0; Pester verification gates Phase 3; PowerShell testing gates Phase 1 implementation.

### Phase 0: Security Hardening (5-6h) — Week 1 Days 1-3 **MANDATORY**
- [ ] Secrets management policy (PSGallery token setup, rotation schedule, masking in logs)
- [ ] Pre-commit hook security (testing on PowerShell versions, verification mechanism)
- [ ] GitHub Actions security (branch protection, secret scoping per job, approval gates)
- [ ] Supply chain verification (package version pinning, signature verification, hash validation)

**Phase 0 DONE when (explicit acceptance criteria):**
- [ ] PSGallery token rotation schedule documented (90-day cycle)
- [ ] GitHub Actions secret masking implemented (`::add-mask::` before token use)
- [ ] Branch protection rules enabled on main + develop (require approvals)
- [ ] CODEOWNERS file created protecting .github/workflows/
- [ ] Pre-commit hooks verified on PowerShell 5.1, 7.4, 7.5+
- [ ] Python dependencies pinned to exact versions (requirements-dev.txt with ==X.Y.Z)
- [ ] Pester install: `-SkipPublisherCheck` removed (use `-Force` only if needed)
- [ ] Supply chain verification method = SHA-256 hash validation + dependency pinning
- [ ] Token masking tested in error paths
- [ ] Pre-Phase-0 security gates verified (branch protection, Pester audit, PS compatibility)**

### Phase 1: Tier 1 — Version Governance (4.5h) — Week 1 Days 3-4 + Week 2 Day 1
1. Canonical Registry → COMPLIANCE.md
2. Governance Rules (X.1-X.4) → CLAUDE.md
3. Pre-Commit Hook (version check) implementation + test
4. Pre-Push Hook (tag prevention) implementation + test [Bug 1 fix — prevents wrong-worktree tags]
5. GitHub Actions workflow + test
6. Documentation + Phase 0 merge

**Phase 1 DONE when:**
- [ ] Canonical version registry documented in COMPLIANCE.md
- [ ] Governance rules X.1-X.4 in CLAUDE.md
- [ ] Pre-commit hook passes on test files (version mismatch detection works)
- [ ] Pre-push hook blocks tags created outside main branch
- [ ] GitHub Actions version validation gate working (blocks merge if versions mismatch)
- [ ] Manual test: v1.3.14 mock bump passes all checks
- [ ] Bug 1 (worktree issue) prevented by pre-push hook
- [ ] All documentation updated

### Phase 2: Tier 2 — Code Quality (4h) — Week 2 Day 1
- PSAnalyzer config + pre-commit hook
- Secret scanning (truffleHog)
- Python SAST (Bandit for discord.py)
- Windows-specific testing setup

### Phase 3: Tier 2 — Testing & Validation (3.5h) — Week 2 Days 2-3
- Pester on GitHub Actions
- Code coverage reporting
- Windows runner testing
- Pre-release checklist automation

### Phase 4: Tier 2 — Dependencies & Release (5h) — Week 2 Days 3-4
- Dependency scanning workflow (weekly)
- Git workflow enforcement hooks
- Release pipeline automation
- Full testing + validation

### Phase 5: Documentation & Observability (2.5h) — Week 2 Days 4-5 **MANDATORY FOR SUSTAINABILITY**
- Architecture diagrams (how all pieces fit together)
- Troubleshooting runbooks (common failure scenarios + recovery)
- Observability metrics + dashboards (automation health monitoring)
- Rollback procedures (if any phase breaks)
- Knowledge transfer document (for future maintainers)

**Why Mandatory (not optional):** 
- Without Phase 5: Project trends toward unmaintainability in 2-3 years (no observability + no docs)
- With Phase 5: Sustainable, extensible, knowable system that Michel can maintain without Claude support
- Critical for long-term success and team scalability

---

## Effort Estimates (Amended per 6-Agent Validation)

| Component | Original | Amended | Risk | Notes |
|-----------|----------|---------|------|-------|
| **Pre-Work (Critical Pre-Phase-0 + Gate Phase)** | 0.75h | 2.75h | Low | +2h for branch protection setup + Pester audit + PS testing |
| **Phase 0: Security Hardening** | 3h | 5-6h | Medium | +2-3h for detailed implementation + 45 gaps closure |
| **Phase 1: Version Governance (POC) + Bug 1 Fix** | 3.5h | 4.5h | Low | +1h for pre-push hook (tag prevention, Bug 1 fix) |
| **Phase 2: Code Quality** | 4h | 4h | Medium | Unchanged (Windows test, secrets, Python SAST already included) |
| **Phase 3: Testing & Validation** | 3.5h | 3.5h | **HIGH** | **GATE: Pester must exist.** If missing: +15-20h additional |
| **Phase 4: Dependencies & Release** | 5h | 5h | Medium | GitHub Actions workflows, dependency scanning |
| **Phase 5: Documentation & Observability** | 2.5h (optional) | 2.5h (MANDATORY) | Low | **NOW MANDATORY** — critical for sustainability |
| **Integration & Testing (throughout)** | 2.25h | 2.5h | Medium | Validation testing across all phases + fallback testing |
| | | | |
| **MVP (Pre-Work + Phases 0-2)** | 11.25h | **11.25h** | — | **Week 1 only** (unchanged) |
| **CORE (Pre-Work + Phases 0-4)** | 19.75h | **24-26h** | — | **Week 1-2** (amended for depth + gaps) |
| **COMPLETE (Pre-Work + Phases 0-5, MANDATORY)** | 22h | **27-29h** | — | **Week 1-2** (Phase 5 moved to Week 2, now mandatory) |

**Realistic Range (per 6-agent validation):** 25-32 hours (Phase 5 mandatory; includes gaps + pre-Phase-0 items)  
**Most Likely:** 27-29 hours (assuming Pester tests exist, security complexity as estimated, gaps closure in scope)

---

## Success Criteria

### Quantifiable
- [ ] Zero version mismatches in v1.3.14+
- [ ] 100% code quality violations caught pre-commit
- [ ] 100% test failures caught before merge
- [ ] Security dependencies updated within 48h of patch
- [ ] Release time: 20 min → 2 min (automation triggered)
- [ ] Manual checklist items: 15 → 0
- [ ] Release failure rate: 33% → <10%

### Qualitative
- [ ] Developers experience immediate feedback (pre-commit)
- [ ] No "I forgot" failures (automation enforces)
- [ ] No context loss (automation persistent, not memory-dependent)
- [ ] Michel can maintain without Claude support (documentation, runbooks)
- [ ] Architecture is extensible (Phases 6+ can be added)

---

## Risk Assessment & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Pre-commit hooks slow development | Medium | Medium | Phase 0: optional locally, enforce in CI |
| Pester tests don't exist | **HIGH** | **CRITICAL** | **GATE:** Verify before Phase 3 (could add 15-20h) |
| GitHub Actions quota exceeded | Low | High | Monitor usage, optimize workflows |
| Secrets exposed in logs | Medium | **CRITICAL** | Phase 0: secret masking, no print statements |
| Pre-commit hook compromised | Medium | **CRITICAL** | Phase 0: hook signing + verification |
| Automation becomes unmaintainable | Medium | High | Phase 5: architecture docs, runbooks, troubleshooting |
| False positives in scanning | Medium | Low | Whitelist procedures, document in Phase 4 |

---

## Why Two Tiers?

**Tier 1 (Version Governance):**
- Solves the **acute problem** (3 identical failures)
- Provides **proof-of-concept** for automation approach
- **Validates** that pre-commit hooks + GitHub Actions actually work
- Can be completed in Week 1 (11 hours for MVP)

**Tier 2 (Comprehensive Automation):**
- Solves the **systemic problem** (cognitive overload on manual processes)
- Prevents **pattern repetition** (same error types won't repeat in other domains)
- Scales automation to **all recurring processes**
- Requires Tier 1 success as foundation

**Together:** Replace "Claude's memory" with "external enforcement"

---

## Next Steps

**Immediately (Today):**
1. ✅ Merge this plan (replace 2 separate plans)
2. ✅ Delete old plan files (VERSION_BUMP_GOVERNANCE_PLAN.md, COMPREHENSIVE_AUTOMATION_PLAN.md)
3. ✅ Update supporting docs (research, implementation guides)

**Pre-Implementation (Week 1 Day 1):**
1. Complete 4 pre-work fixes (25 min)
2. Get Tier 1 approval from Michel

**Implementation (Week 1-3):**
1. Phase 0 (security hardening)
2. Phase 1 (version governance proof-of-concept)
3. Phases 2-4 (comprehensive automation)
4. Phase 5 (optional: observability + docs)

---

## Supporting Documents

- **[MASTER_AUTOMATION_RESEARCH.md](MASTER_AUTOMATION_RESEARCH.md)** — Root cause analysis, 7 automation opportunities, cognitive load research, industry benchmarks, 5-agent findings
- **[AGENT_REVIEW_FINDINGS.md](AGENT_REVIEW_FINDINGS.md)** — Consolidated findings from 5-agent independent review (earlier assessment)
- **[SIX_AGENT_CONSOLIDATED_FINDINGS.md](SIX_AGENT_CONSOLIDATED_FINDINGS.md)** — **CRITICAL: All 6 agent assessments consolidated with amendments required for master plan**

**Critical Amendments Implemented from 6-Agent Review:**
1. ✅ Phase 5 changed to MANDATORY (not optional)
2. ✅ Bug 1 (worktree) moved to Phase 1 (not Phase 6)
3. ✅ Effectiveness target downgraded to 75-85% (realistic)
4. ✅ Pre-Phase-0 critical items added (branch protection, Pester audit, PS testing)
5. ✅ Phase 0 & 4 acceptance criteria explicit
6. ✅ Effort estimates amended (27-29h most likely)
7. ⏳ Parallelization strategy (Phases 2-3) to be documented
8. ⏳ 45 gaps closure plan to be detailed in Phase implementation

**Note:** Implementation details (code examples, technical specs) are documented in research file and will be expanded during Phase implementation.

---

**Plan Status:** AMENDED (6-Agent assessment complete, critical improvements integrated)  
**Next Checkpoint:** Michel approval of amended plan (Phase 5 mandatory, Bug 1 in Phase 1, 27-29h effort, Pre-Phase-0 critical items)  
**Implementation Start:** Pre-Work critical items + Phase 0 begin Week 1 Day 1 (after Michel approval)
