---
title: Windows adapter implementation evidence
date: 2026-10-29
status: implemented
tags: [driftdetect, windows, verification]
---

# Windows adapter implementation report

Task 2 of the approved shared Core plan is implemented in the Windows repository on `feat/shared-core`. Changes are uncommitted for combined review. No Core or ESXi files were edited by this worker. No source files were deleted, no credentials were used, and no live Windows target was queried. The retained `Classes` files are unused by the module loader.

## Delivered behavior

- Module 2.0.0 requires Core >=1.0.0 and checks its major version is 1; no eager PSWriteHTML or Windows-management dependency.
- Existing public commands and path/object parameter sets remain. Added IncludeAll, Strict, TaskArgumentAllowList, AllowPartial and Export-WSConfigurationReport.
- Capture emits sixteen independent status units, including explicit skipped optional units. Successful empty queries remain successful. Provider errors fail only the affected unit and retain sanitized diagnostics. Strict rejects every requested Failed/Partial/Unsupported unit. Session ownership and cleanup are explicit.
- A local/remote transport helper preserves nested positional arrays and uses one self-contained provider scriptblock compatible with Windows PowerShell 5.1. Plain entity records are converted to real Core objects on the client.
- Target identity uses usable SMBIOS UUID, with MachineGuid fallback, including when the SMBIOS query itself is unavailable. Connection or trustworthy identity failure aborts capture.
- Registry recursion and exact paths are in scope. Missing selected keys retain a stable full-hive identity matching later observed keys. Value-kind data and binary encoding are explicit. Known exact-name secret exclusions occur before value reads and are visible as exclusion coverage.
- gpresult uses a unique owned XML file, checks native exit status, parses structured computer GPO identity/application data, excludes refresh timestamps and cleans up its own file. XML parsing prohibits DTD/external resolution. The GPO scope is explicitly limited and does not claim all resultant settings.
- Scheduled task capture retains disabled tasks, full nested trigger data including named XML values/attributes, principals, settings and ordered mixed-type execution actions. Runtime last/next/results are observations. Arguments are removed on the target unless the exact reviewed full task path is allowlisted. Omitted arguments are never hashed. Scope includes the normalized allowlist and a visible exclusion notice.
- Volumes use UniqueId/path; disks use UniqueId. Missing/colliding IDs fail their unit. Drive letters/numbers remain properties. Free space and transient health/state are observations.
- Firewall captures disabled/enabled ActiveStore rules, profiles and all associated address/application/service/port/interface/security filters. Required filter query failures fail the rule unit.
- Services include disabled entries, startup mode, service account and executable configuration. Runtime state/capabilities are observations. Local users/groups use SID identities, groups use SID membership sets, and membership failures cannot become empty lists. Local SAM is positively NotApplicable on domain controllers.
- Network uses adapter GUIDs, ordered per-interface DNS, IP-interface/DHCP configuration and routes. Empty teaming is separate from an unavailable teaming provider.
- Domain trusts are structured and compared with a keyed policy. Workgroup trust scope is positively NotApplicable; domain member capability limitations are Unsupported; actual query failures remain Failed. Feature query failures remain explicit.
- New declarative provider rules cover corrected entity/property names, high-severity security entity additions/removals, Critical firewall/domain properties, keyed trusts and membership sets. Old SeverityRules.json remains as unused legacy source.
- README documents dependency setup, exact scope/privacy tradeoffs, migration from classes/schema 1, corrected TotalChanges semantics and report commands.

## Verification evidence

Test-first evidence was observed before implementation: the initial provider suite had nine missing-helper failures; package tests had three expected old-version/old-loader/parameter failures; Core capture integration failed until new provider rules were present. Additional regressions first demonstrated missing ordered mixed actions, registry absent/present identity mismatch, SMBIOS query fallback failure, and XML leaf-attribute loss, then passed after correction.

Final PowerShell 7 verification: **40 passed, 0 failed, 0 skipped**, Pester 5.7.1. Tests are split across Adapter (21), Contract (3), Integration (9), and ProviderComparison (7). The real Core engine is used for capture contracts, JSON round trips with bracketed literal paths, strict/partial scope behavior, allowlisted task argument drift, default exclusion, disabled task trigger/principal drift, ordered DNS reversal, group membership sets, keyed trust changes, entity severity and CIM character normalization.

Windows PowerShell 5.1 provider verification: **21 passed, 0 failed, 0 skipped**, using Pester 5.7.1 loaded from its installed absolute path. This includes actual 5.1 parsing/execution of the provider and transport functions with mocked platform queries and a serialized remote-envelope simulation. The initial attempt to discover Pester by module name found only the built-in old Pester; using the installed 5.7.1 manifest resolved that harness issue. No production change or module installation was needed.

`Test-ModuleManifest` succeeds and reports module 2.0.0 with client PowerShell minimum 7.0. Current production/test function files parse under the PowerShell 7 parser with no parse errors. Windows PowerShell 5.1 provider tests confirm its separate remote compatibility target. Git status shows only intended Windows source/docs/tests additions and modifications, with all legacy Classes retained.

## Limits and integration handoff

No live Windows Server 2022/2025 collection or actual remote PSSession was exercised. Windows-specific APIs and permissions were represented by mocks and realistic XML/configuration fixtures. Minimum client PowerShell 7.0 was not installed/tested. Remote 5.1 was exercised locally with provider mocks, rather than on a server endpoint.

Core owns HTML renderer behavior, PSWriteHTML loading, legacy snapshot/report adaptation, malformed-snapshot validation and combined import-order/staging checks. These wrappers pass the specified shared arguments. Root integration/review must run all packages and visually verify the shared reports. The worker has not claimed successful live reporting, live gpresult, live feature enumeration, or live firewall/CIM behavior.

Trust collection deliberately reports Unsupported for domain member targets because the retained Microsoft_DomainTrustStatus scope is domain-controller specific. This can make default capture incomplete on a domain member; inspect coverage and use AllowPartial deliberately. Registry exclusions cover documented exact secret names; tasks expose verbatim arguments only by explicit full-path opt-in. They are configuration-coverage policies rather than claims to discover every secret on a host.

## Final integration follow-up
Root completed the review follow-up fixes for direct GPO inventory selection, exact registry secret-name exclusions and scope/profile exclusion notices. The final staged Windows package has 43 passing tests; its provider suite passes 23 tests under real Windows PowerShell 5.1. Combined Core/adapter/integration verification passes 142 tests. See ../review-artifacts/implementation-review-resolutions.md for final evidence and limits.


## 2026-10-30 Copilot follow-up
Version 2.0.1 captures local password expiration policy from Win32_UserAccount joined by SID, joins network inventories by interface index, and bounds manifest and local command imports to Core 1.x. Accounts.Users scope now identifies the corrected policy source; fresh baselines are required for complete comparison with 2.0.0 captures. Regression tests reproduce all three reviewed failures, including both Core majors already loaded. Windows package: 62 passed. Full staged suite: 165 passed, zero failed/skipped. Provider tests under Windows PowerShell 5.1: 36 passed. Parser/manifests and git diff checks pass. New checks remain synthetic; no live server mutation or remote capture was performed.

