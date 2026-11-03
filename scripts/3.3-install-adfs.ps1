<#
  Part 3.3: install AD FS. Run on FRD-ADFS-01, elevated, as a Tier 0 admin who is a Domain Admin.
  CHANGES THE SERVER AND AD: installs the role, creates the federation service and its
  configuration database (WID), generates the token-signing and token-decrypting certificates,
  and creates the AD FS key container in AD.
#>
Install-WindowsFeature ADFS-Federation, RSAT-AD-PowerShell -IncludeManagementTools
Test-ADServiceAccount -Identity 'gmsa-adfs'   # must be True

$thumb = (Get-ChildItem Cert:\LocalMachine\My |
  Where-Object { $_.Subject -eq 'CN=sts.ad.potomacdefense.internal' }).Thumbprint

Install-AdfsFarm -CertificateThumbprint $thumb `
  -FederationServiceName 'sts.ad.potomacdefense.internal' `
  -FederationServiceDisplayName 'Potomac Defense Systems' `
  -GroupServiceAccountIdentifier 'PDS\gmsa-adfs$' `
  -OverwriteConfiguration

Restart-Computer   # required to finish configuration. adfssrv is a delayed-start service

<# After the restart #>
# Auditing: AD FS records every sign-in; Windows only keeps them with the audit policy on
Set-AdfsProperties -AuditLevel Verbose
auditpol /set /subcategory:"Application Generated" /success:enable /failure:enable

# Read-only checks
Get-Service adfssrv | Format-List Name, Status
Get-AdfsProperties | Format-List HostName, Identifier, AutoCertificateRollover, AuditLevel, EnableIdpInitiatedSignonPage
Get-AdfsCertificate | Format-Table CertificateType, IsPrimary, @{n='Expires';e={$_.Certificate.NotAfter}} -AutoSize

# Test: enable the IdP-initiated sign-on page ONLY while testing, then turn it off again
# Set-AdfsProperties -EnableIdpInitiatedSignonPage $true
# ...sign in at https://sts.ad.potomacdefense.internal/adfs/ls/idpinitiatedsignon.aspx from FRD-WS-01...
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; ProviderName = 'AD FS Auditing'; Id = 1200, 1202, 1203 } -MaxEvents 6 |
  Format-Table TimeCreated, Id, @{n='Meaning';e={ switch ($_.Id) { 1200 {'Token issued'} 1202 {'Credentials validated'} 1203 {'Credentials FAILED'} } }} -AutoSize
Set-AdfsProperties -EnableIdpInitiatedSignonPage $false
