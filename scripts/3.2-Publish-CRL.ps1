<#
  Part 3.2: upload the CRL and CA certificate to Azure Blob Storage.

  Runs daily on FRD-CA-01 as a scheduled task (SYSTEM). Signs in with the VM's
  system-assigned managed identity, which has Storage Blob Data Contributor on the
  'pki' container only. No storage key, SAS token or secret is stored anywhere.

  Changes: creates or overwrites PDS-Root-CA.crl and PDS-Root-CA.crt in the container.
  Writes a line per upload (or a FAILED line) to C:\PKI\publish.log.

  C:\PKI is restricted to SYSTEM and Administrators, because the task runs as SYSTEM:
    icacls C:\PKI /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F'
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$account = 'pdspki9876'; $container = 'pki'
$enroll  = 'C:\Windows\System32\CertSrv\CertEnroll'
$log     = 'C:\PKI\publish.log'
try {
  # Short-lived token for Azure Storage from the instance metadata endpoint (only reachable from inside the VM)
  $token = (Invoke-RestMethod -Headers @{ Metadata = 'true' } `
    -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/').access_token

  # The local CA certificate name includes the server name; upload it under the name the AIA address expects
  $files = @{
    'PDS-Root-CA.crl' = Join-Path $enroll 'PDS-Root-CA.crl'
    'PDS-Root-CA.crt' = (Get-ChildItem $enroll -Filter '*_PDS-Root-CA.crt' | Select-Object -First 1).FullName
  }
  foreach ($name in $files.Keys) {
    $type = if ($name -like '*.crl') { 'application/pkix-crl' } else { 'application/pkix-cert' }
    $headers = @{ Authorization = "Bearer $token"; 'x-ms-version' = '2021-08-06'
                  'x-ms-blob-type' = 'BlockBlob'; 'x-ms-blob-content-type' = $type }
    # Uploads go over HTTPS. Only reading the CRL uses HTTP
    Invoke-RestMethod -Method Put -Uri "https://$account.blob.core.windows.net/$container/$name" `
      -Headers $headers -InFile $files[$name] -ContentType $type
    Add-Content $log "$(Get-Date -Format s) Uploaded $name"
  }
} catch {
  Add-Content $log "$(Get-Date -Format s) FAILED: $($_.Exception.Message)"
  exit 1
}

<#
  Scheduled task (created once):
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\PKI\Publish-CRL.ps1'
    $trigger   = New-ScheduledTaskTrigger -Daily -At 6am
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'PKI - Publish CRL to Azure' -Action $action -Trigger $trigger -Principal $principal
#>
