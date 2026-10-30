<img width="2560" height="1280" alt="winsrv-banner-01" src="https://github.com/user-attachments/assets/f057dcbc-7938-468d-af03-458d3c1291a7" />

---
title: DriftDetect.WinServer 2.0
tags: [driftdetect, windows, powershell]
---

# DriftDetect.WinServer

Collect Windows Server 2022/2025 configuration, save a reviewable snapshot, and compare it through **DriftDetect.Core 1.x**. Client PowerShell 7.0+ is required. Remote collection uses Windows PowerShell 5.1-compatible scriptblocks. Offline import and comparison need only Core; HTML export loads PSWriteHTML >= 0.0.170 on demand.

```powershell
Import-Module DriftDetect.WinServer
$baseline = New-WSSnapshot -ComputerName SERVER01 -IncludeAll -OutputPath baseline.json
# Capture again after the intended observation interval.
$current = New-WSSnapshot -ComputerName SERVER01 -IncludeAll -OutputPath current.json
$drift = Compare-WSSnapshot -BaselineSnapshot $baseline -CurrentSnapshot $current
Export-WSDriftReport -DriftResult $drift -OutputPath drift.html
Export-WSConfigurationReport -SnapshotPath current.json -OutputPath configuration.html
```

For remote authentication, pass `-Credential (Get-Credential)` or a PSCredential retrieved from a SecretManagement vault. Credentials are used for the owned remoting session and are never placed in snapshots. The adapter closes its own session in `finally`.

Install Core alongside this package through your normal module workflow. For source development, prepend the workspace containing the sibling packages to process-local `PSModulePath`, or use the workspace staging/test script. Shipping module code has no hardcoded sibling fallback and makes no profile changes.

## Capture and coverage

All existing capture parameters remain: `ComputerName`, `Credential`, `IncludeRegistry`, `IncludeScheduledTasks`, `IncludeGroupPolicy`, and `OutputPath`. `IncludeAll` enables the three optional collectors. `Strict` terminates if any requested applicable collection unit is Failed, Partial, or Unsupported. Without Strict, useful data is retained and incomplete coverage raises a warning.

Every snapshot records all sixteen units, including optional units omitted by the caller:

| Collection unit | Configuration captured |
| --- | --- |
| System.Configuration | Host/domain role, OS, hardware summary and actual timezone |
| Services.Configuration | All services including disabled; startup mode, account and executable path |
| Features.Installed | Installed Windows features and roles |
| Network.Adapters | Adapter GUID, addresses, ordered per-interface DNS, IP-interface settings and routes |
| Network.Teams | Team mode, algorithm and membership; unavailable provider is Unsupported |
| Storage.Volumes | UniqueId (path fallback), filesystem, size and labels |
| Storage.Disks | UniqueId, disk number, partition and configuration details |
| Firewall.Profiles | Effective ActiveStore profile configuration |
| Firewall.Rules | Enabled and disabled ActiveStore rules plus address, application, service, port, interface and security filters |
| Accounts.Users | SID identity and local-account configuration |
| Accounts.Groups | SID identity and SID membership set; member enumeration failures fail the unit |
| Domain.Membership | Domain/workgroup membership and role |
| Domain.Trusts | Structured keyed trusts from Microsoft_DomainTrustStatus on domain controllers |
| ScheduledTasks.Tasks | Optional: full trigger XML configuration, principals, settings and ordered actions |
| GroupPolicy.Applied | Optional: computer GPO identities and application/filter information from checked gpresult XML |
| Registry.Values | Optional: selected registry paths recursively, existence, value kind and value, with secret exclusions |

A successful query returning nothing is Success with zero entities. Unsupported indicates an unavailable provider/capability. Local SAM units are NotApplicable only when the collected DomainRole identifies a domain controller. Trusts are NotApplicable on a positively identified workgroup machine and Unsupported on domain members where this provider is not applicable. Failure and absence are never conflated. Domain member captures may therefore need `-AllowPartial` for comparison; inspect coverage first.

Free space, health/state, boot time, service runtime state, account logon activity and task last/next-run information are Observations. These remain visible to reporting and are excluded from drift. Volume/disk identities must be nonempty and unique; an unusable or colliding identity fails that unit. Target identity uses a usable SMBIOS UUID, falling back to MachineGuid. Capture aborts if neither is trustworthy.

