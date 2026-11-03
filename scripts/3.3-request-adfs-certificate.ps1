<#
  Part 3.3: request the AD FS TLS certificate from PDS-Root-CA. Run on FRD-ADFS-01, elevated.
  CHANGES THE SERVER: creates a private key and installs the issued certificate.

  The PDS Web Server template (PDSWebServer) requires CA certificate manager approval, so the
  request comes back Pending. Approve it on the CA (certsrv.msc > Pending Requests > Issue), then
  run the "collect" section.
#>

# Request: pick up membership of T0-PKI-WebServer-Enroll without a reboot, then request
klist -li 0x3e7 purge
Get-Certificate -Template 'PDSWebServer' `
  -SubjectName 'CN=sts.ad.potomacdefense.internal' `
  -DnsName 'sts.ad.potomacdefense.internal' `
  -CertStoreLocation Cert:\LocalMachine\My

# Collect (after approval)
Get-ChildItem Cert:\LocalMachine\Request | Get-Certificate
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=sts.ad.potomacdefense.internal' }
$cert | Format-List Subject, Issuer, NotAfter, DnsNameList, EnhancedKeyUsageList

# Verify the chain and revocation, downloading the CRL from the address in the certificate (read-only).
# certutil -verify needs a file, not a thumbprint. Only the public certificate is exported.
$file = Join-Path $env:TEMP 'sts.cer'
Export-Certificate -Cert $cert -FilePath $file | Out-Null
certutil -verify -urlfetch $file | Select-String 'pdspki|Verified|revocation check|CertUtil|ERROR'
Remove-Item $file
