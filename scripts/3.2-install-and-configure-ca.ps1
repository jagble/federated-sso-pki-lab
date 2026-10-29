<#
  Part 3.2: install and configure PDS-Root-CA on FRD-CA-01.

  CHANGES THE SERVER. Run in an elevated PowerShell on the CA, signed in as a
  Tier 0 admin who is TEMPORARILY a member of Enterprise Admins (an enterprise CA
  writes to the forest-wide configuration partition). Remove that membership afterwards.

  Prerequisite: C:\Windows\CAPolicy.inf (scripts/3.2-CAPolicy.inf) is in place.
#>

$ErrorActionPreference = 'Stop'
$base = 'http://pdspki9876.blob.core.windows.net/pki'   # public CRL/AIA location (part 3.2, section 1)

# 1. Install the role and create the CA
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA `
  -CACommonName 'PDS-Root-CA' `
  -KeyLength 4096 -HashAlgorithmName SHA256 `
  -ValidityPeriod Years -ValidityPeriodUnits 10 -Force

# 2. CRL distribution point: keep the local copy, drop LDAP and http://<CA>, add the public address
Get-CACrlDistributionPoint | Where-Object { $_.Uri -notmatch '^C:' } | Remove-CACrlDistributionPoint -Force
Add-CACrlDistributionPoint -Uri "$base/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl" -AddToCertificateCdp -Force

# 3. Authority information access: same idea, for the CA certificate
Get-CAAuthorityInformationAccess | Where-Object { $_.Uri -notmatch '^C:' } | Remove-CAAuthorityInformationAccess -Force
Add-CAAuthorityInformationAccess -Uri "$base/<CaName><CertificateName>.crt" -AddToCertificateAia -Force

# 4. Issued certificates last 1 year
certutil -setreg CA\ValidityPeriodUnits 1
certutil -setreg CA\ValidityPeriod "Years"

# 5. Audit every CA event category, and make Windows write them to the Security log
certutil -setreg CA\AuditFilter 127
auditpol /set /subcategory:"Certification Services" /success:enable /failure:enable

# 6. Apply, wait for the service, publish a CRL (running -crl straight after a restart fails with RPC 1722)
Restart-Service CertSvc
Start-Sleep -Seconds 15
certutil -crl

# 7. Show the result (read-only)
Get-CACrlDistributionPoint | Format-Table Uri, AddToCertificateCdp, PublishToServer -AutoSize
Get-CAAuthorityInformationAccess | Format-Table Uri, AddToCertificateAia -AutoSize
Get-ChildItem C:\Windows\System32\CertSrv\CertEnroll
