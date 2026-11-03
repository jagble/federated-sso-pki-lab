<#
  Part 3.3: prerequisites for AD FS. Run on the DC as a Tier 0 admin.
  CHANGES AD AND DNS: creates an enrollment group, the AD FS gMSA and a DNS record.

  Note: AD FS looks for its gMSA in the default 'Managed Service Accounts' container.
  Creating it in a custom OU makes Install-AdfsFarm fail with
  "Unable to retrieve group Managed Service Account information. The system cannot find the file specified."
#>
$domain = 'DC=ad,DC=potomacdefense,DC=internal'

# 1. Servers allowed to enroll for the PDS Web Server certificate template
New-ADGroup -Name 'T0-PKI-WebServer-Enroll' -GroupScope Global -GroupCategory Security `
  -Path "OU=Groups,OU=Tier0,OU=PDS,$domain" `
  -Description 'Tier 0 servers allowed to enroll for the PDS Web Server certificate template'
Add-ADGroupMember -Identity 'T0-PKI-WebServer-Enroll' -Members 'FRD-ADFS-01$'

# 2. AD FS service account: a gMSA only FRD-ADFS-01 can retrieve the password for
New-ADServiceAccount -Name 'gmsa-adfs' -DNSHostName 'sts.ad.potomacdefense.internal' `
  -ServicePrincipalNames 'http/sts.ad.potomacdefense.internal' `
  -PrincipalsAllowedToRetrieveManagedPassword 'FRD-ADFS-01$' `
  -Path "CN=Managed Service Accounts,$domain"

# 3. Federation service name -> AD FS server. An A record, not a CNAME, so Kerberos asks for the right name
$ip = (Resolve-DnsName 'FRD-ADFS-01.ad.potomacdefense.internal' -Type A).IPAddress
Add-DnsServerResourceRecordA -ZoneName 'ad.potomacdefense.internal' -Name 'sts' -IPv4Address $ip

# Read-only checks
Get-ADGroupMember 'T0-PKI-WebServer-Enroll' | Format-List Name, objectClass
Get-ADServiceAccount 'gmsa-adfs' -Properties PrincipalsAllowedToRetrieveManagedPassword, ServicePrincipalNames |
  Format-List Name, DistinguishedName, PrincipalsAllowedToRetrieveManagedPassword, ServicePrincipalNames
Resolve-DnsName 'sts.ad.potomacdefense.internal' | Format-List Name, Type