Group Policy coverage is **computer GPO identity and application information**, not every resultant policy setting. XML generation time and unrelated refresh data are omitted. Nonzero gpresult exit status is a failure. The adapter cleans up only its uniquely named temporary XML file.

## Task argument privacy

Task arguments can contain arbitrary secrets. By default the adapter removes Arguments nodes **on the target before returning data**, stores no argument hash, and records `ArgumentsExcluded` and a readable coverage notice. Argument changes on excluded tasks are not assessed.

To capture reviewed non-secret arguments verbatim, use exact full task paths:

```powershell
New-WSSnapshot -IncludeScheduledTasks -TaskArgumentAllowList '\Ops\Reviewed task'
```

Paths are normalized case-insensitively for Windows identity. Wildcards and folder-only selections are rejected. The normalized allowlist is embedded in the task unit scope and collection profile; changing it changes comparison scope. Review argument contents before opting in. Task arguments remain excluded for every other task, including disabled tasks.

Registry collection recursively covers the seven paths declared in `Private/Transport.ps1` (Windows policies, SMB server/workstation parameters, LSA, SCHANNEL, and Winlogon). Missing selected keys are represented as observed absence. Exact credential-bearing value names declared in the unit scope (including DefaultPassword, DefaultPin, AltDefaultPassword, AutoLogonPassword, Password, Secret, Credential, Credentials, PrivateKey, ClientSecret, AccessToken, RefreshToken and ApiKey) are excluded before reading values. Non-secret policy names such as PasswordComplexity and CredentialGuard remain captured. This exact-name policy does not discover arbitrary secrets. Excluded names are visible as coverage, never original values. Binary non-excluded values use an explicit Base64 encoding record. Selection, recursion and exclusion policy are recorded in unit scope.

## Comparison, reports and migration

`Compare-WSSnapshot` accepts the existing path or object parameter sets, `SeverityConfigPath`, and `OutputPath`, plus `AllowPartial`. Strict comparison requires compatible target identity, rules and collection scopes with successful requested units. AllowPartial compares only compatible successful units and records excluded coverage. A zero-change incomplete result is inconclusive.

New capture rules live in `Config/Rules.json` and are embedded in snapshots. Defaults use keyed trust comparison, set membership comparison, and ordered task actions/DNS. Account, firewall, role and Group Policy entity additions/removals have explicit High rules; firewall enabled/inbound policy and domain membership changes retain Critical classification. `SeverityConfigPath` supplies an explicit override to both snapshots. Legacy `{Rules:[{EntityType,Property,Severity}]}` files remain accepted by Core, but selectors use the new entity type/property names and support only those limited legacy fields.

Version 2 returns ordinary shared snapshot objects. Replace `[WSSnapshot]::Import($path)` with `Get-WSSnapshot -Path $path`, and `$snapshot.Export($path)` with `Export-DDSnapshot -Snapshot $snapshot -Path $path`. `.Entities.Keys`, ComputerName, OSVersion and OSBuild inspection remain supported. TotalChanges now counts all events, including additions and removals; Changes remains the property-event view. Use Events once for totals.

Version 1 snapshots can be imported for inspection/configuration reports and are labelled legacy with unknown coverage. **Capture new schema 2 baselines before comparison**; all legacy comparisons are rejected, including legacy-to-legacy. No command updates or accepts a baseline automatically. Old files in `Classes` and `Config/SeverityRules.json` are retained as unused legacy source; runtime loads only functions and the new rules.

Both reports accept object or JSON path inputs. Configuration reports show everything captured in that snapshot, plus coverage, exclusions and observations. They do not claim to capture every Windows setting. Report rendering and HTML dependency validation are owned by Core.

## Verification

Run `Invoke-Pester -Path .\Tests -Output Detailed` with Pester 5 and Core available through PSModulePath. Tests mock Windows queries and exercise the real Core contracts, persistence and comparison. They use no credentials and perform no live collection. See `implementation-report.md` for current evidence and limits. PowerShell 7.0 and actual Windows PowerShell 5.1 remoting remain compatibility targets requiring live validation; a local 5.1 parser check is recorded separately when available.
