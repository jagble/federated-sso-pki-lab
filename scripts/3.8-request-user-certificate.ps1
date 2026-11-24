<#
  Part 3.8: request, collect and check a user authentication certificate (PDS User Authentication template).

  Run on the user's workstation, signed in AS THE USER, in a normal (non-admin) PowerShell window:
  the certificate and its private key belong to that user's personal store.

  WHAT IT CHANGES: creates a key pair on this machine (non-exportable) and a certificate request in the user's
  store; after approval, installs the certificate. Everything else is read-only checks.

  Usage:
    .\3.8-request-user-certificate.ps1 -Step Request     # submit; expect "Pending" (manager approval required)
    # ... approver issues it on the CA: Pending Requests -> All Tasks -> Issue ...
    .\3.8-request-user-certificate.ps1 -Step Collect     # install it, show the UPN, check revocation over the internet
#>
param(
    [Parameter(Mandatory)] [ValidateSet('Request', 'Collect')] [string] $Step,
    [string] $Template = 'PDSUserAuthentication',     # the template NAME (no spaces), not its display name
    [string] $IssuerLike = '*PDS-Root-CA*'
)

if ($Step -eq 'Request') {
    # New key pair + request to the enterprise CA. Pending until a CA manager approves it.
    $req = Get-Certificate -Template $Template -CertStoreLocation Cert:\CurrentUser\My
    "Status: $($req.Status)"
    return
}

# Collect: pick up the approved certificate from the pending-request store
Get-ChildItem Cert:\CurrentUser\Request | Get-Certificate | Select-Object Status

$c = Get-ChildItem Cert:\CurrentUser\My | Where-Object Issuer -like $IssuerLike |
     Sort-Object NotBefore -Descending | Select-Object -First 1
if (-not $c) { throw "No certificate from $IssuerLike in the user's store yet." }

# What Entra will see: subject, purpose, private key present, and the UPN in the Subject Alternative Name
$c | Format-List Subject, NotAfter, EnhancedKeyUsageList, HasPrivateKey
($c.Extensions | Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' }).Format($true)

# Revocation check over the internet: export the PUBLIC half only, then let certutil fetch AIA and CRL
$cer = Join-Path $env:TEMP 'user-auth.cer'
Export-Certificate -Cert $c -FilePath $cer | Out-Null
certutil -verify -urlfetch $cer      # look for "Leaf certificate revocation check passed"
