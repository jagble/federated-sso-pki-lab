<#
  Part 3.5: decommission AD FS after ServiceNow moved to Entra ID.
  Each section says where it runs. Everything here CHANGES something except the checks.
#>

# ---------- 1. FRD-ADFS-01: prove nothing uses it, then cut it off ----------
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; ProviderName = 'AD FS Auditing'; Id = 1200 } -MaxEvents 3 |
  Format-Table TimeCreated, Id -AutoSize               # last token issued must pre-date the cutover
(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=sts.ad.potomacdefense.internal' }).SerialNumber
Remove-AdfsRelyingPartyTrust -TargetName 'ServiceNow'
Stop-Service adfssrv
Set-Service adfssrv -StartupType Disabled

# ---------- 2. DC: remove AD FS's key container (Golden SAML) ----------
# AD FS protects its token-signing key with a key stored on a contact under Program Data.
# Deleting the VM does not remove it.
$adfs = 'CN=ADFS,CN=Microsoft,CN=Program Data,DC=ad,DC=potomacdefense,DC=internal'
Get-ADObject -SearchBase $adfs -Filter * | Select-Object Name, ObjectClass
Get-ADObject $adfs | Remove-ADObject -Recursive -Confirm:$false

# With the AD Recycle Bin ON, deleted objects keep their attributes (including the key) and stay
# restorable. Check, and if they are not yet recycled, purge them to the recycled state.
Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" | Format-List Name, EnabledScopes
Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects -Properties LastKnownParent, isRecycled, thumbnailPhoto |
  Where-Object { $_.Name -like 'ADFS*' -or $_.LastKnownParent -like '*ADFS*' } |
  Format-Table Name, isRecycled, @{n='KeyPresent';e={ [bool]$_.thumbnailPhoto }} -AutoSize
# Only if any show isRecycled = False:
#   <those objects> | Remove-ADObject -IncludeDeletedObjects -Confirm:$false

# ---------- 3. FRD-CA-01: revoke the TLS certificate and stop issuing the template ----------
certutil -view -restrict "RequesterName=PDS\FRD-ADFS-01$" -out "RequestID,SerialNumber,CommonName,NotAfter"
certutil -revoke <SerialNumber> 5                      # 5 = Cessation of Operation
certutil -crl
Start-ScheduledTask -TaskName 'PKI - Publish CRL to Azure'   # revocation visible from the internet now
Remove-CATemplate -Name 'PDSWebServer' -Force
Get-CATemplate                                         # nothing: the CA issues nothing again

# ---------- 4. DC: everything else AD FS left behind ----------
Remove-ADServiceAccount -Identity 'gmsa-adfs' -Confirm:$false
Remove-ADGroup -Identity 'T0-PKI-WebServer-Enroll' -Confirm:$false
Remove-DnsServerResourceRecord -ZoneName 'ad.potomacdefense.internal' -Name 'sts' -RRType A -Force
# Azure VMs register a "Windows Virtual Machine" serviceConnectionPoint inside their computer
# object, so Remove-ADComputer fails ("leaf object"). Remove it recursively:
Get-ADComputer 'FRD-ADFS-01' | Remove-ADObject -Recursive -Confirm:$false

# ---------- 5. Portals ----------
# Azure: delete FRD-ADFS-01 with its OS disk and network interface
# ServiceNow: delete the inactive "PDS AD FS" identity provider record
