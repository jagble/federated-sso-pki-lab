<#
  Part 3.5: get a new application-access OU into the Entra Connect sync scope.

  Why: GG-App-ServiceNow was created directly in OU=Groups, which Entra Connect doesn't sync
  (its inclusion list was People, Groups\Role and Disabled). Nothing errored; the group just
  never reached Entra ID.

  PART A - on the DC (CHANGES AD): a dedicated OU for app access groups. Not OU=Role, which the
  Project 1 JML engine manages from HR data.
  PART B - on FRD-SYNC-01 (CHANGES SYNC CONFIGURATION): add the OU to the AD connector's
  inclusion list. Done in PowerShell because the Entra Connect wizard needs a cloud admin sign-in,
  and Synchronization Service Manager is read-only while the wizard is open.
#>

# ---------- PART A: on the DC ----------
New-ADOrganizationalUnit -Name 'App' -Path 'OU=Groups,OU=PDS,DC=ad,DC=potomacdefense,DC=internal' `
  -Description 'Application access groups (synced to Entra ID)'
Get-ADGroup 'GG-App-ServiceNow' | Move-ADObject -TargetPath 'OU=App,OU=Groups,OU=PDS,DC=ad,DC=potomacdefense,DC=internal'

# ---------- PART B: on FRD-SYNC-01 (close the Entra Connect wizard first) ----------
$dn   = 'OU=App,OU=Groups,OU=PDS,DC=ad,DC=potomacdefense,DC=internal'
$conn = Get-ADSyncConnector -Name 'ad.potomacdefense.internal'
$part = $conn.Partitions | Where-Object {
  $_.ConnectorPartitionScope.ContainerInclusionList -contains 'OU=Role,OU=Groups,OU=PDS,DC=ad,DC=potomacdefense,DC=internal' }
$part.ConnectorPartitionScope.ContainerInclusionList.Add($dn)
Add-ADSyncConnector -Connector $conn | Out-Null     # saves the edited connector

# Read-only check: four OUs now in scope
(Get-ADSyncConnector -Name 'ad.potomacdefense.internal').Partitions |
  ForEach-Object { $_.ConnectorPartitionScope.ContainerInclusionList }

# A scope change needs a full import, not a delta
Start-ADSyncSyncCycle -PolicyType Initial
