# ADR-002: PowerShell Module Distribution vs Standalone Script

**Date:** 2026-08-30  
**Status:** ACCEPTED  
**Author:** Claude (Project AI)

## Context

The bot requires installation and management capabilities that must be delivered to end users. Two primary distribution models are available:

1. **PowerShell Module** - Distributed via PSGallery, installable with `Install-Module`
2. **Standalone Script** - Single .ps1 file or bootstrap script in GitHub repository

Additional consideration: Python bot component requires separate installation.

## Decision

We chose **PowerShell Module** (full module, distributed via PSGallery).

## Rationale

### Why PowerShell Module?

1. **Standard Distribution** - PSGallery is the de facto standard for PowerShell packages
2. **User Discovery** - Modules are searchable on PSGallery, visible to broader audience
3. **Installation UX** - Users familiar with `Install-Module BATCRelayBot` command
4. **Updates** - Users can update with `Update-Module BATCRelayBot`
5. **Versioning** - Semantic versioning built into module system
6. **Professional** - Signals maturity and support (vs bootstrap scripts)
7. **Discoverability** - Users can find via `Find-Module BATCRelayBot`
8. **Help Integration** - Integrates with PowerShell help system

### Why NOT standalone script?

- **No standard discovery** - Users must know exact GitHub URL
- **Manual updates** - No built-in update mechanism
- **No versioning** - Users don't know which version they have
- **Less professional** - Bootstrap scripts signal experimental/temporary solution
- **Harder to document** - No integration with `Get-Help`

## Consequences

### Positive
- Professional distribution channel (PSGallery)
- Easy for users to install and update
- Built-in help documentation
- Version management is automatic
- Easier for users to trust (established platform)
- Supports multi-version scenarios (users can keep v1.0.0 + v1.1.0)

### Negative
- PSGallery API key management required
- Requires CI/CD for automated publishing
- Module must follow PSGallery guidelines
- Takes longer to go from code to user availability (publishing process)

## Related Decisions

- ADR-003: Bot files location (AppData\Local) - works alongside module
- ADR-004: Full automation via CI/CD - module requires automated tagging and publishing

## Alternatives Considered

1. **Standalone bootstrap script** - Rejected for poor UX and discoverability
2. **GitHub release archives** - Rejected for manual download/extract friction
3. **Hybrid approach** (bootstrap + module) - Rejected for maintenance burden

## Implementation Details

- Module published to PSGallery on git tag (v1.0.0, v1.1.0, etc.)
- Installation: `Install-Module BATCRelayBot -Repository PSGallery`
- Update: `Update-Module -Name BATCRelayBot`
- Help: `Get-Help Install-BATCRelayBot`
- Module location: `$env:USERPROFILE\Documents\PowerShell\Modules\BATCRelayBot\`

## Module Structure

```
BATCRelayBot/
├── BATCRelayBot.psd1          # Module manifest (metadata, version)
├── BATCRelayBot.psm1          # Module implementation
├── Public/                      # Exported functions
│   ├── Install-BATCRelayBot.ps1
│   ├── Start-BATCRelayBot.ps1
│   ├── Stop-BATCRelayBot.ps1
│   ├── Get-BATCRelayBotStatus.ps1
│   └── Uninstall-BATCRelayBot.ps1
└── Private/                     # Internal helpers
    └── (helper functions)
```

## Publishing Workflow

1. Commit changes to main branch
2. Bump version in .psd1 (e.g., 1.0.0 → 1.1.0)
3. Update CHANGELOG.md
4. Create git tag: `git tag v1.1.0`
5. Push tag to GitHub
6. GitHub Actions publishes to PSGallery
7. Users see update: `Update-Module BATCRelayBot`

## Notes

- Module can be developed locally: `Import-Module .\BATCRelayBot`
- PSGallery is trusted by Microsoft, recognized by IT departments
- Aligns with Azure DevOps, Microsoft Teams, and other enterprise tools
